import Foundation
import CryptoKit
import Darwin

struct SnapshotAddon: Codable, Sendable {
    let folder: String
    let title: String
    let version: String
    let source: Int?
}

struct Snapshot: Codable, Identifiable, Sendable {
    let format: Int
    let id: String
    let date: Date
    let origin: String
    let items: [String]
    let hashes: [String: String]
    let addons: [SnapshotAddon]
    let state: LibraryState
    var name: String? = nil
}

struct SnapshotChoice: Identifiable {
    let snapshot: Snapshot
    let location: URL
    var id: String { snapshot.id }
}

private struct SettingsTransaction: Codable {
    let root: String
    let items: [String]
    let existed: [String]
    let hashes: [String: String]
    let before: LibraryState
}

func validSnapshotItem(_ path: String) -> Bool {
    let parts = path.components(separatedBy: "/")
    if parts.count == 1 { return ["UserSettings.txt", "AddOnSettings.txt"].contains(path) }
    guard parts.count == 2, safeComponent(parts[1]) else { return false }
    return parts[0] == "AddOns" || (parts[0] == "SavedVariables" && (parts[1].hasSuffix(".lua") || parts[1].hasSuffix(".lua.bak")))
}

private func fileDigest(_ file: URL) throws -> String {
    try requireRegularFile(file)
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

func addonBackupHashes(_ payload: URL, names: [String]) throws -> [String: String] {
    try snapshotHashes(payload, items: names.map { "AddOns/" + $0 }, addonRoot: true)
}

private func snapshotHashes(_ payload: URL, items: [String], addonRoot: Bool = false) throws -> [String: String] {
    guard items.count <= 10_000, items.allSatisfy(validSnapshotItem), Set(items.map { $0.lowercased() }).count == items.count else { throw AppError("invalidSnapshot") }
    try requireDirectory(payload)
    var hashes = [String: String](), total: Int64 = 0
    for item in items {
        let root = payload.appendingPathComponent(addonRoot ? String(item.dropFirst(7)) : item)
        try requireDirectory(root.deletingLastPathComponent())
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        if item.hasPrefix("AddOns/"), attributes[.type] as? FileAttributeType != .typeDirectory { throw AppError("invalidSnapshot") }
        let files: [URL]
        if attributes[.type] as? FileAttributeType == .typeDirectory {
            guard item.hasPrefix("AddOns/") else { throw AppError("invalidSnapshot") }
            try validateTree(root)
            var found = [URL]()
            var enumerationError: Error?
            guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, error in enumerationError = error; return false }) else { throw AppError("invalidSnapshot") }
            for case let file as URL in entries {
                if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { found.append(file) }
                guard found.count <= 100_000 else { throw AppError("invalidSnapshot") }
            }
            if let enumerationError { throw enumerationError }
            files = found
        } else { files = [root] }
        for file in files {
            let base = payload.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
            let path = file.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
            guard path.hasPrefix(base + "/") else { throw AppError("invalidSnapshot") }
            let relative = (addonRoot ? "AddOns/" : "") + String(path.dropFirst(base.count + 1))
            guard relative.components(separatedBy: "/").allSatisfy({ $0 != "." && $0 != ".." && safeComponent("x" + $0) }) else { throw AppError("invalidSnapshot") }
            total += Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard total <= 8_000_000_000, hashes.count < 100_000 else { throw AppError("invalidSnapshot") }
            hashes[relative] = try fileDigest(file)
        }
    }
    return hashes
}

extension Installer {
    func createSnapshot(root: URL, destination: URL, includeAddons: Bool, name: String = "", canModify: () throws -> Void = { try RuntimeSafety.requireIdle() }) throws -> SnapshotChoice {
        try canModify()
        let fd = try lock(root); defer { close(fd) }
        _ = try recoverLocked(root, canModify: canModify)
        try canModify()
        let fm = FileManager.default, live = root.deletingLastPathComponent()
        try requireDirectory(live); try requireDirectory(destination)
        let title = try backupName(name)
        guard destination.path != live.path, !destination.path.hasPrefix(live.path + "/") else { throw AppError("snapshotInsideGame") }
        let backupFD = try lockBackupDirectory(destination); defer { close(backupFD) }
        let locals = try scanAddons(root)
        let current = try state(root)
        var items = includeAddons ? locals.map { "AddOns/" + $0.folder } : []
        let saved = live.appendingPathComponent("SavedVariables")
        if fm.fileExists(atPath: saved.path) {
            try requireDirectory(saved)
            items += try fm.contentsOfDirectory(at: saved, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasSuffix(".lua") || $0.lastPathComponent.hasSuffix(".lua.bak") }.map { "SavedVariables/" + $0.lastPathComponent }
        }
        items += ["UserSettings.txt", "AddOnSettings.txt"].filter { fm.fileExists(atPath: live.appendingPathComponent($0).path) }
        let id = UUID().uuidString
        let staging = destination.appendingPathComponent(".eso-snapshot-" + id)
        let location = destination.appendingPathComponent("ESO-Backup-" + id)
        try fm.createDirectory(at: staging.appendingPathComponent("payload"), withIntermediateDirectories: true)
        defer { if fm.fileExists(atPath: staging.path) { try? removeAddonTree(staging) } }
        let hashes = try snapshotHashes(live, items: items)
        try copySnapshotItems(items, from: live, to: staging.appendingPathComponent("payload"))
        let copiedHashes = try snapshotHashes(staging.appendingPathComponent("payload"), items: items)
        guard copiedHashes == hashes else { throw AppError("settingsChanged", "snapshot: " + Set(hashes.keys).symmetricDifference(copiedHashes.keys).sorted().joined(separator: ", ")) }
        let inventory = locals.map { SnapshotAddon(folder: $0.folder, title: $0.primary?.title ?? $0.folder, version: $0.primary?.version ?? "", source: current.sources[$0.folder]?.id) }
        let snapshot = Snapshot(format: 1, id: id, date: Date(), origin: live.path, items: items.sorted(), hashes: hashes, addons: inventory, state: current, name: title)
        try JSONEncoder().encode(snapshot).write(to: staging.appendingPathComponent("snapshot.json"), options: .atomic)
        try canModify()
        try fm.moveItem(at: staging, to: location)
        return SnapshotChoice(snapshot: snapshot, location: location)
    }
    func readSnapshot(_ location: URL) throws -> SnapshotChoice {
        let choice = try snapshotMetadata(location)
        guard try snapshotHashes(location.appendingPathComponent("payload"), items: choice.snapshot.items) == choice.snapshot.hashes else { throw AppError("invalidSnapshot") }
        return choice
    }
    func restoreSnapshot(_ choice: SnapshotChoice, root: URL, canModify: () throws -> Void = { try RuntimeSafety.requireIdle() }, afterReplace: () throws -> Void = {}) throws {
        try canModify()
        let fd = try lock(root); defer { close(fd) }
        _ = try recoverLocked(root, canModify: canModify)
        try canModify()
        let verified = try readSnapshot(choice.location)
        guard verified.snapshot.id == choice.snapshot.id, verified.snapshot.hashes == choice.snapshot.hashes,
              verified.snapshot.items == choice.snapshot.items else { throw AppError("settingsChanged") }
        let snapshot = verified.snapshot, fm = FileManager.default
        for item in snapshot.items { try requireUnlockedTree(choice.location.appendingPathComponent("payload/" + item)) }
        let live = root.deletingLastPathComponent(), transaction = libraryHome(root).appendingPathComponent("settings-transaction")
        try requireDirectory(live)
        guard !choice.location.path.hasPrefix(live.path + "/"), choice.location.path != live.path else { throw AppError("snapshotInsideGame") }
        let old = transaction.appendingPathComponent("old")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        let existed = snapshot.items.filter { fm.fileExists(atPath: live.appendingPathComponent($0).path) }
        let incoming = transaction.appendingPathComponent("new")
        do {
            try fm.createDirectory(at: incoming, withIntermediateDirectories: true)
            try copySnapshotItems(snapshot.items, from: choice.location.appendingPathComponent("payload"), to: incoming)
            let stagedHashes = try snapshotHashes(incoming, items: snapshot.items)
            guard stagedHashes == snapshot.hashes else { throw AppError("settingsChanged", "restore staging: " + Set(stagedHashes.keys).symmetricDifference(snapshot.hashes.keys).sorted().joined(separator: ", ")) }
            for item in snapshot.items { try requireUnlockedTree(incoming.appendingPathComponent(item)) }
            let hashes = try snapshotHashes(live, items: existed)
            try copySnapshotItems(existed, from: live, to: old)
            guard try snapshotHashes(old, items: existed) == hashes else { throw AppError("settingsChanged") }
            let journal = SettingsTransaction(root: root.standardizedFileURL.path, items: snapshot.items, existed: existed, hashes: hashes, before: try state(root))
            let names = snapshot.items.filter { $0.hasPrefix("AddOns/") }.map { String($0.dropFirst(7)) }
            if !names.isEmpty { try validateDependencies(staged: incoming.appendingPathComponent("AddOns"), names: names, root: root) }
            try prepareReplacement(snapshot.items.map { live.appendingPathComponent($0) })
            try canModify()
            try JSONEncoder().encode(journal).write(to: transaction.appendingPathComponent("transaction.json"), options: .atomic)
        } catch { try? clearSettingsTransaction(transaction); throw error }
        do {
            try replaceSnapshotItems(snapshot.items, from: incoming, to: live)
            try afterReplace()
            var desired = try state(root)
            for item in snapshot.items where item.hasPrefix("AddOns/") {
                let folder = String(item.dropFirst(7))
                desired.sources[folder] = snapshot.state.sources[folder]
            }
            desired.ignored.formUnion(snapshot.state.ignored)
            try save(desired, root: root)
            try Data().write(to: transaction.appendingPathComponent("committed"), options: .atomic)
            try? clearSettingsTransaction(transaction)
        } catch {
            do { _ = try recoverTransfer(root) }
            catch { throw AppError("recoveryFailed", transaction.path) }
            throw error
        }
    }
    func recoverTransfer(_ root: URL) throws -> Int {
        let fm = FileManager.default, transaction = libraryHome(root).appendingPathComponent("settings-transaction")
        guard fm.fileExists(atPath: transaction.path) else { return 0 }
        try requireDirectory(transaction)
        if fm.fileExists(atPath: transaction.appendingPathComponent("committed").path) { try clearSettingsTransaction(transaction); return 0 }
        let file = transaction.appendingPathComponent("transaction.json")
        if !fm.fileExists(atPath: file.path) { try clearSettingsTransaction(transaction); return 0 }
        try requireRegularFile(file)
        let journal = try JSONDecoder().decode(SettingsTransaction.self, from: Data(contentsOf: file))
        let old = transaction.appendingPathComponent("old")
        guard journal.root == root.standardizedFileURL.path, journal.items.allSatisfy(validSnapshotItem), journal.existed.allSatisfy(journal.items.contains),
              try snapshotHashes(old, items: journal.existed) == journal.hashes else { throw AppError("invalidSnapshot") }
        try replaceSnapshotItems(journal.items, from: old, to: root.deletingLastPathComponent())
        try save(journal.before, root: root)
        try Data().write(to: transaction.appendingPathComponent("committed"), options: .atomic)
        try clearSettingsTransaction(transaction)
        return 1
    }
}

private func clearSettingsTransaction(_ transaction: URL) throws {
    let fm = FileManager.default
    try makeAddonDirectoriesWritable(transaction)
    for name in ["old", "new"] {
        let path = transaction.appendingPathComponent(name)
        if fm.fileExists(atPath: path.path) { try removeAddonTree(path) }
    }
    try removeAddonTree(transaction)
}

private func copySnapshotItems(_ items: [String], from source: URL, to target: URL) throws {
    for item in items {
        let destination = target.appendingPathComponent(item)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try requireDirectory(destination.deletingLastPathComponent())
        try FileManager.default.copyItem(at: source.appendingPathComponent(item), to: destination)
    }
}

private func replaceSnapshotItems(_ items: [String], from source: URL, to target: URL) throws {
    let fm = FileManager.default
    for item in items { guard validSnapshotItem(item) else { throw AppError("invalidSnapshot") } }
    for item in items {
        let destination = target.appendingPathComponent(item)
        if fm.fileExists(atPath: destination.path) {
            try requireUnlocked(destination)
            if try destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { try makeAddonDirectoriesWritable(destination) }
        }
    }
    for item in items {
        guard validSnapshotItem(item) else { throw AppError("invalidSnapshot") }
        let destination = target.appendingPathComponent(item), incoming = source.appendingPathComponent(item)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try requireDirectory(destination.deletingLastPathComponent())
        if fm.fileExists(atPath: destination.path) {
            let attrs = try fm.attributesOfItem(atPath: destination.path)
            if attrs[.type] as? FileAttributeType == .typeDirectory { try removeAddonTree(destination) }
            else { try requireRegularFile(destination); try fm.removeItem(at: destination) }
        }
        if fm.fileExists(atPath: incoming.path) {
            try fm.copyItem(at: incoming, to: destination)
            if item.hasPrefix("AddOns/") { try makeAddonDirectoriesWritable(destination) }
        }
    }
}
