import Foundation
import Darwin

struct BackupRemoval: Identifiable {
    let id = UUID()
    var backups: [Backup] = []
    var snapshots: [SnapshotChoice] = []
    var count: Int { backups.count + snapshots.count }
}

func backupName(_ raw: String) throws -> String? {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard name.count <= 120, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw AppError("invalidBackupName") }
    return name.isEmpty ? nil : name
}

func snapshotMetadata(_ location: URL) throws -> SnapshotChoice {
    try requireDirectory(location)
    let file = location.appendingPathComponent("snapshot.json")
    try requireRegularFile(file)
    guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16_000_000 else { throw AppError("invalidSnapshot") }
    let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
    guard snapshot.format == 1, UUID(uuidString: snapshot.id) != nil else { throw AppError("invalidSnapshot") }
    if let name = snapshot.name, try backupName(name) != name { throw AppError("invalidSnapshot") }
    return SnapshotChoice(snapshot: snapshot, location: location)
}

func lockBackupDirectory(_ directory: URL) throws -> Int32 {
    try requireDirectory(directory)
    let fd = Darwin.open(directory.appendingPathComponent(".eso-backups.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw AppError("folderLocked") }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw AppError("folderLocked") }
    return fd
}

func trashCopies(_ locations: [URL], move: (URL) throws -> URL = { source in
    var result: NSURL?
    try FileManager.default.trashItem(at: source, resultingItemURL: &result)
    guard let result else { throw AppError("trashRecoveryFailed", source.path) }
    return result as URL
}, restore: (URL, URL) throws -> Void = { trash, source in try FileManager.default.moveItem(at: trash, to: source) }) throws -> [URL] {
    var moved: [(source: URL, trash: URL)] = []
    do {
        for location in locations { moved.append((location, try move(location))) }
    } catch {
        var remaining = [String]()
        for item in moved.reversed() {
            do { try restore(item.trash, item.source) }
            catch { remaining.append(item.trash.path) }
        }
        if !remaining.isEmpty { throw AppError("trashRecoveryFailed", remaining.joined(separator: "\n")) }
        throw error
    }
    return moved.map(\.trash)
}

extension Installer {
    private func managedSnapshot(_ choice: SnapshotChoice, directory: URL) throws -> SnapshotChoice {
        let expected = directory.appendingPathComponent("ESO-Backup-" + choice.id)
        guard UUID(uuidString: choice.id) != nil, choice.location.standardizedFileURL.path == expected.standardizedFileURL.path else { throw AppError("invalidSnapshot") }
        let fresh = try snapshotMetadata(expected)
        guard fresh.id == choice.id, fresh.snapshot.date == choice.snapshot.date else { throw AppError("invalidSnapshot") }
        return fresh
    }
    func renameSnapshot(_ choice: SnapshotChoice, name: String, directory: URL) throws -> SnapshotChoice {
        let fd = try lockBackupDirectory(directory); defer { close(fd) }
        let fresh = try managedSnapshot(choice, directory: directory)
        var snapshot = fresh.snapshot
        snapshot.name = try backupName(name)
        try JSONEncoder().encode(snapshot).write(to: fresh.location.appendingPathComponent("snapshot.json"), options: .atomic)
        return SnapshotChoice(snapshot: snapshot, location: fresh.location)
    }
    @discardableResult func trashSnapshots(_ selected: [SnapshotChoice], directory: URL) throws -> [URL] {
        let fd = try lockBackupDirectory(directory); defer { close(fd) }
        guard !selected.isEmpty, Set(selected.map(\.id)).count == selected.count else { throw AppError("invalidSnapshot") }
        let locations = try selected.map { try managedSnapshot($0, directory: directory).location }
        return try trashCopies(locations)
    }
    @discardableResult func trashBackups(_ selected: [Backup], root: URL) throws -> [URL] {
        let fd = try lock(root); defer { close(fd) }
        guard !selected.isEmpty, Set(selected.map(\.id)).count == selected.count else { throw AppError("invalidBackup") }
        let locations = try selected.map { chosen -> URL in
            guard UUID(uuidString: chosen.id) != nil, chosen.root == root.standardizedFileURL.path else { throw AppError("invalidBackup") }
            let location = libraryHome(root).appendingPathComponent("backups").appendingPathComponent(chosen.id)
            try requireDirectory(location)
            let file = location.appendingPathComponent("backup.json")
            try requireRegularFile(file)
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4_000_000 else { throw AppError("invalidBackup") }
            let fresh = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: file))
            guard fresh.id == chosen.id, fresh.root == chosen.root, fresh.date == chosen.date,
                  ["committed", "recovered"].contains(fresh.status) else { throw AppError("invalidBackup") }
            return location
        }
        return try trashCopies(locations)
    }
}
