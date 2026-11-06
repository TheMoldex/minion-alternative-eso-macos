import Foundation
import CryptoKit
import ImageIO

struct AddonScreenshot: Codable, Sendable, Identifiable {
    let thumbUrl: String?
    let imageUrl: String?
    let description: String?
    var id: String { imageUrl ?? "" }
    var image: URL? { imageUrl.flatMap(URL.init(string:)).flatMap { screenshotURL($0) ? $0 : nil } }
    var thumbnail: URL? { thumbUrl.flatMap(URL.init(string:)).flatMap { screenshotURL($0) ? $0 : nil } ?? image }
}

func screenshotURL(_ url: URL) -> Bool {
    NetworkGuard.allowed(url) && url.host == "cdn-eso.mmoui.com" && url.query == nil && url.fragment == nil &&
        url.path.range(of: "^/preview/(tiny/)?pvw[0-9]+\\.(png|jpe?g|gif|webp)$", options: [.regularExpression, .caseInsensitive]) != nil
}

func validScreenshotImage(_ data: Data) -> Bool {
    guard !data.isEmpty, data.count <= 12_000_000,
          let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetStatus(source) == .statusComplete, (1...256).contains(CGImageSourceGetCount(source)),
          let type = CGImageSourceGetType(source) as String?, ["public.png", "public.jpeg", "com.compuserve.gif", "org.webmproject.webp"].contains(type),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
    return (1...16_384).contains(width) && (1...16_384).contains(height) && width <= 40_000_000 / height
}

func screenshotBitmap(_ data: Data, maximum: Int) -> CGImage? {
    guard validScreenshotImage(data), let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: min(4096, max(1, maximum)), kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
}

struct ScreenshotCache {
    let directory: URL
    private func file(_ url: URL) -> URL {
        directory.appendingPathComponent(SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined())
    }
    func read(_ url: URL, now: Date = Date()) throws -> Data? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        try requireDirectory(directory)
        let file = file(url)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        try requireRegularFile(file)
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard (0..<604_800).contains(now.timeIntervalSince(values.contentModificationDate ?? .distantPast)), (values.fileSize ?? .max) <= 12_000_000 else { return nil }
        let data = try Data(contentsOf: file)
        return validScreenshotImage(data) ? data : nil
    }
    func write(_ data: Data, for url: URL) throws {
        guard screenshotURL(url), validScreenshotImage(data) else { throw AppError("screenshotFailed") }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try requireDirectory(directory)
        let target = file(url)
        var entries: [(url: URL, size: Int, date: Date)] = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0 != target }.compactMap { file in
            guard file.lastPathComponent.count == 64, file.lastPathComponent.allSatisfy(\.isHexDigit) else { return nil }
            try requireRegularFile(file)
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.date < $1.date }
        var size = entries.reduce(0) { $0 + $1.size }
        while entries.count >= 64 || size + data.count > 96_000_000 {
            guard !entries.isEmpty else { break }
            let entry = entries.removeFirst()
            try fm.removeItem(at: entry.url); size -= entry.size
        }
        try data.write(to: target, options: .atomic)
    }
}

struct ScreenshotSelection: Identifiable {
    let id = UUID()
    let title: String
    let images: [AddonScreenshot]
    let index: Int
}
