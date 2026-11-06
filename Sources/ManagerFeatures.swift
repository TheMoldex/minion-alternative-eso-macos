import SwiftUI
import AppKit

extension Manager {
    func persistProfiles() { UserDefaults.standard.set(try? JSONEncoder().encode(profiles), forKey: "profiles") }
    func switchProfile(_ root: URL) {
        guard !operationPending else { return }
        folder = root.standardizedFileURL
        profiles = ESOProfile.adding(root, to: profiles); persistProfiles()
        UserDefaults.standard.set(root.path, forKey: "folder")
        selection = nil; locals = []; installed = []; sources = [:]; ignored = []; backups = []; history = []
        backgroundError = nil; backgroundState = "autoWaiting"
        nextBackground = Date().addingTimeInterval(BackgroundSchedule.interval)
        Task { await refresh() }
    }
    func forgetProfile() {
        guard let folder, !operationPending else { return }
        profiles.removeAll { $0.path == folder.standardizedFileURL.path }; persistProfiles()
        self.folder = nil; UserDefaults.standard.removeObject(forKey: "folder")
        selection = nil; locals = []; installed = []; sources = [:]; ignored = []; backups = []; history = []
        if let first = profiles.first { switchProfile(URL(fileURLWithPath: first.path)) }
    }
    func toggleIgnored(_ addon: Addon) async { await toggleIgnored(addon.id, title: addon.title) }
    func toggleIgnored(_ id: Int, title: String) async {
        guard let root = folder, !busy, !blocked else { return }
        busy = true; defer { busy = false }
        do {
            var state = try await installer.state(root)
            if state.ignored.contains(id) { state.ignored.remove(id) } else { state.ignored.insert(id) }
            try await installer.save(state, root: root)
            ignored = state.ignored
            await record(state.ignored.contains(id) ? "ignoreUpdates" : "resumeUpdates", "completed", detail: title)
        } catch { self.error = error }
    }
    func record(_ operation: String, _ outcome: String, detail: String = "", error: Error? = nil) async {
        guard let root = folder else { return }
        let message = error.map { ($0 as? AppError).map { $0.key + "\n" + $0.detail } ?? $0.localizedDescription } ?? detail
        do {
            try await installer.record(root, operation: operation, outcome: outcome, detail: message)
            history = try await installer.history(root); historyError = nil
        } catch { historyError = error }
    }
    func prepareSettingsReset(_ row: AddonRow) {
        guard let root = folder, !busy else { return }
        do {
            let folders = row.locals.map(\.folder)
            let files = try addonSettings(folders: folders, locals: scanAddons(root), live: root.deletingLastPathComponent())
            settingsPreview = SettingsPreview(title: row.title, folders: folders, files: files)
        } catch { self.error = error }
    }
    func resetSettings(_ preview: SettingsPreview) async {
        guard let root = folder, !busy, !blocked else { return }
        busy = true; settingsPreview = nil
        defer { busy = false }
        await record("resetSettings", "started", detail: preview.title)
        do {
            try await installer.resetSettings(preview, root: root)
            await record("resetSettings", "completed", detail: preview.files.joined(separator: ", "))
        } catch { self.error = error; await record("resetSettings", "failed", error: error) }
    }
    func chooseSnapshotDirectory() {
        guard !operationPending else { return }
        choosing = true; defer { choosing = false }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.directoryURL = snapshotDirectory; panel.message = t("snapshotLocation")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        snapshotDirectory = url
        UserDefaults.standard.set(url.path, forKey: "snapshotDirectory")
        loadSnapshotList()
    }
    func loadSnapshotList() {
        do {
            let fm = FileManager.default
            if !fm.fileExists(atPath: snapshotDirectory.path) { snapshots = []; return }
            try requireDirectory(snapshotDirectory)
            snapshots = try fm.contentsOfDirectory(at: snapshotDirectory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("ESO-Backup-") }.compactMap { location in
                try snapshotMetadata(location)
            }.sorted { $0.snapshot.date > $1.snapshot.date }
        } catch { self.error = error }
    }
    func createSnapshot() async {
        guard let root = folder, !busy, !blocked else { return }
        busy = true; activity = "createSnapshot"
        defer { busy = false; activity = "ready" }
        await record("createSnapshot", "started")
        do {
            try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
            let choice = try await installer.createSnapshot(root: root, destination: snapshotDirectory, includeAddons: includeAddonFiles, name: snapshotName)
            snapshotName = ""
            loadSnapshotList()
            await record("createSnapshot", "completed", detail: choice.location.path)
        } catch { self.error = error; await record("createSnapshot", "failed", error: error) }
    }
    func importSnapshot() {
        guard !operationPending else { return }
        choosing = true; defer { choosing = false }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.message = t("importSnapshot")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await previewSnapshot(url) }
    }
    func previewSnapshot(_ location: URL) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { snapshotPreview = try await installer.readSnapshot(location) }
        catch { self.error = error }
    }
    func restoreSnapshot(_ choice: SnapshotChoice) async {
        guard let root = folder, !busy, !blocked else { return }
        busy = true; snapshotPreview = nil; activity = "restoring"
        defer { busy = false; activity = "ready" }
        await record("restoreSnapshot", "started", detail: choice.location.path)
        do {
            try await installer.restoreSnapshot(choice, root: root)
            try await loadLocal(root)
            await record("restoreSnapshot", "completed", detail: choice.location.path)
        } catch {
            self.error = error; await record("restoreSnapshot", "failed", error: error)
            do { _ = try await installer.recover(root); try await loadLocal(root) }
            catch { blocked = true; self.error = error }
        }
    }
    func prepareCopyRemoval(backups: [Backup] = [], snapshots: [SnapshotChoice] = []) {
        guard !operationPending, backups.isEmpty != snapshots.isEmpty else { return }
        deletingCopies = BackupRemoval(backups: backups, snapshots: snapshots)
    }
    func removeCopies(_ selected: BackupRemoval) async {
        guard let root = folder, !busy else { return }
        busy = true; deletingCopies = nil
        defer { busy = false }
        await record("deleteBackups", "started", detail: "\(selected.count)")
        do {
            if !selected.backups.isEmpty { try await installer.trashBackups(selected.backups, root: root) }
            if !selected.snapshots.isEmpty { try await installer.trashSnapshots(selected.snapshots, directory: snapshotDirectory) }
            try await loadLocal(root)
            await record("deleteBackups", "completed", detail: "\(selected.count)")
        } catch {
            self.error = error; await record("deleteBackups", "failed", error: error)
            do { try await loadLocal(root) } catch { self.error = error }
        }
    }
    func renameSnapshot(_ choice: SnapshotChoice, name: String) async {
        guard !busy else { return }
        busy = true; renamingSnapshot = nil
        defer { busy = false }
        do {
            let renamed = try await installer.renameSnapshot(choice, name: name, directory: snapshotDirectory)
            loadSnapshotList()
            await record("renameBackup", "completed", detail: renamed.snapshot.name ?? choice.id)
        } catch { self.error = error; await record("renameBackup", "failed", error: error) }
    }

}
