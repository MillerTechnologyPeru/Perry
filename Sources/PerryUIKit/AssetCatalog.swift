import CPerryGeometry
import Glibc
import PerryObjCInterop

// A bundle's compiled asset catalog, Assets.car, from which +imageNamed:
// and its variant for other bundles take the images that are not loose
// files. It is a BOM file
// of named trees: FACETKEYS maps image names to their attributes,
// KEYFORMAT lists the attributes a rendition's key holds, and RENDITIONS
// holds each rendition: a CSI header, then its pixels, compressed in one
// LZFSE stream or in bands of rows. Many images are links to a rectangle
// of a packed atlas. Pixels are premultiplied BGRA, as UIKit draws, or
// gray and alpha.

enum AssetCatalog {
    typealias Decode = @convention(c) (UnsafeMutablePointer<UInt8>?, Int, UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?, Int32) -> Int
    /// libcompression's compression_decode_buffer.
    nonisolated(unsafe) static var decode: Decode?

    static func load(_ lookup: (String, String) -> UnsafeMutableRawPointer?) {
        decode = lookup("/usr/lib/libcompression.dylib", "_compression_decode_buffer").map { unsafeBitCast($0, to: Decode.self) }
    }

    nonisolated(unsafe) static let main: Catalog? = NSBundle.main().path(forResource: "Assets", ofType: "car").flatMap(Catalog.init)

    /// The named image at the scale nearest the screen's.
    static func image(named name: String) -> (image: Owned, scale: CGFloat)? { main?.image(named: name) }

    /// Other bundles' catalogs (a Swift package's resource bundle, a
    /// framework's), by the bundle's path, read the first time one of their
    /// images is asked for.
    nonisolated(unsafe) private static var catalogs: [String: Catalog?] = [:]
    private static let lock = Lock()

    static func catalog(in bundle: NSBundle) -> Catalog? {
        guard let path = bundle.path(forResource: "Assets", ofType: "car") else { return nil }
        return lock.withLock {
            if let catalog = catalogs[path] { return catalog }
            let catalog = Catalog(path: path)
            catalogs[path] = catalog
            return catalog
        }
    }
}

final class Catalog {
    /// CoreUI's rendition attributes.
    enum Attribute: UInt16 {
        case element = 1, part = 2, dimension1 = 8, dimension2 = 9, scale = 12, idiom = 15, identifier = 17
    }

    /// A rendition's layout: an image with its pixels, a link into an
    /// atlas, a packed atlas.
    enum Layout: UInt16 {
        case image = 12, link = 1003, atlas = 1004
    }

    /// Decoded pixels: premultiplied BGRA rows.
    struct Pixels {
        let width: Int, height: Int
        var bytes: [UInt8]
    }

    private let bytes: [UInt8]
    private var blocks: [(offset: Int, length: Int)] = []
    private var keyFormat: [UInt16] = []
    private var identifiers: [String: UInt16] = [:]
    private var renditions: [(key: [UInt16], range: Range<Int>)] = []
    private var atlases: [Int: Pixels] = [:]

    init?(path: String) {
        guard let bytes = Files.read(path), bytes.count > 32, Array(bytes[0..<8]) == Array("BOMStore".utf8) else { return nil }
        self.bytes = bytes
        guard parse() else { return nil }
    }

    // MARK: Reading

    private func be32(_ at: Int) -> Int {
        guard at >= 0, at + 4 <= bytes.count else { return 0 }
        return Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
    }

    private func be16(_ at: Int) -> Int {
        guard at >= 0, at + 2 <= bytes.count else { return 0 }
        return Int(bytes[at]) << 8 | Int(bytes[at + 1])
    }

    private func le32(_ at: Int) -> Int {
        guard at >= 0, at + 4 <= bytes.count else { return 0 }
        return Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
    }

    private func le16(_ at: Int) -> UInt16 {
        guard at >= 0, at + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private func block(_ index: Int) -> Range<Int>? {
        guard blocks.indices.contains(index) else { return nil }
        let (offset, length) = blocks[index]
        guard offset >= 0, length >= 0, offset + length <= bytes.count else { return nil }
        return offset..<offset + length
    }

    /// The BOM's block table and named variables, then the trees.
    private func parse() -> Bool {
        let indexOffset = be32(16), variablesOffset = be32(24)
        let count = be32(indexOffset)
        guard count > 0, indexOffset + 4 + count * 8 <= bytes.count else { return false }
        blocks = (0..<count).map { (be32(indexOffset + 4 + $0 * 8), be32(indexOffset + 8 + $0 * 8)) }
        var variables: [String: Int] = [:]
        var at = variablesOffset + 4
        for _ in 0..<be32(variablesOffset) {
            guard at + 5 <= bytes.count else { return false }
            let index = be32(at), length = Int(bytes[at + 4])
            guard at + 5 + length <= bytes.count else { return false }
            variables[String(decoding: bytes[at + 5..<at + 5 + length], as: UTF8.self)] = index
            at += 5 + length
        }
        // KEYFORMAT: 'tmfk', a version, the count, then the attributes.
        guard let format = variables["KEYFORMAT"].flatMap(block) else { return false }
        keyFormat = (0..<le32(format.lowerBound + 8)).map { UInt16(truncatingIfNeeded: le32(format.lowerBound + 12 + $0 * 4)) }
        // FACETKEYS: a name to a hot spot and its attributes.
        for (key, value) in tree(variables["FACETKEYS"]) {
            let name = String(decoding: bytes[key], as: UTF8.self)
            let count = Int(le16(value.lowerBound + 4))
            for index in 0..<count where le16(value.lowerBound + 6 + index * 4) == Attribute.identifier.rawValue {
                identifiers[name] = le16(value.lowerBound + 8 + index * 4)
            }
        }
        renditions = tree(variables["RENDITIONS"]).map { key, value in
            ((0..<keyFormat.count).map { le16(key.lowerBound + $0 * 2) }, value)
        }
        return !renditions.isEmpty
    }

    /// A B-tree's keys and values, leaf by leaf.
    private func tree(_ variable: Int?) -> [(key: Range<Int>, value: Range<Int>)] {
        guard let header = variable.flatMap(block), Array(bytes[header.lowerBound..<header.lowerBound + 4]) == Array("tree".utf8),
              var node = block(be32(header.lowerBound + 8)) else { return [] }
        // Down the first children to the leftmost leaf.
        for _ in 0..<64 where be16(node.lowerBound) == 0 {
            guard let child = block(be32(node.lowerBound + 12)) else { return [] }
            node = child
        }
        var entries: [(Range<Int>, Range<Int>)] = []
        for _ in 0..<blocks.count {
            for index in 0..<be16(node.lowerBound + 2) {
                let at = node.lowerBound + 12 + index * 8
                if let value = block(be32(at)), let key = block(be32(at + 4)) { entries.append((key, value)) }
            }
            guard let next = block(be32(node.lowerBound + 4)), be32(node.lowerBound + 4) != 0 else { break }
            node = next
        }
        return entries
    }

    private func attribute(_ key: [UInt16], _ attribute: Attribute) -> UInt16 {
        keyFormat.firstIndex(of: attribute.rawValue).map { key[$0] } ?? 0
    }

    // MARK: Images

    /// The rendition for the screen's scale, else the next larger, else
    /// the largest smaller; for the phone, else any device.
    func image(named name: String) -> (image: Owned, scale: CGFloat)? {
        guard let identifier = identifiers[name] else { return nil }
        // UIUserInterfaceIdiom in catalogs: universal 0, phone 1.
        let candidates = renditions.indices.filter {
            attribute(renditions[$0].key, .identifier) == identifier && attribute(renditions[$0].key, .idiom) <= 1
        }
        let screen = Int(Screen.scale.rounded())
        func rank(_ index: Int) -> (Int, Int) {
            let key = renditions[index].key
            let scale = Int(attribute(key, .scale))
            let distance = scale == screen ? 0 : scale > screen ? scale - screen : 10 + screen - scale
            return (distance, attribute(key, .idiom) == 1 ? 0 : 1)
        }
        for index in candidates.sorted(by: { rank($0) < rank($1) }) {
            guard let pixels = pixels(index), let image = makeImage(pixels) else { continue }
            return (image, CGFloat(max(1, le32(renditions[index].range.lowerBound + 20))) / 100)
        }
        return nil
    }

    private func makeImage(_ pixels: Pixels) -> Owned? {
        guard pixels.width > 0, pixels.height > 0, let space = CG.colorSpaceCreateDeviceRGB() else { return nil }
        defer { CG.release(space) }
        let rowBytes = pixels.width * 4
        guard let context = CG.bitmapContextCreate(nil, pixels.width, pixels.height, 8, rowBytes, space, CG.bitmapInfo(opaque: false)) else {
            return nil
        }
        defer { CG.release(context) }
        guard let data = CG.bitmapContextGetData(context) else { return nil }
        pixels.bytes.withUnsafeBytes { data.copyMemory(from: $0.baseAddress!, byteCount: min($0.count, rowBytes * pixels.height)) }
        return CG.bitmapContextCreateImage(context).map(Owned.init)
    }

    /// A rendition's pixels: its own, or its rectangle of an atlas.
    private func pixels(_ index: Int) -> Pixels? {
        let csi = renditions[index].range
        guard csi.count >= 184, Array(bytes[csi.lowerBound..<csi.lowerBound + 4]) == Array("ISTC".utf8) else { return nil }
        let layout = Layout(rawValue: le16(csi.lowerBound + 36))
        let listLength = le32(csi.lowerBound + 168)
        let list = csi.lowerBound + 184..<min(csi.lowerBound + 184 + listLength, csi.upperBound)
        switch layout {
        case .link: return linked(list)
        case .image, .atlas:
            if layout == .atlas, let atlas = atlases[index] { return atlas }
            let decoded = bitmap(csi, data: list.upperBound..<csi.upperBound)
            if layout == .atlas { atlases[index] = decoded }
            return decoded
        case nil: return nil
        }
    }

    /// The INLK entry: a rectangle, from the bottom left, of the atlas
    /// whose key it gives as attribute pairs.
    private func linked(_ list: Range<Int>) -> Pixels? {
        var at = list.lowerBound
        while at + 8 <= list.upperBound {
            let tag = le32(at), length = le32(at + 4)
            defer { at += 8 + length }
            guard tag == 1010, length >= 30, Array(bytes[at + 8..<at + 12]) == Array("KLNI".utf8) else { continue }
            let entry = at + 8
            let (x, y, width, height) = (le32(entry + 8), le32(entry + 12), le32(entry + 16), le32(entry + 20))
            let keyLength = le32(entry + 26)
            var key = [UInt16](repeating: 0, count: keyFormat.count)
            for pair in stride(from: entry + 30, to: min(entry + 30 + keyLength, entry + length) - 3, by: 4) {
                if let position = keyFormat.firstIndex(of: le16(pair)) { key[position] = le16(pair + 2) }
            }
            guard let atlasIndex = renditions.firstIndex(where: { $0.key == key }), let atlas = pixels(atlasIndex) else { return nil }
            let top = atlas.height - y - height
            guard x >= 0, top >= 0, width > 0, height > 0, x + width <= atlas.width else { return nil }
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            for row in 0..<height {
                let from = ((top + row) * atlas.width + x) * 4
                bytes.replaceSubrange(row * width * 4..<(row + 1) * width * 4, with: atlas.bytes[from..<from + width * 4])
            }
            return Pixels(width: width, height: height, bytes: bytes)
        }
        return nil
    }

    /// The MLEC block: one compressed stream (version 0), or bands of rows
    /// in KCBC chunks (version 1). Rows may be padded; the stride is what
    /// the pixels decode to.
    private func bitmap(_ csi: Range<Int>, data: Range<Int>) -> Pixels? {
        let width = le32(csi.lowerBound + 12), height = le32(csi.lowerBound + 16)
        let format = Array(bytes[csi.lowerBound + 24..<csi.lowerBound + 28])
        let gray = format == Array(" 8AG".utf8)
        guard gray || format == Array("BGRA".utf8), width > 0, height > 0, data.count >= 16,
              Array(bytes[data.lowerBound..<data.lowerBound + 4]) == Array("MLEC".utf8) else { return nil }
        let version = le32(data.lowerBound + 4), compression = le32(data.lowerBound + 8), count = le32(data.lowerBound + 12)
        let depth = gray ? 2 : 4
        var raw: [UInt8] = []
        if version == 0 {
            guard let decoded = decompress(data.lowerBound + 16..<min(data.lowerBound + 16 + count, data.upperBound), compression,
                                           capacity: height * (width * depth + 64)) else { return nil }
            raw = decoded
        } else {
            var at = data.lowerBound + 16
            for _ in 0..<count {
                guard at + 20 <= data.upperBound, Array(bytes[at..<at + 4]) == Array("KCBC".utf8) else { return nil }
                let rows = le32(at + 12), length = le32(at + 16)
                guard let decoded = decompress(at + 20..<min(at + 20 + length, data.upperBound), compression,
                                               capacity: rows * (width * depth + 64)) else { return nil }
                raw += decoded
                at += 20 + length
            }
        }
        let stride = raw.count / height
        guard stride >= width * depth else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let from = row * stride + column * depth, to = (row * width + column) * 4
                if gray {
                    let value = raw[from]
                    (bytes[to], bytes[to + 1], bytes[to + 2], bytes[to + 3]) = (value, value, value, raw[from + 1])
                } else {
                    (bytes[to], bytes[to + 1], bytes[to + 2], bytes[to + 3]) = (raw[from], raw[from + 1], raw[from + 2], raw[from + 3])
                }
            }
        }
        return Pixels(width: width, height: height, bytes: bytes)
    }

    /// CoreUI's compression: none 0, LZVN 3 and LZFSE 4, which the LZFSE
    /// decoder reads both of.
    private func decompress(_ range: Range<Int>, _ compression: Int, capacity: Int) -> [UInt8]? {
        if compression == 0 { return Array(bytes[range]) }
        guard compression == 3 || compression == 4, let decode = AssetCatalog.decode else { return nil }
        var output = [UInt8](repeating: 0, count: capacity)
        let written = bytes.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                decode(destination.baseAddress, capacity, source.baseAddress! + range.lowerBound, range.count, nil, 0x801)
            }
        }
        guard written > 0 else { return nil }
        output.removeSubrange(written...)
        return output
    }
}
