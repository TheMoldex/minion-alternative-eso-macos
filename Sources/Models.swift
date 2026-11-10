import Foundation
import CryptoKit

struct AppError: LocalizedError, Sendable {
    let key: String
    let detail: String
    init(_ key: String, _ detail: String = "") { self.key = key; self.detail = detail }
    var errorDescription: String? { "\(key): \(detail)" }
}

struct RemoteFolder: Codable, Sendable {
    let path: String
    let addOnVersion: String?
    let requiredDependencies: [String]?
    var library: Bool? = nil
}

struct Addon: Codable, Identifiable, Sendable {
    let id: Int
    let categoryId: Int
    let version: String
    let lastUpdate: Double
    let title: String
    let author: String
    let fileInfoUri: String?
    let downloads: Int?
    let addons: [RemoteFolder]?
    var library: Bool? = nil
    var gameVersions: [String]? = nil
    var favorites: Int? = nil
    var downloadsMonthly: Int? = nil
    var folders: [String] { Set((addons ?? []).map { $0.path.components(separatedBy: "/")[0] }).sorted() }
    var dependencies: [Dependency] { (addons ?? []).flatMap { ($0.requiredDependencies ?? []).map(Dependency.init) } }
    var supported: Bool { !folders.isEmpty && (addons ?? []).allSatisfy { $0.path.components(separatedBy: "/").allSatisfy(safeComponent) } }
    var kind: AddonKind {
        if let library { return library ? .library : .addon }
        let roots = (addons ?? []).filter { !$0.path.contains("/") }
        if !roots.isEmpty && roots.allSatisfy({ $0.library == true }) { return .library }
        return categoryId == 53 ? .library : .addon
    }
}

enum AddonKind: String, Sendable {
    case addon, library, unknownType
    var symbol: String { self == .library ? "books.vertical.fill" : self == .addon ? "puzzlepiece.extension.fill" : "questionmark.folder" }
}

func addonKind(remote: Addon?, locals: [LocalAddon]) -> AddonKind {
    if let remote { return remote.kind }
    let manifests = locals.compactMap(\.primary)
    guard !manifests.isEmpty else { return .unknownType }
    return manifests.allSatisfy(\.isLibrary) ? .library : .addon
}

struct Dependency: Hashable, Sendable {
    let name: String
    let minimum: Int?
    init(_ raw: String) {
        let parts = raw.components(separatedBy: ">=")
        name = parts[0].trimmingCharacters(in: .whitespaces)
        minimum = parts.count == 2 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
    }
    func satisfied(by manifests: [Manifest]) -> Bool {
        manifests.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame && (minimum == nil || ($0.number ?? -1) >= minimum!) }
    }
    func matches(_ folder: RemoteFolder) -> Bool {
        guard folder.path.components(separatedBy: "/").last?.caseInsensitiveCompare(name) == .orderedSame else { return false }
        guard let minimum else { return true }
        return (folder.addOnVersion.flatMap(Int.init) ?? -1) >= minimum
    }
    var display: String { name + (minimum.map { ">=\($0)" } ?? "") }
}

struct Manifest: Sendable {
    let name: String
    let title: String
    let version: String
    let number: Int?
    let dependencies: [Dependency]
    let optionalDependencies: [Dependency]
    let isLibrary: Bool
    init?(name: String, text: String) {
        var fields = [String: String]()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{feff}", with: "")
            guard line.hasPrefix("##"), let colon = line.firstIndex(of: ":") else { continue }
            fields[String(line.dropFirst(2)[..<colon].trimmingCharacters(in: .whitespaces)).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard fields["title"] != nil, fields["apiversion"] != nil else { return nil }
        self.name = name
        title = cleanTitle(fields["title"] ?? name)
        version = fields["version"] ?? ""
        number = fields["addonversion"].flatMap(Int.init)
        dependencies = (fields["dependson"] ?? "").split(whereSeparator: \.isWhitespace).map { Dependency(String($0)) }
        optionalDependencies = (fields["optionaldependson"] ?? "").split(whereSeparator: \.isWhitespace).map { Dependency(String($0)) }
        isLibrary = fields["islibrary"]?.lowercased() == "true"
    }
}

struct LocalAddon: Identifiable, Sendable {
    let folder: String
    let manifests: [Manifest]
    var scanError: String? = nil
    var id: String { folder }
    var primary: Manifest? { manifests.first { $0.name.caseInsensitiveCompare(folder) == .orderedSame } ?? manifests.first }
}

struct AddonRow: Identifiable {
    let id: String
    let addon: Addon?
    let locals: [LocalAddon]
    let status: AddonStatus
    var update: Bool { status == .newVersion }
    var title: String { addon?.title ?? locals.first?.primary?.title ?? locals.first?.folder ?? "" }
    var version: String {
        Array(Set(locals.compactMap { local in
            guard let manifest = local.primary else { return nil }
            return manifest.version.isEmpty ? manifest.number.map { "#\($0)" } : manifest.version
        })).sorted().joined(separator: ", ")
    }
    var folderText: String { locals.map(\.folder).joined(separator: ", ") }
    var kind: AddonKind { addonKind(remote: addon, locals: locals) }
}

enum AddonSort: String, CaseIterable {
    case name = "sortName", downloads = "sortDownloads", updated = "sortUpdated"
}

struct AddonFilters: Hashable {
    var category = 0
    var kind: AddonKind?
    var gameVersion = ""
    var sort: AddonSort = .name
    var descending = false
    var active: Bool { category != 0 || kind != nil || !gameVersion.isEmpty }
    func apply(_ rows: [AddonRow], query: String) -> [AddonRow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            if category != 0 && row.addon?.categoryId != category { return false }
            if let kind, row.kind != kind { return false }
            if !gameVersion.isEmpty && row.addon?.gameVersions?.contains(gameVersion) != true { return false }
            let fields = [row.title, row.folderText, row.addon?.author ?? "", row.addon?.folders.joined(separator: " ") ?? ""]
            return query.isEmpty || fields.joined(separator: " ").localizedCaseInsensitiveContains(query)
        }.sorted { left, right in
            let order: ComparisonResult
            switch sort {
            case .name: order = left.title.localizedStandardCompare(right.title)
            case .downloads:
                let a = left.addon?.downloads ?? 0, b = right.addon?.downloads ?? 0
                order = a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
            case .updated:
                let a = left.addon?.lastUpdate ?? 0, b = right.addon?.lastUpdate ?? 0
                order = a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
            }
            if order != .orderedSame { return order == (descending ? .orderedDescending : .orderedAscending) }
            let title = left.title.localizedStandardCompare(right.title)
            return title == .orderedSame ? left.id < right.id : title == .orderedAscending
        }
    }
}

func safeComponent(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.hasPrefix(".") && !name.contains(where: { "/\\:\0".contains($0) || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true })
}

func cleanTitle(_ text: String) -> String {
    text.replacingOccurrences(of: "\\|[cC][0-9a-fA-F]{6}|\\|[rR]", with: "", options: .regularExpression)
}

func scanAddons(_ root: URL, tolerant: Bool = false, folders: Set<String>? = nil) throws -> [LocalAddon] {
    try requireDirectory(root)
    let fm = FileManager.default
    return try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]).compactMap { folder in
        guard folders?.contains(folder.lastPathComponent) != false, safeComponent(folder.lastPathComponent) else { return nil }
        do {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            var manifests = [Manifest]()
            var failures = [String](), enumerationError: Error?
            if let entries = fm.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles], errorHandler: { _, error in enumerationError = error; return false }) {
                for case let file as URL in entries {
                    do {
                        if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { entries.skipDescendants(); continue }
                        guard ["txt", "addon"].contains(file.pathExtension.lowercased()), (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 1_000_000 else { continue }
                        if let text = String(data: try Data(contentsOf: file), encoding: .utf8), let manifest = Manifest(name: file.deletingPathExtension().lastPathComponent, text: text) { manifests.append(manifest) }
                    } catch {
                        guard tolerant else { throw error }
                        failures.append(file.path + "\n" + error.localizedDescription)
                    }
                }
            } else { throw AppError("unsafeFolder", folder.path) }
            if let enumerationError {
                guard tolerant else { throw enumerationError }
                failures.append(enumerationError.localizedDescription)
            }
            manifests.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return LocalAddon(folder: folder.lastPathComponent, manifests: manifests, scanError: failures.isEmpty ? nil : failures.joined(separator: "\n"))
        } catch {
            guard tolerant else { throw error }
            return LocalAddon(folder: folder.lastPathComponent, manifests: [], scanError: error.localizedDescription)
        }
    }.sorted { $0.folder.localizedStandardCompare($1.folder) == .orderedAscending }
}

func requireDirectory(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true, url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else { throw AppError("unsafeFolder", url.path) }
}

struct Receipt: Codable, Sendable {
    var id: Int
    var version: String
}

struct LibraryState: Codable, Sendable {
    var sources: [String: Receipt] = [:]
    var ignored: Set<Int> = []
    enum CodingKeys: String, CodingKey { case sources, ignored }
    init(sources: [String: Receipt] = [:], ignored: Set<Int> = []) { self.sources = sources; self.ignored = ignored }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sources = try values.decodeIfPresent([String: Receipt].self, forKey: .sources) ?? [:]
        ignored = try values.decodeIfPresent(Set<Int>.self, forKey: .ignored) ?? []
    }
}

func sourceCandidates(_ folder: String, catalog: [Addon]) -> [Addon] {
    catalog.filter { $0.folders.contains { $0.caseInsensitiveCompare(folder) == .orderedSame } }
}

func resolveSource(_ folder: String, catalog: [Addon], sources: [String: Receipt]) -> Addon? {
    let candidates = sourceCandidates(folder, catalog: catalog)
    if let source = sources[folder], let match = candidates.first(where: { $0.id == source.id }) { return match }
    let active = candidates.filter { $0.categoryId != 157 }
    if active.count == 1 { return active.first }
    let single = active.filter { $0.folders.count == 1 }
    return single.count == 1 ? single.first : nil
}

func updateAvailable(_ addon: Addon, locals: [LocalAddon], sources: [String: Receipt]) -> Bool {
    for local in locals where addon.folders.contains(where: { $0.caseInsensitiveCompare(local.folder) == .orderedSame }) {
        guard let manifest = local.primary else { continue }
        if let remote = addon.addons?.first(where: { $0.path.caseInsensitiveCompare(local.folder) == .orderedSame }), let number = remote.addOnVersion.flatMap(Int.init), let current = manifest.number, number != current { return number > current }
        let version = manifest.version.isEmpty ? sources[local.folder]?.version ?? "" : manifest.version
        if !version.isEmpty && addon.version.compare(version, options: [.numeric, .caseInsensitive]) == .orderedDescending { return true }
    }
    return false
}

enum AddonStatus: String {
    case notInstalled, newVersion, upToDate, newerVersion, versionUnknown
}

func addonStatus(_ addon: Addon?, locals: [LocalAddon], sources: [String: Receipt]) -> AddonStatus {
    guard !locals.isEmpty else { return .notInstalled }
    guard locals.allSatisfy({ $0.scanError == nil }) else { return .versionUnknown }
    guard let addon else { return .versionUnknown }
    if updateAvailable(addon, locals: locals, sources: sources) { return .newVersion }
    var newer = false
    for local in locals {
        guard addon.folders.contains(where: { $0.caseInsensitiveCompare(local.folder) == .orderedSame }), let manifest = local.primary else { return .versionUnknown }
        let remote = addon.addons?.first { $0.path.caseInsensitiveCompare(local.folder) == .orderedSame }?.addOnVersion.flatMap(Int.init)
        if let remote, let current = manifest.number, remote != current {
            guard current > remote else { return .versionUnknown }
            newer = true; continue
        }
        let version = manifest.version.isEmpty ? sources[local.folder]?.version ?? "" : manifest.version
        if !version.isEmpty && !addon.version.isEmpty {
            let order = version.compare(addon.version, options: [.numeric, .caseInsensitive])
            guard order != .orderedAscending else { return .versionUnknown }
            newer = newer || order == .orderedDescending
        } else if remote == nil || manifest.number == nil { return .versionUnknown }
    }
    return newer ? .newerVersion : .upToDate
}

final class MinionReader: NSObject, XMLParserDelegate {
    private let root: String
    private var matching = false
    private var receipt: Receipt?
    private var inDirectory = false
    private var text = ""
    private(set) var sources: [String: Receipt] = [:]
    init(root: URL) { self.root = root.resolvingSymlinksInPath().path }
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if element == "game" {
            matching = attributes["game-id"] == "ESO" && attributes["addon-path"].flatMap { Data(base64Encoded: $0) }.flatMap { String(data: $0, encoding: .utf8) }.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == root } == true
        }
        if element == "addon", matching, let id = attributes["uid"].flatMap(Int.init) { receipt = Receipt(id: id, version: attributes["ui-version"] ?? "") }
        if element == "dir", matching { inDirectory = true; text = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inDirectory { text += string } }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "dir", inDirectory { let folder = text.trimmingCharacters(in: .whitespacesAndNewlines); if safeComponent(folder), let receipt { sources[folder] = receipt }; inDirectory = false }
        if element == "addon" { receipt = nil }
        if element == "game" { matching = false }
    }
    static func read(_ url: URL, root: URL) -> [String: Receipt] {
        guard let data = try? Data(contentsOf: url), data.count < 20_000_000 else { return [:] }
        let reader = MinionReader(root: root)
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = reader
        return parser.parse() ? reader.sources : [:]
    }
}
