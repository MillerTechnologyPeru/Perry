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
// Names the scan misses can be listed in <App.app>/SFSymbols.txt.
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

/// Names in arm64 code as Swift writes strings of up to 15 bytes: in the
/// instructions themselves, moved into a pair of registers 16 bits at a
/// time (MOVZ, then MOVK), the first 8 bytes in one and the rest in the
/// other, whose top byte is 0xE0 and the string's length. Such names are
/// in no string section for the byte scan to find.
func smallStringNames(in url: URL) -> Set<String> {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= 8,
          data.prefix(4).elementsEqual([0xCF, 0xFA, 0xED, 0xFE]) else { return [] }
    var found: Set<String> = []
    func bytes(_ value: UInt64, count: Int) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
    }
    func add(_ text: [UInt8]) {
        let symbolByte: (UInt8) -> Bool = {
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0)
                || $0 == UInt8(ascii: ".")
        }
        guard text.count >= 3, text.allSatisfy(symbolByte), text.first != UInt8(ascii: "."), text.last != UInt8(ascii: "."),
              let name = String(bytes: text, encoding: .ascii) else { return }
        found.insert(name)
    }
    var registers = [UInt64](repeating: 0, count: 32)
    var written = [Int](repeating: Int.min / 2, count: 32)
    data.withUnsafeBytes { raw in
        let words = raw.bindMemory(to: UInt32.self)
        for index in 0..<words.count {
            let word = UInt32(littleEndian: words[index])
            let register = Int(word & 31)
            let immediate = UInt64((word >> 5) & 0xFFFF), shift = UInt64((word >> 21) & 3) * 16
            switch word & 0xFF80_0000 {
            case 0xD280_0000: registers[register] = immediate << shift
            case 0xF280_0000: registers[register] = (registers[register] & ~(0xFFFF << shift)) | (immediate << shift)
            default: continue
            }
            written[register] = index
            // A pair's registers are written in either order, a few
            // instructions apart: the one with the length (top nibble 0xE)
            // and the one with the first 8 bytes.
            for other in 0..<32 where other != register && index - written[other] < 8 {
                let (first, second) = registers[register] >> 60 == 0xE
                    ? (registers[other], registers[register]) : (registers[register], registers[other])
                guard second >> 60 == 0xE else { continue }
                let length = Int((second >> 56) & 0xF)
                if length <= 8 {
                    add(bytes(first, count: length))
                } else {
                    add(bytes(first, count: 8) + bytes(second, count: length - 8))
                }
            }
        }
    }
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
    for file in sources(in: app) {
        names.formUnion(symbolNames(in: file))
        names.formUnion(smallStringNames(in: file))
    }
    // Names the scans can't see (made in code some other way), listed one
    // a line in <App.app>/SFSymbols.txt: those Perry reports asked for and
    // missing (PERRY_APPKIT_SYMBOL_TRACE, PERRY_UIKIT_SYMBOL_TRACE).
    if let listed = try? String(contentsOf: app.appendingPathComponent("SFSymbols.txt"), encoding: .utf8) {
        names.formUnion(listed.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    // Their filled variants too, which tab bars show for the selected tab
    // without the app naming them.
    names.formUnion(names.map { $0 + ".fill" })
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
