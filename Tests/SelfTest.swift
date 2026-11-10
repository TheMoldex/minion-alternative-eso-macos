import Foundation

private var checks = 0
func check(_ value: Bool, _ label: String) {
    guard value else { fatalError("FAIL: \(label)") }; checks += 1
}
func rejects(_ label: String, _ body: () throws -> Void) {
    do { try body(); fatalError("FAIL: \(label)") } catch { checks += 1 }
}
func rejectsAsync(_ label: String, _ body: () async throws -> Void) async {
    do { try await body(); fatalError("FAIL: \(label)") } catch { checks += 1 }
}
func makeLocal(_ root: URL, _ name: String, dependencies: String = "", version: String = "1", number: Int = 1) throws {
    let directory = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let text = "## Title: \(name)\n## APIVersion: 101051\n## Version: \(version)\n## AddOnVersion: \(number)\n## DependsOn: \(dependencies)"
    try Data(text.utf8).write(to: directory.appendingPathComponent(name + ".addon"))
}
func addon(_ id: Int, _ folder: String, version: String = "2", number: String = "2", dependencies: [String] = []) -> Addon {
    Addon(id: id, categoryId: 53, version: version, lastUpdate: 0, title: folder, author: "Test", fileInfoUri: nil, downloads: 1, addons: [RemoteFolder(path: folder, addOnVersion: number, requiredDependencies: dependencies)])
}
func manifest(_ name: String, version: String = "1", number: String = "1", deps: String = "") -> Manifest {
    Manifest(name: name, text: "## Title: |cffffff\(name)|r\n## APIVersion: 101051\n## Version: \(version)\n## AddOnVersion: \(number)\n## DependsOn: \(deps)\n## OptionalDependsOn: OptionalLibrary")!
}
func crc32(_ bytes: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in bytes { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) } }
    return ~crc
}
func zip(_ names: [String], symbolic: Bool = false, body: String = "fixture") -> Data {
    var data = Data(), central = Data()
    func word(_ value: Int, _ bytes: Int) -> Data { Data((0..<bytes).map { UInt8((value >> ($0 * 8)) & 255) }) }
    for name in names {
        let raw = Data(name.utf8), body = Data(body.utf8), crc = Int(crc32(body)), offset = data.count
        let header: [Data] = [word(0x04034b50, 4), word(20, 2), Data(repeating: 0, count: 8), word(crc, 4), word(body.count, 4), word(body.count, 4), word(raw.count, 2), word(0, 2), raw, body]
        header.forEach { data.append($0) }
        let record: [Data] = [word(0x02014b50, 4), word(0x0314, 2), word(20, 2), Data(repeating: 0, count: 8), word(crc, 4), word(body.count, 4), word(body.count, 4), word(raw.count, 2), Data(repeating: 0, count: 8), word(symbolic ? 0xa1ff0000 : 0x81a40000, 4), word(offset, 4), raw]
        record.forEach { central.append($0) }
    }
    let offset = data.count
    let footer: [Data] = [central, word(0x06054b50, 4), Data(repeating: 0, count: 4), word(names.count, 2), word(names.count, 2), word(central.count, 4), word(offset, 4), word(0, 2)]
    footer.forEach { data.append($0) }
    return data
}

@main struct Tests {
    static func main() async throws {
        setbuf(stdout, nil)
        let updateChecks = try await appUpdateChecks()
        print("PASS: \(updateChecks) app update checks")

        let layout = PaneLayout(width: 1160, sidebar: 220, details: 330)
        check(layout.sidebar == 220 && layout.details == 330 && layout.main == 932, "default panel layout preserved")
        let narrow = PaneLayout(width: 980, sidebar: 420, details: 700)
        check(narrow.sidebar == 352 && narrow.details == 312 && narrow.main - narrow.details - PaneLayout.divider == 300, "narrow window keeps list and details readable")
        let wide = PaneLayout(width: 1600, sidebar: 420, details: 700)
        check(wide.sidebar == 420 && wide.details == 700, "preferred panel widths return when the window expands")
        let small = PaneLayout(width: 1160, sidebar: -10, details: -10)
        check(small.sidebar == 180 && small.details == 280, "panels cannot collapse below minimum widths")
        let huge = PaneLayout(width: 3840, sidebar: 10_000, details: 10_000)
        check(huge.sidebar == 420 && huge.details == 700, "maximum panel widths bounded on large screens")
        let invalid = PaneLayout(width: .nan, sidebar: .infinity, details: .nan)
        check(invalid.sidebar == 220 && invalid.details.isFinite && invalid.main.isFinite, "invalid saved widths do not break layout")
        let layouts = [980.0, 1100, 1160, 1800].flatMap { width in [180.0, 220, 420].flatMap { sidebar in [280.0, 330, 700].map { PaneLayout(width: width, sidebar: sidebar, details: $0) } } }
        check(layouts.allSatisfy { $0.main - $0.details - PaneLayout.divider >= 300 && $0.details >= 280 && $0.sidebar >= 180 }, "list and panel width invariants hold throughout resizing")
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("eso-addons-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let root = temp.appendingPathComponent("live/AddOns")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let local = manifest("Main", deps: "Library>=2 Other")
        check(local.title == "Main" && local.dependencies.count == 2, "manifest color and dependencies")
        check(local.dependencies[0].minimum == 2, "minimum version")
        check(Manifest(name: "README", text: "## Title: Not an addon") == nil, "not a manifest")
        check(!Dependency("Library>=2").satisfied(by: [manifest("Library")]), "old dependency rejected")
        check(Dependency("Library>=2").satisfied(by: [manifest("Library", number: "2")]), "minimum satisfied")
        let main = addon(1, "Main", dependencies: ["Library>=2"]), library = addon(2, "Library")
        let plan = try dependencyPlan([main], catalog: [main, library], locals: [], sources: [:])
        check(plan.addons.count == 2 && plan.missing.isEmpty, "dependency included")
        check(plan.requestedIDs == [main.id], "requested addon distinguished from automatic dependency")
        let satisfiedPlan = try dependencyPlan([main], catalog: [main, library], locals: [LocalAddon(folder: "Library", manifests: [manifest("Library", number: "2")])], sources: [:])
        check(satisfiedPlan.addons.count == 1, "suitable installed library not downloaded again")
        let outdatedPlan = try dependencyPlan([main], catalog: [main, library], locals: [LocalAddon(folder: "Library", manifests: [manifest("Library", number: "1")])], sources: [:])
        check(outdatedPlan.addons.count == 2, "outdated required library included")
        let missing = try dependencyPlan([main], catalog: [main], locals: [], sources: [:])
        check(missing.missing == ["Library>=2"], "unknown dependency prevents install")
        let cycleA = addon(1, "A", dependencies: ["B>=2"]), cycleB = addon(2, "B", dependencies: ["A>=2"])
        let cycle = try dependencyPlan([cycleA], catalog: [cycleA, cycleB], locals: [], sources: [:])
        check(cycle.addons.count == 2 && cycle.missing.isEmpty, "dependency cycle terminates")
        let bundled = Addon(id: 8, categoryId: 20, version: "2", lastUpdate: 0, title: "Bundle", author: "Test", fileInfoUri: nil, downloads: nil, addons: [RemoteFolder(path: "Bundle/Library", addOnVersion: "2", requiredDependencies: nil), RemoteFolder(path: "Bundle", addOnVersion: "2", requiredDependencies: ["Library>=2"])])
        let bundlePlan = try dependencyPlan([bundled], catalog: [bundled], locals: [], sources: [:])
        check(bundled.supported && bundled.folders == ["Bundle"] && bundlePlan.missing.isEmpty, "bundled nested libraries recognized")
        check(bundled.kind == .addon, "addon with a bundled library remains an addon")
        var explicitLibrary = bundled
        explicitLibrary.library = true
        check(explicitLibrary.kind == .library, "catalog library flag used")
        let rootLibrary = Addon(id: 9, categoryId: 20, version: "1", lastUpdate: 0, title: "Not named Lib", author: "Test", fileInfoUri: nil, downloads: nil, addons: [RemoteFolder(path: "Core", addOnVersion: "1", requiredDependencies: nil, library: true)])
        check(rootLibrary.kind == .library, "root library metadata used")
        check(library.kind == .library, "library category supports legacy metadata")
        let libraryManifest = Manifest(name: "Core", text: "## Title: Core\n## APIVersion: 101051\n## IsLibrary: true")!
        check(addonKind(remote: nil, locals: [LocalAddon(folder: "Core", manifests: [libraryManifest])]) == .library, "local manifest library flag used")
        check(addonKind(remote: nil, locals: [LocalAddon(folder: "Main", manifests: [manifest("Main")])]) == .addon, "ordinary local addon")
        check(addonKind(remote: nil, locals: []) == .unknownType, "unknown type not guessed")
        let duplicate = addon(3, "Main")
        check(resolveSource("Main", catalog: [main, duplicate], sources: [:]) == nil, "ambiguous source not guessed")
        check(resolveSource("Main", catalog: [main, duplicate], sources: ["Main": Receipt(id: 3, version: "1")])?.id == 3, "explicit source used")
        rejects("overlapping packages rejected") { _ = try dependencyPlan([main, duplicate], catalog: [main, duplicate, library], locals: [], sources: [:]) }
        let old = LocalAddon(folder: "Main", manifests: [local])
        check(updateAvailable(main, locals: [old], sources: [:]), "newer addon detected")
        check(!updateAvailable(main, locals: [LocalAddon(folder: "Main", manifests: [manifest("Main", version: "3", number: "3")])], sources: [:]), "no automatic downgrade")
        check(addonStatus(main, locals: [old], sources: [:]) == .newVersion, "row explicitly shows an update")
        check(addonStatus(main, locals: [LocalAddon(folder: "Main", manifests: [manifest("Main", version: "2", number: "2")])], sources: [:]) == .upToDate, "equal versions are current")
        check(addonStatus(main, locals: [LocalAddon(folder: "Main", manifests: [manifest("Main", version: "3", number: "3")])], sources: [:]) == .newerVersion, "newer local version has its own status")
        check(addonStatus(nil, locals: [old], sources: [:]) == .versionUnknown, "unlinked addon is not labelled current")
        check(addonStatus(main, locals: [LocalAddon(folder: "Main", manifests: [])], sources: [:]) == .versionUnknown, "missing manifest has no green check")
        check(addonStatus(main, locals: [], sources: [:]) == .notInstalled, "catalog entry is not installed")
        check(addonStatus(main, locals: [LocalAddon(folder: "Main", manifests: [manifest("Main", version: "", number: "")])], sources: [:]) == .versionUnknown, "missing versions cannot be checked")
        check(addonStatus(main, locals: [LocalAddon(folder: "Main", manifests: [manifest("Main", version: "", number: "2")])], sources: [:]) == .upToDate, "numeric build can establish the current version")
        check(addonStatus(main, locals: [LocalAddon(folder: "Main", manifests: [manifest("Main", version: "", number: "")])], sources: ["Main": Receipt(id: main.id, version: "2")]) == .upToDate, "receipt version is used when manifest omits it")
        let category = AddonCategory(id: "17", title: "Graphic UI Mods", iconUrl: "https://cdn-eso.mmoui.com/images/icons/m17.jpg")
        check(category.icon != nil, "official category icon accepted")
        for address in ["http://cdn-eso.mmoui.com/images/icons/m17.jpg", "https://evil.invalid/images/icons/m17.jpg", "https://cdn-eso.mmoui.com/downloads/file.zip"] {
            check(AddonCategory(id: "17", title: "Test", iconUrl: address).icon == nil, "untrusted category image rejected")
        }
        let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jD1sAAAAASUVORK5CYII=")!
        check(validCategoryImage(pixel) && !validCategoryImage(Data("not an image".utf8)), "image format and dimensions checked")
        check(!validCategoryImage(Data(repeating: 0, count: 1_000_001)), "oversized image rejected")
        let categoryHome = temp.appendingPathComponent("category-cache")
        try fm.createDirectory(at: categoryHome, withIntermediateDirectories: true)
        try JSONEncoder().encode([category]).write(to: categoryHome.appendingPathComponent("categories.json"))
        let categoryClient = CatalogClient(cache: categoryHome.appendingPathComponent("catalog.json"))
        check(try await categoryClient.categories()[17]?.title == category.title, "category metadata works from disk without a catalog download")
        try JSONEncoder().encode([category, AddonCategory(id: "017", title: "Duplicate", iconUrl: category.iconUrl)]).write(to: categoryHome.appendingPathComponent("categories.json"))
        await rejectsAsync("duplicate numeric category ids are rejected") { _ = try await categoryClient.categories() }
        let xml = temp.appendingPathComponent("minion.xml"), encoded = Data(root.path.utf8).base64EncodedString()
        try Data("<minion><games><game game-id=\"ESO\" addon-path=\"\(encoded)\"><addons><addon uid=\"3\" ui-version=\"1\"><dirs><dir>Main</dir></dirs></addon></addons></game><game game-id=\"WOW\" addon-path=\"\(encoded)\"><addons><addon uid=\"99\"><dirs><dir>Main</dir></dirs></addon></addons></game></games></minion>".utf8).write(to: xml)
        check(MinionReader.read(xml, root: root)["Main"]?.id == 3, "Minion import scoped to ESO folder")
        for name in ["../escape", "/absolute", "Main/../escape", "Main\\escape", "Main/evil\nname", "Main//file"] { rejects("unsafe zip name \(name)") { _ = try ZipArchive.paths(zip([name])) } }
        rejects("zip symlink") { _ = try ZipArchive.paths(zip(["Main/link"], symbolic: true)) }
        rejects("case collision") { _ = try ZipArchive.paths(zip(["Main/file", "main/FILE"])) }
        var mismatch = zip(["Main/file"]); mismatch[30] = 88
        rejects("local header mismatch") { _ = try ZipArchive.paths(mismatch) }
        check(try ZipArchive.paths(zip(["Main/file"])) == ["Main/file"], "valid zip")
        let archive = temp.appendingPathComponent("fixture.zip"); try zip(["Main/file"]).write(to: archive)
        try ZipArchive.extract(archive, into: temp.appendingPathComponent("extract"), expected: ["Main"])
        check(fm.fileExists(atPath: temp.appendingPathComponent("extract/Main/file").path), "valid extraction")
        rejects("unexpected package root") { try ZipArchive.extract(archive, into: temp.appendingPathComponent("bad"), expected: ["Other"]) }
        let link = root.appendingPathComponent("Linked"); try fm.createSymbolicLink(at: link, withDestinationURL: temp)
        rejects("symlink tree rejected") { try validateTree(link) }
        try fm.removeItem(at: link)
        check(NetworkGuard.allowed(URL(string: "https://cdn.esoui.com/downloads/getfile.php?id=7")!), "trusted download URL")
        for url in ["http://api.mmoui.com/", "https://api.mmoui.com.evil.test/", "https://user@api.mmoui.com/", "https://api.mmoui.com:8443/"] { check(!NetworkGuard.allowed(URL(string: url)!), "untrusted redirect rejected") }
        check(Language.strings.values.allSatisfy { !$0.0.isEmpty && !$0.1.isEmpty }, "all UI messages bilingual")
        check(Set(Language.french.keys) == Set(Language.strings.keys) && Language.french.values.allSatisfy { !$0.isEmpty }, "French translations complete")
        check(Set(Language.spanish.keys) == Set(Language.strings.keys) && Language.spanish.values.allSatisfy { !$0.isEmpty }, "Spanish translations complete")
        check(Language.preferred(saved: nil, system: "fr-FR") == .fr && Language.preferred(saved: nil, system: "es-MX") == .es, "French and Spanish system languages detected")
        check(Language.preferred(saved: "ru", system: "es-ES") == .ru, "saved language takes priority")
        var alpha = Addon(id: 101, categoryId: 17, version: "1", lastUpdate: 10, title: "Alpha 2", author: "Alice", fileInfoUri: nil, downloads: 10, addons: [RemoteFolder(path: "AlphaFolder", addOnVersion: "1", requiredDependencies: nil)])
        alpha.gameVersions = ["12.0.0"]
        var beta = Addon(id: 102, categoryId: 53, version: "1", lastUpdate: 20, title: "Beta", author: "Bob", fileInfoUri: nil, downloads: 100, addons: [RemoteFolder(path: "BetaFolder", addOnVersion: "1", requiredDependencies: nil)])
        beta.gameVersions = ["12.0.0", "11.3.0"]
        var older = Addon(id: 103, categoryId: 17, version: "1", lastUpdate: 5, title: "Alpha 10", author: "Carol", fileInfoUri: nil, downloads: 50, addons: [RemoteFolder(path: "OldFolder", addOnVersion: "1", requiredDependencies: nil)])
        older.gameVersions = ["11.3.0"]
        let filterRows = [alpha, beta, older].map { AddonRow(id: "remote:\($0.id)", addon: $0, locals: [], status: .notInstalled) } + [AddonRow(id: "local:Loose", addon: nil, locals: [LocalAddon(folder: "Loose", manifests: [manifest("Loose")])], status: .versionUnknown)]
        check(AddonFilters().apply(filterRows, query: "").map(\.title) == ["Alpha 2", "Alpha 10", "Beta", "Loose"], "name sorting uses natural numeric order")
        check(AddonFilters(category: 17).apply(filterRows, query: "").count == 2, "category filter excludes other categories and unlinked addons")
        check(AddonFilters(kind: .library).apply(filterRows, query: "").map(\.title) == ["Beta"], "library filter uses metadata")
        check(AddonFilters(kind: .addon).apply(filterRows, query: "").count == 3, "addon filter includes recognized local addon manifests")
        check(AddonFilters(gameVersion: "12.0.0").apply(filterRows, query: "").count == 2, "ESO compatibility filter matches any listed game version")
        check(AddonFilters(category: 17, kind: .addon, gameVersion: "12.0.0").apply(filterRows, query: " alice ").map(\.title) == ["Alpha 2"], "category, type, compatibility and trimmed search combine")
        check(AddonFilters().apply(filterRows, query: "alphafolder").map(\.title) == ["Alpha 2"], "folder search remains case insensitive")
        check(AddonFilters().apply(filterRows, query: "loose").map(\.title) == ["Loose"], "unlinked addon remains searchable")
        check(AddonFilters(category: 999).apply(filterRows, query: "").isEmpty, "nonmatching filter returns no results")
        check(AddonFilters(sort: .downloads, descending: true).apply(filterRows, query: "").map(\.title) == ["Beta", "Alpha 10", "Alpha 2", "Loose"], "downloads sorted highest first")
        check(AddonFilters(sort: .downloads).apply(filterRows, query: "").first?.title == "Loose", "sort direction can be reversed")
        check(AddonFilters(sort: .updated, descending: true).apply(filterRows, query: "").map(\.title) == ["Beta", "Alpha 2", "Alpha 10", "Loose"], "newly updated addons sorted first")
        check(AddonFilters(descending: true).apply(filterRows, query: "").map(\.title) == ["Loose", "Beta", "Alpha 10", "Alpha 2"], "names can be sorted descending")
        let noVersions = addon(104, "NoVersions")
        check(try JSONDecoder().decode(Addon.self, from: JSONEncoder().encode(noVersions)).gameVersions == nil, "catalog entries without compatibility remain decodable")
        check(AddonFilters(gameVersion: "12.0.0").apply([AddonRow(id: "noVersions", addon: noVersions, locals: [], status: .notInstalled)], query: "").isEmpty, "missing compatibility is not assumed to match")
        check(!AddonFilters(sort: .downloads).active && AddonFilters(kind: .library).active, "sorting alone does not imply a narrowed result set")
        let pricesRoot = temp.appendingPathComponent("prices/AddOns"), pricesStage = temp.appendingPathComponent("prices/staged")
        for dir in [pricesRoot, pricesStage] { try fm.createDirectory(at: dir.appendingPathComponent("TamrielTradeCentre"), withIntermediateDirectories: true) }
        let priceName = "TamrielTradeCentre/PriceTableEU.lua"
        try Data("current prices".utf8).write(to: pricesRoot.appendingPathComponent(priceName))
        try Data("bundled prices".utf8).write(to: pricesStage.appendingPathComponent(priceName))
        let priceInstaller = Installer(home: temp.appendingPathComponent("prices/state"))
        try await priceInstaller.preservePrices(root: pricesRoot, staged: pricesStage)
        check(try String(contentsOf: pricesStage.appendingPathComponent(priceName), encoding: .utf8) == "current prices", "TTC prices preserved")
        let now = Date(timeIntervalSince1970: 1000)
        check(BackgroundSchedule.due(enabled: true, busy: false, next: now, now: now), "background deadline reached")
        check(!BackgroundSchedule.due(enabled: false, busy: false, next: now, now: now), "disabled background does not run")
        check(!BackgroundSchedule.due(enabled: true, busy: true, next: now, now: now), "busy app does not start another update")
        check(!BackgroundSchedule.due(enabled: true, busy: false, next: now.addingTimeInterval(1), now: now), "background waits until due")
        check(RuntimeSafety.blockers("ESOAddons\njava\neso64.exe\nMinion\n").count == 2, "game and Minion pause automatic updates")
        check(RuntimeSafety.blockers("ESOAddons\nSteam\nSafari\n").isEmpty, "unrelated apps do not pause automatic updates")
        check(descriptionText("[B]Hello[/B] [URL=\"https://www.esoui.com/test\"]details[/URL]") == "Hello details (https://www.esoui.com/test)", "description markup readable and URL preserved")
        check(descriptionText("[IMG]https://evil.invalid/image.png[/IMG]<b>Text</b>") == "Text", "description does not load images or HTML")
        let removeRoot = temp.appendingPathComponent("remove/live/AddOns")
        try makeLocal(removeRoot, "Main", dependencies: "Library>=2")
        try makeLocal(removeRoot, "Library", number: 2)
        let removal = Installer(home: temp.appendingPathComponent("removal-state"))
        await rejectsAsync("required library cannot be removed") { try await removal.remove(folders: ["Library"], root: removeRoot) }
        check(fm.fileExists(atPath: removeRoot.appendingPathComponent("Library/Library.addon").path), "blocked removal preserves library")
        let oldLibrary = LocalAddon(folder: "Library", manifests: [manifest("Library", number: "1")])
        check(!removalDependents(folders: ["Library"], locals: [LocalAddon(folder: "Main", manifests: [manifest("Main", deps: "Library>=2")]), oldLibrary]).isEmpty, "outdated required library still protected")
        let base = LocalAddon(folder: "Main", manifests: [manifest("Main", deps: "LibraryA")])
        let libraryA = LocalAddon(folder: "LibraryA", manifests: [manifest("LibraryA", deps: "LibraryB")])
        let libraryB = LocalAddon(folder: "LibraryB", manifests: [manifest("LibraryB")])
        let independent = LocalAddon(folder: "UnrelatedLibrary", manifests: [manifest("UnrelatedLibrary")])
        let libraryNames: Set<String> = ["LibraryA", "LibraryB", "UnrelatedLibrary"]
        let unusedPreview = removalPreview(folders: ["Main"], locals: [base, libraryA, libraryB, independent], libraryFolders: libraryNames)
        check(unusedPreview.folders(includeUnused: false) == ["Main"], "removal keeps all dependencies by default")
        check(Set(unusedPreview.folders(includeUnused: true)) == ["Main", "LibraryA", "LibraryB"], "optional cleanup follows unused dependency chain")
        check(!unusedPreview.libraries.contains { $0.folder == "UnrelatedLibrary" }, "unrelated unused libraries are untouched")
        let otherUsingB = LocalAddon(folder: "Other", manifests: [manifest("Other", deps: "LibraryB")])
        let sharedPreview = removalPreview(folders: ["Main"], locals: [base, libraryA, libraryB, otherUsingB], libraryFolders: libraryNames)
        check(Set(sharedPreview.folders(includeUnused: true)) == ["Main", "LibraryA"], "shared transitive library not removed")
        check(sharedPreview.libraries.first { $0.folder == "LibraryB" }?.usedBy == ["Other"], "shared library consumers displayed")
        let optionalUser = LocalAddon(folder: "OptionalUser", manifests: [Manifest(name: "OptionalUser", text: "## Title: OptionalUser\n## APIVersion: 101051\n## OptionalDependsOn: LibraryB")!])
        let optionalShared = removalPreview(folders: ["Main"], locals: [base, libraryA, libraryB, optionalUser], libraryFolders: libraryNames)
        check(optionalShared.libraries.first { $0.folder == "LibraryB" }?.canRemove == false, "cleanup keeps libraries optionally used by other addons")
        let otherUsingA = LocalAddon(folder: "Other", manifests: [manifest("Other", deps: "LibraryA")])
        let sharedChain = removalPreview(folders: ["Main"], locals: [base, libraryA, libraryB, otherUsingA], libraryFolders: libraryNames)
        check(sharedChain.folders(includeUnused: true) == ["Main"], "kept library keeps its dependencies")
        let cyclicB = LocalAddon(folder: "LibraryB", manifests: [manifest("LibraryB", deps: "LibraryA")])
        let cyclicPreview = removalPreview(folders: ["Main"], locals: [base, libraryA, cyclicB], libraryFolders: libraryNames)
        check(cyclicPreview.libraries.allSatisfy(\.canRemove) && cyclicPreview.libraries.count == 2, "unused library cycle can be removed together")
        try await removal.save(LibraryState(sources: ["Main": Receipt(id: 1, version: "1"), "Library": Receipt(id: 2, version: "2")]), root: removeRoot)
        let beforeTrash = try Data(contentsOf: removeRoot.appendingPathComponent("Main/Main.addon"))
        let trash = try await removal.remove(folders: ["Main"], root: removeRoot)
        check(!fm.fileExists(atPath: removeRoot.appendingPathComponent("Main").path), "addon removed from AddOns")
        check(trash.count == 1 && trash[0].path != removeRoot.appendingPathComponent("Main").path, "addon moved to native Trash")
        check(try Data(contentsOf: trash[0].appendingPathComponent("Main.addon")) == beforeTrash, "trashed addon remains intact")
        check(try await removal.backups(removeRoot).isEmpty, "removal creates no application backup")
        let removedState = try await removal.state(removeRoot)
        check(removedState.sources["Main"] == nil && removedState.sources["Library"]?.id == 2, "removal clears only affected source metadata")
        try fm.moveItem(at: trash[0], to: removeRoot.appendingPathComponent("Main"))
        check(fm.fileExists(atPath: removeRoot.appendingPathComponent("Main/Main.addon").path), "addon can be returned from Trash")
        let invalidHome = temp.appendingPathComponent("not-a-directory")
        try Data("block metadata save".utf8).write(to: invalidHome)
        let failedRemoval = Installer(home: invalidHome)
        await rejectsAsync("metadata save failure aborts removal") { try await failedRemoval.remove(folders: ["Main", "Library"], root: removeRoot) }
        check(fm.fileExists(atPath: removeRoot.appendingPathComponent("Main/Main.addon").path) && fm.fileExists(atPath: removeRoot.appendingPathComponent("Library/Library.addon").path), "failed removal puts all trashed folders back")
        await rejectsAsync("duplicate removal folders rejected before moving") { try await removal.remove(folders: ["Main", "Main"], root: removeRoot) }
        let safeBefore = try await removal.backups(removeRoot).count
        await rejectsAsync("removal traversal rejected") { try await removal.remove(folders: ["../SavedVariables"], root: removeRoot) }
        check(try await removal.backups(removeRoot).count == safeBefore, "failed removal creates no backup")
        let retentionRoot = temp.appendingPathComponent("retention/AddOns")
        try fm.createDirectory(at: retentionRoot, withIntermediateDirectories: true)
        let keeper = Installer(home: temp.appendingPathComponent("retention/state"))
        let libraryHome = await keeper.libraryHome(retentionRoot)
        for i in 0..<5 {
            let id = UUID().uuidString
            let backup = Backup(id: id, date: Date(timeIntervalSince1970: Double(i)), label: "fixture-\(i)", root: retentionRoot.path, folders: [], existed: [], before: LibraryState(), status: i == 0 ? "applying" : "committed")
            let path = libraryHome.appendingPathComponent("backups/\(id)")
            try fm.createDirectory(at: path, withIntermediateDirectories: true)
            try JSONEncoder().encode(backup).write(to: path.appendingPathComponent("backup.json"))
        }
        try await keeper.pruneBackups(retentionRoot, keep: 0)
        check(try await keeper.backups(retentionRoot).count == 5, "keep all does not delete backups")
        try await keeper.pruneBackups(retentionRoot, keep: 2)
        let retained = try await keeper.backups(retentionRoot)
        check(retained.count == 3 && retained.contains { $0.status == "applying" }, "retention preserves pending recovery")
        check(Set(retained.filter { $0.status == "committed" }.map(\.label)) == ["fixture-3", "fixture-4"], "retention keeps newest completed backups")
        try await featureChecks(temp)
        try await backupManagementChecks(temp)
        try await screenshotChecks(temp)
        try await readOnlyChecks(temp)
        try await recoveryChecks(temp)
        print("PASS: \(checks) offline checks")
        if CommandLine.arguments.contains("--live") { try await live(temp: temp, root: root) }
    }
    static func live(temp: URL, root: URL) async throws {
        let fm = FileManager.default
        let client = CatalogClient(cache: temp.appendingPathComponent("catalog.json"))
        let download: @Sendable (Addon, URL) async throws -> URL = { try await client.download($0, to: $1) }
        let catalog = try await client.catalog()
        let categories = try await client.categories()
        check(categories[17]?.icon != nil && categories[53]?.title == "Libraries", "live category metadata received")
        let icon = await client.icon(categories[17]!)
        check(icon.map(validCategoryImage) == true, "live category icon decoded")
        let cachedClient = CatalogClient(cache: temp.appendingPathComponent("catalog.json"))
        check(await cachedClient.icon(categories[17]!) == icon && icon != nil, "category icon can be read by a fresh client from disk")
        let liveDetails = try await client.details(1091)
        check(!(liveDetails.description ?? "").isEmpty && !(liveDetails.changeLog ?? "").isEmpty, "live descriptions and changelog received")
        guard let lam = catalog.first(where: { $0.id == 7 }) else { fatalError("missing live fixture") }
        let directory = root.appendingPathComponent("LibAddonMenu-2.0")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let prior = "## Title: LibAddonMenu-2.0\n## APIVersion: 101051\n## Version: 0\n## AddOnVersion: 0"
        try Data(prior.utf8).write(to: directory.appendingPathComponent("LibAddonMenu-2.0.addon"))
        let custom = Data("keep this old addon file".utf8)
        try custom.write(to: directory.appendingPathComponent("custom.txt"))
        let saved = root.deletingLastPathComponent().appendingPathComponent("SavedVariables")
        try fm.createDirectory(at: saved, withIntermediateDirectories: true)
        let sentinel = saved.appendingPathComponent("sentinel.lua"); try custom.write(to: sentinel)
        let installer = Installer(home: temp.appendingPathComponent("state"))
        let planned = try dependencyPlan([lam], catalog: catalog, locals: scanAddons(root), sources: [:])
        try await installer.install(planned, root: root, download: download) { print("Downloading: \($0)") }
        let installed = try scanAddons(root)
        check(installed.first?.primary?.version == lam.version, "live package installed")
        check(!fm.fileExists(atPath: directory.appendingPathComponent("custom.txt").path), "obsolete files replaced")
        let records = try await installer.backups(root)
        check(records.count == 1 && records[0].status == "committed", "backup committed")
        var state = try await installer.state(root)
        state.sources["Unrelated"] = Receipt(id: 999, version: "1")
        try await installer.save(state, root: root)
        try await installer.restore(records[0], root: root)
        check(try await installer.state(root).sources["Unrelated"]?.id == 999, "rollback preserves unrelated metadata")
        check(try Data(contentsOf: directory.appendingPathComponent("custom.txt")) == custom, "rollback restores original files")
        check(try String(contentsOf: directory.appendingPathComponent("LibAddonMenu-2.0.addon"), encoding: .utf8) == prior, "rollback restores version")
        check(try Data(contentsOf: sentinel) == custom, "SavedVariables untouched")
        try fm.removeItem(at: directory)
        try await installer.install(planned, root: root, download: download) { _ in }
        let fresh = try await installer.backups(root)[0]
        try await installer.restore(fresh, root: root)
        check(!fm.fileExists(atPath: directory.path), "rollback removes a newly installed addon")
        try await installer.install(planned, root: root, download: download) { _ in }
        var interrupted = try await installer.backups(root)[0]
        interrupted.status = "applying"
        let home = await installer.libraryHome(root)
        try JSONEncoder().encode(interrupted).write(to: home.appendingPathComponent("backups/\(interrupted.id)/backup.json"), options: .atomic)
        let recovered = try await installer.recover(root)
        check(recovered == 1 && !fm.fileExists(atPath: directory.path), "interrupted install recovered")
        check(try Data(contentsOf: sentinel) == custom, "recovery preserves SavedVariables")
        guard let autoRecharge = catalog.first(where: { $0.id == 1091 }) else { fatalError("missing dependency fixture") }
        let dependencyRoot = temp.appendingPathComponent("dependency/live/AddOns")
        try fm.createDirectory(at: dependencyRoot, withIntermediateDirectories: true)
        let rechargePlan = try dependencyPlan([autoRecharge], catalog: catalog, locals: [], sources: [:])
        check(Set(rechargePlan.addons.map(\.id)) == [1091, 7] && rechargePlan.missing.isEmpty, "real addon includes missing library")
        try await installer.install(rechargePlan, root: dependencyRoot, download: download) { print("Downloading dependency fixture: \($0)") }
        let dependencyLocals = try scanAddons(dependencyRoot)
        check(dependencyLocals.contains { $0.folder == "Recharge" }, "real addon installed with its dependency")
        let dependencyLibrary = dependencyLocals.filter { $0.folder == "LibAddonMenu-2.0" }
        check(dependencyLibrary.count == 1 && addonKind(remote: nil, locals: dependencyLibrary) == .library, "missing library downloaded and recognized")
        check(autoRecharge.dependencies.allSatisfy { $0.satisfied(by: dependencyLocals.flatMap(\.manifests)) }, "installed dependency satisfies real minimum version")
        await rejectsAsync("real dependency cannot be removed while required") { try await installer.remove(folders: ["LibAddonMenu-2.0"], root: dependencyRoot) }
        let copiesBeforeRemoval = try await installer.backups(dependencyRoot).count
        let rechargeTrash = try await installer.remove(folders: ["Recharge"], root: dependencyRoot)
        check(!fm.fileExists(atPath: dependencyRoot.appendingPathComponent("Recharge").path) && fm.fileExists(atPath: dependencyRoot.appendingPathComponent("LibAddonMenu-2.0").path), "real addon trashed while dependency stays")
        check(try await installer.backups(dependencyRoot).count == copiesBeforeRemoval, "real removal creates no backup")
        try fm.moveItem(at: rechargeTrash[0], to: dependencyRoot.appendingPathComponent("Recharge"))
        check(fm.fileExists(atPath: dependencyRoot.appendingPathComponent("Recharge/Recharge.addon").path) || fm.fileExists(atPath: dependencyRoot.appendingPathComponent("Recharge/Recharge.txt").path), "real removed addon restored")
        let removableLocals = try scanAddons(dependencyRoot)
        let cleanupPlan = removalPreview(folders: ["Recharge"], locals: removableLocals, libraryFolders: ["LibAddonMenu-2.0"])
        check(cleanupPlan.libraries.count == 1 && cleanupPlan.libraries[0].canRemove, "real unused dependency identified")
        let removingFolders = cleanupPlan.folders(includeUnused: true)
        let cleanupTrash = try await installer.remove(folders: removingFolders, root: dependencyRoot)
        check(try scanAddons(dependencyRoot).isEmpty, "optional removal moves real addon and unused library to Trash")
        check(try await installer.backups(dependencyRoot).count == copiesBeforeRemoval, "optional dependency cleanup creates no backup")
        for (name, file) in zip(removingFolders, cleanupTrash) { try fm.moveItem(at: file, to: dependencyRoot.appendingPathComponent(name)) }
        check(try scanAddons(dependencyRoot).count == 2, "addon and optional dependency can be returned from Trash")
        let autoRoot = temp.appendingPathComponent("automatic/live/AddOns")
        try makeLocal(autoRoot, "LibAddonMenu-2.0", version: "0", number: 0)
        try await installer.save(LibraryState(ignored: [7]), root: autoRoot)
        let ignored = try await automaticUpdate(root: autoRoot, client: client, installer: installer, minion: temp.appendingPathComponent("no-minion.xml"), canModify: {}, progress: { _ in })
        check(try ignored.installed.isEmpty && ignored.failures.isEmpty && scanAddons(autoRoot).first?.primary?.version == "0", "background updates skip ignored addons")
        try await installer.save(LibraryState(), root: autoRoot)
        let updated = try await automaticUpdate(root: autoRoot, client: client, installer: installer, minion: temp.appendingPathComponent("no-minion.xml"), canModify: {}, progress: { _ in })
        let autoInstalled = try scanAddons(autoRoot)
        check(updated.installed.count == 1 && updated.failures.isEmpty && autoInstalled.first?.primary?.version == lam.version, "automatic updater installs a newer version")
        let autoCopies = try await installer.backups(autoRoot)
        check(autoCopies.count == 1 && autoCopies[0].status == "committed", "automatic update creates a backup")
        try await installer.restore(autoCopies[0], root: autoRoot)
        await rejectsAsync("automatic update pauses while another app is running") {
            _ = try await automaticUpdate(root: autoRoot, client: client, installer: installer, minion: temp.appendingPathComponent("no-minion.xml"), canModify: { throw AppError("backgroundPaused") }, progress: { _ in })
        }
        check(try scanAddons(autoRoot).first?.primary?.version == "0", "paused automatic update changes no addon files")
        let copiesBeforePause = try await installer.backups(autoRoot).count
        await rejectsAsync("game launch before commit stops installation") { try await installer.install(planned, root: autoRoot, beforeCommit: { throw AppError("backgroundPaused") }, download: download, progress: { _ in }) }
        check(try scanAddons(autoRoot).first?.primary?.version == "0", "pre-commit pause preserves old version")
        check(try await installer.backups(autoRoot).count == copiesBeforePause, "pre-commit pause leaves no partial backup")
        guard let quest = catalog.first(where: { $0.id == 13 }) else { fatalError("missing quest fixture") }
        let questRoot = temp.appendingPathComponent("quest/live/AddOns")
        try fm.createDirectory(at: questRoot, withIntermediateDirectories: true)
        let questPlan = try dependencyPlan([quest], catalog: catalog, locals: [], sources: [:])
        try await installer.install(questPlan, root: questRoot, download: download) { print("Quest package: \($0)") }
        check(try scanAddons(questRoot).contains { $0.folder == "RavaloxsQuestTracker" && $0.primary?.version == quest.version }, "real Ravalox archive installs despite obsolete documentation folder")
        check(!fm.fileExists(atPath: questRoot.appendingPathComponent("Ravalox'QuestTracker").path), "obsolete placeholder directory is never installed")
        guard let icons = catalog.first(where: { $0.id == 4161 }) else { fatalError("missing LibCustomIcons fixture") }
        let iconsRoot = temp.appendingPathComponent("custom-icons/live/AddOns")
        try fm.createDirectory(at: iconsRoot, withIntermediateDirectories: true)
        let iconsPlan = try dependencyPlan([icons], catalog: catalog, locals: [], sources: [:])
        let iconsResult = try await installer.install(iconsPlan, root: iconsRoot, download: download) { print("Icons package: \($0)") }
        check(try iconsResult.failures.isEmpty && scanAddons(iconsRoot).contains { $0.folder == "LibCustomIcons" && $0.primary?.version == icons.version }, "real LibCustomIcons archive installs")
        check(!fm.fileExists(atPath: iconsRoot.appendingPathComponent("LibCustomIcons/icons/MikaMilka/.gitkeep").path), "LibCustomIcons placeholder is not installed")
        check(catalog.contains { $0.favorites != nil && $0.downloadsMonthly != nil }, "live catalog provides favorite and monthly download counts")
        print("PASS: live ESOUI download, checksum, install, backup, restore, crash recovery, automatic dependency install (\(checks) total checks)")
    }
}
