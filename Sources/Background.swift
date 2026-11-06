import Foundation

struct BackgroundSchedule {
    static let interval: TimeInterval = 3600
    static let retry: TimeInterval = 300
    static func due(enabled: Bool, busy: Bool, next: Date, now: Date) -> Bool { enabled && !busy && now >= next }
}

enum RuntimeSafety {
    static func blockers(_ names: String) -> [String] {
        let blocked: Set<String> = ["eso", "eso64", "eso.exe", "eso64.exe", "elder scrolls online", "minion", "minion.exe"]
        return names.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { blocked.contains(URL(fileURLWithPath: $0).lastPathComponent.lowercased()) || $0.lowercased().contains("/minion.app/") }
    }
    static func requireIdle() throws {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps"); process.arguments = ["-Aco", "comm="]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, let names = String(data: data, encoding: .utf8) else { throw AppError("runtimeUnavailable") }
        let running = blockers(names)
        guard running.isEmpty else { throw AppError("backgroundPaused", running.joined(separator: ", ")) }
    }
}

func automaticUpdate(root: URL, client: CatalogClient, installer: Installer, minion: URL, parallelism: Int = 3, canModify: @Sendable () throws -> Void, progress: @escaping @Sendable (String) async -> Void) async throws -> Int {
    try canModify()
    _ = try await installer.recover(root, canModify: canModify)
    let catalog = try await client.catalog(force: true)
    let locals = try scanAddons(root)
    var sources = MinionReader.read(minion, root: root)
    let state = try await installer.state(root)
    sources.merge(state.sources) { _, own in own }
    let matches = locals.compactMap { resolveSource($0.folder, catalog: catalog, sources: sources) }
    let updates = matches.filter { !state.ignored.contains($0.id) && $0.supported && updateAvailable($0, locals: locals, sources: sources) }
    let unique = Dictionary(updates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    guard !unique.isEmpty else { return 0 }
    let plan = try dependencyPlan(Array(unique.values), catalog: catalog, locals: locals, sources: sources)
    try respectIgnored(plan, ignored: state.ignored)
    try canModify()
    try await installer.install(plan, root: root, client: client, parallelism: parallelism, beforeCommit: canModify, progress: progress)
    return unique.count
}

func removalDependents(folders: [String], locals: [LocalAddon]) -> [String] {
    let removing = Set(folders.map { $0.lowercased() })
    let provided = Set(locals.filter { removing.contains($0.folder.lowercased()) }.flatMap(\.manifests).map { $0.name.lowercased() })
    let remaining = locals.filter { !removing.contains($0.folder.lowercased()) }
    let after = remaining.flatMap(\.manifests)
    return remaining.flatMap { local in local.manifests.flatMap { manifest in
        manifest.dependencies.filter { provided.contains($0.name.lowercased()) && !$0.satisfied(by: after) }.map { "\(local.primary?.title ?? local.folder) → \($0.display)" }
    } }.sorted()
}

struct LibraryUsage: Identifiable, Sendable {
    let folder: String
    let title: String
    let usedBy: [String]
    let canRemove: Bool
    var id: String { folder }
}

struct RemovalPreview: Sendable {
    let selected: [String]
    let libraries: [LibraryUsage]
    func folders(includeUnused: Bool) -> [String] {
        selected + (includeUnused ? libraries.filter(\.canRemove).map(\.folder) : [])
    }
}

func removalPreview(folders: [String], locals: [LocalAddon], libraryFolders: Set<String>) -> RemovalPreview {
    let selected = Set(folders.map { $0.lowercased() })
    let knownLibraries = Set(libraryFolders.map { $0.lowercased() })
    var pending = locals.filter { selected.contains($0.folder.lowercased()) }
    var candidates = Set<String>()
    while let local = pending.popLast() {
        for dependency in local.manifests.flatMap(\.dependencies) {
            for library in locals where !selected.contains(library.folder.lowercased()) && knownLibraries.contains(library.folder.lowercased()) {
                if library.manifests.contains(where: { $0.name.caseInsensitiveCompare(dependency.name) == .orderedSame }), candidates.insert(library.folder).inserted { pending.append(library) }
            }
        }
    }
    func users(of library: LocalAddon, excluding removed: Set<String>) -> [String] {
        let provided = Set(library.manifests.map { $0.name.lowercased() })
        return locals.filter { local in
            local.folder != library.folder && !removed.contains(local.folder.lowercased()) && local.manifests.flatMap({ $0.dependencies + $0.optionalDependencies }).contains { provided.contains($0.name.lowercased()) }
        }.map { $0.primary?.title ?? $0.folder }.sorted()
    }
    var unused = candidates
    var changed = true
    while changed {
        changed = false
        let removed = selected.union(unused.map { $0.lowercased() })
        for library in locals where unused.contains(library.folder) && !users(of: library, excluding: removed).isEmpty {
            unused.remove(library.folder); changed = true
        }
    }
    let removed = selected.union(unused.map { $0.lowercased() })
    let libraries = locals.filter { candidates.contains($0.folder) }.map { library in
        LibraryUsage(folder: library.folder, title: library.primary?.title ?? library.folder, usedBy: users(of: library, excluding: removed), canRemove: unused.contains(library.folder))
    }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    return RemovalPreview(selected: folders, libraries: libraries)
}

func descriptionText(_ raw: String) -> String {
    var text = String(raw.prefix(200_000)).replacingOccurrences(of: "\r\n", with: "\n")
    text = text.replacingOccurrences(of: "\\[IMG[^\\]]*\\].*?\\[/IMG\\]", with: "", options: [.regularExpression, .caseInsensitive])
    text = text.replacingOccurrences(of: "\\[URL=[\"']?(https?://[^\\]\\\"']+)[\"']?\\](.*?)\\[/URL\\]", with: "$2 ($1)", options: [.regularExpression, .caseInsensitive])
    text = text.replacingOccurrences(of: "\\[\\*\\]", with: "• ", options: .regularExpression)
    text = text.replacingOccurrences(of: "\\[/?[A-Za-z][^\\]]*\\]", with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
    for (entity, replacement) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#039;", "'"), ("&amp;", "&")] { text = text.replacingOccurrences(of: entity, with: replacement) }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func respectIgnored(_ plan: InstallPlan, ignored: Set<Int>) throws {
    let blocked = plan.addons.filter { ignored.contains($0.id) && !plan.requestedIDs.contains($0.id) }
    guard blocked.isEmpty else { throw AppError("ignoredDependency", blocked.map(\.title).joined(separator: ", ")) }
}

func parallelDownloads(_ addons: [Addon], limit: Int, download: @escaping @Sendable (Addon) async throws -> URL) async throws -> [Int: URL] {
    try await withThrowingTaskGroup(of: (Int, URL).self) { group in
        var next = addons.makeIterator(), result = [Int: URL]()
        for _ in 0..<min(max(1, limit), 4) {
            if let addon = next.next() { group.addTask { (addon.id, try await download(addon)) } }
        }
        while let (id, file) = try await group.next() {
            result[id] = file
            if let addon = next.next() { group.addTask { (addon.id, try await download(addon)) } }
        }
        return result
    }
}
