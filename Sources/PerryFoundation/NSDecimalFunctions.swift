import CPerryFoundation
import Glibc
import PerryObjCInterop

// NSDecimal and its C functions (NSDecimalAdd and the rest), which
// NSDecimalNumber computes with. The arithmetic is swift-foundation's
// Decimal (Apache License 2.0 with Runtime Library Exception, Apple Inc. and
// the Swift project authors), which Darwin's Foundation now uses too, on
// Darwin's own layout of the struct and with Darwin's NSCalculationError
// numbers. Results match Darwin's bit for bit, its quirks included: a
// mantissa that overflows is truncated rather than rounded, subtraction and
// multiplication report no lost precision, and a product's exponent below
// -128 wraps.

// MARK: - The value

/// An NSDecimal: a mantissa of up to 38 decimal digits, eight 16-bit words
/// least first, times ten to an exponent of -128 through 127. A length of
/// zero is zero, or not a number when negative. In memory, as Darwin has
/// it, a word of bit fields (the exponent in its low byte, the length in
/// the next four bits, then the sign and compact bits and 18 reserved
/// ones) and the mantissa: 20 bytes.
struct PerryDecimal {
    static let maxSize = 8
    static let byteCount = 20
    /// NSDecimalNoScale.
    static let noScale = Int(Int16.max)

    var exponent: Int32 = 0
    var length: UInt32 = 0
    var isNegative = false
    var isCompact = false
    var reserved: UInt32 = 0
    var mantissa: [UInt16] = Array(repeating: 0, count: PerryDecimal.maxSize)

    init() {}

    static var zero: PerryDecimal { PerryDecimal() }

    static var nan: PerryDecimal {
        var value = PerryDecimal()
        value.isNegative = true
        return value
    }

    var isNaN: Bool { length == 0 && isNegative }
    var isZero: Bool { length == 0 && !isNegative }

    // MARK: Memory

    init(bytes: UnsafeRawPointer) {
        let flags = bytes.loadUnaligned(as: UInt32.self)
        exponent = Int32(Int8(truncatingIfNeeded: flags & 0xff))
        length = flags >> 8 & 0xf
        isNegative = flags & 0x1000 != 0
        isCompact = flags & 0x2000 != 0
        reserved = flags >> 14
        mantissa = (0 ..< PerryDecimal.maxSize).map { bytes.loadUnaligned(fromByteOffset: 4 + 2 * $0, as: UInt16.self) }
    }

    func store(to bytes: UnsafeMutableRawPointer) {
        var flags = UInt32(UInt8(bitPattern: Int8(truncatingIfNeeded: exponent))) | (length & 0xf) << 8
        if isNegative { flags |= 0x1000 }
        if isCompact { flags |= 0x2000 }
        flags |= (reserved & 0x3ffff) << 14
        bytes.storeBytes(of: flags, as: UInt32.self)
        for index in 0 ..< PerryDecimal.maxSize {
            bytes.storeBytes(of: index < mantissa.count ? mantissa[index] : 0, toByteOffset: 4 + 2 * index, as: UInt16.self)
        }
    }

    // MARK: Conversions

    init(_ value: UInt64) {
        guard value != 0 else { return }
        var compactValue = value
        var exponent: Int32 = 0
        while compactValue % 10 == 0 {
            compactValue /= 10
            exponent += 1
        }
        isCompact = true
        self.exponent = exponent
        length = UInt32((UInt64.bitWidth - compactValue.leadingZeroBitCount + 15) / 16)
        for index in 0 ..< 4 { mantissa[index] = UInt16(truncatingIfNeeded: compactValue >> (16 * UInt64(index))) }
    }

    init(_ value: Int64) {
        self.init(value.magnitude)
        if value < 0 { isNegative = true }
    }

    init(mantissa: UInt64, exponent: Int16, isNegative: Bool) {
        self.init(mantissa)
        self.exponent += Int32(exponent)
        self.isNegative = isNegative
    }

    /// A double as Darwin's NSDecimalNumber and -decimalValue take one:
    /// multiplied or divided by ten in floating point until just under
    /// 2^64, its whole part as the mantissa, then compacted. 0.1 stays 0.1;
    /// 13291.571428571429 is 13291.571428571430912.
    init(_ value: Double) {
        if value.isNaN || value.isInfinite {
            self = .nan
            return
        }
        if value == 0 { return }
        var scaled = abs(value)
        var exponent = 0
        // Too small: the digits there are at the smallest exponent, none
        // for a value under 1e-147.
        while scaled < Double(UInt64.max - 1), exponent > Int(Int8.min) {
            scaled *= 10
            exponent -= 1
        }
        // Too large: the largest mantissa at the largest exponent.
        while Double(UInt64.max) <= scaled, exponent < Int(Int8.max) {
            scaled /= 10
            exponent += 1
        }
        var whole = scaled >= Double(UInt64.max) ? UInt64.max : UInt64(scaled)
        var index = 0
        while whole != 0 && index < PerryDecimal.maxSize {
            mantissa[index] = UInt16(truncatingIfNeeded: whole)
            whole >>= 16
            index += 1
        }
        guard index > 0 else { return }
        length = UInt32(index)
        isNegative = value < 0
        self.exponent = Int32(exponent)
        compact()
    }

    var doubleValue: Double {
        if length == 0 { return isNegative ? .nan : 0 }
        var value = 0.0
        for index in (0 ..< min(Int(length), PerryDecimal.maxSize)).reversed() {
            value = value * 65536 + Double(mantissa[index])
        }
        if exponent < 0 {
            for _ in exponent ..< 0 { value /= 10 }
        } else {
            for _ in 0 ..< exponent { value *= 10 }
        }
        return isNegative ? -value : value
    }

    private var unsignedInt64Value: UInt64 {
        if exponent < -38 || exponent > 20 || length == 0 { return 0 }
        var value = self
        value.exponent = 0
        value.isNegative = false
        for _ in 0 ..< abs(exponent) {
            if exponent < 0 {
                if let result = try? value.divide(byShort: 10) { value = result.result }
            } else if let result = try? value.multiply(byShort: 10) {
                value = result
            }
        }
        return (0 ..< 4).reduce(0) { $0 | UInt64(value.mantissa[$1]) << (16 * UInt64($1)) }
    }

    var int64Value: Int64 {
        let magnitude = unsignedInt64Value
        if isNegative {
            if magnitude == Int64.max.magnitude + 1 { return Int64.min }
            if magnitude <= Int64.max.magnitude { return -Int64(magnitude) }
        }
        return Int64(bitPattern: magnitude)
    }

    var uint64Value: UInt64 {
        let magnitude = unsignedInt64Value
        if !isNegative { return magnitude }
        if magnitude == Int64.max.magnitude + 1 { return UInt64(bitPattern: Int64.min) }
        if magnitude <= Int64.max.magnitude { return UInt64(bitPattern: -Int64(magnitude)) }
        return magnitude
    }

    // MARK: Text

    /// The digits with `separator` between the whole part and the
    /// fraction, as NSDecimalString writes them: "NaN" for not a number,
    /// no exponent, and a leading zero before the separator.
    func string(separator: String = ".") -> String {
        if isNaN { return "NaN" }
        if length == 0 { return "0" }
        var buffer: [String] = []
        var copy = self
        while copy.exponent > 0 {
            buffer.append("0")
            copy.exponent -= 1
        }
        if copy.exponent == 0 { copy.exponent = 1 }
        while copy.length != 0 {
            if copy.exponent == 0 { buffer.append(String(separator.reversed())) }
            copy.exponent += 1
            // Only dividing by zero throws.
            guard let step = try? copy.divide(byShort: 10) else { break }
            copy = step.result
            buffer.append(String(UnicodeScalar(UInt8(48 + step.remainder))))
        }
        if copy.exponent <= 0 {
            while copy.exponent != 0 {
                buffer.append("0")
                copy.exponent += 1
            }
            buffer.append(String(separator.reversed()))
            buffer.append("0")
        }
        if copy.isNegative { buffer.append("-") }
        return String(buffer.joined().reversed())
    }

    /// What NSDecimal's scanner reads at the start of `text`: white space,
    /// a sign, digits, the separator and more digits, and an exponent
    /// after "e" or "E". The value, nil when there is no number or it is
    /// out of range, and the bytes read.
    static func parse(_ text: [UInt8], separator: [UInt8] = Array(".".utf8),
                      matchEntireString: Bool = false) -> (value: PerryDecimal?, length: Int) {
        func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || (0x09 ... 0x0d).contains(byte) }
        func digit(_ index: Int) -> UInt16? {
            index < text.count && (0x30 ... 0x39).contains(text[index]) ? UInt16(text[index] - 0x30) : nil
        }
        func skipSpaces(_ index: Int) -> Int {
            var index = index
            while index < text.count, isSpace(text[index]) { index += 1 }
            return index
        }
        var result = PerryDecimal()
        var index = skipSpaces(0)
        if index < text.count, text[index] == 0x2b || text[index] == 0x2d {
            result.isNegative = text[index] == 0x2d
            index += 1
        }
        var tooBigToFit = false
        while let value = digit(index) {
            index += 1
            if !tooBigToFit, let product = try? result.multiplyBy10AndAdd(value) {
                result = product
                continue
            }
            tooBigToFit = true
            if result.exponent == Int32(Int8.max) { return (nil, 0) }
            result.exponent += 1
        }
        if !separator.isEmpty, index + separator.count <= text.count, Array(text[index ..< index + separator.count]) == separator {
            index += separator.count
            while let value = digit(index) {
                index += 1
                guard !tooBigToFit else { continue }
                guard let product = try? result.multiplyBy10AndAdd(value) else {
                    tooBigToFit = true
                    continue
                }
                result = product
                if result.exponent == Int32(Int8.min) { return (nil, 0) }
                result.exponent -= 1
            }
        }
        if index < text.count, text[index] == 0x45 || text[index] == 0x65 {
            index += 1
            // Nothing after the "e": what came before.
            guard index < text.count else { return (result, index) }
            var negative = false
            var exponent = 0
            if text[index] == 0x2d || text[index] == 0x2b {
                negative = text[index] == 0x2d
                index += 1
            }
            while let value = digit(index) {
                exponent = 10 * exponent + Int(value)
                if exponent > 2 * Int(Int8.max) { return (nil, 0) }
                index += 1
            }
            if negative { exponent = -exponent }
            exponent += Int(result.exponent)
            if exponent > Int(Int8.max) || exponent < Int(Int8.min) { return (nil, 0) }
            result.exponent = Int32(exponent)
        }
        if matchEntireString {
            index = skipSpaces(index)
            guard index == text.count else { return (nil, 0) }
        }
        if index == 0 { return (nil, 0) }
        result.compact()
        // "-0", which compacting leaves with no digits but its sign.
        if result.isNaN { return (.zero, index) }
        return (result, index)
    }

    // MARK: Arithmetic

    enum Failure: Error {
        case overflow
        case underflow
        case divideByZero

        /// Its NSCalculationError.
        var code: UInt {
            switch self {
            case .underflow: return 2
            case .overflow: return 3
            case .divideByZero: return 4
            }
        }
    }

    /// NSRoundingMode: plain 0, down 1, up 2, bankers 3.
    enum Rounding: UInt {
        case plain, down, up, bankers

        init(mode: UInt) { self = Rounding(rawValue: mode) ?? .plain }
    }

    typealias Words = [UInt16]

    /// The mantissa without its high zero words.
    var words: Words {
        var words = mantissa
        while let last = words.last, last == 0 { words.removeLast() }
        return words
    }

    mutating func setWords(_ source: Words) throws {
        guard source.count <= PerryDecimal.maxSize else { throw Failure.overflow }
        length = UInt32(source.count)
        mantissa = source + Array(repeating: 0, count: PerryDecimal.maxSize - source.count)
    }

    func add(_ other: PerryDecimal, rounding: Rounding) throws -> (result: PerryDecimal, lossOfPrecision: Bool) {
        if isNaN || other.isNaN { throw Failure.overflow }
        if length == 0 { return (other, false) }
        if other.length == 0 { return (self, false) }
        var a = self, b = other
        let lossOfPrecision = try PerryDecimal.normalize(&a, &b, rounding: rounding)
        if a.length == 0 { return (b, lossOfPrecision) }
        if b.length == 0 { return (a, lossOfPrecision) }
        var result = a
        if a.isNegative == b.isNegative {
            var sum = try PerryDecimal.integerAdd(a.words, b.words, maxResultLength: PerryDecimal.maxSize + 1)
            if sum.count > PerryDecimal.maxSize {
                let fitted = try PerryDecimal.fitMantissa(sum)
                sum = fitted.result
                if result.exponent + Int32(fitted.exponent) > Int32(Int8.max) { throw Failure.overflow }
                result.exponent += Int32(fitted.exponent)
            }
            try result.setWords(sum)
        } else {
            switch PerryDecimal.integerCompare(a.words, b.words) {
            case 0:
                return (.zero, lossOfPrecision)
            case -1:
                try result.setWords(PerryDecimal.integerSubtract(b.words, a.words, maxResultLength: PerryDecimal.maxSize))
                result.isNegative = b.isNegative
            default:
                try result.setWords(PerryDecimal.integerSubtract(a.words, b.words, maxResultLength: PerryDecimal.maxSize))
                result.isNegative = a.isNegative
            }
        }
        result.isCompact = false
        result.compact()
        return (result, lossOfPrecision)
    }

    func add(short amount: UInt16) throws -> PerryDecimal {
        var result = self
        var carry = UInt32(amount)
        var index = 0
        while index < Int(result.length) {
            let sum = UInt32(result.mantissa[index]) + carry
            carry = sum >> 16
            result.mantissa[index] = UInt16(sum & 0xffff)
            index += 1
        }
        if carry != 0 {
            if Int(result.length) >= PerryDecimal.maxSize { throw Failure.overflow }
            result.mantissa[index] = UInt16(carry)
            index += 1
        }
        result.length = UInt32(index)
        return result
    }

    func subtract(_ other: PerryDecimal, rounding: Rounding) throws -> (result: PerryDecimal, lossOfPrecision: Bool) {
        var right = other
        if right.length != 0 { right.isNegative.toggle() }
        // Darwin's reports no loss of precision from a subtraction.
        return (try add(right, rounding: rounding).result, false)
    }

    func multiply(byShort multiplicand: UInt16) throws -> PerryDecimal {
        var result = self
        if multiplicand == 0 {
            result.length = 0
            return result
        }
        var carry: UInt32 = 0
        var index = 0
        while index < Int(result.length) {
            let product = UInt32(result.mantissa[index]) * UInt32(multiplicand) + carry
            carry = product >> 16
            result.mantissa[index] = UInt16(product & 0xffff)
            index += 1
        }
        if carry != 0 {
            if Int(result.length) >= PerryDecimal.maxSize { throw Failure.overflow }
            result.mantissa[index] = UInt16(carry)
            index += 1
        }
        result.length = UInt32(index)
        return result
    }

    func multiply(_ other: PerryDecimal, rounding: Rounding) throws -> (result: PerryDecimal, lossOfPrecision: Bool) {
        if isNaN || other.isNaN { throw Failure.overflow }
        if length == 0 || other.length == 0 { return (.zero, false) }
        var big = try PerryDecimal.integerMultiply(words, other.words, maxResultLength: 2 * PerryDecimal.maxSize)
        var result = PerryDecimal()
        result.isNegative = isNegative != other.isNegative
        var exponent = self.exponent + other.exponent
        if big.count > PerryDecimal.maxSize {
            let fitted = try PerryDecimal.fitMantissa(big)
            big = fitted.result
            exponent += Int32(fitted.exponent)
        }
        try result.setWords(big)
        if exponent > Int32(Int8.max) { throw Failure.overflow }
        // Darwin's neither reports the digits it drops nor checks for
        // underflow: the exponent wraps around in its eight bits.
        result.exponent = Int32(Int8(truncatingIfNeeded: exponent))
        result.compact()
        return (result, false)
    }

    func multiply(byPowerOf10 power: Int) throws -> PerryDecimal {
        if isNaN { throw Failure.overflow }
        if length == 0 { return .zero }
        var result = self
        let exponent = Int(result.exponent) + power
        if exponent < Int(Int8.min) { throw Failure.underflow }
        if exponent > Int(Int8.max) { throw Failure.overflow }
        result.exponent = Int32(exponent)
        return result
    }

    func multiplyBy10AndAdd(_ number: UInt16) throws -> PerryDecimal {
        try multiply(byShort: 10).add(short: number)
    }

    func divide(byShort divisor: UInt16) throws -> (result: PerryDecimal, remainder: UInt16) {
        let (quotient, remainder) = try PerryDecimal.integerDivide(words, byShort: UInt32(divisor))
        var result = self
        try result.setWords(quotient)
        return (result, UInt16(remainder))
    }

    func divide(_ divisor: PerryDecimal, rounding: Rounding) throws -> PerryDecimal {
        guard !isNaN, !divisor.isNaN else { throw Failure.overflow }
        guard divisor.length > 0 else { throw Failure.divideByZero }
        if length == 0 { return .zero }
        var a = self, b = divisor
        // Far apart exponents lose most of the quotient's digits: brought
        // together first, unless that leaves one of them zero.
        if 19 <= a.exponent - b.exponent {
            _ = try PerryDecimal.normalize(&a, &b, rounding: rounding)
            if a.length == 0 || b.length == 0 {
                a = self
                b = divisor
            }
        }
        var big = try PerryDecimal.integerMultiply(a.words, byPowerOf10: 38, maxResultLength: 2 * PerryDecimal.maxSize)
        big = try PerryDecimal.integerDivide(big, b.words, maxResultLength: big.count)
        let fitted = try PerryDecimal.fitMantissa(big)
        var result = PerryDecimal()
        try result.setWords(fitted.result)
        result.isNegative = a.isNegative != b.isNegative
        let exponent = Int(a.exponent) - Int(b.exponent) - 38 + fitted.exponent
        if exponent < Int(Int8.min) { throw Failure.underflow }
        if exponent > Int(Int8.max) { throw Failure.overflow }
        result.exponent = Int32(exponent)
        result.compact()
        return result
    }

    func power(_ exponent: Int, rounding: Rounding) throws -> PerryDecimal {
        if isNaN { throw Failure.overflow }
        if exponent == 0 { return PerryDecimal(UInt64(1)) }
        if PerryDecimal.compare(self, .zero) == 0 { return exponent > 0 ? .zero : .nan }
        var power = abs(exponent)
        var result = self
        var temporary = PerryDecimal(UInt64(1))
        while power > 1 {
            if power & 1 == 1 {
                temporary = try temporary.multiply(result, rounding: rounding).result
                power -= 1
            }
            if power != 0 {
                result = try result.multiply(result, rounding: rounding).result
                power /= 2
            }
        }
        result = try temporary.multiply(result, rounding: rounding).result
        if exponent < 0 { result = try PerryDecimal(UInt64(1)).divide(result, rounding: rounding) }
        return result
    }

    /// NSComparisonResult: -1, 0 or 1. Not a number is less than every
    /// number.
    static func compare(_ lhs: PerryDecimal, _ rhs: PerryDecimal) -> Int {
        if lhs.isNaN { return rhs.isNaN ? 0 : -1 }
        if rhs.isNaN { return 1 }
        if lhs.isNegative && !rhs.isNegative { return -1 }
        if !lhs.isNegative && rhs.isNegative { return 1 }
        if lhs.length == 0 { return rhs.length != 0 ? -1 : 0 }
        if rhs.length == 0 { return lhs.length != 0 ? 1 : 0 }
        var a = lhs, b = rhs
        _ = try? normalize(&a, &b, rounding: .down)
        let result = integerCompare(a.words, b.words)
        return a.isNegative ? -result : result
    }

    /// Both at the same exponent: the one with the larger multiplied up as
    /// far as its mantissa allows, the other's divided down to meet it.
    /// Whether digits were lost.
    static func normalize(_ a: inout PerryDecimal, _ b: inout PerryDecimal, rounding: Rounding) throws -> Bool {
        var difference = Int(a.exponent - b.exponent)
        if difference == 0 { return false }
        // `larger` has the larger exponent: its mantissa is multiplied by ten
        // to lower it to the other's, or as far as it goes and the other's
        // divided to meet it.
        func meet(_ larger: inout PerryDecimal, _ smaller: inout PerryDecimal) throws -> Bool {
            if let product = try? integerMultiply(larger.words, byPowerOf10: difference, maxResultLength: maxSize) {
                try larger.setWords(product)
                larger.exponent = smaller.exponent
                larger.isCompact = false
                return false
            }
            let maxPower = integerMaxPowerOf10Multiplier(larger.words, maxResultLength: maxSize)
            let quotient = try integerMultiply(smaller.words, byPowerOf10: maxPower - difference, maxResultLength: maxSize)
            try smaller.setWords(quotient)
            smaller.exponent -= Int32(maxPower - difference)
            smaller.isCompact = false
            if smaller.length != 0 {
                try larger.setWords(integerMultiply(larger.words, byPowerOf10: maxPower, maxResultLength: maxSize))
                larger.exponent -= Int32(maxPower)
                larger.isCompact = false
            } else {
                smaller.exponent = larger.exponent
            }
            return true
        }
        if difference < 0 {
            difference = -difference
            return try meet(&b, &a)
        }
        return try meet(&a, &b)
    }

    /// Trailing zero digits moved into the exponent.
    mutating func compact() {
        if isCompact || isNaN || length == 0 { return }
        var exponent = self.exponent
        var remainder: UInt16 = 0
        repeat {
            guard let step = try? divide(byShort: 10) else { return }
            remainder = step.remainder
            self = step.result
            exponent += 1
        } while remainder == 0 && length > 0
        if length == 0 && remainder == 0 {
            self = PerryDecimal()
            return
        }
        // The last digit divided off, back.
        if let restored = try? multiply(byShort: 10).add(short: remainder) { self = restored }
        exponent -= 1
        while exponent > Int32(Int8.max) {
            if let product = try? multiply(byShort: 10) { self = product }
            exponent -= 1
        }
        self.exponent = exponent
        isCompact = true
    }

    /// Rounded to `scale` digits after the point (NSDecimalNoScale leaves
    /// it), by an NSRoundingMode: plain (halves away from zero), down
    /// (toward negative infinity), up (toward positive infinity), bankers
    /// (halves to even).
    func round(scale: Int, rounding: Rounding) throws -> PerryDecimal {
        var digits = scale + Int(exponent)
        if scale == PerryDecimal.noScale || digits >= 0 { return self }
        digits = -digits
        var exponent = Int(self.exponent) + digits
        var result = self
        var remainder: UInt16 = 0
        var previousRemainder: UInt16 = 0
        while digits > 4 {
            if remainder != 0 { previousRemainder = 1 }
            (result, remainder) = try result.divide(byShort: 10000)
            digits -= 4
        }
        while digits != 0 {
            if remainder != 0 { previousRemainder = 1 }
            (result, remainder) = try result.divide(byShort: 10)
            digits -= 1
        }
        // A tie with more digits after it is past the tie: .50001 is .6.
        if previousRemainder != 0 && (remainder == 0 || remainder == 5) { remainder += 1 }
        if remainder != 0 {
            var up: Bool
            switch rounding {
            case .down: up = isNegative
            case .up: up = !isNegative
            case .plain: up = remainder >= 5
            case .bankers: up = remainder > 5 || (remainder == 5 && result.mantissa[0] & 1 == 1)
            }
            if up { result = try result.add(short: 1) }
            if result.length == 0 { result.isNegative = false }
        }
        result.isCompact = false
        while exponent > Int(Int8.max) {
            exponent -= 1
            result = try result.multiply(byShort: 10)
        }
        result.exponent = Int32(exponent)
        result.compact()
        return result
    }

    // MARK: Integers of 16-bit words, least first

    private static let powersOf10: [Words] = {
        var powers: [Words] = [[1]]
        for _ in 1 ... 38 {
            var carry: UInt32 = 0
            var next: Words = []
            for word in powers.last! {
                let product = UInt32(word) * 10 + carry
                next.append(UInt16(product & 0xffff))
                carry = product >> 16
            }
            if carry != 0 { next.append(UInt16(carry)) }
            powers.append(next)
        }
        return powers
    }()

    static func integerAdd(_ lhs: Words, _ rhs: Words, maxResultLength: Int) throws -> Words {
        var result: Words = []
        var carry: UInt32 = 0
        for index in 0 ..< max(lhs.count, rhs.count) {
            let sum = UInt32(index < lhs.count ? lhs[index] : 0) + UInt32(index < rhs.count ? rhs[index] : 0) + carry
            carry = sum >> 16
            result.append(UInt16(sum & 0xffff))
        }
        if carry != 0 {
            if result.count >= maxResultLength { throw Failure.overflow }
            result.append(UInt16(carry))
        }
        return result
    }

    static func integerSubtract(_ term: Words, _ subtrahend: Words, maxResultLength: Int) throws -> Words {
        var result: Words = []
        var borrow: Int32 = 0
        for index in 0 ..< max(term.count, subtrahend.count) {
            var difference = Int32(index < term.count ? term[index] : 0) - Int32(index < subtrahend.count ? subtrahend[index] : 0) - borrow
            borrow = difference < 0 ? 1 : 0
            if difference < 0 { difference += 0x10000 }
            result.append(UInt16(difference))
        }
        if borrow != 0 { throw Failure.overflow }
        while let last = result.last, last == 0 { result.removeLast() }
        return result
    }

    static func integerDivide(_ dividend: Words, byShort divisor: UInt32) throws -> (quotient: Words, remainder: UInt32) {
        if divisor == 0 { throw Failure.divideByZero }
        var carry: UInt32 = 0
        var result = Words(repeating: 0, count: dividend.count)
        for index in (0 ..< dividend.count).reversed() {
            let value = UInt32(dividend[index]) + carry << 16
            result[index] = UInt16(value / divisor)
            carry = value % divisor
        }
        while let last = result.last, last == 0 { result.removeLast() }
        return (result, carry)
    }

    /// Long division (Knuth's algorithm D).
    static func integerDivide(_ dividend: Words, _ divisor: Words, maxResultLength: Int) throws -> Words {
        if divisor.isEmpty { throw Failure.divideByZero }
        if integerCompare(dividend, divisor) < 0 { return [] }
        if divisor.count == 1 { return try integerDivide(dividend, byShort: UInt32(divisor[0])).quotient }
        let d: UInt32 = (1 << 16) / (UInt32(divisor[divisor.count - 1]) + 1)
        var u = try integerMultiply(dividend, byShort: d, maxResultLength: dividend.count + 1)
        var v = try integerMultiply(divisor, byShort: d, maxResultLength: divisor.count + 1)
        if u.count == dividend.count { u.append(0) }
        let uLength = u.count
        let vLength = v.count
        v.append(0)
        let quotientLength = uLength - vLength
        let v1 = UInt32(v[vLength - 1])
        let v2: UInt32 = vLength > 1 ? UInt32(v[vLength - 2]) : 0
        var result = Words(repeating: 0, count: max(maxResultLength, quotientLength))
        for j in 0 ..< quotientLength {
            let top = (UInt32(u[uLength - j - 1]) << 16) + UInt32(u[uLength - j - 2])
            var rhat = top % v1
            var q = top / v1
            let next = uLength - j - 3 >= 0 ? UInt64(u[uLength - j - 3]) : 0
            if q == 1 << 16 || UInt64(v2) * UInt64(q) > (UInt64(rhat) << 16) + next {
                q -= 1
                rhat += v1
                if rhat < 1 << 16, q == 1 << 16 || UInt64(v2) * UInt64(q) > (UInt64(rhat) << 16) + next {
                    q -= 1
                }
            }
            var multiplyCarry: UInt64 = 0
            var borrow: Int64 = 0
            for i in 0 ..< vLength + 1 {
                let product = UInt64(q) * UInt64(v[i]) + multiplyCarry
                multiplyCarry = product >> 16
                let position = uLength - vLength + i - j - 1
                var difference = Int64(u[position]) - Int64(product & 0xffff) - borrow
                borrow = difference < 0 ? 1 : 0
                if difference < 0 { difference += 0x10000 }
                u[position] = UInt16(difference)
            }
            if borrow != 0 {
                q -= 1
                var carry: UInt32 = 0
                for i in 0 ..< vLength {
                    let position = uLength - vLength + i - j - 1
                    let sum = UInt32(v[i]) + UInt32(u[position]) + carry
                    carry = sum >> 16
                    u[position] = UInt16(sum & 0xffff)
                }
            }
            result[quotientLength - j - 1] = UInt16(q)
        }
        while let last = result.last, last == 0 { result.removeLast() }
        return result
    }

    static func integerMultiply(_ lhs: Words, _ rhs: Words, maxResultLength: Int) throws -> Words {
        if lhs.isEmpty || rhs.isEmpty { return [] }
        let resultLength = min(maxResultLength, lhs.count + rhs.count)
        var result = Words(repeating: 0, count: resultLength)
        for j in 0 ..< rhs.count {
            var carry: UInt32 = 0
            for i in 0 ..< lhs.count {
                if i + j < resultLength {
                    let product = carry + UInt32(result[i + j]) + UInt32(rhs[j]) * UInt32(lhs[i])
                    carry = product >> 16
                    result[i + j] = UInt16(truncatingIfNeeded: product)
                } else if carry != 0 || (rhs[j] > 0 && lhs[i] > 0) {
                    throw Failure.overflow
                }
            }
            if carry != 0 {
                if lhs.count + j < resultLength {
                    result[lhs.count + j] = UInt16(carry)
                } else {
                    throw Failure.overflow
                }
            }
        }
        while let last = result.last, last == 0 { result.removeLast() }
        return result
    }

    static func integerMultiply(_ lhs: Words, byShort multiplicand: UInt32, maxResultLength: Int) throws -> Words {
        if multiplicand == 0 { return [] }
        if maxResultLength < lhs.count { throw Failure.overflow }
        var result = Words(repeating: 0, count: lhs.count)
        var carry: UInt32 = 0
        for index in 0 ..< lhs.count {
            let product = UInt32(lhs[index]) * multiplicand + carry
            carry = product >> 16
            result[index] = UInt16(product & 0xffff)
        }
        if carry != 0 {
            if maxResultLength == lhs.count { throw Failure.overflow }
            result.append(UInt16(carry))
        }
        return result
    }

    /// Times ten to `power`, or divided by ten to minus it.
    static func integerMultiply(_ lhs: Words, byPowerOf10 power: Int, maxResultLength: Int) throws -> Words {
        if power == 0 { return lhs }
        var result = lhs
        var remaining = abs(power)
        let largest = powersOf10.count - 1
        func apply(_ factor: Words) throws {
            result = power > 0
                ? try integerMultiply(result, factor, maxResultLength: maxResultLength)
                : try integerDivide(result, factor, maxResultLength: maxResultLength)
        }
        while remaining > largest {
            remaining -= largest
            try apply(powersOf10[largest])
        }
        try apply(powersOf10[remaining])
        return result
    }

    /// How many decimal digits a number of `number`'s words can grow by in
    /// `maxResultLength` words: 4.8 a word.
    static func integerMaxPowerOf10Multiplier(_ number: Words, maxResultLength: Int) -> Int {
        Int(Double(maxResultLength - number.count) * 4.81647993)
    }

    static func integerCompare(_ lhs: Words, _ rhs: Words) -> Int {
        if lhs.count != rhs.count { return lhs.count > rhs.count ? 1 : -1 }
        for index in (0 ..< lhs.count).reversed() where lhs[index] != rhs[index] {
            return lhs[index] > rhs[index] ? 1 : -1
        }
        return 0
    }

    /// A mantissa of more than eight words divided by ten until it fits:
    /// the words, the power of ten divided by, and whether digits were
    /// lost. Darwin's works out the rounding but keeps the digits as
    /// divided, and so does this.
    static func fitMantissa(_ value: Words) throws -> (result: Words, exponent: Int, lossOfPrecision: Bool) {
        if value.count <= maxSize { return (value, 0, false) }
        var result = value
        var lost = false
        var remainder: UInt32 = 0
        var exponent = 0
        while result.count > maxSize + 1 {
            (result, remainder) = try integerDivide(result, byShort: 10000)
            lost = lost || remainder != 0
            exponent += 4
        }
        while result.count > maxSize {
            (result, remainder) = try integerDivide(result, byShort: 10)
            lost = lost || remainder != 0
            exponent += 1
        }
        return (result, exponent, lost)
    }
}

// MARK: - Foundation's C functions

// Each takes its NSDecimals by pointer. A failed operation leaves not a
// number in `result` and returns its NSCalculationError: lost precision 1,
// underflow 2, overflow 3, division by zero 4.

private func calculate(_ result: UnsafeMutableRawPointer?,
                       _ operation: () throws -> (result: PerryDecimal, lossOfPrecision: Bool)) -> UInt {
    do {
        let (value, lossOfPrecision) = try operation()
        if let result { value.store(to: result) }
        return lossOfPrecision ? 1 : 0
    } catch {
        if let result { PerryDecimal.nan.store(to: result) }
        return (error as? PerryDecimal.Failure)?.code ?? 3
    }
}

private func decimal(_ pointer: UnsafeRawPointer?) -> PerryDecimal {
    pointer.map { PerryDecimal(bytes: $0) } ?? .nan
}

@c(_NSDecimalAdd)
public func perryDecimalAdd(_ result: UnsafeMutableRawPointer?, _ left: UnsafeRawPointer?, _ right: UnsafeRawPointer?,
                            _ mode: UInt) -> UInt {
    calculate(result) { try decimal(left).add(decimal(right), rounding: .init(mode: mode)) }
}

/// No loss of precision reported, as Darwin's.
@c(_NSDecimalSubtract)
public func perryDecimalSubtract(_ result: UnsafeMutableRawPointer?, _ left: UnsafeRawPointer?, _ right: UnsafeRawPointer?,
                                 _ mode: UInt) -> UInt {
    calculate(result) { try decimal(left).subtract(decimal(right), rounding: .init(mode: mode)) }
}

/// A product of more than 38 digits keeps its leading ones, truncated,
/// with no loss of precision reported, and an exponent below -128 wraps,
/// as Darwin's.
@c(_NSDecimalMultiply)
public func perryDecimalMultiply(_ result: UnsafeMutableRawPointer?, _ left: UnsafeRawPointer?, _ right: UnsafeRawPointer?,
                                 _ mode: UInt) -> UInt {
    calculate(result) { try decimal(left).multiply(decimal(right), rounding: .init(mode: mode)) }
}

@c(_NSDecimalDivide)
public func perryDecimalDivide(_ result: UnsafeMutableRawPointer?, _ left: UnsafeRawPointer?, _ right: UnsafeRawPointer?,
                               _ mode: UInt) -> UInt {
    calculate(result) { (try decimal(left).divide(decimal(right), rounding: .init(mode: mode)), false) }
}

/// The power, an NSUInteger; zero to the zeroth is one.
@c(_NSDecimalPower)
public func perryDecimalPower(_ result: UnsafeMutableRawPointer?, _ number: UnsafeRawPointer?, _ power: UInt, _ mode: UInt) -> UInt {
    calculate(result) { (try decimal(number).power(Int(bitPattern: power), rounding: .init(mode: mode)), false) }
}

/// The exponent moved: underflow below -128, overflow above 127.
@c(_NSDecimalMultiplyByPowerOf10)
public func perryDecimalMultiplyByPowerOf10(_ result: UnsafeMutableRawPointer?, _ number: UnsafeRawPointer?, _ power: Int16,
                                            _ mode: UInt) -> UInt {
    calculate(result) { (try decimal(number).multiply(byPowerOf10: Int(power)), false) }
}

/// NSOrderedAscending -1, NSOrderedSame 0, NSOrderedDescending 1.
@c(_NSDecimalCompare)
public func perryDecimalCompare(_ left: UnsafeRawPointer?, _ right: UnsafeRawPointer?) -> Int {
    PerryDecimal.compare(decimal(left), decimal(right))
}

/// The number rounded to `scale` places after the point (NSDecimalNoScale
/// leaves it), by an NSRoundingMode: plain 0 (halves away from zero),
/// down 1 (toward negative infinity), up 2 (toward positive infinity),
/// bankers 3 (halves to even). `result` may be `number`; one that cannot
/// be rounded leaves `result` as it was.
@c(_NSDecimalRound)
public func perryDecimalRound(_ result: UnsafeMutableRawPointer?, _ number: UnsafeRawPointer?, _ scale: Int, _ mode: UInt) {
    guard let result, let number else { return }
    guard let rounded = try? PerryDecimal(bytes: number).round(scale: scale, rounding: .init(mode: mode)) else { return }
    rounded.store(to: result)
}

/// Both brought to the same exponent, the larger one's digits multiplied
/// up and, where they would not fit, the smaller one's divided down:
/// NSCalculationLossOfPrecision then. Left as they were on an error.
@c(_NSDecimalNormalize)
public func perryDecimalNormalize(_ first: UnsafeMutableRawPointer?, _ second: UnsafeMutableRawPointer?, _ mode: UInt) -> UInt {
    guard let first, let second else { return 0 }
    var a = PerryDecimal(bytes: first), b = PerryDecimal(bytes: second)
    do {
        let lost = try PerryDecimal.normalize(&a, &b, rounding: .init(mode: mode))
        a.store(to: first)
        b.store(to: second)
        return lost ? 1 : 0
    } catch {
        return (error as? PerryDecimal.Failure)?.code ?? 3
    }
}

/// Trailing zeros moved into the exponent, in place.
@c(_NSDecimalCompact)
public func perryDecimalCompact(_ number: UnsafeMutableRawPointer?) {
    guard let number else { return }
    var value = PerryDecimal(bytes: number)
    value.compact()
    value.store(to: number)
}

@c(_NSDecimalCopy)
public func perryDecimalCopy(_ destination: UnsafeMutableRawPointer?, _ source: UnsafeRawPointer?) {
    guard let destination, let source else { return }
    destination.copyMemory(from: source, byteCount: PerryDecimal.byteCount)
}

/// The digits, as an autoreleased string: "NaN", "0", "-12.34", never an
/// exponent. The locale, an NSLocale or a dictionary, gives the decimal
/// separator; nil is ".".
@c(_NSDecimalString)
public func perryDecimalString(_ number: UnsafeRawPointer?, _ locale: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    Strings.autoreleased(decimal(number).string(separator: DecimalNumbers.separator(locale)))
}
