import Foundation
import ImageIO

func screenshotChecks(_ temp: URL) async throws {
    let fm = FileManager.default
    let imageURL = URL(string: "https://cdn-eso.mmoui.com/preview/pvw123.png")!
    let thumbURL = URL(string: "https://cdn-eso.mmoui.com/preview/tiny/pvw123.png")!
    check(screenshotURL(imageURL) && screenshotURL(thumbURL), "official screenshot and thumbnail paths accepted")
    for address in ["http://cdn-eso.mmoui.com/preview/pvw123.png", "https://evil.invalid/preview/pvw123.png", "https://cdn-eso.mmoui.com/images/icons/m17.jpg", "https://cdn-eso.mmoui.com/preview/../../secrets.png", "https://cdn-eso.mmoui.com/preview/pvw123.svg", "https://cdn-eso.mmoui.com/preview/pvw123.png?token=x", "https://user@cdn-eso.mmoui.com/preview/pvw123.png"] {
        check(!screenshotURL(URL(string: address)!), "untrusted screenshot address rejected")
    }
    var details = DownloadDetails(id: 1, version: "1", checksum: "", downloadUri: "", description: "Text", changeLog: nil)
    check(details.screenshots.isEmpty, "older API metadata without screenshots remains compatible")
    let screenshot = AddonScreenshot(thumbUrl: thumbURL.absoluteString, imageUrl: imageURL.absoluteString, description: "Caption")
    details.images = [screenshot, screenshot, AddonScreenshot(thumbUrl: nil, imageUrl: "https://evil.invalid/test.png", description: nil)]
    check(details.screenshots.count == 1 && details.screenshots[0].thumbnail == thumbURL, "screenshot metadata removes duplicates and foreign URLs")
    check(AddonScreenshot(thumbUrl: "https://evil.invalid/tiny.png", imageUrl: imageURL.absoluteString, description: nil).thumbnail == imageURL, "missing trusted thumbnail falls back to validated original")
    details.images = (1...100).map { AddonScreenshot(thumbUrl: nil, imageUrl: "https://cdn-eso.mmoui.com/preview/pvw\($0).png", description: nil) }
    check(details.screenshots.count == 64, "screenshot list bounded for unexpectedly large API responses")
    let context = CGContext(data: nil, width: 1600, height: 900, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
    let bytes = NSMutableData()
    let encoder = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(encoder, context.makeImage()!, nil)
    check(CGImageDestinationFinalize(encoder), "image fixture encoded")
    let data = bytes as Data
    check(validScreenshotImage(data) && !validScreenshotImage(Data("<svg>not a screenshot</svg>".utf8)), "screenshots require a supported raster format")
    check(!validScreenshotImage(Data(repeating: 0, count: 12_000_001)), "oversized screenshot download rejected")
    let bitmap = screenshotBitmap(data, maximum: 320)
    check(bitmap?.width == 320 && bitmap?.height == 180, "thumbnail decoding bounds memory and preserves aspect ratio")
    var huge = data
    for (offset, value) in [(16, 7000), (20, 7000)] { for index in 0..<4 { huge[offset + index] = UInt8((value >> ((3 - index) * 8)) & 255) } }
    let crc = crc32(Data(huge[12..<29])); for index in 0..<4 { huge[29 + index] = UInt8((crc >> ((3 - index) * 8)) & 255) }
    check(!validScreenshotImage(huge), "excessive pixel count rejected before bitmap decoding")
    let cache = ScreenshotCache(directory: temp.appendingPathComponent("screenshot-cache"))
    check(try cache.read(imageURL) == nil, "missing screenshot cache falls back to network")
    try cache.write(data, for: imageURL)
    check(try cache.read(imageURL) == data, "screenshot cache persists validated bytes")
    let stored = try fm.contentsOfDirectory(at: cache.directory, includingPropertiesForKeys: nil)[0]
    try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-604_801)], ofItemAtPath: stored.path)
    check(try cache.read(imageURL) == nil, "screenshot cache expires after seven days")
    try cache.write(data, for: imageURL)
    try Data("corrupt cache".utf8).write(to: stored)
    check(try cache.read(imageURL) == nil, "corrupt cached image is not displayed")
    rejects("unsafe addresses cannot be stored in screenshot cache") { try cache.write(data, for: URL(string: "https://evil.invalid/x.png")!) }
    for index in 1...66 { try cache.write(data, for: URL(string: "https://cdn-eso.mmoui.com/preview/pvw\(index).png")!) }
    let files = try fm.contentsOfDirectory(at: cache.directory, includingPropertiesForKeys: nil)
    check(try files.count == 64 && cache.read(URL(string: "https://cdn-eso.mmoui.com/preview/pvw66.png")!) == data, "screenshot cache evicts older files and keeps at most 64 images")
    let outside = temp.appendingPathComponent("screenshot-outside")
    try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    let link = temp.appendingPathComponent("screenshot-cache-link")
    try fm.createSymbolicLink(at: link, withDestinationURL: outside)
    rejects("screenshot cache does not write through symlinked directories") { try ScreenshotCache(directory: link).write(data, for: imageURL) }
    check(try fm.contentsOfDirectory(atPath: outside.path).isEmpty, "unsafe cache location leaves external files untouched")
    if ProcessInfo.processInfo.environment["SCREENSHOTS_LIVE_TESTS"] == "1" {
        let client = CatalogClient(cache: temp.appendingPathComponent("live-screenshots/catalog.json"))
        let details = try await client.details(1161)
        guard let shot = details.screenshots.first, let thumbnail = shot.thumbnail, let original = shot.image else { throw AppError("screenshotFailed", "Addon Selector has no screenshot fixture") }
        check(details.screenshots.count >= 5, "live Addon Selector screenshot metadata decoded")
        let small = try await client.screenshot(thumbnail)
        check(validScreenshotImage(small) && screenshotBitmap(small, maximum: 320) != nil, "real ESOUI thumbnail fetched and decoded")
        let full = try await client.screenshot(original)
        check(validScreenshotImage(full) && screenshotBitmap(full, maximum: 4096) != nil, "real ESOUI original fetched and decoded")
        let persisted = ScreenshotCache(directory: temp.appendingPathComponent("live-screenshots/screenshots"))
        check(try persisted.read(original) == full, "real screenshot persists in bounded disk cache")
        let fresh = CatalogClient(cache: temp.appendingPathComponent("live-screenshots/catalog.json"))
        check(try await fresh.screenshot(original) == full, "new catalog client can reuse cached screenshot")
        print("PASS: live ESOUI screenshot metadata, thumbnail, original and disk cache")
    }
}
