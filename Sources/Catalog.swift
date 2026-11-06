import Foundation
import CryptoKit
import ImageIO

struct AddonCategory: Codable, Sendable {
    let id: String
    let title: String
    let iconUrl: String
    var icon: URL? {
        guard let url = URL(string: iconUrl), NetworkGuard.allowed(url), url.host == "cdn-eso.mmoui.com", url.path.hasPrefix("/images/icons/") else { return nil }
        return url
    }
}

func validCategoryImage(_ data: Data) -> Bool {
    guard data.count <= 1_000_000, let image = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
    return (1...1024).contains(width) && (1...1024).contains(height)
}

final class NetworkGuard: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let maximum: Int64
    init(maximum: Int64 = .max) { self.maximum = maximum }
    static let hosts: Set<String> = ["api.mmoui.com", "cdn.esoui.com", "cdn-eso.mmoui.com", "cdn.mmoui.com", "www.esoui.com", "esoui.com"]
    static func allowed(_ url: URL) -> Bool { url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) && hosts.contains(url.host?.lowercased() ?? "") }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(request.url.map(Self.allowed) == true ? request : nil) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximum || totalBytesExpectedToWrite > maximum { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

struct DownloadDetails: Codable, Sendable {
    let id: Int
    let version: String
    let checksum: String
    let downloadUri: String
    let description: String?
    let changeLog: String?
    var images: [AddonScreenshot]? = nil
    var screenshots: [AddonScreenshot] {
        var seen = Set<String>()
        return Array((images ?? []).filter { $0.image != nil && seen.insert($0.id).inserted }.prefix(64))
    }
}

actor CatalogClient {
    private let session: URLSession
    private let cache: URL
    private var lastAttempt: Date = .distantPast
    private var detailCache: [Int: (Date, DownloadDetails)] = [:]
    private var pendingIcons: [String: Task<Data?, Never>] = [:]
    private var failedIcons: [String: Date] = [:]
    init(cache: URL) {
        self.cache = cache
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 180
        config.httpMaximumConnectionsPerHost = 4
        config.httpAdditionalHeaders = ["User-Agent": "ESOAddonsMac/0.1 (native macOS addon manager)", "Referer": "https://www.esoui.com/"]
        session = URLSession(configuration: config, delegate: NetworkGuard(), delegateQueue: nil)
    }
    func cached() -> [Addon] { (try? JSONDecoder().decode([Addon].self, from: Data(contentsOf: cache))) ?? [] }
    func categories() async throws -> [Int: AddonCategory] {
        let file = cache.deletingLastPathComponent().appendingPathComponent("categories.json")
        let saved = try? Data(contentsOf: file)
        let data: Data
        var downloaded = false
        if let saved, let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, Date().timeIntervalSince(date) < 604800 {
            data = saved
        } else {
            do {
                data = try await request(URL(string: "https://api.mmoui.com/v4/game/ESO/categorylist.json")!, maximum: 1_000_000)
                downloaded = true
            } catch { guard let saved else { throw error }; data = saved }
        }
        let categories = try JSONDecoder().decode([AddonCategory].self, from: data)
        let entries = categories.compactMap { entry in Int(entry.id).flatMap { $0 > 0 ? ($0, entry) : nil } }
        guard !categories.isEmpty, categories.count <= 256, entries.count == categories.count, Set(entries.map { $0.0 }).count == entries.count else { throw AppError("catalogError") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if downloaded { try data.write(to: file, options: .atomic) }
        return Dictionary(uniqueKeysWithValues: entries)
    }
    func icon(_ category: AddonCategory) async -> Data? {
        guard let url = category.icon else { return nil }
        if let failed = failedIcons[category.iconUrl], Date().timeIntervalSince(failed) < 300 { return nil }
        if let pending = pendingIcons[category.iconUrl] { return await pending.value }
        let task = Task { try? await self.loadIcon(url) }
        pendingIcons[category.iconUrl] = task
        let data = await task.value
        pendingIcons.removeValue(forKey: category.iconUrl)
        if data == nil { failedIcons[category.iconUrl] = Date() }
        return data
    }
    private func loadIcon(_ url: URL) async throws -> Data {
        let folder = cache.deletingLastPathComponent().appendingPathComponent("category-icons")
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = folder.appendingPathComponent(name)
        if let saved = try? Data(contentsOf: file), validCategoryImage(saved) { return saved }
        let data = try await request(url, maximum: 1_000_000)
        guard validCategoryImage(data) else { throw AppError("catalogError") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        if files.count >= 64, let first = files.first { try? FileManager.default.removeItem(at: first) }
        try data.write(to: file, options: .atomic)
        return data
    }
    func screenshot(_ url: URL, force: Bool = false) async throws -> Data {
        guard screenshotURL(url) else { throw AppError("unsafeURL") }
        try Task.checkCancellation()
        let images = ScreenshotCache(directory: cache.deletingLastPathComponent().appendingPathComponent("screenshots"))
        if !force, let saved = try? images.read(url) { return saved }
        let data = try await request(url, maximum: 12_000_000)
        try Task.checkCancellation()
        guard validScreenshotImage(data) else { throw AppError("screenshotFailed") }
        try? images.write(data, for: url)
        return data
    }
    func catalog(force: Bool = false) async throws -> [Addon] {
        let current = cached()
        let changed = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if !current.isEmpty && ((!force && Date().timeIntervalSince(changed) < 3600) || Date().timeIntervalSince(lastAttempt) < 60) { return current }
        lastAttempt = Date()
        let data = try await request(URL(string: "https://api.mmoui.com/v4/game/ESO/filelist.json")!, maximum: 16_000_000)
        let entries = try JSONDecoder().decode([Addon].self, from: data)
        guard !entries.isEmpty, Set(entries.map(\.id)).count == entries.count else { throw AppError("catalogError") }
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cache, options: .atomic)
        return entries
    }
    func details(_ id: Int, force: Bool = false) async throws -> DownloadDetails {
        if !force, let (date, entry) = detailCache[id], Date().timeIntervalSince(date) < 3600 { return entry }
        let data = try await request(URL(string: "https://api.mmoui.com/v4/game/ESO/filedetails/\(id).json")!, maximum: 8_000_000)
        guard let entry = try JSONDecoder().decode([DownloadDetails].self, from: data).first(where: { $0.id == id }) else { throw AppError("catalogError") }
        if detailCache.count >= 32, let oldest = detailCache.min(by: { $0.value.0 < $1.value.0 })?.key { detailCache.removeValue(forKey: oldest) }
        detailCache[id] = (Date(), entry)
        return entry
    }
    func download(_ addon: Addon, to folder: URL) async throws -> URL {
        let entry = try await details(addon.id, force: true)
        guard entry.version == addon.version, entry.checksum.count == 32, entry.checksum.allSatisfy(\.isHexDigit), let url = URL(string: entry.downloadUri), NetworkGuard.allowed(url) else { throw AppError("changedCatalog", addon.title) }
        let archive = try await request(url, maximum: 128_000_000)
        let hash = Insecure.MD5.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard hash == entry.checksum.lowercased() else { throw AppError("checksumError", addon.title) }
        let file = folder.appendingPathComponent("\(addon.id).zip")
        try archive.write(to: file, options: .atomic)
        return file
    }
    private func request(_ url: URL, maximum: Int) async throws -> Data {
        guard NetworkGuard.allowed(url) else { throw AppError("unsafeURL") }
        let (file, response) = try await session.download(from: url, delegate: NetworkGuard(maximum: Int64(maximum)))
        defer { try? FileManager.default.removeItem(at: file) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, response.url.map(NetworkGuard.allowed) == true else { throw AppError("httpError", "\((response as? HTTPURLResponse)?.statusCode ?? 0)") }
        let length = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard length > 0 && length <= maximum else { throw AppError("downloadSize") }
        return try Data(contentsOf: file)
    }
}
