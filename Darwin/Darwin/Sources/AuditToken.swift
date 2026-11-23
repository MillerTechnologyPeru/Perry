import Darwin.Mach.message

// audit_token_t as a Swift value: its eight words compared, hashed and
// coded in order, and the two tokens <mach/message.h> defines as macros.

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension audit_token_t: Codable, Equatable, Hashable {
    /// The words of `val`, first to last.
    private var words: [UInt32] {
        withUnsafeBytes(of: val) { Array($0.bindMemory(to: UInt32.self)) }
    }

    private init(words: [UInt32]) {
        var token = audit_token_t()
        withUnsafeMutableBytes(of: &token.val) { buffer in
            let slots = buffer.bindMemory(to: UInt32.self)
            for (index, word) in words.prefix(slots.count).enumerated() { slots[index] = word }
        }
        self = token
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for word in words { try container.encode(word) }
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var words: [UInt32] = []
        for _ in 0..<8 { words.append(try container.decode(UInt32.self)) }
        self.init(words: words)
    }

    public static func == (lhs: audit_token_t, rhs: audit_token_t) -> Bool {
        lhs.words == rhs.words
    }

    public func hash(into hasher: inout Hasher) {
        for word in words { hasher.combine(word) }
    }
}

/// INVALID_AUDIT_TOKEN_VALUE: every word UINT_MAX.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public var INVALID_AUDIT_TOKEN_VALUE: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32) {
    (.max, .max, .max, .max, .max, .max, .max, .max)
}

/// KERNEL_AUDIT_TOKEN_VALUE: every word zero.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public var KERNEL_AUDIT_TOKEN_VALUE: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32) {
    (0, 0, 0, 0, 0, 0, 0, 0)
}
