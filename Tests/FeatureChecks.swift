import Foundation

private actor DownloadProbe {
    var active = 0, maximum = 0, started = 0
    func run(_ addon: Addon, fail: Bool = false) async throws -> URL {
        active += 1; started += 1; maximum = max(maximum, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(fail && addon.id == 1 ? 10 : 50))
        if fail && addon.id == 1 { throw AppError("httpError", "fixture") }
        return URL(fileURLWithPath: "/tmp/package-\(addon.id).zip")
    }
}

func featureChecks(_ temp: URL) async throws {
    let fm = FileManager.default
    let legacy = try JSONDecoder().decode(LibraryState.self, from: Data("{\"sources\":{}}".utf8))
    check(legacy.ignored.isEmpty, "old state migrates without losing source records")
    let updated = try JSONDecoder().decode(LibraryState.self, from: JSONEncoder().encode(LibraryState(ignored: [3])))
    check(updated.ignored == [3], "ignored updates persist")
    let request = addon(1, "Main"), library = addon(2, "Lib")
    let plan = InstallPlan(addons: [request, library], missing: [], requestedIDs: [1])
    rejects("ignored dependency cannot be silently upgraded") { try respectIgnored(plan, ignored: [2]) }
    try respectIgnored(plan, ignored: [1])
    check(true, "explicit individual update of ignored addon allowed")
    check(RuntimeSafety.blockers("/Applications/Minion.app/Contents/PlugIns/jre/bin/java\n/usr/bin/java").count == 1, "Minion Java runtime detected without blocking unrelated Java")
    let root = temp.appendingPathComponent("features/live/AddOns"), live = root.deletingLastPathComponent()
    try makeLocal(root, "Main")
    try makeLocal(root, "Other")
    let profiles = ESOProfile.adding(root, to: ESOProfile.adding(root, to: []))
    check(profiles.count == 1 && profiles[0].path == root.standardizedFileURL.path, "profiles deduplicate normalized folders")
    let saved = live.appendingPathComponent("SavedVariables")
    try fm.createDirectory(at: saved, withIntermediateDirectories: true)
    try Data("original settings".utf8).write(to: saved.appendingPathComponent("Main.lua"))
    try Data("previous settings".utf8).write(to: saved.appendingPathComponent("Main.lua.bak"))
    try Data("unrelated settings".utf8).write(to: saved.appendingPathComponent("Other.lua"))
    try Data("game options".utf8).write(to: live.appendingPathComponent("UserSettings.txt"))
    try Data("enabled addons".utf8).write(to: live.appendingPathComponent("AddOnSettings.txt"))
    let locals = try scanAddons(root)
    let files = try addonSettings(folders: ["Main"], locals: locals, live: live)
    check(files == ["Main.lua", "Main.lua.bak"], "settings use manifest names and include ESO backup file")
    let shared = locals + [LocalAddon(folder: "Shared", manifests: [manifest("Main")])]
    rejects("shared settings cannot be reset") { _ = try addonSettings(folders: ["Main"], locals: shared, live: live) }
    let store = Installer(home: temp.appendingPathComponent("features/state"))
    let preview = SettingsPreview(title: "Main", folders: ["Main"], files: files)
    await rejectsAsync("reset rechecks running game before moving settings") { try await store.resetSettings(preview, root: root, canModify: { throw AppError("backgroundPaused") }) }
    let changedPreview = SettingsPreview(title: "Main", folders: ["Main"], files: ["Other.lua"])
    await rejectsAsync("stale or forged reset preview changes no files") { try await store.resetSettings(changedPreview, root: root, canModify: {}) }
    let trash = try await store.resetSettings(preview, root: root, canModify: {})
    check(!fm.fileExists(atPath: saved.appendingPathComponent("Main.lua").path) && fm.fileExists(atPath: saved.appendingPathComponent("Other.lua").path) && fm.fileExists(atPath: root.appendingPathComponent("Main").path), "reset trashes only chosen settings and keeps addons and other settings")
    for (name, file) in zip(files, trash) { try fm.moveItem(at: file, to: saved.appendingPathComponent(name)) }
    check(try await store.backups(root).isEmpty, "reset creates no addon backup")
    let destination = temp.appendingPathComponent("portable")
    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
    try await store.save(LibraryState(sources: ["Main": Receipt(id: 1, version: "1")], ignored: [1]), root: root)
    let choice = try await store.createSnapshot(root: root, destination: destination, includeAddons: true, canModify: {})
    let loaded = try await store.readSnapshot(choice.location)
    check(loaded.snapshot.items.contains("AddOns/Main") && loaded.snapshot.items.contains("SavedVariables/Main.lua") && loaded.snapshot.items.contains("UserSettings.txt") && loaded.snapshot.items.contains("AddOnSettings.txt"), "portable backup includes addon files, addon settings, game settings")
    check(loaded.snapshot.addons.count == 2 && loaded.snapshot.state.ignored == [1], "portable backup includes inventory and ignore preferences")
    await rejectsAsync("backup cannot recurse into game directory") { _ = try await store.createSnapshot(root: root, destination: live, includeAddons: true, canModify: {}) }
    let settingsOnly = try await store.createSnapshot(root: root, destination: destination, includeAddons: false, canModify: {})
    check(!settingsOnly.snapshot.items.contains { $0.hasPrefix("AddOns/") } && settingsOnly.snapshot.addons.count == 2, "settings-only backup retains inventory without addon binaries")
    let target = temp.appendingPathComponent("transfer/pts/AddOns"), targetLive = target.deletingLastPathComponent()
    try makeLocal(target, "Untouched")
    try await store.restoreSnapshot(choice, root: target, canModify: {})
    check(try scanAddons(target).map(\.folder) == ["Main", "Other", "Untouched"], "backup transfers into another ESO installation while preserving unrelated addons")
    check(try String(contentsOf: targetLive.appendingPathComponent("SavedVariables/Main.lua"), encoding: .utf8) == "original settings", "portable restore transfers saved variables")
    let transferredState = try await store.state(target)
    check(transferredState.sources["Main"]?.id == 1 && transferredState.ignored == [1], "portable restore transfers source mapping and ignored updates")
    try Data("newer target settings".utf8).write(to: targetLive.appendingPathComponent("SavedVariables/Main.lua"))
    await rejectsAsync("failed restore rolls back every replaced item") { try await store.restoreSnapshot(choice, root: target, canModify: {}, afterReplace: { throw AppError("fixtureFailure") }) }
    check(try String(contentsOf: targetLive.appendingPathComponent("SavedVariables/Main.lua"), encoding: .utf8) == "newer target settings", "failed restore preserves current settings")
    check(fm.fileExists(atPath: target.appendingPathComponent("Untouched").path), "failed restore preserves unrelated addons")
    let home = await store.libraryHome(target)
    let transaction = home.appendingPathComponent("settings-transaction")
    try fm.createDirectory(at: transaction, withIntermediateDirectories: true)
    try fm.copyItem(at: choice.location.appendingPathComponent("payload"), to: transaction.appendingPathComponent("old"))
    struct Journal: Encodable { let root: String; let items: [String]; let existed: [String]; let hashes: [String: String]; let before: LibraryState }
    let journal = Journal(root: target.standardizedFileURL.path, items: loaded.snapshot.items, existed: loaded.snapshot.items, hashes: loaded.snapshot.hashes, before: loaded.snapshot.state)
    try JSONEncoder().encode(journal).write(to: transaction.appendingPathComponent("transaction.json"))
    try fm.removeItem(at: target.appendingPathComponent("Main"))
    check(try await store.recover(target) == 1 && fm.fileExists(atPath: target.appendingPathComponent("Main").path), "startup recovers an interrupted portable restore")
    try Data("tampered".utf8).write(to: choice.location.appendingPathComponent("payload/SavedVariables/Main.lua"))
    await rejectsAsync("tampered backup rejected before touching live files") { _ = try await store.readSnapshot(choice.location) }
    let unsafe = Snapshot(format: 1, id: UUID().uuidString, date: Date(), origin: live.path, items: ["../escape"], hashes: [:], addons: [], state: LibraryState())
    let bad = destination.appendingPathComponent("unsafe")
    try fm.createDirectory(at: bad.appendingPathComponent("payload"), withIntermediateDirectories: true)
    try JSONEncoder().encode(unsafe).write(to: bad.appendingPathComponent("snapshot.json"))
    await rejectsAsync("portable restore path traversal rejected") { _ = try await store.readSnapshot(bad) }
    let oldSaved = targetLive.appendingPathComponent("SavedVariables-old")
    try fm.moveItem(at: targetLive.appendingPathComponent("SavedVariables"), to: oldSaved)
    try fm.createSymbolicLink(at: targetLive.appendingPathComponent("SavedVariables"), withDestinationURL: saved)
    await rejectsAsync("symlink settings target rejected before mutation") { try await store.restoreSnapshot(settingsOnly, root: target, canModify: {}) }
    try fm.removeItem(at: targetLive.appendingPathComponent("SavedVariables")); try fm.moveItem(at: oldSaved, to: targetLive.appendingPathComponent("SavedVariables"))
    check(try String(contentsOf: saved.appendingPathComponent("Main.lua"), encoding: .utf8) == "original settings", "symlink attack cannot modify another installation")
    let entries = (0..<501).map { OperationRecord(id: UUID(), date: Date(), operation: "installing", outcome: "completed", detail: "fixture-\($0)") }
    try JSONEncoder().encode(entries).write(to: home.appendingPathComponent("history.json"))
    try await store.record(target, operation: "installing", outcome: "failed", detail: "Main · ESOUI #1 · extract\nunexpectedFolders")
    let persisted = try await Installer(home: temp.appendingPathComponent("features/state")).history(target)
    check(persisted.count == 500 && persisted.first?.detail.contains("ESOUI #1") == true, "operation log persists error context and limits retention to 500")
    check(try await store.history(root).isEmpty, "operation history isolated by ESO folder")
    let packages = (1...8).map { addon($0, "Package\($0)") }
    let probe = DownloadProbe()
    let downloaded = try await parallelDownloads(packages, limit: 2) { try await probe.run($0) }
    let maximum = await probe.maximum, active = await probe.active
    check(downloaded.count == 8 && maximum == 2 && active == 0, "downloads run concurrently with the chosen bound")
    let failure = DownloadProbe()
    let outcomes = try await parallelDownloads(packages, limit: 2) { try await failure.run($0, fail: true) }
    let failedStarted = await failure.started, failedActive = await failure.active
    check(failedStarted == 8 && failedActive == 0 && outcomes.values.compactMap { try? $0.get() }.count == 7, "a failed download does not cancel active or queued downloads")
    let zipFile = temp.appendingPathComponent("obsolete-docs.zip")
    try zip(["Main/file.lua", "Old/Old.txt/obsoleteFolder.txt", "Old/readme.txt"]).write(to: zipFile)
    try ZipArchive.extract(zipFile, into: temp.appendingPathComponent("obsolete-docs"), expected: ["Main"])
    check(fm.fileExists(atPath: temp.appendingPathComponent("obsolete-docs/Main/file.lua").path), "obsolete documentation root accepted without installing it")
    try zip(["Main/file.lua", "Extra/extra.lua"]).write(to: zipFile)
    rejects("unexpected executable addon root remains blocked") { try ZipArchive.extract(zipFile, into: temp.appendingPathComponent("extra-addon"), expected: ["Main"]) }
    try zip(["Main/file.lua", "Extra/Extra.txt"], body: "## Title: Extra\n## APIVersion: 101051").write(to: zipFile)
    rejects("extra active addon manifest cannot masquerade as documentation") { try ZipArchive.extract(zipFile, into: temp.appendingPathComponent("extra-manifest"), expected: ["Main"]) }
    try zip(["Main/file.lua", "Main/images/.gitkeep", ".gitkeep"]).write(to: zipFile)
    let extracted = temp.appendingPathComponent("gitkeep-archive")
    try ZipArchive.extract(zipFile, into: extracted, expected: ["Main"])
    check(fm.fileExists(atPath: extracted.appendingPathComponent("Main/file.lua").path) && !fm.fileExists(atPath: extracted.appendingPathComponent("Main/images/.gitkeep").path) && !fm.fileExists(atPath: extracted.appendingPathComponent(".gitkeep").path), "ordinary .gitkeep files are ignored during extraction")
    rejects("a .gitkeep file cannot hide traversal in its parent path") { _ = try ZipArchive.paths(zip(["Main/../.gitkeep"])) }
    rejects("a .gitkeep symlink is still rejected") { _ = try ZipArchive.paths(zip(["Main/.gitkeep"], symbolic: true)) }
    rejects("a .gitkeep directory is still rejected") { _ = try ZipArchive.paths(zip(["Main/.gitkeep/payload.lua"])) }
    rejects("other dotfiles remain rejected") { _ = try ZipArchive.paths(zip(["Main/.env"])) }
    try await partialInstallChecks(temp)
}

private func partialInstallChecks(_ temp: URL) async throws {
    let root = temp.appendingPathComponent("partial-install/live/AddOns")
    let store = Installer(home: temp.appendingPathComponent("partial-install/state"))
    let library = addon(1, "Library"), compatible = addon(2, "Compatible", dependencies: ["Library>=1"])
    let dependent = addon(3, "Dependent", dependencies: ["Library>=2", "Orphan>=2"])
    let healthy = addon(4, "Healthy", dependencies: ["Required>=2"]), timeout = addon(5, "Timeout")
    let orphan = addon(6, "Orphan"), required = addon(7, "Required"), invalid = addon(8, "Invalid")
    let requests = [library, compatible, dependent, healthy, timeout, invalid]
    for package in requests { try makeLocal(root, package.title) }
    try await store.save(LibraryState(sources: ["Library": Receipt(id: 1, version: "1")]), root: root)
    let plan = try dependencyPlan(requests, catalog: requests + [orphan, required], locals: scanAddons(root), sources: [:])
    let result = try await store.install(plan, root: root, download: { package, folder in
        if package.id == timeout.id { throw AppError("httpError", "fixture") }
        let name = package.title
        let body = "## Title: \(name)\n## APIVersion: 101051\n## Version: 2\n## AddOnVersion: 2\n## DependsOn: \(package.dependencies.map(\.display).joined(separator: " "))"
        var paths = [name + "/" + name + ".addon"]
        if package.id == library.id { paths.append(name + "/../escape.lua") }
        if package.id == invalid.id { paths = [name + "/file.lua"] }
        let file = folder.appendingPathComponent("\(package.id).zip")
        try zip(paths, body: body).write(to: file)
        return file
    }, progress: { _ in })
    check(Set(result.installed.map(\.id)) == [compatible.id, healthy.id, required.id], "independent packages and a consumer of the old library install with their required dependencies")
    check(Set(result.failures.map(\.key)) == ["unsafeArchive", "httpError", "invalidManifest", "missingDependencies"] && result.failures.contains { $0.detail.contains("Dependent → Library>=2") }, "partial result identifies the bad archives and unavailable dependency version")
    let versions = Dictionary(uniqueKeysWithValues: try scanAddons(root).map { ($0.folder, $0.primary?.version ?? "") })
    check(versions == ["Library": "1", "Compatible": "2", "Dependent": "1", "Healthy": "2", "Timeout": "1", "Invalid": "1", "Required": "2"], "failed and dependent addons stay unchanged and an orphan library is not installed")
    let backups = try await store.backups(root)
    check(backups.count == 1 && Set(backups[0].folders) == ["Compatible", "Healthy", "Required"], "the rollback copy contains only installed packages")
    let receipts = try await store.state(root).sources
    check(receipts["Library"]?.version == "1" && receipts["Healthy"]?.version == "2", "source receipts reflect only packages that actually installed")

    let protectedRoot = temp.appendingPathComponent("partial-retained/live/AddOns")
    try makeLocal(protectedRoot, "Library", version: "2", number: 2)
    try makeLocal(protectedRoot, "Retained", dependencies: "Library>=2")
    try makeLocal(protectedRoot, "Independent")
    let replacement = addon(9, "Library", version: "3", number: "3"), independent = addon(10, "Independent")
    let replacementPlan = try dependencyPlan([replacement, independent], catalog: [replacement, independent], locals: scanAddons(protectedRoot), sources: [:])
    let protected = try await store.install(replacementPlan, root: protectedRoot, download: { package, folder in
        let number = package.id == replacement.id ? 1 : 2
        let file = folder.appendingPathComponent("\(package.id).zip")
        try zip(["\(package.title)/\(package.title).addon"], body: "## Title: \(package.title)\n## APIVersion: 101051\n## Version: \(number)\n## AddOnVersion: \(number)").write(to: file)
        return file
    }, progress: { _ in })
    check(protected.installed.map(\.id) == [independent.id] && protected.failures.first?.detail.contains("Retained → Library>=2") == true, "a library replacement cannot break a retained addon or block an unrelated update")
    check(try scanAddons(protectedRoot).first { $0.folder == "Library" }?.primary?.number == 2, "the working library is preserved")
}
