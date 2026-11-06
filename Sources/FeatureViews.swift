import SwiftUI
import AppKit

struct HistoryPanel: View {
    @ObservedObject var model: Manager
    @State private var errorsOnly = false
    private var entries: [OperationRecord] { model.history.filter { !errorsOnly || $0.outcome == "failed" } }
    private func historyDetail(_ entry: OperationRecord) -> String {
        guard entry.outcome == "failed", let first = entry.detail.firstIndex(of: "\n") else { return entry.detail }
        return model.t(String(entry.detail[..<first])) + String(entry.detail[first...])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Toggle(model.t("errorsOnly"), isOn: $errorsOnly).toggleStyle(.checkbox)
                Spacer()
                Button(model.t("copyLog")) {
                    let text = entries.map { "\($0.date.formatted()) · \(model.t($0.operation)) · \(model.t($0.outcome))\n\($0.detail)" }.joined(separator: "\n\n")
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                }.disabled(entries.isEmpty)
            }
            Text(model.t("historyHint")).font(.caption).foregroundStyle(.secondary)
            if let error = model.historyError { Text(model.localizedError(error)).foregroundStyle(.orange).textSelection(.enabled) }
            if entries.isEmpty { ContentUnavailableView(model.t("emptyHistory"), systemImage: "list.bullet.rectangle") }
            else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: entry.outcome == "failed" ? "exclamationmark.triangle" : entry.outcome == "completed" ? "checkmark.circle" : "arrow.triangle.2.circlepath").foregroundStyle(entry.outcome == "failed" ? .orange : .secondary)
                            Text(model.t(entry.operation)).bold()
                            Text(model.t(entry.outcome)).foregroundStyle(.secondary)
                            Spacer(); Text(entry.date, format: .dateTime.year().month().day().hour().minute().second()).foregroundStyle(.secondary)
                        }
                        if !entry.detail.isEmpty { Text(historyDetail(entry)).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    }.padding(.vertical, 6)
                }
            }
        }.padding(22)
    }
}

struct SnapshotPanel: View {
    @ObservedObject var model: Manager
    @Environment(\.openSettings) private var openSettings
    @State private var selectedIDs = Set<String>()
    private var selected: [SnapshotChoice] { model.snapshots.filter { selectedIDs.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.t("snapshotHint")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(model.snapshotDirectory.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).font(.caption).textSelection(.enabled).lineLimit(2)
                Spacer(); Button { model.settingsTab = "general"; openSettings() } label: { Label(model.t("settings"), systemImage: "gearshape") }
            }
            Toggle(model.t("includeAddonFiles"), isOn: $model.includeAddonFiles).toggleStyle(.checkbox)
            TextField(model.t("backupName"), text: $model.snapshotName).textFieldStyle(.roundedBorder).accessibilityLabel(model.t("backupName"))
            HStack {
                Button { Task { await model.createSnapshot() } } label: { Label(model.t("createSnapshot"), systemImage: "externaldrive.badge.plus") }.buttonStyle(.borderedProminent)
                Button(model.t("importSnapshot"), action: model.importSnapshot)
            }
            Text(model.t("transferHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(model.t("backupSelectionHint")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.t("renameBackup")) { model.renamingSnapshot = selected.first }.disabled(selected.count != 1)
                Button(role: .destructive) { model.prepareCopyRemoval(snapshots: selected) } label: {
                    Label(model.t("deleteSelected") + " (\(selectedIDs.count))", systemImage: "trash")
                }.disabled(selected.isEmpty)
            }
            List(model.snapshots, selection: $selectedIDs) { choice in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        if let name = choice.snapshot.name { Text(name).font(.headline).lineLimit(2) }
                        Text(choice.snapshot.date, format: .dateTime.year().month().day().hour().minute())
                        Text(choice.snapshot.origin).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text("\(model.t("backupCount")): \(choice.snapshot.addons.count) · \(model.t("backupItems")): \(choice.snapshot.items.count)").font(.caption)
                    }
                    Spacer()
                    Button(model.t("showInFinder")) { NSWorkspace.shared.activateFileViewerSelecting([choice.location]) }
                    Button(model.t("restore")) { Task { await model.previewSnapshot(choice.location) } }
                }.padding(.vertical, 8).contentShape(Rectangle()).tag(choice.id)
            }.contextMenu(forSelectionType: String.self) { ids in
                let chosen = model.snapshots.filter { ids.contains($0.id) }
                if chosen.count == 1, let choice = chosen.first {
                    Button(model.t("renameBackup")) { model.renamingSnapshot = choice }
                    Button(model.t("restore")) { Task { await model.previewSnapshot(choice.location) } }
                    Button(model.t("showInFinder")) { NSWorkspace.shared.activateFileViewerSelecting([choice.location]) }
                }
                if !chosen.isEmpty {
                    Button(model.t("deleteBackups") + " (\(chosen.count))", role: .destructive) { model.prepareCopyRemoval(snapshots: chosen) }
                }
            }.onDeleteCommand { model.prepareCopyRemoval(snapshots: selected) }
                .onChange(of: model.snapshots.map(\.id)) { _, ids in selectedIDs.formIntersection(ids) }
        }.padding(20).disabled(model.busy || model.blocked)
    }
}

struct SnapshotRestorePanel: View {
    let choice: SnapshotChoice
    @ObservedObject var model: Manager
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.t("restoreSnapshot")).font(.title2.bold())
            if let name = choice.snapshot.name { Text(name).font(.headline).textSelection(.enabled) }
            Text(model.t("snapshotRestoreHint")).fixedSize(horizontal: false, vertical: true)
            Text(model.folder?.deletingLastPathComponent().path ?? "").font(.caption).textSelection(.enabled)
            List {
                Section(model.t("backupItems")) { ForEach(choice.snapshot.items, id: \.self) { Text($0).font(.caption) } }
                Section(model.t("addonInventory")) { ForEach(choice.snapshot.addons, id: \.folder) { addon in Text("\(addon.title) · \(addon.version)").font(.caption) } }
            }.frame(height: 300)
            HStack {
                Spacer(); Button(model.t("cancel")) { model.snapshotPreview = nil }.keyboardShortcut(.cancelAction)
                Button(model.t("restore")) { Task { await model.restoreSnapshot(choice) } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 600)
    }
}

struct SettingsResetPanel: View {
    let preview: SettingsPreview
    @ObservedObject var model: Manager
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.t("resetSettings")).font(.title2.bold())
            Text(preview.title).bold()
            Text(model.t("resetSettingsHint")).fixedSize(horizontal: false, vertical: true)
            if preview.files.isEmpty { Text(model.t("noSettingsFiles")).foregroundStyle(.secondary) }
            else { List(preview.files, id: \.self) { Text("SavedVariables/" + $0).font(.caption) }.frame(height: min(240, CGFloat(preview.files.count * 30 + 20))) }
            HStack {
                Spacer(); Button(model.t("cancel")) { model.settingsPreview = nil }.keyboardShortcut(.cancelAction)
                Button(model.t("resetSettings"), role: .destructive) { Task { await model.resetSettings(preview) } }.disabled(preview.files.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560)
    }
}

struct RenameBackupPanel: View {
    let choice: SnapshotChoice
    @ObservedObject var model: Manager
    @State private var name: String
    @FocusState private var focused: Bool
    init(choice: SnapshotChoice, model: Manager) {
        self.choice = choice; self.model = model
        _name = State(initialValue: choice.snapshot.name ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.t("renameBackup")).font(.title2.bold())
            TextField(model.t("backupName"), text: $name).textFieldStyle(.roundedBorder).focused($focused)
            Text(model.t("backupNameHint")).font(.caption).foregroundStyle(.secondary)
            if (try? backupName(name)) == nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(model.t("invalidBackupName")).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button(model.t("cancel")) { model.renamingSnapshot = nil }.keyboardShortcut(.cancelAction)
                Button(model.t("saveBackupName")) { Task { await model.renameSnapshot(choice, name: name) } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (try? backupName(name)) == nil)
            }
        }.padding(24).frame(width: 480).onAppear { focused = true }
    }
}
