import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 56, y: 56, width: 912, height: 912)
let shape = NSBezierPath(roundedRect: rect, xRadius: 205, yRadius: 205)
NSGradient(colors: [NSColor(red: 0.14, green: 0.24, blue: 0.53, alpha: 1), NSColor(red: 0.28, green: 0.55, blue: 0.94, alpha: 1)])!.draw(in: shape, angle: 55)
let config = NSImage.SymbolConfiguration(pointSize: 480, weight: .medium)
let icon = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config.applying(NSImage.SymbolConfiguration(paletteColors: [.white])))!
NSColor.white.set()
let iconRect = NSRect(x: 238, y: 235, width: 548, height: 548)
icon.draw(in: iconRect)
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
