// Renders the SF Symbols an app names with macOS's own, into
// <App>.app/SFSymbols/<name>.png, for Perry to draw the symbols it has no
// drawing of. SF Symbols are Apple's, so they stay in the app's copy on the
// machine that renders them rather than in Perry.
//
// A symbol's name is any string in the app's binaries, nibs or data files
// that macOS knows as a symbol. Each is drawn in black, as a template, at
// Symbols.renderedPointSize (34 points) and 3 pixels a point, its image the
// size the symbol is at that point size.
//
// Usage: extract-symbols <App.app>...
import AppKit
import Foundation

let pointSize: CGFloat = 34
let scale: CGFloat = 3

/// The words in a file shaped as symbols' names are: lowercase letters and
/// digits, in parts joined by dots, as macOS's own names are, wherever they
/// stand (a C string, a nib's string, an XML element's text).
func symbolNames(in url: URL) -> Set<String> {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
    var found: Set<String> = []
    var word: [UInt8] = []
    func flush() {
        // Not starting or ending in a dot, nor with two together.
        while word.last == UInt8(ascii: ".") { word.removeLast() }
        while word.first == UInt8(ascii: ".") { word.removeFirst() }
        if word.count >= 3, word.count <= 64, let text = String(bytes: word, encoding: .ascii), !text.contains("..") {
            found.insert(text)
        }
        word.removeAll(keepingCapacity: true)
    }
    for byte in data {
        let symbolByte = (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || byte == UInt8(ascii: ".")
        if symbolByte { word.append(byte) } else { flush() }
    }
    flush()
    return found
}

/// The files of an app that may name symbols: its code, nibs and data
/// (property lists, XML, JSON, databases), everything but its media and
/// asset catalogs.
func sources(in app: URL) -> [URL] {
    let media: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "pdf", "caf", "aif", "aiff", "wav", "mp3", "m4a",
                              "mp4", "mov", "car", "ttf", "otf"]
    guard let walker = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return [] }
    var files: [URL] = []
    for case let url as URL in walker {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true, !media.contains(url.pathExtension.lowercased()),
              (values?.fileSize ?? 0) < 256 << 20, !url.path.contains("/SFSymbols/"), !url.path.contains(".car.images/") else { continue }
        files.append(url)
    }
    return files
}

/// The symbol drawn black on a clear background, as PNG data.
func render(_ name: String) -> Data? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
        return nil
    }
    let size = symbol.size
    let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
    guard width > 0, height > 0,
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    // Drawn as it is, a template symbol comes out black in the light
    // appearance, its cut-out parts (the lines in a filled circle's)
    // left clear. Filling over it would fill those too.
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
        symbol.draw(in: NSRect(origin: .zero, size: size))
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

var failed = false
for path in CommandLine.arguments.dropFirst() {
    let app = URL(fileURLWithPath: path)
    var names: Set<String> = []
    for file in sources(in: app) { names.formUnion(symbolNames(in: file)) }
    let output = app.appendingPathComponent("SFSymbols")
    try? FileManager.default.removeItem(at: output)
    var written = 0
    for name in names.sorted() {
        guard let png = render(name) else { continue }
        if written == 0 { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        do {
            try png.write(to: output.appendingPathComponent(name + ".png"))
            written += 1
        } catch {
            FileHandle.standardError.write(Data("extract-symbols: \(name): \(error.localizedDescription)\n".utf8))
            failed = true
        }
    }
    print("\(output.path): \(written) symbols of \(names.count) candidate names")
}
exit(failed ? 1 : 0)
