import Foundation

private actor UpdateProbe {
    var calls = 0
    var code = 200
    var failure = false
    var data: Data
    func respond(_ data: Data) { self.data = data }
    init(_ data: Data) { self.data = data }
    func configure(code: Int = 200, failure: Bool = false) { self.code = code; self.failure = failure }
    func fetch(_ url: URL) async throws -> (Int, Data) {
        calls += 1
        try await Task.sleep(for: .milliseconds(30))
        if failure { throw URLError(.notConnectedToInternet) }
        return (code, data)
    }
}

@MainActor func appUpdateChecks() async throws -> Int {
    var count = 0
    func verify(_ value: Bool, _ label: String) throws {
        guard value else { throw NSError(domain: "AppUpdateChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
        count += 1
    }
    let repository = "owner/project", asset = "App.zip"
    func payload(tag: String = "v1.10.0", changes: [String: Any] = [:]) throws -> Data {
        var value: [String: Any] = ["tag_name": tag, "html_url": "https://github.com/owner/project/releases/tag/" + tag, "body": "Changes", "draft": false, "prerelease": false, "assets": [["name": asset, "state": "uploaded", "size": 100, "browser_download_url": "https://github.com/owner/project/releases/download/" + tag + "/" + asset]]]
        value.merge(changes) { _, new in new }
        return try JSONSerialization.data(withJSONObject: value)
    }
    func result(_ data: Data, current: String = "1.9.0") throws -> (AppUpdateState, AppRelease?) { try AppUpdater.release(data, repository: repository, asset: asset, version: current) }
    try verify(AppVersion("1.10.0")! > AppVersion("v1.9.0")!, "numeric release version comparison")
    try verify(AppVersion("0.3.10")! > AppVersion("0.3.9")!, "numeric patch comparison")
    for value in ["1.2", "1.2.3.4", "1.02.3", "1.2.3-rc.1", "1.a.3", "v1.2.999999999999999999999999"] { try verify(AppVersion(value) == nil, "invalid stable version rejected") }
    let data = try payload()
    let (state, release) = try result(data)
    try verify(state == .available && release?.version == "1.10.0" && release?.url.absoluteString == "https://github.com/owner/project/releases/tag/v1.10.0", "ready newer release offered")
    try verify(try result(data, current: "1.10.0").0 == .current, "equal release is current")
    try verify(try result(data, current: "2.0.0").0 == .current, "newer installed release never downgraded")
    try verify(try result(payload(changes: ["draft": true])).0 == .unpublished, "draft ignored")
    try verify(try result(payload(tag: "v2.0.0-rc.1", changes: ["prerelease": true])).0 == .unpublished, "prerelease ignored")
    try verify(try result(payload(changes: ["assets": []])).0 == .unpublished, "release without a ready app archive ignored")
    try verify(try result(payload(changes: ["assets": [["name": asset, "state": "uploaded", "size": 1, "browser_download_url": "https://evil.invalid/App.zip"]]])).0 == .unpublished, "foreign download URL rejected")
    var rejected = false
    do { _ = try result(payload(changes: ["html_url": "https://github.com.evil.invalid/owner/project/releases/tag/v1.10.0"])) } catch { rejected = true }
    try verify(rejected, "foreign release page rejected")
    rejected = false
    do { _ = try result(Data(repeating: 32, count: 1_000_001)) } catch { rejected = true }
    try verify(rejected, "oversized release response rejected")
    try verify(try result(payload(changes: ["body": String(repeating: "a", count: 20_000)])).1?.notes.count == 12_000, "release notes bounded")
    try verify(AppUpdateHTTP.allowed(URL(string: "https://api.github.com/repos/owner/project/releases/latest")!), "official HTTPS API allowed")
    for url in ["http://api.github.com/", "https://user@api.github.com/", "https://api.github.com:8443/", "https://api.github.com.evil.invalid/"] { try verify(!AppUpdateHTTP.allowed(URL(string: url)!), "unsafe API redirect rejected") }
    let suite = "AppUpdateChecks." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let probe = UpdateProbe(data)
    let updater = AppUpdater(repository: repository, asset: asset, version: "1.9.0", defaults: defaults, fetch: { try await probe.fetch($0) })
    await updater.start()
    try verify(updater.latest?.version == "1.10.0" && updater.showing, "startup offers a new app version")
    updater.showing = false
    await updater.start()
    try verify(await probe.calls == 1 && !updater.showing, "window reopening does not repeat the startup prompt")
    let cached = AppUpdater(repository: repository, asset: asset, version: "1.9.0", defaults: defaults, fetch: { try await probe.fetch($0) })
    await cached.start()
    try verify(await probe.calls == 2 && cached.showing, "each app launch refreshes GitHub even when a recent release is cached")
    await cached.check(manual: true)
    try verify(await probe.calls == 3, "manual check refreshes GitHub despite the startup cache")
    cached.showing = false
    await probe.configure(failure: true)
    await cached.check(manual: true)
    try verify(cached.state == .failed && cached.showStatus && !cached.showing && cached.latest != nil, "offline failure preserves known update without reopening a dialog")
    let offlineStartup = AppUpdater(repository: repository, asset: asset, version: "1.9.0", defaults: defaults, fetch: { try await probe.fetch($0) })
    await offlineStartup.start()
    try verify(offlineStartup.state == .failed && offlineStartup.latest?.version == "1.10.0", "startup network failure preserves a validated cached update")
    await probe.configure(code: 404)
    await cached.check(manual: true)
    try verify(cached.state == .unpublished && cached.latest == nil && !cached.showing, "unpublished repository is handled without an update prompt")
    defaults.removePersistentDomain(forName: suite)
    await probe.configure()
    let concurrent = AppUpdater(repository: repository, asset: asset, version: "1.9.0", defaults: defaults, fetch: { try await probe.fetch($0) })
    let before = await probe.calls
    async let first: Void = concurrent.check(manual: true)
    async let second: Void = concurrent.check(manual: true)
    _ = await (first, second)
    try verify(await probe.calls == before + 1, "concurrent update checks share one active request")
    defaults.removePersistentDomain(forName: suite)
    let clock = Date(timeIntervalSince1970: 1_800_000_000)
    let scheduledProbe = UpdateProbe(data)
    let scheduled = AppUpdater(repository: repository, asset: asset, version: "1.9.0", defaults: defaults, fetch: { try await scheduledProbe.fetch($0) })
    await scheduled.check(now: clock)
    scheduled.showing = false
    await scheduled.tick(now: clock.addingTimeInterval(3599))
    try verify(await scheduledProbe.calls == 1, "periodic check waits an hour")
    await scheduled.tick(now: clock.addingTimeInterval(3600))
    try verify(await scheduledProbe.calls == 2 && !scheduled.showing && scheduled.latest != nil, "hourly check keeps banner without repeating dismissed notice")
    await scheduledProbe.respond(try payload(tag: "v1.11.0"))
    await scheduled.tick(now: clock.addingTimeInterval(7200))
    try verify(scheduled.latest?.version == "1.11.0" && scheduled.showing, "new release discovered automatically while running")
    scheduled.showing = false
    await scheduled.check(manual: true, now: clock.addingTimeInterval(7201))
    try verify(scheduled.showing, "manual check can reopen a dismissed update")
    defaults.removePersistentDomain(forName: suite)
    await scheduledProbe.configure(failure: true)
    await scheduled.check(manual: true, now: clock)
    let failedCache = AppUpdater(repository: repository, asset: asset, version: "1.9.0", defaults: defaults, fetch: { try await scheduledProbe.fetch($0) })
    await failedCache.check(now: clock.addingTimeInterval(30))
    try verify(failedCache.state == .failed, "cached network failure is not shown as an unpublished repository")
    await scheduledProbe.configure()
    await failedCache.tick(now: clock.addingTimeInterval(3600))
    try verify(failedCache.state == .available, "periodic checking recovers after a network failure")
    if ProcessInfo.processInfo.environment["APP_UPDATES_LIVE_TESTS"] == "1" {
        let (code, response) = try await AppUpdateHTTP.fetch(URL(string: "https://api.github.com/repos/TheMoldex/ttc-client-macos/releases/latest")!)
        try verify(code == 200, "live GitHub latest release fetched")
        let live = try AppUpdater.release(response, repository: "TheMoldex/ttc-client-macos", asset: "TTC-Client-macOS-AppleSilicon.zip", version: "1.0.0")
        try verify(live.0 == .available && live.1 != nil, "live published app archive accepted")
        print("PASS: live GitHub release and archive metadata")
    }
    return count
}
