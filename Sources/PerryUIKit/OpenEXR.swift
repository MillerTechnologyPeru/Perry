import Glibc

// OpenEXR pictures, as far as SceneKit's baked light maps need: scanline
// files whose channels are half or float, stored raw or with PIZ (the
// wavelet and Huffman scheme of the format), read into floats. Other
// compressions are not read.

enum OpenEXR {
    struct Channel {
        var name: String
        /// 0 for unsigned int, 1 for half, 2 for float.
        var type: Int
    }

    /// A picture: red, green, blue and alpha as floats, the top row first.
    static func decode(_ b: [UInt8]) -> (width: Int, height: Int, rgba: [Float])? {
        guard b.count > 16, b[0] == 0x76, b[1] == 0x2f, b[2] == 0x31, b[3] == 0x01 else { return nil }
        func u32(_ at: Int) -> Int { Int(UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24) }
        func i32(_ at: Int) -> Int { Int(Int32(truncatingIfNeeded: u32(at))) }
        var position = 8
        var channels: [Channel] = []
        var compression = -1
        var window = (minX: 0, minY: 0, maxX: -1, maxY: -1)
        while position < b.count, b[position] != 0 {
            guard let nameEnd = b[position...].firstIndex(of: 0) else { return nil }
            let name = String(decoding: b[position..<nameEnd], as: UTF8.self)
            position = nameEnd + 1
            guard let typeEnd = b[position...].firstIndex(of: 0) else { return nil }
            position = typeEnd + 1
            let size = u32(position)
            position += 4
            let value = position
            switch name {
            case "compression": compression = Int(b[value])
            case "dataWindow": window = (i32(value), i32(value + 4), i32(value + 8), i32(value + 12))
            case "channels":
                var at = value
                while at < value + size, b[at] != 0 {
                    guard let end = b[at...].firstIndex(of: 0) else { return nil }
                    channels.append(Channel(name: String(decoding: b[at..<end], as: UTF8.self), type: i32(end + 1)))
                    at = end + 1 + 16
                }
            default: break
            }
            position = value + size
        }
        position += 1
        let width = window.maxX - window.minX + 1, height = window.maxY - window.minY + 1
        guard width > 0, height > 0, compression == 0 || compression == 4, !channels.isEmpty, channels.allSatisfy({ $0.type == 1 || $0.type == 2 }) else { return nil }
        let linesPerBlock = compression == 4 ? 32 : 1
        let blocks = (height + linesPerBlock - 1) / linesPerBlock
        let table = position
        guard table + blocks * 8 <= b.count else { return nil }
        var rgba = [Float](repeating: 1, count: width * height * 4)
        let slot: [String: Int] = ["R": 0, "G": 1, "B": 2, "A": 3]
        // Samples of a channel in 16-bit words: one for half, two for float.
        let words = channels.map { $0.type == 1 ? 1 : 2 }
        for block in 0..<blocks {
            let offset = u32(table + block * 8)
            guard offset + 8 <= b.count else { return nil }
            let y = i32(offset) - window.minY, size = u32(offset + 4)
            guard offset + 8 + size <= b.count, y >= 0 else { return nil }
            let rows = min(linesPerBlock, height - y)
            let data = Array(b[(offset + 8)..<(offset + 8 + size)])
            // The block's samples as 16-bit words, channel by channel, a row at a time.
            var planes: [[UInt16]]
            if compression == 4 {
                guard let decoded = piz(data, width: width, rows: rows, words: words) else { return nil }
                planes = decoded
            } else {
                // Raw: each row has each channel's samples in turn.
                planes = words.map { [UInt16](repeating: 0, count: width * rows * $0) }
                var at = 0
                for row in 0..<rows {
                    for (c, w) in words.enumerated() {
                        for i in 0..<width * w {
                            guard at + 1 < data.count else { return nil }
                            planes[c][row * width * w + i] = UInt16(data[at]) | UInt16(data[at + 1]) << 8
                            at += 2
                        }
                    }
                }
            }
            for row in 0..<rows {
                for (c, channel) in channels.enumerated() {
                    guard let target = slot[channel.name] else { continue }
                    for x in 0..<width {
                        let value: Float
                        if channel.type == 1 {
                            value = half(planes[c][row * width + x])
                        } else {
                            let lo = UInt32(planes[c][(row * width + x) * 2]), hi = UInt32(planes[c][(row * width + x) * 2 + 1])
                            value = Float(bitPattern: lo | hi << 16)
                        }
                        rgba[((y + row) * width + x) * 4 + target] = value
                    }
                }
            }
        }
        return (width, height, rgba)
    }

    static func half(_ h: UInt16) -> Float {
        let sign: UInt32 = UInt32(h >> 15) << 31
        let exponent = Int((h >> 10) & 0x1f), mantissa = UInt32(h & 0x3ff)
        if exponent == 0 {
            if mantissa == 0 { return Float(bitPattern: sign) }
            // A subnormal.
            let f = Float(mantissa) / 1024 * powf(2, -14)
            return sign == 0 ? f : -f
        }
        if exponent == 31 { return Float(bitPattern: sign | 0x7f80_0000 | mantissa << 13) }
        return Float(bitPattern: sign | UInt32(exponent + 112) << 23 | mantissa << 13)
    }

    // MARK: PIZ

    /// A PIZ block's channels' words: Huffman decoded, wavelet transformed back, and mapped through the
    /// table of the values the block uses.
    private static func piz(_ data: [UInt8], width: Int, rows: Int, words: [Int]) -> [[UInt16]]? {
        guard data.count >= 4 else { return nil }
        var at = 0
        func u16() -> Int { let v = Int(data[at]) | Int(data[at + 1]) << 8; at += 2; return v }
        let minimum = u16(), maximum = u16()
        var bitmap = [UInt8](repeating: 0, count: 8192)
        if minimum <= maximum {
            guard maximum < 8192, at + (maximum - minimum + 1) <= data.count else { return nil }
            for i in minimum...maximum { bitmap[i] = data[at]; at += 1 }
        }
        var lut = [UInt16](repeating: 0, count: 65536)
        var used = 0
        for i in 0..<65536 where i == 0 || bitmap[i >> 3] & UInt8(1 << (i & 7)) != 0 {
            lut[used] = UInt16(i)
            used += 1
        }
        let maxValue = used - 1
        guard at + 4 <= data.count else { return nil }
        let length = Int(UInt32(data[at]) | UInt32(data[at + 1]) << 8 | UInt32(data[at + 2]) << 16 | UInt32(data[at + 3]) << 24)
        at += 4
        guard length >= 0, at + length <= data.count else { return nil }
        let total = words.reduce(0) { $0 + $1 * width * rows }
        guard var words16 = huffman(Array(data[at..<(at + length)]), count: total) else { return nil }
        var starts: [Int] = []
        var offset = 0
        for w in words { starts.append(offset); offset += width * rows * w }
        for (c, w) in words.enumerated() {
            for j in 0..<w { wavelet(&words16, base: starts[c] + j, nx: width, ox: w, ny: rows, oy: width * w, maximum: maxValue) }
        }
        for i in words16.indices { words16[i] = lut[Int(words16[i])] }
        return words.enumerated().map { c, w in Array(words16[starts[c]..<(starts[c] + width * rows * w)]) }
    }

    // MARK: Wavelet

    private static func decode14(_ l: UInt16, _ h: UInt16) -> (UInt16, UInt16) {
        let ls = Int(Int16(bitPattern: l)), hs = Int(Int16(bitPattern: h))
        let a = ls + (hs & 1) + (hs >> 1)
        return (UInt16(truncatingIfNeeded: a), UInt16(truncatingIfNeeded: a - hs))
    }

    private static func decode16(_ l: UInt16, _ h: UInt16) -> (UInt16, UInt16) {
        let m = Int(l), d = Int(h)
        let b = (m - (d >> 1)) & 0xffff
        return (UInt16((d + b) & 0xffff), UInt16(b))
    }

    private static func wavelet(_ data: inout [UInt16], base: Int, nx: Int, ox: Int, ny: Int, oy: Int, maximum: Int) {
        let w14 = maximum < (1 << 14)
        func pair(_ l: UInt16, _ h: UInt16) -> (UInt16, UInt16) { w14 ? decode14(l, h) : decode16(l, h) }
        let n = nx > ny ? ny : nx
        var p = 1
        while p <= n { p <<= 1 }
        p >>= 1
        var p2 = p
        p >>= 1
        while p >= 1 {
            var py = base
            let ey = base + oy * (ny - p2)
            let oy1 = oy * p, oy2 = oy * p2, ox1 = ox * p, ox2 = ox * p2
            while py <= ey {
                var px = py
                let ex = py + ox * (nx - p2)
                while px <= ex {
                    let p01 = px + ox1, p10 = px + oy1, p11 = p10 + ox1
                    let (i00, i10) = pair(data[px], data[p10])
                    let (i01, i11) = pair(data[p01], data[p11])
                    (data[px], data[p01]) = pair(i00, i01)
                    (data[p10], data[p11]) = pair(i10, i11)
                    px += ox2
                }
                // The last column, if it is left over.
                if nx & p != 0 {
                    let p10 = px + oy1
                    (data[px], data[p10]) = pair(data[px], data[p10])
                }
                py += oy2
            }
            // The last row.
            if ny & p != 0 {
                var px = py
                let ex = py + ox * (nx - p2)
                while px <= ex {
                    let p01 = px + ox1
                    (data[px], data[p01]) = pair(data[px], data[p01])
                    px += ox2
                }
            }
            p2 = p
            p >>= 1
        }
    }

    // MARK: Huffman

    private static let shortZeroRun = 59, longZeroRun = 63, shortestLongRun = 6
    private static let decodeBits = 14, encodeSize = (1 << 16) + 1

    private static func huffman(_ input: [UInt8], count: Int) -> [UInt16]? {
        guard input.count >= 20 else { return nil }
        func u32(_ at: Int) -> Int { Int(UInt32(input[at]) | UInt32(input[at + 1]) << 8 | UInt32(input[at + 2]) << 16 | UInt32(input[at + 3]) << 24) }
        let minCode = u32(0), maxCode = u32(4), bits = u32(12)
        guard minCode >= 0, maxCode < encodeSize, minCode <= maxCode else { return nil }
        var position = 20
        var table = [UInt64](repeating: 0, count: encodeSize)
        // The code lengths, six bits each, with runs of zeros.
        var buffer: UInt64 = 0, held = 0
        func take(_ n: Int) -> Int? {
            while held < n {
                guard position < input.count else { return nil }
                buffer = buffer << 8 | UInt64(input[position])
                position += 1
                held += 8
            }
            held -= n
            return Int((buffer >> UInt64(held)) & ((1 << UInt64(n)) - 1))
        }
        var code = minCode
        while code <= maxCode {
            guard let length = take(6) else { return nil }
            if length == longZeroRun {
                guard let run = take(8) else { return nil }
                let zeros = run + shortestLongRun
                guard code + zeros <= maxCode + 1 else { return nil }
                code += zeros
            } else if length >= shortZeroRun {
                let zeros = length - shortZeroRun + 2
                guard code + zeros <= maxCode + 1 else { return nil }
                code += zeros
            } else {
                table[code] = UInt64(length)
                code += 1
            }
        }
        // Canonical codes: shorter lengths take the higher numbers.
        var counts = [UInt64](repeating: 0, count: 59)
        for i in 0..<encodeSize { counts[Int(table[i])] += 1 }
        var next: UInt64 = 0
        for i in stride(from: 58, through: 0, by: -1) {
            let following = (next + counts[i]) >> 1
            counts[i] = next
            next = following
        }
        for i in 0..<encodeSize {
            let l = Int(table[i])
            if l > 0 {
                table[i] = UInt64(l) | counts[l] << 6
                counts[l] += 1
            }
        }
        // The decoding tables: a short code fills every entry it starts, a long one is listed under its prefix.
        let decodeSize = 1 << decodeBits
        var shortLength = [UInt8](repeating: 0, count: decodeSize)
        var shortSymbol = [UInt32](repeating: 0, count: decodeSize)
        var longSymbols = [Int: [Int]]()
        for symbol in minCode...maxCode {
            let l = Int(table[symbol] & 63), c = Int(table[symbol] >> 6)
            if l == 0 { continue }
            if c >> l != 0 { return nil }
            if l > decodeBits {
                longSymbols[c >> (l - decodeBits), default: []].append(symbol)
            } else {
                let first = c << (decodeBits - l)
                for i in 0..<(1 << (decodeBits - l)) {
                    guard shortLength[first + i] == 0 else { return nil }
                    shortLength[first + i] = UInt8(l)
                    shortSymbol[first + i] = UInt32(symbol)
                }
            }
        }
        // Decode: the run-length symbol (the last) repeats the value before it.
        var out = [UInt16]()
        out.reserveCapacity(count)
        var bitBuffer: UInt64 = 0, bitCount = 0
        var read = position
        let end = position + (bits + 7) / 8
        guard end <= input.count else { return nil }
        func emit(_ symbol: Int) -> Bool {
            if symbol == maxCode {
                guard bitCount >= 0, let last = out.last else { return false }
                if bitCount < 8 {
                    guard read < end else { return false }
                    bitBuffer = bitBuffer << 8 | UInt64(input[read]); read += 1; bitCount += 8
                }
                bitCount -= 8
                let repeats = Int((bitBuffer >> UInt64(bitCount)) & 0xff)
                guard out.count + repeats <= count else { return false }
                for _ in 0..<repeats { out.append(last) }
            } else {
                guard out.count < count else { return false }
                out.append(UInt16(symbol))
            }
            return true
        }
        while read < end {
            bitBuffer = bitBuffer << 8 | UInt64(input[read]); read += 1; bitCount += 8
            while bitCount >= decodeBits {
                let index = Int((bitBuffer >> UInt64(bitCount - decodeBits)) & UInt64(decodeSize - 1))
                if shortLength[index] != 0 {
                    bitCount -= Int(shortLength[index])
                    guard emit(Int(shortSymbol[index])) else { return nil }
                } else {
                    guard let candidates = longSymbols[index] else { return nil }
                    var found = false
                    for symbol in candidates {
                        let l = Int(table[symbol] & 63)
                        while bitCount < l, read < end { bitBuffer = bitBuffer << 8 | UInt64(input[read]); read += 1; bitCount += 8 }
                        if bitCount >= l, Int(table[symbol] >> 6) == Int((bitBuffer >> UInt64(bitCount - l)) & ((1 << UInt64(l)) - 1)) {
                            bitCount -= l
                            guard emit(symbol) else { return nil }
                            found = true
                            break
                        }
                    }
                    if !found { return nil }
                }
            }
        }
        // The last few short codes, padded to a byte.
        let spare = (8 - bits) & 7
        bitBuffer >>= UInt64(spare)
        bitCount -= spare
        while bitCount > 0 {
            let index = Int((bitBuffer << UInt64(decodeBits - bitCount)) & UInt64(decodeSize - 1))
            guard shortLength[index] != 0 else { return nil }
            bitCount -= Int(shortLength[index])
            guard emit(Int(shortSymbol[index])) else { return nil }
        }
        return out.count == count ? out : nil
    }
}
