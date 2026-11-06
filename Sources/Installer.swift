import Foundation
import CryptoKit
import Darwin
import zlib

enum ZipArchive {
    struct Entry { let name: String; let offset: Int; let compressed: Int; let expanded: Int; let method: Int; let crc: Int }
    static func paths(_ data: Data) throws -> [String] { try entries(data).map(\.name) }
    static func entries(_ data: Data) throws -> [Entry] {
        func bad() -> AppError { AppError("unsafeArchive") }
        func u16(_ n: Int) throws -> Int { guard n >= 0 && n + 2 <= data.count else { throw bad() }; return Int(data[n]) | Int(data[n + 1]) << 8 }
        func u32(_ n: Int) throws -> Int { try u16(n) | u16(n + 2) << 16 }
        guard data.count >= 22 else { throw bad() }
        var end: Int?
        for i in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try u32(i) == 0x06054b50, try i + 22 + u16(i + 20) == data.count { end = i; break }
        }
        guard let end, try u16(end + 4) == 0, try u16(end + 6) == 0, try u16(end + 8) == u16(end + 10) else { throw bad() }
        let count = try u16(end + 10), size = try u32(end + 12), start = try u32(end + 16)
        guard count > 0 && count < 30_000, start + size == end else { throw bad() }
        var offset = start, total = 0
        var entries = [Entry](), seen = Set<String>()
        for _ in 0..<count {
            guard try u32(offset) == 0x02014b50 else { throw bad() }
            let flags = try u16(offset + 8), method = try u16(offset + 10), expanded = try u32(offset + 24)
            let length = try u16(offset + 28), extra = try u16(offset + 30), comment = try u16(offset + 32)
            let attributes = try u32(offset + 38), local = try u32(offset + 42)
            let next = offset + 46 + length + extra + comment
            guard flags & 1 == 0, [0, 8].contains(method), length > 0, next <= end, expanded <= 128_000_000, let name = String(data: data[(offset + 46)..<(offset + 46 + length)], encoding: .utf8) else { throw bad() }
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            let mode = (attributes >> 16) & 0xf000
            guard !name.hasPrefix("/"), parts.count <= 40, name.utf8.count < 1024, parts.enumerated().allSatisfy({ i, p in (i == parts.count - 1 && p.isEmpty && name.hasSuffix("/")) || safeComponent(String(p)) }), [0, 0x8000, 0x4000].contains(mode) else { throw bad() }
            let key = name.trimmingCharacters(in: CharacterSet(charactersIn: "/")).precomposedStringWithCanonicalMapping.lowercased()
            guard seen.insert(key).inserted else { throw bad() }
            guard local >= 0 && local + 30 <= start, try u32(local) == 0x04034b50, try u16(local + 8) == method, try u16(local + 6) == flags else { throw bad() }
            let localLength = try u16(local + 26), localExtra = try u16(local + 28)
            guard local + 30 + localLength + localExtra + (try u32(offset + 20)) <= start, localLength == length,
                  data[(local + 30)..<(local + 30 + localLength)] == data[(offset + 46)..<(offset + 46 + length)] else { throw bad() }
            total += expanded
            guard total <= 512_000_000 else { throw bad() }
            entries.append(Entry(name: name, offset: local + 30 + localLength + localExtra, compressed: try u32(offset + 20), expanded: expanded, method: method, crc: try u32(offset + 16))); offset = next
        }
        guard offset == end else { throw bad() }
        return entries
    }
    static func extract(_ file: URL, into destination: URL, expected: [String]) throws {
        let data = try Data(contentsOf: file), records = try entries(data), names = records.map(\.name)
        let roots = Set(names.compactMap { $0.split(separator: "/").first.map(String.init) })
        let mismatch = AppError("unexpectedFolders", "Expected: \(expected.sorted().joined(separator: ", "))\nFound: \(roots.sorted().joined(separator: ", "))")
        guard !expected.isEmpty, expected.allSatisfy(safeComponent), expected.allSatisfy(roots.contains) else { throw mismatch }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in records {
            let target = destination.appendingPathComponent(entry.name)
            guard target.standardizedFileURL.path.hasPrefix(destination.standardizedFileURL.path + "/") else { throw AppError("unsafeArchive") }
            if entry.name.hasSuffix("/") {
                guard entry.expanded == 0 else { throw AppError("unsafeArchive") }
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true); continue
            }
            let compressed = Data(data[entry.offset..<(entry.offset + entry.compressed)])
            var decoded: Data
            if entry.method == 0 {
                guard entry.compressed == entry.expanded else { throw AppError("unsafeArchive") }
                decoded = compressed
            } else {
                decoded = Data(count: entry.expanded + 1)
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw AppError("archiveError") }
                defer { inflateEnd(&stream) }
                let status = decoded.withUnsafeMutableBytes { output in
                    compressed.withUnsafeBytes { input -> Int32 in
                        stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                        stream.avail_in = uInt(entry.compressed)
                        stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(entry.expanded + 1)
                        return inflate(&stream, Z_FINISH)
                    }
                }
                guard status == Z_STREAM_END, stream.total_out == entry.expanded, stream.total_in == entry.compressed else { throw AppError("archiveError", entry.name) }
                decoded.count = entry.expanded
            }
            let checksum = decoded.withUnsafeBytes { zlib.crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(decoded.count)) }
            guard checksum == entry.crc else { throw AppError("checksumError", entry.name) }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try decoded.write(to: target, options: .withoutOverwriting)
        }
        for root in roots where !expected.contains(root) {
            let files = records.filter { $0.name.hasPrefix(root + "/") && !$0.name.hasSuffix("/") }
            for file in files {
                let url = destination.appendingPathComponent(file.name)
                guard file.expanded <= 64_000, ["txt", "md", "rtf"].contains(url.pathExtension.lowercased()) else { throw mismatch }
                if url.pathExtension.lowercased() == "txt", let text = try? String(contentsOf: url, encoding: .utf8), Manifest(name: url.deletingPathExtension().lastPathComponent, text: text) != nil { throw mismatch }
            }
        }
        try validateTree(destination)
        for folder in expected { try requireDirectory(destination.appendingPathComponent(folder)) }
    }
}

func validateTree(_ root: URL) throws {
    try requireDirectory(root)
    let fm = FileManager.default
    var failure: Error?
    guard let entries = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], errorHandler: { _, error in failure = error; return false }) else { throw AppError("unsafeFolder", root.path) }
    for case let file as URL in entries {
        let attributes = try fm.attributesOfItem(atPath: file.path)
        guard let type = attributes[.type] as? FileAttributeType, [.typeRegular, .typeDirectory].contains(type), (attributes[.referenceCount] as? Int ?? 1) <= 1 || type == .typeDirectory else { throw AppError("unsafeFolder", file.path) }
    }
    if let failure { throw failure }
}

func requireUnlocked(_ path: URL) throws {
    var info = stat()
    guard lstat(path.path, &info) == 0 else { throw AppError("unsafeFolder", path.path) }
    guard info.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) == 0 else { throw AppError("addonLocked", path.path) }
}

func requireUnlockedTree(_ root: URL) throws {
    try requireUnlocked(root)
    guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { return }
    try validateTree(root)
    var failure: Error?
    guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, error in failure = error; return false }) else { throw AppError("unsafeFolder", root.path) }
    for case let path as URL in entries { try requireUnlocked(path) }
    if let failure { throw failure }
}

func makeAddonDirectoriesWritable(_ root: URL) throws {
    try validateTree(root)
    let fm = FileManager.default
    var paths = [root], failure: Error?
    try requireUnlocked(root)
    guard let entries = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], errorHandler: { _, error in failure = error; return false }) else { throw AppError("unsafeFolder", root.path) }
    for case let path as URL in entries {
        try requireUnlocked(path)
        if try path.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { paths.append(path) }
    }
    if let failure { throw failure }
    var changes: [(URL, Int)] = []
    for path in paths {
        let attributes = try fm.attributesOfItem(atPath: path.path)
        guard let mode = attributes[.posixPermissions] as? Int, let owner = attributes[.ownerAccountID] as? NSNumber else { throw AppError("unsafeFolder", path.path) }
        guard mode & 0o200 == 0 else { continue }
        guard owner.uint32Value == getuid() else { throw AppError("addonReadOnly", path.path) }
        changes.append((path, mode | 0o200))
    }
    for (path, mode) in changes { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: path.path) }
    for path in paths where !fm.isWritableFile(atPath: path.path) { throw AppError("addonReadOnly", path.path) }
}

func removeAddonTree(_ root: URL) throws {
    try makeAddonDirectoriesWritable(root)
    try FileManager.default.removeItem(at: root)
}

struct Backup: Codable, Identifiable, Sendable {
    let id: String
    let date: Date
    let label: String
    let root: String
    let folders: [String]
    let existed: [String]
    let before: LibraryState
    var status: String
    var hashes: [String: String]? = nil
}

struct InstallPlan: Sendable {
    let addons: [Addon]
    let missing: [String]
    let requestedIDs: Set<Int>
}

func dependencyPlan(_ requested: [Addon], catalog: [Addon], locals: [LocalAddon], sources: [String: Receipt]) throws -> InstallPlan {
    let manifests = locals.flatMap(\.manifests)
    var selected = Dictionary(uniqueKeysWithValues: requested.map { ($0.id, $0) })
    var pending = requested, unresolved = Set<String>()
    while !pending.isEmpty {
        let addon = pending.removeFirst()
        guard addon.supported else { throw AppError("unsupportedAddon", addon.title) }
        for dependency in addon.dependencies {
            if dependency.satisfied(by: manifests) { continue }
            let selectedFolders: [RemoteFolder] = selected.values.flatMap { $0.addons ?? [] }
            if selectedFolders.contains(where: dependency.matches) { continue }
            let matches = catalog.filter { $0.categoryId != 157 && $0.supported && ($0.addons ?? []).contains(where: dependency.matches) }
            let preferred = resolveSource(dependency.name, catalog: matches, sources: sources)
            guard let match = preferred else { unresolved.insert(dependency.display); continue }
            if selected[match.id] == nil { selected[match.id] = match; pending.append(match) }
        }
        guard selected.count <= 200 else { throw AppError("dependencyLimit") }
    }
    var owners = [String: Int]()
    for addon in selected.values {
        for name in addon.folders {
            let key = name.precomposedStringWithCanonicalMapping.lowercased()
            if let owner = owners[key], owner != addon.id { throw AppError("folderConflict", name) }
            owners[key] = addon.id
        }
    }
    return InstallPlan(addons: selected.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }, missing: unresolved.sorted(), requestedIDs: Set(requested.map(\.id)))
}

actor Installer {
    let home: URL
    private let fm = FileManager.default
    init(home: URL) { self.home = home }
    func libraryHome(_ root: URL) -> URL {
        let hash = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return home.appendingPathComponent(hash)
    }
    func state(_ root: URL) throws -> LibraryState {
        let file = libraryHome(root).appendingPathComponent("state.json")
        guard fm.fileExists(atPath: file.path) else { return LibraryState() }
        return try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: file))
    }
    func save(_ state: LibraryState, root: URL) throws {
        let folder = libraryHome(root)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: folder.appendingPathComponent("state.json"), options: .atomic)
    }
    func backups(_ root: URL) throws -> [Backup] {
        let dir = libraryHome(root).appendingPathComponent("backups")
        guard fm.fileExists(atPath: dir.path) else { return [] }
        return try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).compactMap { folder in
            let file = folder.appendingPathComponent("backup.json")
            guard fm.fileExists(atPath: file.path) else { return nil }
            do {
                try requireRegularFile(file)
                let backup = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: file))
                guard backup.id == folder.lastPathComponent, UUID(uuidString: backup.id) != nil, backup.root == root.standardizedFileURL.path else { throw AppError("invalidBackup", file.path) }
                return backup
            } catch { throw AppError("invalidBackup", file.path + "\n" + error.localizedDescription) }
        }.sorted { $0.date > $1.date }
    }
    func pruneBackups(_ root: URL, keep: Int) throws {
        guard keep > 0 else { return }
        let fd = try lock(root); defer { close(fd) }
        let finished = try backups(root).filter { ["committed", "recovered"].contains($0.status) }
        for backup in finished.dropFirst(keep) {
            guard UUID(uuidString: backup.id) != nil, backup.root == root.standardizedFileURL.path else { throw AppError("invalidBackup") }
            let location = backupHome(backup, root)
            try requireDirectory(location)
            try removeAddonTree(location)
        }
    }
    private func backupHome(_ backup: Backup, _ root: URL) -> URL { libraryHome(root).appendingPathComponent("backups").appendingPathComponent(backup.id) }
    private func write(_ backup: Backup, _ root: URL) throws {
        try JSONEncoder().encode(backup).write(to: backupHome(backup, root).appendingPathComponent("backup.json"), options: .atomic)
    }
    func lock(_ root: URL) throws -> Int32 {
        try requireDirectory(root)
        let fd = Darwin.open(root.appendingPathComponent(".eso-addons.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw AppError("folderLocked") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw AppError("folderLocked") }
        return fd
    }
    func recover(_ root: URL, canModify: () throws -> Void = { try RuntimeSafety.requireIdle() }) throws -> Int {
        let fd = try lock(root); defer { close(fd) }
        return try recoverLocked(root, canModify: canModify)
    }
    func recoverLocked(_ root: URL, canModify: () throws -> Void = { try RuntimeSafety.requireIdle() }) throws -> Int {
        let pending = try backups(root).reversed().filter { $0.status == "applying" }
        if !pending.isEmpty || fm.fileExists(atPath: libraryHome(root).appendingPathComponent("settings-transaction").path) { try canModify() }
        var count = try recoverTransfer(root)
        for var backup in pending {
            try canModify()
            try restoreOld(backup, root)
            backup.status = "recovered"; try write(backup, root); count += 1
        }
        return count
    }
    func install(_ plan: InstallPlan, root: URL, client: CatalogClient, parallelism: Int = 3, beforeCommit: @Sendable () throws -> Void = {}, progress: @escaping @Sendable (String) async -> Void) async throws {
        let fd = try lock(root); defer { close(fd) }
        _ = try recoverLocked(root)
        guard plan.missing.isEmpty else { throw AppError("missingDependencies", plan.missing.joined(separator: ", ")) }
        let temp = fm.temporaryDirectory.appendingPathComponent("eso-addons-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? removeAddonTree(temp) }
        let staged = temp.appendingPathComponent("staged")
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        let archives = try await parallelDownloads(plan.addons, limit: parallelism) { addon in
            await progress(addon.title)
            do { return try await client.download(addon, to: temp) }
            catch { throw packageError(error, addon: addon, stage: "download") }
        }
        for addon in plan.addons {
            try Task.checkCancellation()
            guard let zip = archives[addon.id] else { throw AppError("archiveError", addon.title) }
            let unpacked = temp.appendingPathComponent("unpacked-\(addon.id)")
            do { try ZipArchive.extract(zip, into: unpacked, expected: addon.folders) }
            catch { throw packageError(error, addon: addon, stage: "extract") }
            for name in addon.folders { try fm.moveItem(at: unpacked.appendingPathComponent(name), to: staged.appendingPathComponent(name)) }
        }
        let newLocals = try scanAddons(staged)
        for addon in plan.addons {
            for name in addon.folders {
                guard newLocals.contains(where: { $0.folder == name && !$0.manifests.isEmpty }) else { throw AppError("invalidManifest", name) }
            }
        }
        try preservePrices(root: root, staged: staged)
        var next = try state(root)
        for addon in plan.addons { for name in addon.folders { next.sources[name] = Receipt(id: addon.id, version: addon.version) } }
        try apply(staged: staged, names: plan.addons.flatMap(\.folders), desired: next, root: root, label: plan.addons.map(\.title).joined(separator: ", "), beforeCommit: beforeCommit)
    }
    @discardableResult func remove(folders: [String], root: URL) throws -> [URL] {
        let fd = try lock(root); defer { close(fd) }
        _ = try recoverLocked(root)
        guard !folders.isEmpty, folders.allSatisfy(safeComponent), Set(folders.map { $0.lowercased() }).count == folders.count else { throw AppError("unexpectedFolders") }
        for name in folders { try validateTree(root.appendingPathComponent(name)) }
        let dependents = removalDependents(folders: folders, locals: try scanAddons(root))
        guard dependents.isEmpty else { throw AppError("addonRequired", dependents.joined(separator: "\n")) }
        var desired = try state(root)
        for name in folders { desired.sources.removeValue(forKey: name) }
        var moved: [(source: URL, trash: URL)] = []
        do {
            for name in folders {
                let source = root.appendingPathComponent(name)
                var trash: NSURL?
                try fm.trashItem(at: source, resultingItemURL: &trash)
                guard let trash else { throw AppError("trashRecoveryFailed", name) }
                moved.append((source, trash as URL))
            }
            try save(desired, root: root)
        } catch {
            var remaining = [String]()
            for item in moved.reversed() {
                do { try fm.moveItem(at: item.trash, to: item.source) }
                catch { remaining.append(item.trash.path) }
            }
            if !remaining.isEmpty { throw AppError("trashRecoveryFailed", remaining.joined(separator: "\n")) }
            throw error
        }
        return moved.map(\.trash)
    }
    func preservePrices(root: URL, staged: URL) throws {
        let name = "TamrielTradeCentre", existing = root.appendingPathComponent(name), target = staged.appendingPathComponent(name)
        guard fm.fileExists(atPath: existing.path), fm.fileExists(atPath: target.path) else { return }
        try validateTree(existing)
        for file in try fm.contentsOfDirectory(at: existing, includingPropertiesForKeys: nil) where file.pathExtension == "lua" && (file.lastPathComponent.hasPrefix("PriceTable") || file.lastPathComponent.hasPrefix("ItemLookUpTable")) {
            let copy = target.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: copy.path) { try fm.removeItem(at: copy) }
            try fm.copyItem(at: file, to: copy)
        }
    }
    func restore(_ selected: Backup, root: URL) throws {
        let fd = try lock(root); defer { close(fd) }
        _ = try recoverLocked(root)
        guard selected.root == root.standardizedFileURL.path, selected.status == "committed", safeComponent(selected.id) else { throw AppError("invalidBackup") }
        let file = backupHome(selected, root).appendingPathComponent("backup.json")
        try requireRegularFile(file)
        let fresh = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: file))
        guard fresh.id == selected.id, fresh.date == selected.date, fresh.status == "committed" else { throw AppError("invalidBackup") }
        let old = try verifiedBackup(fresh, root)
        var desired = try state(root)
        for name in fresh.folders { desired.sources[name] = fresh.before.sources[name] }
        try apply(staged: old, names: fresh.folders, desired: desired, root: root, label: "↩ " + fresh.label)
    }

    func validateDependencies(staged: URL, names: [String], root: URL) throws {
        let current = try scanAddons(root), replacing = Set(names.map { $0.lowercased() })
        let incoming = try scanAddons(staged).filter { replacing.contains($0.folder.lowercased()) }
        let retained = current.filter { !replacing.contains($0.folder.lowercased()) }
        let before = current.flatMap(\.manifests), after = retained.flatMap(\.manifests) + incoming.flatMap(\.manifests)
        let missing = (incoming + retained).flatMap { local in local.manifests.flatMap { manifest in
            manifest.dependencies.filter { !$0.satisfied(by: after) && (replacing.contains(local.folder.lowercased()) || $0.satisfied(by: before)) }.map { local.folder + " → " + $0.display }
        } }
        guard missing.isEmpty else { throw AppError("missingDependencies", Set(missing).sorted().joined(separator: "\n")) }
    }

    func prepareReplacement(_ paths: [URL]) throws {
        for path in paths where fm.fileExists(atPath: path.path) {
            try requireUnlocked(path)
            if try path.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { try makeAddonDirectoriesWritable(path) }
            guard fm.isWritableFile(atPath: path.deletingLastPathComponent().path) else { throw AppError("addonReadOnly", path.path) }
        }
    }
    private func apply(staged: URL, names: [String], desired: LibraryState, root: URL, label: String, beforeCommit: @Sendable () throws -> Void = {}) throws {
        guard names.allSatisfy(safeComponent), Set(names.map { $0.lowercased() }).count == names.count else { throw AppError("unexpectedFolders") }
        try validateTree(staged)
        for name in names where fm.fileExists(atPath: staged.appendingPathComponent(name).path) { try requireUnlockedTree(staged.appendingPathComponent(name)) }
        try validateDependencies(staged: staged, names: names, root: root)
        try prepareReplacement(names.map { root.appendingPathComponent($0) })
        let id = UUID().uuidString
        let location = libraryHome(root).appendingPathComponent("backups").appendingPathComponent(id)
        let old = location.appendingPathComponent("old")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        var journalWritten = false
        defer { if !journalWritten { try? removeAddonTree(location) } }
        var existed = [String]()
        var hashes = [String: String]()
        for name in names {
            let current = root.appendingPathComponent(name)
            if fm.fileExists(atPath: current.path) || (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                try validateTree(current)
                let original = try addonBackupHashes(root, names: [name])
                try fm.copyItem(at: current, to: old.appendingPathComponent(name)); existed.append(name)
                let copied = try addonBackupHashes(old, names: [name])
                guard original == copied else { throw AppError("settingsChanged", name) }
                hashes.merge(copied) { _, new in new }
            }
        }
        var backup = Backup(id: id, date: Date(), label: label, root: root.standardizedFileURL.path, folders: names.sorted(), existed: existed, before: try state(root), status: "applying", hashes: hashes)
        do { try beforeCommit() }
        catch { try? removeAddonTree(location); throw error }
        try write(backup, root)
        journalWritten = true
        do {
            try replace(names: names, staged: staged, root: root)
            try save(desired, root: root)
            backup.status = "committed"; try write(backup, root)
        } catch {
            do { try restoreOld(backup, root); backup.status = "recovered"; try write(backup, root) }
            catch { throw AppError("recoveryFailed", location.path) }
            throw error
        }
    }
    private func restoreOld(_ backup: Backup, _ root: URL) throws {
        let old = try verifiedBackup(backup, root)
        try replace(names: backup.folders, staged: old, root: root)
        try save(backup.before, root: root)
    }
    private func verifiedBackup(_ backup: Backup, _ root: URL) throws -> URL {
        guard backup.root == root.standardizedFileURL.path, safeComponent(backup.id), backup.folders.allSatisfy(safeComponent), backup.existed.allSatisfy(backup.folders.contains) else { throw AppError("invalidBackup") }
        let old = backupHome(backup, root).appendingPathComponent("old")
        try validateTree(old)
        for name in backup.existed { try requireDirectory(old.appendingPathComponent(name)) }
        let entries = try fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).map(\.lastPathComponent)
        guard Set(entries) == Set(backup.existed) else { throw AppError("invalidBackup", old.path) }
        guard let hashes = backup.hashes else { throw AppError("unverifiedBackup", backupHome(backup, root).path) }
        guard try addonBackupHashes(old, names: backup.existed) == hashes else { throw AppError("invalidBackup", old.path) }
        return old
    }
    private func replace(names: [String], staged: URL, root: URL) throws {
        try requireDirectory(root)
        try prepareReplacement(names.map { root.appendingPathComponent($0) })
        let transaction = root.appendingPathComponent(".eso-addons-\(UUID().uuidString)")
        try fm.createDirectory(at: transaction, withIntermediateDirectories: false)
        defer { try? removeAddonTree(transaction) }
        for name in names {
            let source = staged.appendingPathComponent(name), target = root.appendingPathComponent(name)
            let copy = transaction.appendingPathComponent(name)
            let exists = fm.fileExists(atPath: source.path)
            if exists { try validateTree(source); try fm.copyItem(at: source, to: copy); try makeAddonDirectoriesWritable(copy) }
            if fm.fileExists(atPath: target.path) { try removeAddonTree(target) }
            if exists { try fm.moveItem(at: copy, to: target) }
        }
    }
}

func packageError(_ error: Error, addon: Addon, stage: String) -> AppError {
    let cause = error as? AppError
    return AppError(cause?.key ?? "archiveError", "\(addon.title) · ESOUI #\(addon.id) · \(addon.version) · \(stage)\n" + (cause?.detail ?? error.localizedDescription))
}
