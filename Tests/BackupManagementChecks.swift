import Foundation
import Darwin

func backupManagementChecks(_ temp: URL) async throws {
    let fm = FileManager.default
    let root = temp.appendingPathComponent("backup-management/live/AddOns")
    try makeLocal(root, "Main")
    let live = root.deletingLastPathComponent(), saved = live.appendingPathComponent("SavedVariables")
    try fm.createDirectory(at: saved, withIntermediateDirectories: true)
    let sentinel = saved.appendingPathComponent("Main.lua"), original = Data("preserve live settings".utf8)
    try original.write(to: sentinel)
    let store = Installer(home: temp.appendingPathComponent("backup-management/state"))
    let destination = temp.appendingPathComponent("backup-management/manual")
    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
    check(try backupName("   Рейды / перед обновлением 🐉   ") == "Рейды / перед обновлением 🐉", "backup names support Unicode and do not become filesystem paths")
    check(try backupName(" \n ") == nil, "empty backup name retains date-based display")
    rejects("overlong backup name rejected") { _ = try backupName(String(repeating: "a", count: 121)) }
    rejects("backup name control characters rejected") { _ = try backupName("a\nb") }
    let named = try await store.createSnapshot(root: root, destination: destination, includeAddons: true, name: "  Перед обновлением  ", canModify: {})
    check(named.snapshot.name == "Перед обновлением" && named.location.lastPathComponent == "ESO-Backup-" + named.id, "named copy uses stable UUID directory")
    let read = try await store.readSnapshot(named.location)
    check(read.snapshot.name == named.snapshot.name, "backup name persists inside portable metadata")
    let renamed = try await store.renameSnapshot(named, name: "Рейды / 1", directory: destination)
    let checked = try await store.readSnapshot(named.location)
    check(checked.snapshot.name == "Рейды / 1" && checked.snapshot.id == named.id && checked.snapshot.date == named.snapshot.date && checked.snapshot.hashes == named.snapshot.hashes, "renaming preserves date, identity and payload integrity")
    let cleared = try await store.renameSnapshot(renamed, name: "", directory: destination)
    check(cleared.snapshot.name == nil, "clearing a name restores date-based display")
    let header = try JSONSerialization.jsonObject(with: Data(contentsOf: named.location.appendingPathComponent("snapshot.json"))) as! [String: Any]
    check(try header["name"] == nil && snapshotMetadata(named.location).snapshot.name == nil, "old metadata without a name remains supported")
    await rejectsAsync("invalid rename leaves existing metadata intact") { _ = try await store.renameSnapshot(named, name: "a\nb", directory: destination) }
    check(try snapshotMetadata(named.location).snapshot.name == nil, "failed rename leaves metadata unchanged")
    let other = try await store.createSnapshot(root: root, destination: destination, includeAddons: false, name: "Вторая", canModify: {})
    let forged = SnapshotChoice(snapshot: other.snapshot, location: live)
    await rejectsAsync("manual batch validates every selected location before moving any") { try await store.trashSnapshots([named, forged], directory: destination) }
    check(fm.fileExists(atPath: named.location.path) && fm.fileExists(atPath: other.location.path), "invalid batch preserves all legitimate copies")
    await rejectsAsync("duplicate manual backup selection rejected") { try await store.trashSnapshots([named, named], directory: destination) }
    let lock = try lockBackupDirectory(destination)
    await rejectsAsync("backup management respects the shared folder lock") { try await store.trashSnapshots([named], directory: destination) }
    close(lock)
    let moved = try await store.trashSnapshots([named, other], directory: destination)
    check(moved.count == 2 && !fm.fileExists(atPath: named.location.path) && !fm.fileExists(atPath: other.location.path), "selected manual copies move to Trash together")
    for (copy, trash) in zip([named, other], moved) { try fm.moveItem(at: trash, to: copy.location) }
    check(try await store.readSnapshot(named.location).snapshot.id == named.id, "trashed copy can be put back and restored")
    try Data("damaged saved variables".utf8).write(to: other.location.appendingPathComponent("payload/SavedVariables/Main.lua"))
    let damagedTrash = try await store.trashSnapshots([other], directory: destination)
    check(damagedTrash.count == 1, "damaged payload can still be removed using validated backup metadata")
    try fm.moveItem(at: damagedTrash[0], to: other.location)
    let home = await store.libraryHome(root)
    func rollback(_ status: String) throws -> Backup {
        let id = UUID().uuidString
        let backup = Backup(id: id, date: Date(), label: "fixture-" + status, root: root.standardizedFileURL.path, folders: ["Main"], existed: ["Main"], before: LibraryState(), status: status)
        let directory = home.appendingPathComponent("backups/" + id)
        try fm.createDirectory(at: directory.appendingPathComponent("old/Main"), withIntermediateDirectories: true)
        try original.write(to: directory.appendingPathComponent("old/Main/settings.txt"))
        try JSONEncoder().encode(backup).write(to: directory.appendingPathComponent("backup.json"))
        return backup
    }
    let first = try rollback("committed"), second = try rollback("recovered"), pending = try rollback("applying")
    await rejectsAsync("pending recovery copy is protected from deletion") { try await store.trashBackups([first, pending], root: root) }
    check(try await store.backups(root).count == 3, "mixed pending batch leaves all rollback copies in place")
    let rollbackTrash = try await store.trashBackups([first, second], root: root)
    let remaining = try await store.backups(root)
    check(remaining.count == 1 && remaining[0].id == pending.id, "finished rollback copies can be trashed without deleting pending recovery")
    for (copy, trash) in zip([first, second], rollbackTrash) { try fm.moveItem(at: trash, to: home.appendingPathComponent("backups/" + copy.id)) }
    check(try Data(contentsOf: sentinel) == original && scanAddons(root).count == 1, "deleting backups does not change installed addons or saved variables")
    let batch = temp.appendingPathComponent("trash-rollback"), fakeTrash = temp.appendingPathComponent("trash-rollback-destination")
    try fm.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
    let locations = [batch.appendingPathComponent("first"), batch.appendingPathComponent("second")]
    for url in locations { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
    var attempts = 0
    rejects("a failed batch returns already moved copies") {
        _ = try trashCopies(locations, move: { source in
            attempts += 1
            if attempts == 2 { throw AppError("fixtureFailure") }
            let target = fakeTrash.appendingPathComponent(source.lastPathComponent)
            try fm.moveItem(at: source, to: target)
            return target
        })
    }
    check(try locations.allSatisfy { fm.fileExists(atPath: $0.path) } && fm.contentsOfDirectory(atPath: fakeTrash.path).isEmpty, "failed trash batch restores prior filesystem state")
}
