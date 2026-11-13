import Glibc

// A bundle's compiled asset catalog, Assets.car, which UIKit's and AppKit's
// named images and colors come from. It is a BOM file of named trees:
// FACETKEYS maps image names to their attributes, KEYFORMAT lists the
// attributes a rendition's key holds, and RENDITIONS holds each rendition:
// a CSI header, then its pixels, compressed in one LZFSE stream or in
// bands of rows, or as CoreUI's "deepmap-lzfse", which predicts a pixel's
// colors from its neighbors. Many images are links to a rectangle of a
// packed atlas. Pixels are premultiplied BGRA, or gray and alpha; named
// colors are their components.

public final class CompiledAssetCatalog {
    public typealias Decode = @convention(c) (UnsafeMutablePointer<UInt8>?, Int, UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?, Int32) -> Int
    /// libcompression's compression_decode_buffer, which the provider
    /// that reads catalogs binds.
    nonisolated(unsafe) public static var decode: Decode?

    /// CoreUI's rendition attributes.
    enum Attribute: UInt16 {
        case element = 1, part = 2, appearance = 7, dimension1 = 8, dimension2 = 9, scale = 12, idiom = 15, identifier = 17
    }

    /// A rendition's layout: an image with its pixels, a link into an
    /// atlas, a packed atlas.
    enum Layout: UInt16 {
        case image = 12, link = 1003, atlas = 1004
    }

    /// Decoded pixels: premultiplied BGRA rows.
    public struct Pixels {
        public let width: Int, height: Int
        public var bytes: [UInt8]
    }

    private let bytes: [UInt8]
    private var blocks: [(offset: Int, length: Int)] = []
    private var keyFormat: [UInt16] = []
    private var identifiers: [String: UInt16] = [:]
    private var renditions: [(key: [UInt16], range: Range<Int>)] = []
    private var atlases: [Int: Pixels] = [:]
    /// The dark appearance's number in renditions' keys (APPEARANCEKEYS),
    /// if the catalog has renditions for it.
    private var darkAppearance: UInt16?

    /// Whether AppKit draws the named image as a template: Scripts/
    /// extract-assets.sh lists those CoreUI says are (templates.txt), and
    /// names ending in "Template" are.
    public func isTemplate(named name: String) -> Bool {
        if name.hasSuffix("Template") { return true }
        return templates.contains(name)
    }

    private lazy var templates: Set<String> = {
        guard let bytes = Self.read(extracted + "/templates.txt") else { return [] }
        return Set(String(decoding: bytes, as: UTF8.self).split(separator: "\n").map(String.init))
    }()

    /// Images Scripts/extract-assets.sh decoded on a Mac, for renditions
    /// whose compression Perry doesn't decode (CoreUI's deepmap2):
    /// <name>@<scale>x.png in a directory beside the catalog, and
    /// <name>~dark@<scale>x.png for the dark appearance.
    private let extracted: String

    public init?(path: String) {
        guard let bytes = CompiledAssetCatalog.read(path), bytes.count > 32, Array(bytes[0..<8]) == Array("BOMStore".utf8) else { return nil }
        self.bytes = bytes
        extracted = path + ".images"
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
        // APPEARANCEKEYS: an appearance's name to its number.
        for (key, value) in tree(variables["APPEARANCEKEYS"])
        where String(decoding: bytes[key], as: UTF8.self) == "UIAppearanceDark" && value.count >= 2 {
            darkAppearance = le16(value.lowerBound)
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

    // MARK: Images

    /// The named image's pixels: the rendition for the appearance asked
    /// for, else the default one; for the screen's scale, else the next
    /// larger, else the largest smaller; for the phone, else any device.
    public func pixels(named name: String, dark: Bool, screenScale: Int) -> (pixels: Pixels, scale: Double)? {
        guard let identifier = identifiers[name] else { return nil }
        // UIUserInterfaceIdiom in catalogs: universal 0, phone 1.
        let candidates = renditions.indices.filter {
            attribute(renditions[$0].key, .identifier) == identifier && attribute(renditions[$0].key, .idiom) <= 1
        }
        // The appearance asked for first: the dark one's renditions only
        // when it is asked for.
        func rank(_ index: Int) -> (Int, Int, Int) {
            let key = renditions[index].key
            let isDark = darkAppearance.map { attribute(key, .appearance) == $0 } ?? false
            let scale = Int(attribute(key, .scale))
            let distance = scale == screenScale ? 0 : scale > screenScale ? scale - screenScale : 10 + screenScale - scale
            return (isDark == dark ? 0 : 1, distance, attribute(key, .idiom) == 1 ? 0 : 1)
        }
        for index in candidates.sorted(by: { rank($0) < rank($1) }) {
            guard let pixels = pixels(index), pixels.width > 0, pixels.height > 0 else { continue }
            return (pixels, Double(max(1, le32(renditions[index].range.lowerBound + 20))) / 100)
        }
        return nil
    }

    /// Images Scripts/extract-assets.sh decoded on a Mac, for renditions
    /// whose compression Perry doesn't decode: the file at the scale
    /// nearest the screen's, the dark appearance's first when it is asked
    /// for.
    public func extractedImageFiles(named name: String, dark: Bool, screenScale: Int) -> [(path: String, scale: Int)] {
        let scales = [screenScale] + [3, 2, 1].filter { $0 != screenScale }
        return (dark ? ["~dark", ""] : [""]).flatMap { variant in scales.map { (extracted + "/\(name)\(variant)@\($0)x.png", $0) } }
    }

    /// The file Scripts/extract-assets.sh wrote for a named data set (what
    /// NSDataAsset reads), if there is one: data/<name> beside the catalog.
    public func extractedDataFile(named name: String) -> String? {
        guard !name.isEmpty, !name.contains(".."), !name.hasPrefix("/") else { return nil }
        let path = extracted + "/data/" + name
        var info = stat()
        return stat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG ? path : nil
    }

    /// A file's bytes; nil for directories and missing files.
    static func read(_ path: String) -> [UInt8]? {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, let file = fopen(path, "rb") else { return nil }
        defer { fclose(file) }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        let count = bytes.withUnsafeMutableBytes { fread($0.baseAddress, 1, $0.count, file) }
        return count == bytes.count ? bytes : nil
    }

    // MARK: Colors

    /// A named color's components (white and alpha, or red, green, blue and
    /// alpha), for the appearance asked for, else the default one. A color
    /// rendition's data is 'RLOC', a version, flags, the count of
    /// components, then the components as doubles.
    public func color(named name: String, dark: Bool) -> [Double]? {
        guard let identifier = identifiers[name] else { return nil }
        let candidates = renditions.indices.filter {
            attribute(renditions[$0].key, .identifier) == identifier && attribute(renditions[$0].key, .idiom) <= 1
        }
        let ordered = candidates.sorted { first, second in
            let isDark = { (index: Int) in self.darkAppearance.map { self.attribute(self.renditions[index].key, .appearance) == $0 } ?? false }
            return (isDark(first) == dark ? 0 : 1) < (isDark(second) == dark ? 0 : 1)
        }
        let magic = Array("RLOC".utf8)
        for index in ordered {
            let range = renditions[index].range
            var at = range.lowerBound
            while at + 16 <= range.upperBound {
                defer { at += 1 }
                guard bytes[at] == magic[0], Array(bytes[at..<at + 4]) == magic else { continue }
                let count = le32(at + 12)
                guard (1...5).contains(count), at + 16 + count * 8 <= range.upperBound else { continue }
                return (0..<count).map { component in
                    var bits: UInt64 = 0
                    for byte in 0..<8 { bits |= UInt64(bytes[at + 16 + component * 8 + byte]) << (8 * UInt64(byte)) }
                    return Double(bitPattern: bits)
                }
            }
        }
        return nil
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
        if compression == 10 { return deepmap(data, version: version, count: count, width: width, height: height) }
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

    // MARK: Deepmap

    /// A rendition in CoreUI's "deepmap-lzfse" compression (10): one block
    /// (MLEC versions 0 and 2) or bands of rows in KCBC chunks (1 and 3).
    private func deepmap(_ data: Range<Int>, version: Int, count: Int, width: Int, height: Int) -> Pixels? {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height * 4)
        if version == 0 || version == 2 {
            guard count >= 0, data.lowerBound + 16 + count <= data.upperBound,
                  let band = deepmapBand(data.lowerBound + 16..<data.lowerBound + 16 + count, width: width, rows: height) else { return nil }
            pixels = band
        } else {
            var at = data.lowerBound + 16
            for _ in 0..<count {
                guard at + 20 <= data.upperBound, Array(bytes[at..<at + 4]) == Array("KCBC".utf8) else { return nil }
                let rows = le32(at + 12), length = le32(at + 16)
                guard rows > 0, length >= 0, at + 20 + length <= data.upperBound,
                      let band = deepmapBand(at + 20..<at + 20 + length, width: width, rows: rows) else { return nil }
                pixels += band
                at += 20 + length
            }
        }
        guard pixels.count == width * height * 4 else { return nil }
        return Pixels(width: width, height: height, bytes: pixels)
    }

    /// One band: a header (a 5, the channels, a length), "dmap", the band's
    /// kind and its channels again, then its tiles, of 256 by 256 pixels at
    /// most, in rows, each with its length before it and compressed by
    /// itself, with LZFSE or, when small, bare LZVN. By kind:
    ///
    /// - 3: the tile's pixels as they are, BGRA or gray and alpha.
    /// - 4: a palette of BGRA colors before the tiles; a tile is its
    ///   alpha, then an index into the palette for each pixel.
    /// - 2: a tile is its alpha, a predictor for each row, then each
    ///   pixel's colors as what they differ by from the prediction: the
    ///   high bytes of every difference, then the low ones, the sign in
    ///   the lowest bit. The colors are a luma and two halved chroma
    ///   differences (t = luma - c2, B = t + c1, R = B - 2 c1,
    ///   G = t + 2 c2), or a gray. A row predicts nothing (0), the pixel
    ///   to the left (2), the one above (3), their rounded mean (4), or
    ///   (1) whichever of the two the luma above and above-left say is
    ///   nearer, as Paeth's predictor chooses between them. Tiles predict
    ///   from nothing outside them.
    private func deepmapBand(_ blob: Range<Int>, width: Int, rows: Int) -> [UInt8]? {
        guard blob.count >= 24, Array(bytes[blob.lowerBound + 16..<blob.lowerBound + 20]) == Array("dmap".utf8) else { return nil }
        let channels = le32(blob.lowerBound + 4), kind = Int(bytes[blob.lowerBound + 20])
        guard channels == 4 || channels == 2, width > 0, rows > 0 else { return nil }
        let colors = channels - 1
        var at = blob.lowerBound + 24
        var palette: ArraySlice<UInt8> = []
        if kind == 4 {
            let count = le32(at)
            guard channels == 4, count >= 0, at + 4 + count * 4 <= blob.upperBound else { return nil }
            palette = bytes[at + 4..<at + 4 + count * 4]
            at += 4 + count * 4
        }
        var out = [UInt8](repeating: 0, count: width * rows * 4)
        func clamped(_ value: Int32) -> UInt8 { UInt8(max(0, min(255, value))) }
        for top in stride(from: 0, to: rows, by: 256) {
            let tileRows = min(256, rows - top)
            for left in stride(from: 0, to: width, by: 256) {
                let tileWidth = min(256, width - left), count = tileWidth * tileRows
                let length = le32(at)
                guard at + 4 <= blob.upperBound, length >= 0, at + 4 + length <= blob.upperBound,
                      let raw = expand(at + 4..<at + 4 + length, capacity: count * (2 * colors + 1) + tileRows + 64) else { return nil }
                at += 4 + length
                switch kind {
                case 3:
                    guard raw.count >= count * channels else { return nil }
                    for row in 0..<tileRows {
                        for column in 0..<tileWidth {
                            let from = (row * tileWidth + column) * channels, to = ((top + row) * width + left + column) * 4
                            if channels == 4 {
                                (out[to], out[to + 1], out[to + 2], out[to + 3]) = (raw[from], raw[from + 1], raw[from + 2], raw[from + 3])
                            } else {
                                (out[to], out[to + 1], out[to + 2], out[to + 3]) = (raw[from], raw[from], raw[from], raw[from + 1])
                            }
                        }
                    }
                case 4:
                    // An index is two bytes when the palette is past 256 colors.
                    let wide = palette.count > 256 * 4
                    guard raw.count >= count * (wide ? 3 : 2) else { return nil }
                    for row in 0..<tileRows {
                        for column in 0..<tileWidth {
                            let pixel = row * tileWidth + column, to = ((top + row) * width + left + column) * 4
                            let index = wide ? Int(raw[count + pixel * 2]) | Int(raw[count + pixel * 2 + 1]) << 8 : Int(raw[count + pixel])
                            guard index * 4 + 3 < palette.count else { return nil }
                            let color = palette.startIndex + index * 4
                            (out[to], out[to + 1], out[to + 2], out[to + 3]) = (palette[color], palette[color + 1], palette[color + 2], raw[pixel])
                        }
                    }
                case 2:
                    let modes = count, high = count + tileRows, low = high + colors * count
                    guard raw.count >= low + colors * count else { return nil }
                    var above = [Int32](repeating: 0, count: tileWidth * colors), current = above
                    for row in 0..<tileRows {
                        let mode = raw[modes + row]
                        guard mode <= 4 else { return nil }
                        for column in 0..<tileWidth {
                            let pixel = row * tileWidth + column
                            var chooseLeft = true
                            if mode == 1 {
                                let leftLuma = column > 0 ? current[(column - 1) * colors] : 0
                                let aboveLuma = row > 0 ? above[column * colors] : 0
                                let cornerLuma = row > 0 && column > 0 ? above[(column - 1) * colors] : 0
                                chooseLeft = abs(aboveLuma - cornerLuma) <= abs(leftLuma - cornerLuma)
                            }
                            for channel in 0..<colors {
                                let leftValue = column > 0 ? current[(column - 1) * colors + channel] : 0
                                let aboveValue = row > 0 ? above[column * colors + channel] : 0
                                let prediction: Int32
                                switch mode {
                                case 0: prediction = 0
                                case 1: prediction = chooseLeft ? leftValue : aboveValue
                                case 2: prediction = leftValue
                                case 3: prediction = aboveValue
                                default: prediction = column == 0 ? aboveValue : row == 0 ? leftValue : (leftValue + aboveValue + 1) / 2
                                }
                                let coded = Int32(raw[high + pixel * colors + channel]) << 8 | Int32(raw[low + pixel * colors + channel])
                                current[column * colors + channel] = prediction + (coded & 1 != 0 ? -(coded >> 1) : coded >> 1)
                            }
                            let to = ((top + row) * width + left + column) * 4
                            if colors == 3 {
                                let luma = current[column * 3], first = current[column * 3 + 1], second = current[column * 3 + 2]
                                let middle = luma - second, blue = middle + first
                                (out[to], out[to + 1], out[to + 2]) = (clamped(blue), clamped(middle + 2 * second), clamped(blue - 2 * first))
                            } else {
                                let gray = clamped(current[column])
                                (out[to], out[to + 1], out[to + 2]) = (gray, gray, gray)
                            }
                            out[to + 3] = raw[pixel]
                        }
                        swap(&above, &current)
                    }
                default:
                    return nil
                }
            }
        }
        return out
    }

    /// A tile's bytes: an LZFSE stream, which begins "bvx", or bare LZVN.
    private func expand(_ range: Range<Int>, capacity: Int) -> [UInt8]? {
        if range.count >= 4, Array(bytes[range.lowerBound..<range.lowerBound + 3]) == Array("bvx".utf8) {
            return decompress(range, 4, capacity: capacity)
        }
        return lzvn(range, capacity: capacity)
    }

    /// LZVN without a container, as small tiles are compressed: opcodes
    /// that copy literals from the stream and matches from what was
    /// written, to the end-of-stream opcode.
    private func lzvn(_ range: Range<Int>, capacity: Int) -> [UInt8]? {
        var out: [UInt8] = []
        out.reserveCapacity(capacity)
        var at = range.lowerBound, distance = 0
        func literals(_ count: Int) -> Bool {
            guard at + count <= range.upperBound, out.count + count <= capacity else { return false }
            out += bytes[at..<at + count]
            at += count
            return true
        }
        func match(_ count: Int) -> Bool {
            guard distance > 0, distance <= out.count, out.count + count <= capacity else { return false }
            var from = out.count - distance
            for _ in 0..<count {
                out.append(out[from])
                from += 1
            }
            return true
        }
        while at < range.upperBound {
            let opcode = Int(bytes[at])
            switch opcode {
            case 0x06:
                return out
            case 0x0e, 0x16:
                at += 1
            case 0x1e, 0x26, 0x2e, 0x36, 0x3e, 0x70...0x7f, 0xd0...0xdf:
                return nil
            case 0xe0...0xef:
                // Literals alone: 1 to 15, or 16 and more with their count
                // in the next byte.
                var count = opcode & 15
                if opcode == 0xe0 {
                    guard at + 1 < range.upperBound else { return nil }
                    count = Int(bytes[at + 1]) + 16
                    at += 1
                }
                at += 1
                guard literals(count) else { return nil }
            case 0xf0...0xff:
                // A match alone, at the last distance.
                var count = opcode & 15
                if opcode == 0xf0 {
                    guard at + 1 < range.upperBound else { return nil }
                    count = Int(bytes[at + 1]) + 16
                    at += 1
                }
                at += 1
                guard match(count) else { return nil }
            default:
                // Up to three literals, then a match of three to ten bytes
                // (more for a medium distance), with its distance in the
                // opcode and the bytes after it, or the last distance.
                var literalCount = opcode >> 6, matchCount = (opcode >> 3 & 7) + 3
                if (0xa0...0xbf).contains(opcode) {
                    guard at + 2 < range.upperBound else { return nil }
                    let next = Int(bytes[at + 1]) | Int(bytes[at + 2]) << 8
                    literalCount = opcode >> 3 & 3
                    matchCount = ((opcode & 7) << 2 | next & 3) + 3
                    distance = next >> 2
                    at += 3
                } else if opcode & 7 == 6 {
                    at += 1
                } else if opcode & 7 == 7 {
                    guard at + 2 < range.upperBound else { return nil }
                    distance = Int(bytes[at + 1]) | Int(bytes[at + 2]) << 8
                    at += 3
                } else {
                    guard at + 1 < range.upperBound else { return nil }
                    distance = (opcode & 7) << 8 | Int(bytes[at + 1])
                    at += 2
                }
                guard literals(literalCount), match(matchCount) else { return nil }
            }
        }
        return nil
    }

    /// CoreUI's compression: none 0, LZVN 3 and LZFSE 4, which the LZFSE
    /// decoder reads both of.
    private func decompress(_ range: Range<Int>, _ compression: Int, capacity: Int) -> [UInt8]? {
        if compression == 0 { return Array(bytes[range]) }
        guard compression == 3 || compression == 4, let decode = CompiledAssetCatalog.decode else { return nil }
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
