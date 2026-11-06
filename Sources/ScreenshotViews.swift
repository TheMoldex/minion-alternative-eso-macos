import SwiftUI
import AppKit

struct ScreenshotGallery: View {
    let images: [AddonScreenshot]
    let title: String
    @ObservedObject var model: Manager
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if images.isEmpty {
                Text(model.t("noScreenshots")).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(model.t("screenshots") + " (\(images.count))").font(.headline)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                            Button { model.screenshotPreview = ScreenshotSelection(title: title, images: images, index: index) } label: {
                                ScreenshotTile(screenshot: image, client: model.client)
                            }.buttonStyle(.plain).accessibilityLabel(model.t("viewScreenshot") + " \(index + 1)")
                                .help(descriptionText(image.description ?? "").isEmpty ? model.t("viewScreenshot") : descriptionText(image.description ?? ""))
                        }
                    }
                }.frame(height: 96)
            }
        }
    }
}

private struct ScreenshotTile: View {
    let screenshot: AddonScreenshot
    let client: CatalogClient
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3))
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(3) }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            else { ProgressView().controlSize(.small) }
        }.frame(width: 128, height: 80)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            .task(id: screenshot.id) {
                image = nil; failed = false
                guard let url = screenshot.thumbnail else { failed = true; return }
                do {
                    let data = try await client.screenshot(url)
                    try Task.checkCancellation()
                    let bitmap = await Task.detached(priority: .utility) { screenshotBitmap(data, maximum: 320) }.value
                    guard !Task.isCancelled else { return }
                    guard let bitmap else { failed = true; return }
                    image = NSImage(cgImage: bitmap, size: .zero)
                } catch { if !Task.isCancelled { failed = true } }
            }
    }
}

struct ScreenshotViewer: View {
    let selection: ScreenshotSelection
    @ObservedObject var model: Manager
    @State private var index: Int
    @State private var attempt = 0
    @State private var image: NSImage?
    @State private var failure: Error?
    @State private var enlarged = false
    init(selection: ScreenshotSelection, model: Manager) {
        self.selection = selection; self.model = model
        _index = State(initialValue: min(max(0, selection.index), max(0, selection.images.count - 1)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selection.title).font(.headline).lineLimit(2)
                Spacer()
                Text("\(index + 1) / \(selection.images.count)").foregroundStyle(.secondary).monospacedDigit()
                Button(model.t("closeScreenshots")) { model.screenshotPreview = nil }.keyboardShortcut(.cancelAction)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4))
                if let image {
                    if enlarged {
                        ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().frame(width: image.size.width, height: image.size.height) }
                    } else { Image(nsImage: image).resizable().scaledToFit().padding(8) }
                } else if let failure {
                    VStack(spacing: 12) {
                        Label(model.t("screenshotFailed"), systemImage: "photo.badge.exclamationmark")
                        Text(model.localizedError(failure)).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                        Button(model.t("retry")) { attempt += 1 }
                    }.padding(24)
                } else { ProgressView() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button { index -= 1; attempt = 0 } label: { Label(model.t("previousScreenshot"), systemImage: "chevron.left") }.disabled(index == 0).keyboardShortcut(.leftArrow, modifiers: [])
                Button { index += 1; attempt = 0 } label: { Label(model.t("nextScreenshot"), systemImage: "chevron.right") }.disabled(index + 1 >= selection.images.count).keyboardShortcut(.rightArrow, modifiers: [])
                Spacer()
                Button { enlarged.toggle() } label: { Label(model.t(enlarged ? "fitScreenshot" : "zoomScreenshot"), systemImage: enlarged ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass") }.disabled(image == nil)
            }
            if selection.images.indices.contains(index) {
                let caption = String(descriptionText(selection.images[index].description ?? "").prefix(1000))
                if !caption.isEmpty { Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled) }
            }
        }.padding(22)
            .frame(width: max(600, min(1100, (NSScreen.main?.visibleFrame.width ?? 1280) - 120)), height: max(400, min(780, (NSScreen.main?.visibleFrame.height ?? 900) - 160)))
            .task(id: "\(index):\(attempt)") { await load() }
    }
    @MainActor private func load() async {
        image = nil; failure = nil; enlarged = false
        guard selection.images.indices.contains(index), let url = selection.images[index].image else { failure = AppError("screenshotFailed"); return }
        do {
            let data = try await model.client.screenshot(url, force: attempt > 0)
            try Task.checkCancellation()
            let bitmap = await Task.detached(priority: .utility) { screenshotBitmap(data, maximum: 4096) }.value
            guard !Task.isCancelled else { return }
            guard let bitmap else { throw AppError("screenshotFailed") }
            image = NSImage(cgImage: bitmap, size: .zero)
        } catch { if !Task.isCancelled { failure = error } }
    }
}
