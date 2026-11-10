import SwiftUI
import AppKit

@MainActor final class Manager: ObservableObject {
    let appUpdates = AppUpdater(repository: "TheMoldex/minion-alternative-eso-macos", asset: "ESO-Addons-for-Mac.zip")
    @Published var language = Language.preferred(saved: UserDefaults.standard.string(forKey: "language"), system: Locale.preferredLanguages.first) {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }
    @Published var folder: URL?
    @Published var catalog = [Addon]() { didSet { rebuildInstalled() } }
    @Published var installed = [AddonRow]()
    @Published var categories = [Int: AddonCategory]()
    @Published var locals = [LocalAddon]()
    @Published var sources = [String: Receipt]()
    @Published var backups = [Backup]()
    @Published var ignored: Set<Int> = []
    @Published var profiles = [ESOProfile]()
    @Published var history = [OperationRecord]()
    @Published var historyError: Error?
    @Published var snapshots = [SnapshotChoice]()
    @Published var snapshotName = ""
    @Published var deletingCopies: BackupRemoval?
    @Published var renamingSnapshot: SnapshotChoice?
    @Published var screenshotPreview: ScreenshotSelection?
    @Published var snapshotPreview: SnapshotChoice?
    @Published var settingsPreview: SettingsPreview?
    @Published var includeAddonFiles = true
    @Published var snapshotDirectory: URL
    @Published var parallelism = max(1, min(4, UserDefaults.standard.object(forKey: "parallelism") as? Int ?? 3)) {
        didSet { UserDefaults.standard.set(parallelism, forKey: "parallelism") }
    }
    @Published var busy = false
    @Published var choosing = false
    @Published var settingsVisible = false
    @Published var settingsTab = "general"
    @Published var blocked = false
    @Published var activity = "ready"
    @Published var detail = ""
    @Published var error: Error?
    @Published var section = "installed"
    @Published var query = ""
    @Published var installedFilters = AddonFilters()
    @Published var browseFilters = AddonFilters(sort: .downloads, descending: true)
    @Published var selection: String?
    @Published var plan: InstallPlan?
    @Published var restoring: Backup?
    @Published var removing: AddonRow?
    @Published var backupLimit = UserDefaults.standard.integer(forKey: "backupLimit") {
        didSet { UserDefaults.standard.set(backupLimit, forKey: "backupLimit") }
    }
    @Published var backupCleanupError: Error?
    @Published var autoUpdates = UserDefaults.standard.object(forKey: "autoUpdates") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoUpdates, forKey: "autoUpdates")
            nextBackground = Date().addingTimeInterval(BackgroundSchedule.interval)
            backgroundError = nil; backgroundState = "autoWaiting"
        }
    }
    @Published var nextBackground = UserDefaults.standard.object(forKey: "nextBackground") as? Date ?? Date().addingTimeInterval(BackgroundSchedule.interval) {
        didSet { UserDefaults.standard.set(nextBackground, forKey: "nextBackground") }
    }
    @Published var backgroundState = "autoWaiting"
    @Published var backgroundError: Error?
    @Published var backgroundCount = 0
    private var backgroundTask: Task<Void, Never>?
    let installer: Installer
    let client: CatalogClient
    let support: URL
    init() {
        support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ESOAddonsMac")
        snapshotDirectory = UserDefaults.standard.string(forKey: "snapshotDirectory").map { URL(fileURLWithPath: $0) } ?? support.appendingPathComponent("manual-backups")
        installer = Installer(home: support)
        client = CatalogClient(cache: support.appendingPathComponent("catalog.json"))
        UserDefaults.standard.set(autoUpdates, forKey: "autoUpdates")
        UserDefaults.standard.set(nextBackground, forKey: "nextBackground")
        if let saved = UserDefaults.standard.string(forKey: "folder") { folder = URL(fileURLWithPath: saved) }
        else {
            let detected = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Elder Scrolls Online/live/AddOns")
            if FileManager.default.fileExists(atPath: detected.path) { folder = detected }
        }
        profiles = UserDefaults.standard.data(forKey: "profiles").flatMap { try? JSONDecoder().decode([ESOProfile].self, from: $0) } ?? []
        if let folder { profiles = ESOProfile.adding(folder, to: profiles) }
        let pts = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Elder Scrolls Online/pts/AddOns")
        if FileManager.default.fileExists(atPath: pts.path) { profiles = ESOProfile.adding(pts, to: profiles) }
        persistProfiles()
    }
    deinit { backgroundTask?.cancel() }
    func start() async {
        guard backgroundTask == nil else { await refresh(); return }
        Task { await appUpdates.start() }
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                await self?.appUpdates.tick()
                await self?.backgroundTick()
            }
        }
        await refresh()
    }
    var operationPending: Bool { busy || choosing || plan != nil || restoring != nil || removing != nil || snapshotPreview != nil || settingsPreview != nil || deletingCopies != nil || renamingSnapshot != nil || screenshotPreview != nil }
    func backgroundTick() async {
        let occupied = blocked || operationPending || settingsVisible || appUpdates.showing
        guard let root = folder, BackgroundSchedule.due(enabled: autoUpdates, busy: occupied, next: nextBackground, now: Date()) else { return }
        busy = true; backgroundState = "autoChecking"; backgroundError = nil
        nextBackground = Date().addingTimeInterval(BackgroundSchedule.interval)
        defer { busy = false; detail = "" }
        await record("autoUpdates", "started")
        do {
            activity = "installing"
            let result = try await automaticUpdate(root: root, client: client, installer: installer, minion: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".minion/minion.xml"), parallelism: parallelism, canModify: { try RuntimeSafety.requireIdle() }) { title in await self.showProgress(title) }
            backgroundCount = result.installed.count
            catalog = await client.cached(); try await loadLocal(root, cleanup: backgroundCount > 0)
            backgroundState = backgroundCount == 0 ? "autoNoUpdates" : "autoDone"
            activity = backgroundCount == 0 ? "ready" : "installedDone"
            if let failure = installError(result) {
                backgroundError = failure
                nextBackground = Date().addingTimeInterval(900)
                await record("autoUpdates", "failed", error: failure)
            } else {
                await record("autoUpdates", "completed", detail: "\(backgroundCount)")
            }
        } catch {
            await record("autoUpdates", "failed", error: error)
            backgroundError = error
            let paused = (error as? AppError)?.key == "backgroundPaused"
            nextBackground = Date().addingTimeInterval(paused ? BackgroundSchedule.retry : 900)
            activity = "ready"
            do { if !paused { _ = try await installer.recover(root) }; try await loadLocal(root) }
            catch { blocked = true; backgroundError = error }
        }
    }
    var backgroundLabel: String {
        if let backgroundError { return localizedError(backgroundError) }
        return t(backgroundState) + (backgroundState == "autoDone" ? ": \(backgroundCount)" : "")
    }
    func t(_ key: String) -> String { language.text(key) }
    func rebuildInstalled() {
        var groups = [String: AddonRow]()
        for local in locals {
            let addon = resolveSource(local.folder, catalog: catalog, sources: sources)
            let id = addon.map { "remote:\($0.id)" } ?? "local:\(local.folder)"
            let members = (groups[id]?.locals ?? []) + [local]
            groups[id] = AddonRow(id: id, addon: addon, locals: members, status: addonStatus(addon, locals: members, sources: sources))
        }
        installed = groups.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var updates: [AddonRow] { installed.filter { $0.update && $0.addon?.supported == true && !ignored.contains($0.addon?.id ?? 0) } }
    var unknownCount: Int { installed.filter { $0.addon == nil }.count }
    var filters: AddonFilters {
        get { section == "browse" ? browseFilters : installedFilters }
        set { if section == "browse" { browseFilters = newValue } else { installedFilters = newValue } }
    }
    var defaultFilters: AddonFilters { section == "browse" ? AddonFilters(sort: .downloads, descending: true) : AddonFilters() }
    var narrowed: Bool { filters.active || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canResetFilters: Bool { filters != defaultFilters || !query.isEmpty }
    func resetFilters() { filters = defaultFilters; query = ""; selection = nil }
    var categoryOptions: [AddonCategory] {
        var ids = Set(baseRows.compactMap { $0.addon?.categoryId })
        if filters.category != 0 { ids.insert(filters.category) }
        return ids.map { categories[$0] ?? AddonCategory(id: String($0), title: "ESOUI #\($0)", iconUrl: "") }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var gameVersions: [String] {
        var versions = Set(baseRows.flatMap { $0.addon?.gameVersions ?? [] }.filter { !$0.isEmpty })
        if !filters.gameVersion.isEmpty { versions.insert(filters.gameVersion) }
        return versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
    }
    var rows: [AddonRow] { filters.apply(baseRows, query: query) }
    var baseRows: [AddonRow] {
        switch section {
        case "browse":
            let current = Dictionary(uniqueKeysWithValues: installed.compactMap { row in row.addon.map { ($0.id, row) } })
            return catalog.filter { $0.categoryId != 157 && $0.supported }.map { current[$0.id] ?? AddonRow(id: "remote:\($0.id)", addon: $0, locals: [], status: .notInstalled) }
        case "updates": return updates
        default: return installed
        }
    }
    func chooseFolder() {
        guard !operationPending else { return }
        choosing = true; defer { choosing = false }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = t("chooseHint"); panel.directoryURL = folder?.deletingLastPathComponent()
        guard panel.runModal() == .OK, var selected = panel.url else { return }
        choosing = false
        if selected.lastPathComponent.caseInsensitiveCompare("AddOns") != .orderedSame { selected.appendPathComponent("AddOns") }
        do {
            guard selected.lastPathComponent.caseInsensitiveCompare("AddOns") == .orderedSame else { throw AppError("chooseAddons") }
            try requireDirectory(selected)
            switchProfile(selected)
        } catch { self.error = error }
    }
    func refresh(force: Bool = false) async {
        guard !busy else { return }
        busy = true; blocked = false; activity = "scanning"; detail = ""
        defer { busy = false }
        let cached = await client.cached()
        if catalog.isEmpty { catalog = cached }
        do {
            if let root = folder {
                let recovered = try await installer.recover(root)
                try await loadLocal(root)
                if recovered > 0 { activity = "recovered" }
            }
        } catch {
            blocked = true; self.error = error; activity = "recoveryBlocked"
            if let root = folder { try? await loadLocal(root) }
            return
        }
        activity = "catalogLoading"
        do { catalog = try await client.catalog(force: force); activity = "ready" }
        catch { activity = catalog.isEmpty ? "noCatalog" : "cached"; self.error = error }
        if let entries = try? await client.categories() { categories = entries }
    }
    func loadLocal(_ root: URL, cleanup: Bool = false) async throws {
        locals = try await Task.detached { try scanAddons(root, tolerant: true) }.value
        sources = MinionReader.read(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".minion/minion.xml"), root: root)
        ignored = []
        defer { rebuildInstalled() }
        let state = try await installer.state(root)
        sources.merge(state.sources) { _, own in own }
        ignored = state.ignored
        do { history = try await installer.history(root); historyError = nil } catch { historyError = error }
        loadSnapshotList()
        if cleanup {
            do { try await installer.pruneBackups(root, keep: backupLimit); backupCleanupError = nil }
            catch { backupCleanupError = error }
        }
        backups = []
        backups = try await installer.backups(root).filter { $0.status == "committed" }
        let failures = locals.compactMap(\.scanError)
        if !failures.isEmpty { throw AppError("addonScanFailed", failures.joined(separator: "\n")) }
    }
    func prepare(_ addons: [Addon]) {
        guard !operationPending, !blocked else { return }
        do {
            let proposed = try dependencyPlan(addons, catalog: catalog, locals: locals, sources: sources)
            try respectIgnored(proposed, ignored: ignored)
            plan = proposed
        }
        catch { self.error = error }
    }
    func execute(_ planned: InstallPlan) async {
        guard let root = folder, !busy, !blocked else { return }
        busy = true; activity = "installing"; detail = ""; plan = nil
        defer { busy = false; detail = "" }
        await record("installing", "started", detail: planned.addons.map(\.title).joined(separator: ", "))
        do {
            let result = try await installer.install(planned, root: root, parallelism: parallelism, download: { [client] in try await client.download($0, to: $1) }) { title in
                await self.showProgress(title)
            }
            try await loadLocal(root, cleanup: !result.installed.isEmpty)
            activity = result.installed.isEmpty ? "ready" : "installedDone"
            if let failure = installError(result) {
                error = failure
                await record("installing", "failed", error: failure)
            } else {
                await record("installing", "completed", detail: result.installed.map(\.title).joined(separator: ", "))
            }
        } catch {
            await record("installing", "failed", error: error)
            self.error = error; activity = "ready"
            do { _ = try await installer.recover(root); try await loadLocal(root) }
            catch { blocked = true; self.error = error }
        }
    }
    private func showProgress(_ title: String) async { detail = title; await record("downloading", "started", detail: title) }
    func link(_ addon: Addon, local: LocalAddon) async {
        guard let root = folder, !busy, !blocked else { return }
        busy = true; defer { busy = false }
        do {
            var state = try await installer.state(root)
            state.sources[local.folder] = Receipt(id: addon.id, version: local.primary?.version ?? "")
            try await installer.save(state, root: root); try await loadLocal(root)
            selection = "remote:\(addon.id)"
        } catch { self.error = error }
    }
    func restore(_ backup: Backup) async {
        guard let root = folder, !busy, !blocked else { return }
        busy = true; activity = "restoring"; restoring = nil
        defer { busy = false }
        await record("restoring", "started", detail: backup.label)
        do { try await installer.restore(backup, root: root); try await loadLocal(root, cleanup: true); activity = "restoreDone"; await record("restoring", "completed", detail: backup.label) }
        catch { await record("restoring", "failed", error: error); self.error = error; do { _ = try await installer.recover(root); try await loadLocal(root) } catch { blocked = true; self.error = error } }
    }
    func prepareRemoval(_ row: AddonRow) {
        removing = row
    }
    func previewRemoval(_ row: AddonRow) -> RemovalPreview {
        let libraries = Set(locals.filter { local in
            addonKind(remote: resolveSource(local.folder, catalog: catalog, sources: sources), locals: [local]) == .library
        }.map(\.folder))
        return removalPreview(folders: row.locals.map(\.folder), locals: locals, libraryFolders: libraries)
    }
    func remove(_ row: AddonRow, includeUnused: Bool) async {
        guard let root = folder, !busy, !blocked else { return }
        let folders = previewRemoval(row).folders(includeUnused: includeUnused)
        busy = true; activity = "removing"; removing = nil
        defer { busy = false }
        await record("removing", "started", detail: folders.joined(separator: ", "))
        do {
            try await installer.remove(folders: folders, root: root)
            selection = nil; try await loadLocal(root); activity = "removeDone"
            await record("removing", "completed", detail: folders.joined(separator: ", "))
        } catch {
            await record("removing", "failed", error: error)
            self.error = error; activity = "ready"
            do { _ = try await installer.recover(root); try await loadLocal(root) }
            catch { blocked = true; self.error = error }
        }
    }
    private func installError(_ result: InstallResult) -> AppError? {
        guard !result.failures.isEmpty else { return nil }
        if result.installed.isEmpty && result.failures.count == 1 { return result.failures[0] }
        let counts = "\(t("installed")): \(result.installed.count) · \(t("packagesSkipped")): \(result.failures.count)"
        return AppError("somePackagesFailed", counts + "\n\n" + result.failures.map(localizedError).joined(separator: "\n\n"))
    }
    func localizedError(_ error: Error) -> String {
        if let app = error as? AppError { return t(app.key) + (app.detail.isEmpty ? "" : "\n\n" + app.detail) }
        return error.localizedDescription
    }
    var errorText: String {
        guard let error else { return "" }
        return localizedError(error)
    }
}

struct MainView: View {
    @ObservedObject var model: Manager
    @Environment(\.openSettings) private var openSettings
    @State private var backupPage = 0
    @State private var selectedBackupIDs = Set<String>()
    @State private var selectedDetails: DownloadDetails?
    @State private var detailsFailure: Error?
    @State private var detailsAttempt = 0
    @AppStorage("layout.sidebarWidth") private var sidebarWidth = 220.0
    @AppStorage("layout.detailsWidth") private var detailsWidth = 330.0
    private let accent = Color(red: 0.25, green: 0.54, blue: 0.98)
    var body: some View {
        GeometryReader { geometry in
          let layout = PaneLayout(width: Double(geometry.size.width), sidebar: sidebarWidth, details: detailsWidth)
          HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(systemName: "shippingbox.fill").font(.system(size: 30)).foregroundStyle(accent.gradient)
                    VStack(alignment: .leading, spacing: 2) { Text("ESO Addons").font(.title2.bold()); Text("for Mac").foregroundStyle(.secondary) }
                }.padding(.horizontal, 16).padding(.top, 24)
                List(selection: $model.section) {
                    Label(model.t("installed"), systemImage: "square.stack.3d.up").tag("installed")
                    Label(model.t("browse"), systemImage: "magnifyingglass").tag("browse")
                    HStack { Label(model.t("updates"), systemImage: "arrow.down.circle"); Spacer(); Text("\(model.updates.count)").foregroundStyle(.secondary) }.tag("updates")
                    Label(model.t("backups"), systemImage: "clock.arrow.circlepath").tag("backups")
                    Label(model.t("history"), systemImage: "list.bullet.rectangle").tag("history")
                }.listStyle(.sidebar).frame(minHeight: 112)
                VStack(alignment: .leading, spacing: 12) {
                    AppUpdateControl(updater: model.appUpdates, text: model.t, canPresent: !model.operationPending && !model.settingsVisible && model.error == nil, compact: true)
                    if model.backgroundError != nil {
                        Button { model.settingsTab = "updates"; openSettings() } label: {
                            Label(model.t("autoUpdateProblem"), systemImage: "exclamationmark.triangle")
                        }.buttonStyle(.link).foregroundStyle(.orange).font(.caption).help(model.backgroundLabel)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.folder?.deletingLastPathComponent().lastPathComponent ?? model.t("choose")).font(.caption.weight(.medium))
                            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.caption2).foregroundStyle(.secondary)
                        }.help(model.folder?.path ?? "")
                        Spacer()
                        Button { openSettings() } label: { Image(systemName: "gearshape").font(.title3) }
                            .buttonStyle(.plain).help(model.t("settings")).accessibilityLabel(model.t("settings")).accessibilityIdentifier("openSettings")
                    }
                }.padding(16)
            }.frame(width: CGFloat(layout.sidebar)).background(Color(nsColor: .windowBackgroundColor))
            PaneDivider(width: Binding(get: { layout.sidebar }, set: { sidebarWidth = $0 }), range: 180...layout.sidebarMaximum, label: model.t("resizeSidebar"))
            VStack(spacing: 0) {
                header(width: layout.main)
                Divider()
                if model.folder == nil { ContentUnavailableView { Label(model.t("choose"), systemImage: "folder.badge.plus") } description: { Text(model.t("chooseHint")) } actions: { Button(model.t("choose"), action: model.chooseFolder) } }
                else if model.section == "backups" { backups }
                else if model.section == "history" { HistoryPanel(model: model) }
                else { content(layout: layout).frame(minHeight: 220, maxHeight: .infinity) }
                Divider()
                HStack(spacing: 8) {
                    if model.busy { ProgressView().controlSize(.small) } else { Image(systemName: model.blocked ? "exclamationmark.triangle" : "checkmark.circle").foregroundStyle(model.blocked ? .orange : .secondary) }
                    Text(model.t(model.activity) + (model.detail.isEmpty ? "" : ": " + model.detail)).lineLimit(1).font(.caption)
                    Spacer()
                    Text(model.t("reloadHint")).font(.caption).foregroundStyle(.secondary)
                }.padding(12).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(minWidth: 980, minHeight: 620)
        .tint(accent)
        .task { await model.start() }
        .onChange(of: model.section) { _, _ in model.selection = nil; model.query = "" }
        .alert(model.t("errorTitle"), isPresented: Binding(get: { model.error != nil && !model.settingsVisible }, set: { if !$0 && !model.settingsVisible { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.errorText) }
        .sheet(isPresented: Binding(get: { model.plan != nil }, set: { if !$0 { model.plan = nil } })) {
            if let plan = model.plan { planView(plan) }
        }
        .confirmationDialog(model.t("restoreTitle"), isPresented: Binding(get: { model.restoring != nil }, set: { if !$0 { model.restoring = nil } }), titleVisibility: .visible) {
            if let backup = model.restoring { Button(model.t("restore")) { Task { await model.restore(backup) } } }
            Button(model.t("cancel"), role: .cancel) { model.restoring = nil }
        } message: { Text(model.t("restoreHint")) }
        .confirmationDialog(model.t("deleteBackupsTitle"), isPresented: Binding(get: { model.deletingCopies != nil }, set: { if !$0 { model.deletingCopies = nil } }), titleVisibility: .visible) {
            if let selected = model.deletingCopies { Button(model.t("deleteBackups") + " (\(selected.count))", role: .destructive) { Task { await model.removeCopies(selected) } } }
            Button(model.t("cancel"), role: .cancel) { model.deletingCopies = nil }
        } message: {
            Text(model.t("deleteBackupsHint"))
        }
        .sheet(item: $model.screenshotPreview) { selection in ScreenshotViewer(selection: selection, model: model) }
        .sheet(item: $model.renamingSnapshot) { choice in RenameBackupPanel(choice: choice, model: model) }
        .sheet(item: $model.settingsPreview) { preview in SettingsResetPanel(preview: preview, model: model) }
        .sheet(item: $model.snapshotPreview) { choice in SnapshotRestorePanel(choice: choice, model: model) }
        .sheet(isPresented: Binding(get: { model.removing != nil }, set: { if !$0 { model.removing = nil } })) {
            if let row = model.removing { RemovalView(row: row, model: model).id(row.id) }
        }
    }
    private func header(width: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let stack = width < 820 ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            stack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.t(model.section)).font(.system(size: 28, weight: .bold))
                    Text("\(model.t("folderCount")): \(model.locals.count)  ·  \(model.t("catalogCount")): \(model.catalog.count)  ·  \(model.t("unknownSources")): \(model.unknownCount)").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button { Task { await model.refresh(force: true) } } label: { Label(model.t("refresh"), systemImage: "arrow.clockwise") }.disabled(model.busy)
                    Button { model.prepare(model.updates.compactMap(\.addon)) } label: { Label(model.t("updateAll") + " (\(model.updates.count))", systemImage: "arrow.down.to.line") }.buttonStyle(.borderedProminent).disabled(model.busy || model.blocked || model.updates.isEmpty)
                }.fixedSize(horizontal: true, vertical: false)
            }
            if model.section != "backups" && model.section != "history" {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(model.t("search"), text: $model.query).textFieldStyle(.plain); if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) } }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                filters(compact: width < 740)
            }
        }.padding(22).fixedSize(horizontal: false, vertical: true)
    }
    private func filters(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            let stack = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 9)) : AnyLayout(HStackLayout(spacing: 10))
            stack {
                HStack(spacing: 10) {
                    Picker(model.t("category"), selection: $model.filters.category) {
                        Text(model.t("allCategories")).tag(0)
                        ForEach(model.categoryOptions, id: \.id) { category in Text(category.title).tag(Int(category.id) ?? 0) }
                    }.labelsHidden().frame(minWidth: 160, maxWidth: .infinity).help(model.t("category"))
                    Picker(model.t("addonType"), selection: $model.filters.kind) {
                        Text(model.t("allTypes")).tag(Optional<AddonKind>.none)
                        Text(model.t("addon")).tag(Optional(AddonKind.addon))
                        Text(model.t("library")).tag(Optional(AddonKind.library))
                    }.labelsHidden().frame(width: 130).help(model.t("addonType"))
                    Picker(model.t("esoVersion"), selection: $model.filters.gameVersion) {
                        Text(model.t("allGameVersions")).tag("")
                        ForEach(model.gameVersions, id: \.self) { version in Text("ESO \(version)").tag(version) }
                    }.labelsHidden().frame(width: 150).help(model.t("compatibilityHint"))
                }
                HStack(spacing: 10) {
                    Picker(model.t("sort"), selection: Binding(get: { model.filters.sort }, set: { sort in model.filters.sort = sort; model.filters.descending = sort != .name })) {
                        ForEach(AddonSort.allCases, id: \.self) { sort in Text(model.t(sort.rawValue)).tag(sort) }
                    }.labelsHidden().frame(width: 150).help(model.t("sort"))
                    Button { model.filters.descending.toggle() } label: {
                        Image(systemName: model.filters.descending ? "arrow.down" : "arrow.up")
                    }.help(model.t(model.filters.descending ? "descending" : "ascending"))
                        .accessibilityLabel(model.t(model.filters.descending ? "descending" : "ascending"))
                }.fixedSize(horizontal: true, vertical: false)
            }
            HStack {
                Text("\(model.t("shown")): \(model.rows.count) \(model.t("outOf")) \(model.baseRows.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.t("resetFilters")) { model.resetFilters() }.buttonStyle(.link).disabled(!model.canResetFilters)
            }
        }
    }
    private func content(layout: PaneLayout) -> some View {
        HStack(spacing: 0) {
            let rows = model.rows
            if rows.isEmpty {
                if model.narrowed {
                    ContentUnavailableView {
                        Label(model.t("noMatches"), systemImage: "line.3.horizontal.decrease.circle")
                    } description: { Text(model.t("noMatchesHint")) }
                    actions: { Button(model.t("resetFilters")) { model.resetFilters() } }
                        .frame(minWidth: 300, maxWidth: .infinity)
                } else {
                    ContentUnavailableView(model.t(model.section == "updates" ? "noUpdates" : "empty"), systemImage: model.section == "updates" ? "checkmark.seal" : "shippingbox", description: Text(model.t(model.section == "updates" ? "noUpdatesHint" : "search")))
                        .frame(minWidth: 300, maxWidth: .infinity)
                }
            } else {
                List(rows, selection: $model.selection) { row in
                    HStack(spacing: 12) {
                        CategoryIcon(category: row.addon.flatMap { model.categories[$0.categoryId] }, kind: row.kind, client: model.client)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(row.title).font(.headline).lineLimit(1); kindBadge(row.kind) }
                            Text([row.addon.flatMap { model.categories[$0.categoryId]?.title }, row.addon?.author ?? row.folderText].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            status(row)
                            if let addon = row.addon {
                                HStack(spacing: 12) {
                                    if let downloads = addon.downloads { Label(downloads.formatted(), systemImage: "arrow.down.to.line") }
                                    if let favorites = addon.favorites { Label(favorites.formatted(), systemImage: "heart") }
                                }.font(.caption2).foregroundStyle(.secondary)
                            }
                            if let addon = row.addon, model.ignored.contains(addon.id) { Label(model.t("updatesIgnored"), systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                    }.padding(.vertical, 7).contentShape(Rectangle()).tag(row.id)
                }.contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let row = rows.first(where: { $0.id == id }) { rowMenu(row) }
                }.listStyle(.inset).frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    .id(model.filters).id(model.query).id(model.section)
            }
            PaneDivider(width: Binding(get: { layout.details }, set: { detailsWidth = $0 }), range: 280...layout.detailsMaximum, label: model.t("resizeDetails"), reversed: true)
            if let row = rows.first(where: { $0.id == model.selection }) { detail(row).frame(width: CGFloat(layout.details)) }
            else { ContentUnavailableView(model.t("select"), systemImage: "puzzlepiece.extension", description: Text(model.t("selectHint"))).frame(width: CGFloat(layout.details)) }
        }
    }
    @ViewBuilder private func rowMenu(_ row: AddonRow) -> some View {
        Text(row.title)
        Button { model.selection = row.id } label: { Label(model.t("showDetails"), systemImage: "info.circle") }
        if let addon = row.addon {
            if !row.locals.isEmpty {
                Button(model.t(model.ignored.contains(addon.id) ? "resumeUpdates" : "ignoreUpdates")) { Task { await model.toggleIgnored(addon) } }.disabled(model.busy)
            }
            Button { model.prepare([addon]) } label: { Label(model.t(row.locals.isEmpty ? "install" : row.update ? "update" : "reinstall"), systemImage: "arrow.down.to.line") }.disabled(model.busy || model.blocked || !addon.supported)
            Button { openWebsite(addon) } label: { Label(model.t("openWebsite"), systemImage: "arrow.up.right.square") }
        }
        if let root = model.folder, !row.locals.isEmpty {
            Divider()
            if row.locals.count == 1, let local = row.locals.first {
                Button { NSWorkspace.shared.open(root.appendingPathComponent(local.folder)) } label: { Label(model.t("openAddonFolder"), systemImage: "folder") }
            } else {
                Menu { ForEach(row.locals) { local in Button(local.folder) { NSWorkspace.shared.open(root.appendingPathComponent(local.folder)) } } } label: { Label(model.t("openAddonFolder"), systemImage: "folder") }
            }
            Button(model.t("resetSettings")) { model.prepareSettingsReset(row) }.disabled(model.busy || model.blocked)
            removeButton(row)
        }
    }
    private func openWebsite(_ addon: Addon) {
        guard let url = URL(string: addon.fileInfoUri ?? "https://www.esoui.com/downloads/info\(addon.id).html"), NetworkGuard.allowed(url) else { return }
        NSWorkspace.shared.open(url)
    }
    private func detail(_ row: AddonRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CategoryIcon(category: row.addon.flatMap { model.categories[$0.categoryId] }, kind: row.kind, client: model.client).padding(.top, 8)
                Text(row.title).font(.title2.bold()).textSelection(.enabled)
                kindBadge(row.kind)
                if let addon = row.addon {
                    Text(addon.author).foregroundStyle(.secondary)
                    if let details = selectedDetails, details.id == addon.id {
                        ScreenshotGallery(images: details.screenshots, title: addon.title, model: model)
                    }
                    if !row.locals.isEmpty { field("localVersion", row.version.isEmpty ? model.t("unknown") : row.version) }
                    field("remoteVersion", addon.version)
                    HStack(spacing: 18) {
                        if let downloads = addon.downloads { Label(downloads.formatted(), systemImage: "arrow.down.to.line").help(model.t("sortDownloads")) }
                        if let favorites = addon.favorites { Label(favorites.formatted(), systemImage: "heart").help(model.t("favorites")) }
                    }.font(.caption).foregroundStyle(.secondary)
                    if let monthly = addon.downloadsMonthly { Text(model.t("monthlyDownloads") + ": " + monthly.formatted()).font(.caption).foregroundStyle(.secondary) }
                    status(row)
                    Button { model.prepare([addon]) } label: { Label(model.t(row.locals.isEmpty ? "install" : row.update ? "update" : "reinstall"), systemImage: "arrow.down.to.line").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy || model.blocked || !addon.supported)
                    if !addon.supported { Text(model.t("unsupportedAddon")).font(.caption).foregroundStyle(.orange) }
                    Button { openWebsite(addon) } label: { Label(model.t("openWebsite"), systemImage: "arrow.up.right.square") }.buttonStyle(.link)
                    if !row.locals.isEmpty {
                        Button(model.t(model.ignored.contains(addon.id) ? "resumeUpdates" : "ignoreUpdates")) { Task { await model.toggleIgnored(addon) } }.disabled(model.busy)
                        Button(model.t("resetSettings")) { model.prepareSettingsReset(row) }.disabled(model.busy || model.blocked)
                        removeButton(row)
                    }
                    Divider()
                    DescriptionView(details: selectedDetails?.id == addon.id ? selectedDetails : nil, failure: detailsFailure, model: model, retry: { detailsAttempt += 1 }).id("\(addon.id):\(addon.version)")
                    Divider()
                    field("folders", addon.folders.joined(separator: "\n"))
                    field("dependencies", addon.dependencies.isEmpty ? model.t("none") : Set(addon.dependencies.map(\.display)).sorted().joined(separator: "\n"))
                    field("source", "ESOUI #\(addon.id)")
                } else if let local = row.locals.first {
                    status(row)
                    field("localVersion", local.primary?.version ?? model.t("unknown"))
                    field("folders", local.folder)
                    let candidates = sourceCandidates(local.folder, catalog: model.catalog)
                    Label(model.t(candidates.isEmpty ? "notFound" : "ambiguous"), systemImage: "questionmark.circle").foregroundStyle(.secondary)
                    if !candidates.isEmpty {
                        Menu(model.t("linkSource")) { ForEach(candidates) { addon in Button("\(addon.title) · #\(addon.id) · \(addon.version)") { Task { await model.link(addon, local: local) } } } }.disabled(model.busy || model.blocked)
                    }
                    field("dependencies", (local.primary?.dependencies ?? []).map(\.display).joined(separator: "\n"))
                    Button(model.t("resetSettings")) { model.prepareSettingsReset(row) }.disabled(model.busy || model.blocked)
                    removeButton(row)
                }
                Spacer()
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.task(id: "\(row.id):\(row.addon?.version ?? ""):\(detailsAttempt)") { await loadDetails(row.addon) }
    }
    @MainActor private func loadDetails(_ addon: Addon?) async {
        selectedDetails = nil; detailsFailure = nil
        guard let addon else { return }
        do {
            let entry = try await model.client.details(addon.id)
            if !Task.isCancelled { selectedDetails = entry }
        } catch { if !Task.isCancelled { detailsFailure = error } }
    }
    private func removeButton(_ row: AddonRow) -> some View {
        Button(role: .destructive) { model.prepareRemoval(row) } label: { Label(model.t("remove"), systemImage: "trash") }.disabled(model.busy || model.blocked)
    }
    private func status(_ row: AddonRow) -> some View {
        let symbol: String
        let color: Color
        switch row.status {
        case .newVersion: symbol = "arrow.down.circle.fill"; color = .orange
        case .upToDate: symbol = "checkmark.circle.fill"; color = .green
        case .newerVersion: symbol = "arrow.up.circle"; color = .blue
        case .versionUnknown: symbol = "questionmark.circle"; color = .secondary
        case .notInstalled: symbol = "plus.circle"; color = .secondary
        }
        let versions = row.locals.isEmpty ? row.addon?.version ?? "" : row.update ? "\(row.version.isEmpty ? model.t("unknown") : row.version) → \(row.addon?.version ?? "")" : row.version
        return VStack(alignment: .leading, spacing: 3) {
            Label(model.t(row.status.rawValue), systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(color)
            if !versions.isEmpty { Text(versions).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).help(versions) }
        }
    }
    private func field(_ key: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(model.t(key)).font(.caption).foregroundStyle(.secondary); Text(value.isEmpty ? "—" : value).font(.callout).textSelection(.enabled) } }
    private func kindBadge(_ kind: AddonKind) -> some View {
        let color: Color = kind == .library ? .mint : kind == .addon ? accent : .secondary
        return Text(model.t(kind.rawValue)).font(.caption2.weight(.medium)).lineLimit(1).padding(.horizontal, 7).padding(.vertical, 3).foregroundStyle(color).background(color.opacity(0.14), in: Capsule()).fixedSize()
    }
    private var backups: some View {
        VStack(spacing: 0) {
            Picker(model.t("backups"), selection: $backupPage) {
                Text(model.t("manualBackups")).tag(0)
                Text(model.t("rollbackCopies")).tag(1)
            }.pickerStyle(.segmented).labelsHidden().padding(20)
            if backupPage == 0 { SnapshotPanel(model: model) }
            else { rollbackBackups }
        }
    }
    private var rollbackBackups: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.t("backupHint")).foregroundStyle(.secondary)
            Text(model.t("backupRetention") + ": " + (model.backupLimit == 0 ? model.t("keepAllBackups") : model.t("lastBackups") + " \(model.backupLimit)")).font(.caption).foregroundStyle(.secondary)
            Text(model.t("retentionHint")).font(.caption).foregroundStyle(.secondary)
            if let error = model.backupCleanupError { Text(model.t("cleanupFailed") + "\n" + model.localizedError(error)).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button(model.t("openBackups")) { NSWorkspace.shared.open(model.support) }
                Spacer()
                Button(role: .destructive) { model.prepareCopyRemoval(backups: model.backups.filter { selectedBackupIDs.contains($0.id) }) } label: {
                    Label(model.t("deleteSelected") + " (\(selectedBackupIDs.count))", systemImage: "trash")
                }.disabled(model.busy || selectedBackupIDs.isEmpty)
            }
            Text(model.t("backupSelectionHint")).font(.caption).foregroundStyle(.secondary)
            List(model.backups, selection: $selectedBackupIDs) { backup in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(backup.date, format: .dateTime.year().month().day().hour().minute())
                        Text(backup.label).lineLimit(2).foregroundStyle(.secondary)
                        Text("\(model.t("backupCount")): \(backup.folders.count)").font(.caption)
                        if backup.hashes == nil { Text(model.t("unverifiedBackup")).font(.caption).foregroundStyle(.orange) }
                    }
                    Spacer(); Button(model.t("restore")) { model.restoring = backup }.disabled(model.busy || model.blocked || backup.hashes == nil)
                }.padding(.vertical, 8).contentShape(Rectangle()).tag(backup.id)
            }.contextMenu(forSelectionType: String.self) { ids in
                let chosen = model.backups.filter { ids.contains($0.id) }
                if chosen.count == 1, let backup = chosen.first {
                    Button(model.t("restore")) { model.restoring = backup }.disabled(model.busy || model.blocked || backup.hashes == nil)
                }
                if !chosen.isEmpty {
                    Button(model.t("deleteBackups") + " (\(chosen.count))", role: .destructive) { model.prepareCopyRemoval(backups: chosen) }.disabled(model.busy)
                }
            }.onDeleteCommand { model.prepareCopyRemoval(backups: model.backups.filter { selectedBackupIDs.contains($0.id) }) }
                .onAppear { selectedBackupIDs.formIntersection(model.backups.map(\.id)) }
                .onChange(of: model.backups.map(\.id)) { _, ids in selectedBackupIDs.formIntersection(ids) }
                .onChange(of: model.folder) { _, _ in selectedBackupIDs = [] }
        }.padding(22)
    }
    private func planView(_ plan: InstallPlan) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.t("planTitle")).font(.title2.bold())
            Text(model.t("planHint"))
            List(plan.addons) { addon in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(addon.title); kindBadge(addon.kind) }
                        Text(addon.folders.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        if !plan.requestedIDs.contains(addon.id) { Text(model.t("autoDependency")).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(); Text(addon.version).foregroundStyle(.secondary)
                }
            }.frame(height: min(300, CGFloat(plan.addons.count * 70 + 30)))
            if !plan.missing.isEmpty { Label(model.t("missingDependencies"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange); Text(plan.missing.joined(separator: ", ")).textSelection(.enabled) }
            Text(model.t("savedHint")).font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button(model.t("cancel")) { model.plan = nil }.keyboardShortcut(.cancelAction); Button(model.t("continue")) { Task { await model.execute(plan) } }.buttonStyle(.borderedProminent).disabled(!plan.missing.isEmpty).keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width: 570)
    }
}

struct CategoryIcon: View {
    let category: AddonCategory?
    let kind: AddonKind
    let client: CatalogClient
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: kind.symbol).font(.title2).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary.opacity(0.4)) }
        }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
            .task(id: category?.iconUrl) {
                image = nil
                if let category, let data = await client.icon(category), !Task.isCancelled { image = NSImage(data: data) }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !UserDefaults.standard.bool(forKey: "autoUpdates") }
}

@main struct ESOAddonsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = Manager()
    var body: some Scene {
        Window("ESO Addons for Mac", id: "main") { MainView(model: model).environment(\.locale, Locale(identifier: model.language.rawValue)) }.defaultSize(width: 1160, height: 760)
            .commands { CommandGroup(after: .appInfo) { Button(model.t("checkAppUpdates")) { Task { await model.appUpdates.check(manual: true) } } } }
        Settings { PreferencesView(model: model).environment(\.locale, Locale(identifier: model.language.rawValue)) }
        MenuBarExtra("ESO Addons", systemImage: "shippingbox") { TrayView(model: model).environment(\.locale, Locale(identifier: model.language.rawValue)) }
    }
}

struct TrayView: View {
    @ObservedObject var model: Manager
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(model.t("showWindow")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Toggle(model.t("autoUpdates"), isOn: $model.autoUpdates).disabled(model.busy)
        if model.autoUpdates { Text(model.backgroundLabel) }
        Button(model.t("refresh")) { Task { await model.refresh(force: true) } }.disabled(model.busy)
        Button(model.t("checkAppUpdates")) { openWindow(id: "main"); Task { await model.appUpdates.check(manual: true) } }
        Divider()
        Button(model.t("quit")) { NSApp.terminate(nil) }
    }
}

struct RemovalView: View {
    let row: AddonRow
    @ObservedObject var model: Manager
    @State private var includeUnused = false
    var body: some View {
        let preview = model.previewRemoval(row)
        let folders = preview.folders(includeUnused: includeUnused)
        let blockers = removalDependents(folders: folders, locals: model.locals)
        VStack(alignment: .leading, spacing: 16) {
            Text(model.t("removeTitle")).font(.title2.bold())
            Text(row.title).font(.headline)
            Text(model.t("removeHint")).font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.t("foldersToRemove")).font(.headline)
                    Text(folders.joined(separator: "\n")).textSelection(.enabled)
                    if !preview.libraries.isEmpty {
                        Divider()
                        Text(model.t("dependencyLibraries")).font(.headline)
                        ForEach(preview.libraries) { library in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: library.canRemove && includeUnused ? "trash" : "lock.shield")
                                    Text(library.title).font(.headline)
                                    Spacer()
                                    Text(model.t(library.canRemove && includeUnused ? "willRemoveLibrary" : "willKeepLibrary")).font(.caption).foregroundStyle(.secondary)
                                }
                                if library.canRemove {
                                    Text(model.t("libraryUnused")).font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(model.t("libraryUsedBy") + " " + library.usedBy.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    if !blockers.isEmpty { Label(model.t("addonRequired"), systemImage: "lock.shield").foregroundStyle(.orange); Text(blockers.joined(separator: "\n")).font(.callout).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: min(330, 80 + CGFloat(preview.libraries.count) * 90 + CGFloat(blockers.count) * 26))
            if !preview.libraries.isEmpty {
                Toggle(model.t("removeUnusedLibraries"), isOn: $includeUnused).disabled(!preview.libraries.contains(where: \.canRemove))
            }
            Text(model.t("sharedLibrariesStay")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(model.t("cancel")) { model.removing = nil }.keyboardShortcut(.cancelAction)
                Button(model.t("remove"), role: .destructive) { Task { await model.remove(row, includeUnused: includeUnused) } }.disabled(!blockers.isEmpty || model.busy || model.blocked)
            }
        }.padding(26).frame(width: 620).onAppear { includeUnused = false }
    }
}

struct DescriptionView: View {
    let details: DownloadDetails?
    let failure: Error?
    @ObservedObject var model: Manager
    let retry: () -> Void
    @State private var tab = "description"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(model.t("description"), selection: $tab) { Text(model.t("description")).tag("description"); Text(model.t("changeLog")).tag("changeLog") }.pickerStyle(.segmented).labelsHidden()
            if let details {
                let text = descriptionText((tab == "description" ? details.description : details.changeLog) ?? "")
                Text(verbatim: text.isEmpty ? model.t("noDescription") : text).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            } else if let failure {
                Text(model.localizedError(failure)).font(.caption).foregroundStyle(.secondary)
                Button(model.t("retry"), action: retry)
            } else { ProgressView().controlSize(.small) }
        }
    }
}
