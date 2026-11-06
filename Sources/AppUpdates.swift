import Foundation
import SwiftUI
import AppKit

struct AppVersion: Comparable {
    let parts: [Int]
    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields = text.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty && ($0.count == 1 || $0.first != "0") && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let numbers = fields.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        parts = numbers
    }
    static func < (left: Self, right: Self) -> Bool { left.parts.lexicographicallyPrecedes(right.parts) }
}

struct AppRelease: Sendable {
    let version: String
    let url: URL
    let notes: String
}

enum AppUpdateState: String {
    case idle, checking = "appUpdateChecking", current = "appUpdateCurrent", available = "appUpdateAvailable", failed = "appUpdateFailed", unpublished = "appUpdateUnpublished"
}

enum AppUpdateError: Error { case invalidResponse }

private struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let state: String
        let size: Int
    }
}

final class AppUpdateHTTP: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "api.github.com" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(request.url.map(Self.allowed) == true ? request : nil) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData written: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 1_000_000 || totalBytesExpectedToWrite > 1_000_000 { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    static func fetch(_ url: URL) async throws -> (Int, Data) {
        guard allowed(url) else { throw AppUpdateError.invalidResponse }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        config.httpAdditionalHeaders = ["User-Agent": "ESO-Mac-Tools", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2026-03-10"]
        let session = URLSession(configuration: config, delegate: AppUpdateHTTP(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (file, response) = try await session.download(from: url, delegate: AppUpdateHTTP())
        defer { try? FileManager.default.removeItem(at: file) }
        guard let response = response as? HTTPURLResponse, response.url.map(allowed) == true,
              (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 1_000_000 else { throw AppUpdateError.invalidResponse }
        return (response.statusCode, try Data(contentsOf: file))
    }
}

@MainActor final class AppUpdater: ObservableObject {
    @Published var latest: AppRelease?
    @Published var showing = false
    @Published var state = AppUpdateState.idle
    @Published var showStatus = false
    let version: String
    let repository: String
    private let asset: String
    private let defaults: UserDefaults
    private let fetch: @Sendable (URL) async throws -> (Int, Data)
    private var started = false
    private var notifiedVersion: String?
    private var key: String { "appUpdate." + repository }
    var checking: Bool { state == .checking }
    init(repository: String, asset: String, version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0", defaults: UserDefaults = .standard, fetch: @escaping @Sendable (URL) async throws -> (Int, Data) = { try await AppUpdateHTTP.fetch($0) }) {
        self.repository = repository; self.asset = asset; self.version = version; self.defaults = defaults; self.fetch = fetch
    }
    static func release(_ data: Data, repository: String, asset: String, version: String) throws -> (AppUpdateState, AppRelease?) {
        guard data.count <= 1_000_000, let current = AppVersion(version) else { throw AppUpdateError.invalidResponse }
        let entry = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !entry.draft, !entry.prerelease else { return (.unpublished, nil) }
        guard let remote = AppVersion(entry.tag_name) else { throw AppUpdateError.invalidResponse }
        guard remote > current else { return (.current, nil) }
        let base = "https://github.com/" + repository
        guard entry.html_url == base + "/releases/tag/" + entry.tag_name,
              let url = URL(string: entry.html_url) else { throw AppUpdateError.invalidResponse }
        guard entry.assets.contains(where: { $0.name == asset && $0.state == "uploaded" && $0.size > 0 && $0.browser_download_url == base + "/releases/download/" + entry.tag_name + "/" + asset }) else { return (.unpublished, nil) }
        let display = entry.tag_name.hasPrefix("v") ? String(entry.tag_name.dropFirst()) : entry.tag_name
        return (.available, AppRelease(version: display, url: url, notes: String((entry.body ?? "").prefix(12_000))))
    }
    func start() async {
        guard !started else { return }
        started = true
        if let data = defaults.data(forKey: key + ".cache") { accept(data) }
        await check(force: true)
    }
    func tick(now: Date = Date()) async {
        if let last = defaults.object(forKey: key + ".checked") as? Date, (0..<3600).contains(now.timeIntervalSince(last)) { return }
        await check(now: now)
    }
    func check(manual: Bool = false, force: Bool = false, now: Date = Date()) async {
        guard !checking else { return }
        showStatus = manual; state = .checking
        if !manual, !force, let last = defaults.object(forKey: key + ".checked") as? Date, now.timeIntervalSince(last) >= 0, now.timeIntervalSince(last) < 3600 {
            if let data = defaults.data(forKey: key + ".cache") { accept(data) }
            else { state = AppUpdateState(rawValue: defaults.string(forKey: key + ".outcome") ?? "") ?? .unpublished }
            return
        }
        defaults.set(now, forKey: key + ".checked")
        defer { defaults.set(state.rawValue, forKey: key + ".outcome") }
        do {
            let (code, data) = try await fetch(URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
            if code == 404 { defaults.removeObject(forKey: key + ".cache"); latest = nil; showing = false; state = .unpublished; return }
            guard code == 200 else { throw AppUpdateError.invalidResponse }
            _ = try Self.release(data, repository: repository, asset: asset, version: version)
            defaults.set(data, forKey: key + ".cache")
            accept(data, repeatNotice: manual)
        } catch { state = .failed }
    }
    private func accept(_ data: Data, repeatNotice: Bool = false) {
        do {
            let (state, release) = try Self.release(data, repository: repository, asset: asset, version: version)
            self.state = state; latest = release
            if let release {
                if repeatNotice || notifiedVersion != release.version { showing = true }
                notifiedVersion = release.version
            } else { showing = false; notifiedVersion = nil }
        } catch { defaults.removeObject(forKey: key + ".cache"); state = .failed }
    }
}

struct AppUpdateControl: View {
    @ObservedObject var updater: AppUpdater
    let text: (String) -> String
    var canPresent = true
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let release = updater.latest {
                if compact {
                    Button { updater.showing = true } label: {
                        Label(text("appUpdateAvailable") + " " + release.version, systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.borderedProminent).controlSize(.regular)
                } else {
                    Button(text("appUpdateAvailable") + " " + release.version) { updater.showing = true }.buttonStyle(.link)
                }
            }
            if !compact {
              Button(text("checkAppUpdates")) { Task { await updater.check(manual: true) } }.buttonStyle(.link).disabled(updater.checking)
            }
            if (compact && updater.latest == nil && updater.state != .idle) || (!compact && (updater.showStatus || updater.checking)) {
                Text(text(updater.state.rawValue)).font(.caption2).foregroundStyle(updater.state == .failed ? .orange : .secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.font(.caption)
            .sheet(isPresented: Binding(get: { updater.showing && canPresent }, set: { updater.showing = $0 })) {
                if let release = updater.latest {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(text("appUpdateTitle")).font(.title2.bold())
                        Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "") · \(updater.version) → \(release.version)").font(.headline)
                        if !release.notes.isEmpty { ScrollView { Text(verbatim: release.notes).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 220) }
                        Text(text("appUpdateInstallHint")).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Spacer()
                            Button(text("appUpdateLater")) { updater.showing = false }.keyboardShortcut(.cancelAction)
                            Button(text("appUpdateDownload")) { NSWorkspace.shared.open(release.url); updater.showing = false }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        }
                    }.padding(24).frame(width: 510)
                }
            }
    }
}
