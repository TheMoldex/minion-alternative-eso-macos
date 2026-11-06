import Foundation

struct ESOProfile: Codable, Identifiable, Equatable {
    let path: String
    var id: String { path }
    var title: String {
        let live = URL(fileURLWithPath: path).deletingLastPathComponent()
        return live.lastPathComponent + " · " + live.deletingLastPathComponent().path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
    static func adding(_ root: URL, to profiles: [ESOProfile]) -> [ESOProfile] {
        let path = root.standardizedFileURL.path
        return profiles.contains { $0.path == path } ? profiles : profiles + [ESOProfile(path: path)]
    }
}

struct OperationRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let operation: String
    let outcome: String
    let detail: String
}

struct SettingsPreview: Identifiable {
    let id = UUID()
    let title: String
    let folders: [String]
    let files: [String]
}

func addonSettings(folders: [String], locals: [LocalAddon], live: URL) throws -> [String] {
    let selected = Set(folders)
    let names = Set(locals.filter { selected.contains($0.folder) }.flatMap(\.manifests).map(\.name))
    let other = Set(locals.filter { !selected.contains($0.folder) }.flatMap(\.manifests).map { $0.name.lowercased() })
    guard names.allSatisfy(safeComponent) else { throw AppError("unsafeFolder") }
    let shared = names.filter { other.contains($0.lowercased()) }
    guard shared.isEmpty else { throw AppError("sharedSettings", shared.sorted().joined(separator: ", ")) }
    let saved = live.appendingPathComponent("SavedVariables")
    guard FileManager.default.fileExists(atPath: saved.path) else { return [] }
    try requireDirectory(saved)
    return try names.sorted().flatMap { name in
        try [name + ".lua", name + ".lua.bak"].filter { file in
            let url = saved.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            try requireRegularFile(url)
            return true
        }
    }
}

func requireRegularFile(_ file: URL) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.referenceCount] as? Int ?? 1) == 1,
          file.standardizedFileURL.path == file.resolvingSymlinksInPath().path else { throw AppError("unsafeFolder", file.path) }
}

extension Installer {
    func history(_ root: URL) throws -> [OperationRecord] {
        let file = libraryHome(root).appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([OperationRecord].self, from: Data(contentsOf: file))
    }
    func record(_ root: URL, operation: String, outcome: String, detail: String) throws {
        var entries = try history(root)
        entries.insert(OperationRecord(id: UUID(), date: Date(), operation: operation, outcome: outcome, detail: String(detail.prefix(16_000))), at: 0)
        let directory = libraryHome(root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(Array(entries.prefix(500))).write(to: directory.appendingPathComponent("history.json"), options: .atomic)
    }
    @discardableResult func resetSettings(_ preview: SettingsPreview, root: URL, canModify: () throws -> Void = { try RuntimeSafety.requireIdle() }) throws -> [URL] {
        try canModify()
        let fd = try lock(root); defer { close(fd) }
        _ = try recoverLocked(root, canModify: canModify)
        try canModify()
        let files = try addonSettings(folders: preview.folders, locals: scanAddons(root), live: root.deletingLastPathComponent())
        guard files == preview.files else { throw AppError("settingsChanged") }
        let saved = root.deletingLastPathComponent().appendingPathComponent("SavedVariables")
        var moved: [(URL, URL)] = []
        do {
            for name in files {
                var trash: NSURL?
                let source = saved.appendingPathComponent(name)
                try FileManager.default.trashItem(at: source, resultingItemURL: &trash)
                guard let trash else { throw AppError("trashRecoveryFailed", name) }
                moved.append((source, trash as URL))
            }
        } catch {
            var remaining = [String]()
            for (source, trash) in moved.reversed() {
                do { try FileManager.default.moveItem(at: trash, to: source) }
                catch { remaining.append(trash.path) }
            }
            if !remaining.isEmpty { throw AppError("trashRecoveryFailed", remaining.joined(separator: "\n")) }
            throw error
        }
        return moved.map { $0.1 }
    }
}
