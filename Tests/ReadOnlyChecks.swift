import Foundation

func readOnlyChecks(_ temp: URL) async throws {
    let fm = FileManager.default, root = temp.appendingPathComponent("readonly/live/AddOns")
    try makeLocal(root, "LibSets", version: "broken")
    let current = root.appendingPathComponent("LibSets")
    let nested = current.appendingPathComponent("SearchUI/Keyboard")
    try fm.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("partial current".utf8).write(to: nested.appendingPathComponent("existing.lua"))
    for path in [current, current.appendingPathComponent("SearchUI"), nested] { try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path.path) }
    let saved = root.deletingLastPathComponent().appendingPathComponent("SavedVariables")
    try fm.createDirectory(at: saved, withIntermediateDirectories: true)
    let sentinel = saved.appendingPathComponent("LibSets.lua"), settings = Data("preserve player settings".utf8)
    try settings.write(to: sentinel)
    let store = Installer(home: temp.appendingPathComponent("readonly/state")), id = UUID().uuidString
    let home = await store.libraryHome(root), backupHome = home.appendingPathComponent("backups/" + id)
    let old = backupHome.appendingPathComponent("old/LibSets")
    try fm.createDirectory(at: old.appendingPathComponent("SearchUI/Keyboard"), withIntermediateDirectories: true)
    try Data("## Title: LibSets\n## APIVersion: 101051\n## Version: 1".utf8).write(to: old.appendingPathComponent("LibSets.addon"))
    let recoveredData = Data("complete original addon".utf8)
    try recoveredData.write(to: old.appendingPathComponent("SearchUI/Keyboard/missing.lua"))
    for path in [old, old.appendingPathComponent("SearchUI"), old.appendingPathComponent("SearchUI/Keyboard")] { try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path.path) }
    let backup = Backup(id: id, date: Date(), label: "readonly fixture", root: root.standardizedFileURL.path, folders: ["LibSets"], existed: ["LibSets"], before: LibraryState(sources: ["LibSets": Receipt(id: 2241, version: "1")]), status: "applying", hashes: try addonBackupHashes(backupHome.appendingPathComponent("old"), names: ["LibSets"]))
    try JSONEncoder().encode(backup).write(to: backupHome.appendingPathComponent("backup.json"))
    check(try await store.recover(root) == 1, "interrupted update can recover a read-only addon tree")
    check(try Data(contentsOf: current.appendingPathComponent("SearchUI/Keyboard/missing.lua")) == recoveredData, "read-only recovery restores missing files")
    check(!fm.fileExists(atPath: current.appendingPathComponent("SearchUI/Keyboard/existing.lua").path), "read-only recovery removes partial replacement files")
    check(try scanAddons(root).first?.primary?.version == "1", "recovery restores original addon manifest")
    check(try Data(contentsOf: sentinel) == settings, "permission recovery leaves SavedVariables untouched")
    check(try await store.state(root).sources["LibSets"]?.version == "1", "recovery restores source metadata")
    check(try await store.backups(root).first?.status == "recovered", "recovered transaction is not left pending")
    check(try await store.recover(root) == 0, "recovery does not repeat a completed transaction")
    check(try fm.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".eso-addons-") }.isEmpty, "read-only transaction cleanup leaves no staging folders")
    let mode = try fm.attributesOfItem(atPath: current.path)[.posixPermissions] as! Int
    let backupMode = try fm.attributesOfItem(atPath: old.path)[.posixPermissions] as! Int
    check(mode == 0o755 && backupMode == 0o555, "recovery adds only owner write access to the installed copy and preserves the backup")
    let outside = temp.appendingPathComponent("readonly/outside")
    try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: outside.path)
    let link = temp.appendingPathComponent("readonly/link")
    try fm.createSymbolicLink(at: link, withDestinationURL: outside)
    rejects("permission normalization rejects symlink roots") { try makeAddonDirectoriesWritable(link) }
    check(try fm.attributesOfItem(atPath: outside.path)[.posixPermissions] as! Int == 0o555, "permission normalization never follows a symlink")
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outside.path)
    try fm.removeItem(at: link)
    try removeAddonTree(temp.appendingPathComponent("readonly"))
}
