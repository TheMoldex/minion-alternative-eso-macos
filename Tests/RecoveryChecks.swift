import Foundation
import Darwin

func recoveryFixture(_ store: Installer, root: URL, name: String = "Main", number: Int = 1, status: String = "committed") async throws -> (Backup, URL) {
    let id = UUID().uuidString
    let location = await store.libraryHome(root).appendingPathComponent("backups/" + id)
    let old = location.appendingPathComponent("old")
    try makeLocal(old, name, version: String(number), number: number)
    let record = Backup(id: id, date: Date(), label: "fixture", root: root.standardizedFileURL.path, folders: [name], existed: [name], before: LibraryState(), status: status, hashes: try addonBackupHashes(old, names: [name]))
    try JSONEncoder().encode(record).write(to: location.appendingPathComponent("backup.json"))
    return (record, location)
}

func recoveryChecks(_ temp: URL) async throws {
    let fm = FileManager.default, base = temp.appendingPathComponent("recovery-checks")
    defer { try? removeAddonTree(base) }
    let root = base.appendingPathComponent("integrity/live/AddOns")
    try makeLocal(root, "Main", version: "3", number: 3)
    let store = Installer(home: base.appendingPathComponent("integrity/state"))
    let module = root.appendingPathComponent("Main/valuable.lua"), contents = Data("keep the working addon".utf8)
    try contents.write(to: module)
    var (record, location) = try await recoveryFixture(store, root: root, status: "applying")
    let original = try Data(contentsOf: location.appendingPathComponent("old/Main/Main.addon"))
    try fm.removeItem(at: location.appendingPathComponent("old/Main/Main.addon"))
    await rejectsAsync("empty automatic backup cannot replace working addon") { _ = try await store.recover(root, canModify: {}) }
    check(try Data(contentsOf: module) == contents && scanAddons(root).first?.primary?.version == "3", "invalid recovery preserves all current files")
    check(try await store.backups(root).first?.status == "applying", "invalid recovery is never marked successful")
    try original.write(to: location.appendingPathComponent("old/Main/Main.addon"))
    try Data("altered bytes".utf8).write(to: location.appendingPathComponent("old/Main/Main.addon"))
    await rejectsAsync("changed backup bytes fail integrity verification") { _ = try await store.recover(root, canModify: {}) }
    try original.write(to: location.appendingPathComponent("old/Main/Main.addon"))
    record.hashes = nil
    try JSONEncoder().encode(record).write(to: location.appendingPathComponent("backup.json"))
    await rejectsAsync("legacy backup without hashes is never automatically trusted") { _ = try await store.recover(root, canModify: {}) }
    check(try Data(contentsOf: module) == contents, "unverified legacy recovery leaves current addon untouched")
    record.hashes = try addonBackupHashes(location.appendingPathComponent("old"), names: ["Main"])
    record.status = "committed"
    try JSONEncoder().encode(record).write(to: location.appendingPathComponent("backup.json"))
    try await store.restore(record, root: root)
    check(try scanAddons(root).first?.primary?.version == "1", "valid automatic backup restores successfully")
    let newBackup = try await store.backups(root).first { $0.id != record.id }!
    check(try newBackup.hashes == addonBackupHashes(await store.libraryHome(root).appendingPathComponent("backups/" + newBackup.id + "/old"), names: ["Main"]), "new rollback copy stores verified hashes of current addon files")
    try await store.restore(newBackup, root: root)
    check(try Data(contentsOf: module) == contents, "valid restore can itself be rolled back without losing custom files")

    let badFile = location.appendingPathComponent("backup.json")
    try Data("{ broken metadata".utf8).write(to: badFile)
    do { _ = try await store.recover(root); check(false, "corrupt metadata must report its location") }
    catch { check((error as? AppError)?.detail.contains(badFile.path) == true, "corrupt metadata identifies the specific backup file") }
    check(try scanAddons(root, tolerant: true).count == 1 && Data(contentsOf: module) == contents, "corrupt backup metadata does not prevent independent addon scan")

    let scanRoot = base.appendingPathComponent("scan/live/AddOns")
    try makeLocal(scanRoot, "Healthy"); try makeLocal(scanRoot, "Other")
    let readme = scanRoot.appendingPathComponent("Other/README.txt")
    try Data("documentation".utf8).write(to: readme)
    try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: readme.path)
    let scanned = try scanAddons(scanRoot, tolerant: true)
    check(scanned.count == 2 && scanned.first { $0.folder == "Healthy" }?.primary != nil, "one unreadable text file does not hide healthy addons")
    check(scanned.first { $0.folder == "Other" }?.scanError?.contains("README.txt") == true, "partial scan reports the inaccessible file")
    check(addonStatus(addon(1, "Other"), locals: scanned.filter { $0.folder == "Other" }, sources: [:]) == .versionUnknown, "partial scan never reports addon as current")
    rejects("file-changing scans still reject unreadable addon metadata") { _ = try scanAddons(scanRoot) }
    try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: readme.path)

    let readonlyRoot = base.appendingPathComponent("readonly/live/AddOns")
    try makeLocal(readonlyRoot, "Main")
    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readonlyRoot.appendingPathComponent("Main").path)
    let snapshots = base.appendingPathComponent("readonly/copies")
    try fm.createDirectory(at: snapshots, withIntermediateDirectories: true)
    let snapshotStore = Installer(home: base.appendingPathComponent("readonly/state"))
    let choice = try await snapshotStore.createSnapshot(root: readonlyRoot, destination: snapshots, includeAddons: true, canModify: {})
    try await snapshotStore.restoreSnapshot(choice, root: readonlyRoot, canModify: {})
    let transaction = await snapshotStore.libraryHome(readonlyRoot).appendingPathComponent("settings-transaction")
    check(!fm.fileExists(atPath: transaction.path), "read-only manual restore removes both payloads and its journal")
    check(try await snapshotStore.recover(readonlyRoot, canModify: {}) == 0, "next operation is not blocked after read-only manual restore")
    await rejectsAsync("read-only restore rollback preserves current addon on injected failure") { try await snapshotStore.restoreSnapshot(choice, root: readonlyRoot, canModify: {}, afterReplace: { throw AppError("fixture") }) }
    check(!fm.fileExists(atPath: transaction.path) && fm.fileExists(atPath: readonlyRoot.appendingPathComponent("Main/Main.addon").path), "read-only failed restore also cleans recovery journal")

    let protectedPayload = choice.location.appendingPathComponent("payload/AddOns/Main/Main.addon")
    guard chflags(protectedPayload.path, UInt32(UF_IMMUTABLE)) == 0 else { throw AppError("fixture", "chflags payload") }
    await rejectsAsync("locked incoming snapshot file rejects restore before changing live files") { try await snapshotStore.restoreSnapshot(choice, root: readonlyRoot, canModify: {}) }
    check(fm.fileExists(atPath: readonlyRoot.appendingPathComponent("Main/Main.addon").path), "locked incoming payload preserves current addon")
    _ = chflags(protectedPayload.path, 0)
    check(!fm.fileExists(atPath: transaction.path), "locked source payload never creates a staging transaction")
    check(try await snapshotStore.recover(readonlyRoot, canModify: {}) == 0, "unfinished locked staging cleanup never rolls back untouched live files")

    let lockedRoot = base.appendingPathComponent("locked/live/AddOns")
    try makeLocal(lockedRoot, "Main", version: "3", number: 3)
    let lockedStore = Installer(home: base.appendingPathComponent("locked/state"))
    let (lockedBackup, _) = try await recoveryFixture(lockedStore, root: lockedRoot)
    let locked = lockedRoot.appendingPathComponent("Main/locked.lua")
    try contents.write(to: locked)
    guard chflags(locked.path, UInt32(UF_IMMUTABLE)) == 0 else { throw AppError("fixture", "chflags") }
    defer { _ = chflags(locked.path, 0) }
    await rejectsAsync("Finder Locked file rejects replacement before starting transaction") { try await lockedStore.restore(lockedBackup, root: lockedRoot) }
    check(try Data(contentsOf: locked) == contents && scanAddons(lockedRoot).first?.primary?.version == "3", "Finder lock failure preserves the whole current addon")
    check(try await lockedStore.backups(lockedRoot).count == 1, "Finder lock failure creates no pending or unnecessary backup")

    let depRoot = base.appendingPathComponent("dependencies/live/AddOns")
    try makeLocal(depRoot, "Library", version: "3", number: 3)
    try makeLocal(depRoot, "Consumer", dependencies: "Library>=2")
    let depStore = Installer(home: base.appendingPathComponent("dependencies/state"))
    let (oldLibrary, _) = try await recoveryFixture(depStore, root: depRoot, name: "Library")
    await rejectsAsync("library rollback cannot break a retained addon") { try await depStore.restore(oldLibrary, root: depRoot) }
    check(try scanAddons(depRoot).first { $0.folder == "Library" }?.primary?.number == 3, "blocked dependency rollback preserves current library")
    let depCopies = base.appendingPathComponent("dependencies/copies")
    try fm.createDirectory(at: depCopies, withIntermediateDirectories: true)
    let source = base.appendingPathComponent("dependencies/source/AddOns")
    try makeLocal(source, "Library", number: 1)
    let oldSnapshot = try await depStore.createSnapshot(root: source, destination: depCopies, includeAddons: true, canModify: {})
    await rejectsAsync("portable restore checks retained addon dependencies too") { try await depStore.restoreSnapshot(oldSnapshot, root: depRoot, canModify: {}) }
    let depTransaction = await depStore.libraryHome(depRoot).appendingPathComponent("settings-transaction")
    check(!fm.fileExists(atPath: depTransaction.path), "dependency rejection leaves no manual restore transaction")
    try makeLocal(depRoot, "AlreadyBroken", dependencies: "Absent")
    let (compatible, _) = try await recoveryFixture(depStore, root: depRoot, name: "Library", number: 2)
    try await depStore.restore(compatible, root: depRoot)
    check(try scanAddons(depRoot).first { $0.folder == "Library" }?.primary?.number == 2, "unrelated existing missing dependency does not prevent safe rollback")

    let pausedRoot = base.appendingPathComponent("paused/live/AddOns")
    try makeLocal(pausedRoot, "Main", version: "3", number: 3)
    let pausedStore = Installer(home: base.appendingPathComponent("paused/state"))
    _ = try await recoveryFixture(pausedStore, root: pausedRoot, status: "applying")
    let deny: @Sendable () throws -> Void = { throw AppError("backgroundPaused") }
    await rejectsAsync("snapshot creation checks game before pending recovery") { _ = try await pausedStore.createSnapshot(root: pausedRoot, destination: snapshots, includeAddons: true, canModify: deny) }
    await rejectsAsync("snapshot restore checks game before pending recovery") { try await pausedStore.restoreSnapshot(choice, root: pausedRoot, canModify: deny) }
    await rejectsAsync("settings reset checks game before pending recovery") { _ = try await pausedStore.resetSettings(SettingsPreview(title: "Main", folders: ["Main"], files: []), root: pausedRoot, canModify: deny) }
    await rejectsAsync("startup recovery checks game before changing any files") { _ = try await pausedStore.recover(pausedRoot, canModify: deny) }
    check(try scanAddons(pausedRoot).first?.primary?.version == "3", "all paused operations leave the current addon unchanged")
    check(try await pausedStore.backups(pausedRoot).first?.status == "applying", "paused operations leave pending recovery intact")
    check(try await pausedStore.recover(pausedRoot, canModify: {}) == 1, "pending recovery succeeds after the game closes")
}
