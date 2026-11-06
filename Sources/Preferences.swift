import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var model: Manager
    var body: some View {
        TabView(selection: $model.settingsTab) {
            general.tabItem { Label(model.t("generalSettings"), systemImage: "gearshape") }.tag("general")
            updates.tabItem { Label(model.t("updates"), systemImage: "arrow.triangle.2.circlepath") }.tag("updates")
        }.padding(12).frame(width: 680, height: 640)
            .onAppear { model.settingsVisible = true }
            .onDisappear { model.settingsVisible = false }
            .alert(model.t("errorTitle"), isPresented: Binding(get: { model.error != nil && model.settingsVisible }, set: { if !$0 && model.settingsVisible { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.errorText) }
    }
    private var general: some View {
        ScrollView {
            Form {
                Section(model.t("profile")) {
                    Picker(model.t("folder"), selection: Binding(get: { model.folder?.standardizedFileURL.path ?? "" }, set: { model.switchProfile(URL(fileURLWithPath: $0)) })) {
                        if model.folder == nil { Text("—").tag("") }
                        ForEach(model.profiles) { profile in Text(profile.title).tag(profile.path) }
                    }.disabled(model.operationPending)
                    if let folder = model.folder { Text(folder.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    HStack {
                        Button(model.t("choose"), action: model.chooseFolder)
                        if let folder = model.folder {
                            Button("Finder") { NSWorkspace.shared.open(folder) }
                            Spacer()
                            Button(model.t("forgetProfile"), action: model.forgetProfile)
                        }
                    }.disabled(model.operationPending)
                }
                Section(model.t("interfaceSettings")) {
                    Picker(model.t("language"), selection: $model.language) {
                        ForEach(Language.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                }
                Section(model.t("backups")) {
                    Text(model.snapshotDirectory.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Button(model.t("snapshotLocation"), action: model.chooseSnapshotDirectory).disabled(model.operationPending)
                    Picker(model.t("backupRetention"), selection: $model.backupLimit) {
                        Text(model.t("keepAllBackups")).tag(0)
                        ForEach([5, 10, 20], id: \.self) { Text(model.t("lastBackups") + " \($0)").tag($0) }
                    }.disabled(model.busy)
                    Text(model.t("retentionHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(model.t("manualRetentionHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.formStyle(.grouped)
        }
    }
    private var updates: some View {
        ScrollView {
            Form {
                Section(model.t("addonUpdateSettings")) {
                    Toggle(model.t("autoUpdates"), isOn: $model.autoUpdates).disabled(model.busy)
                    Text(model.t("autoHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.autoUpdates {
                        Text(model.backgroundLabel).font(.caption).foregroundStyle(model.backgroundError == nil ? Color.secondary : .orange).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        HStack { Text(model.t("nextCheck")); Text(model.nextBackground, format: .dateTime.hour().minute()) }.font(.caption).foregroundStyle(.secondary)
                    }
                    Picker(model.t("parallelDownloads"), selection: $model.parallelism) { ForEach(1...4, id: \.self) { Text("\($0)").tag($0) } }.disabled(model.busy)
                }
                Section(model.t("ignoredAddons")) {
                    Text(model.t("ignoredSettingsHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.ignored.isEmpty { Text(model.t("noIgnoredAddons")).foregroundStyle(.secondary) }
                    ForEach(model.ignored.sorted(), id: \.self) { id in
                        let title = model.catalog.first(where: { $0.id == id })?.title ?? "ESOUI #\(id)"
                        HStack {
                            Text(title).lineLimit(2)
                            Spacer()
                            Button(model.t("resumeUpdates")) { Task { await model.toggleIgnored(id, title: title) } }.disabled(model.operationPending)
                        }
                    }
                }
                Section(model.t("appUpdateSettings")) {
                    AppUpdatePreferences(updater: model.appUpdates, text: model.t)
                }
            }.formStyle(.grouped)
        }
    }
}

private struct AppUpdatePreferences: View {
    @ObservedObject var updater: AppUpdater
    let text: (String) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("installedAppVersion") + ": " + updater.version)
            Text(text("automaticAppCheckHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if updater.state != .idle {
                Text(text(updater.state.rawValue) + (updater.latest.map { " " + $0.version } ?? "")).foregroundStyle(updater.state == .failed ? .orange : .secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(text("checkAppUpdates")) { Task { await updater.check(manual: true) } }.disabled(updater.checking)
                if let release = updater.latest {
                    Button(text("appUpdateDownload")) { NSWorkspace.shared.open(release.url); updater.showing = false }.buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
