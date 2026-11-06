import Foundation
import SwiftUI
import AppKit

struct PaneLayout {
    static let divider = 8.0
    let sidebar: Double
    let details: Double
    let sidebarMaximum: Double
    let detailsMaximum: Double
    let main: Double
    init(width: Double, sidebar: Double, details: Double) {
        let width = width.isFinite ? max(980, width) : 980
        sidebarMaximum = min(420, width - 620 - Self.divider)
        self.sidebar = Self.clamp(sidebar, to: 180...sidebarMaximum, fallback: 220)
        main = width - self.sidebar - Self.divider
        detailsMaximum = min(700, main - 300 - Self.divider)
        self.details = Self.clamp(details, to: 280...detailsMaximum, fallback: 330)
    }
    static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
    }
}

struct PaneDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let label: String
    var reversed = false
    @State private var origin: Double?
    @State private var hovered = false
    var body: some View {
        Rectangle().fill(hovered ? Color.accentColor.opacity(0.15) : .clear)
            .overlay { Rectangle().fill(hovered ? Color.accentColor : Color(nsColor: .separatorColor)).frame(width: 1) }
            .frame(width: PaneLayout.divider).frame(maxHeight: .infinity).contentShape(Rectangle())
            .onHover { inside in
                guard inside != hovered else { return }
                hovered = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .onDisappear { if hovered { NSCursor.pop(); hovered = false } }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { drag in
                    if origin == nil { origin = width }
                    resize((origin ?? width) + Double(drag.translation.width) * (reversed ? -1 : 1))
                }
                .onEnded { _ in origin = nil })
            .focusable()
            .onKeyPress(.leftArrow) { resize(width + (reversed ? 10 : -10)); return .handled }
            .onKeyPress(.rightArrow) { resize(width + (reversed ? -10 : 10)); return .handled }
            .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityValue(String(Int(width)))
            .accessibilityAdjustableAction { direction in resize(width + (direction == .increment ? 10 : -10)) }
            .help(label)
    }
    private func resize(_ value: Double) { width = PaneLayout.clamp(value, to: range, fallback: width) }
}
