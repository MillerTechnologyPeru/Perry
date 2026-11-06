// CryptoKit's hash functions and digests, over CommonCrypto's, which
// Perry's libSystem provides. A hash function is a value: copying it copies
// its state, so its CommonCrypto context is kept in the value's own bytes.

public import Foundation
import CommonCrypto

// MARK: - Digest and HashFunction

/// A type that represents the output of a hash.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
@preconcurrency
public protocol Digest: ContiguousBytes, CustomStringConvertible, Hashable, Sendable, Sequence where Element == UInt8 {
    static var byteCount: Int { get }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension Digest {
    public func makeIterator() -> Array<UInt8>.Iterator {
        withUnsafeBytes { Array($0) }.makeIterator()
    }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension Digest {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.withUnsafeBytes { a in rhs.withUnsafeBytes { b in a.elementsEqual(b) } }
    }

    public static func == <D>(lhs: Self, rhs: D) -> Bool where D: DataProtocol {
        lhs.withUnsafeBytes { a in a.count == rhs.count && a.elementsEqual(rhs) }
    }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension Digest {
    public var description: String {
        "\(Self.self): " + withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
    }
}

/// A type that performs cryptographically secure hashing.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
@preconcurrency
public protocol HashFunction: Sendable {
    @available(iOS 13.2, macOS 10.15, watchOS 6.1, tvOS 13.2, macCatalyst 13.2, *)
    static var blockByteCount: Int { get }
    associatedtype Digest: CryptoKit.Digest
    init()
    mutating func update(bufferPointer: UnsafeRawBufferPointer)
    func finalize() -> Self.Digest
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension HashFunction {
    @inlinable
    internal static func hash(bufferPointer: UnsafeRawBufferPointer) -> Self.Digest {
        var hasher = Self()
        hasher.update(bufferPointer: bufferPointer)
        return hasher.finalize()
    }

    @inlinable
    public static func hash<D>(data: D) -> Self.Digest where D: DataProtocol {
        var hasher = Self()
        hasher.update(data: data)
        return hasher.finalize()
    }

    @inlinable
    public mutating func update<D>(data: D) where D: DataProtocol {
        data.regions.forEach { region in
            region.withUnsafeBytes { self.update(bufferPointer: $0) }
        }
    }
}

// MARK: - Digest storage

/// A digest's bytes, compared and hashed by content.
@usableFromInline
struct DigestBytes: Hashable, Sendable {
    let bytes: [UInt8]
}

// MARK: - SHA-2

/// The SHA-256 hash function.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public struct SHA256: HashFunction, Sendable {
    @available(iOS 13.2, macOS 10.15, watchOS 6.1, tvOS 13.2, macCatalyst 13.2, *)
    public static let blockByteCount = 64
    public static let byteCount = 32
    public typealias Digest = SHA256Digest

    private var context = CC_SHA256_CTX()

    public init() {
        CC_SHA256_Init(&context)
    }

    public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
        CC_SHA256_Update(&context, bufferPointer.baseAddress, CC_LONG(bufferPointer.count))
    }

    public func finalize() -> SHA256Digest {
        var copy = context
        var bytes = [UInt8](repeating: 0, count: Self.byteCount)
        CC_SHA256_Final(&bytes, &copy)
        return SHA256Digest(storage: DigestBytes(bytes: bytes))
    }
}

/// The SHA-384 hash function.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public struct SHA384: HashFunction, Sendable {
    @available(iOS 13.2, macOS 10.15, watchOS 6.1, tvOS 13.2, macCatalyst 13.2, *)
    public static let blockByteCount = 128
    public static let byteCount = 48
    public typealias Digest = SHA384Digest

    private var context = CC_SHA512_CTX()

    public init() {
        CC_SHA384_Init(&context)
    }

    public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
        CC_SHA384_Update(&context, bufferPointer.baseAddress, CC_LONG(bufferPointer.count))
    }

    public func finalize() -> SHA384Digest {
        var copy = context
        var bytes = [UInt8](repeating: 0, count: Self.byteCount)
        CC_SHA384_Final(&bytes, &copy)
        return SHA384Digest(storage: DigestBytes(bytes: bytes))
    }
}

/// The SHA-512 hash function.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public struct SHA512: HashFunction, Sendable {
    @available(iOS 13.2, macOS 10.15, watchOS 6.1, tvOS 13.2, macCatalyst 13.2, *)
    public static let blockByteCount = 128
    public static let byteCount = 64
    public typealias Digest = SHA512Digest

    private var context = CC_SHA512_CTX()

    public init() {
        CC_SHA512_Init(&context)
    }

    public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
        CC_SHA512_Update(&context, bufferPointer.baseAddress, CC_LONG(bufferPointer.count))
    }

    public func finalize() -> SHA512Digest {
        var copy = context
        var bytes = [UInt8](repeating: 0, count: Self.byteCount)
        CC_SHA512_Final(&bytes, &copy)
        return SHA512Digest(storage: DigestBytes(bytes: bytes))
    }
}

/// The output of a SHA-256 hash.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public struct SHA256Digest {
    let storage: DigestBytes

    public static var byteCount: Int { SHA256.byteCount }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try storage.bytes.withUnsafeBytes(body)
    }

    public var description: String {
        "SHA256 digest: " + storage.bytes.map { String(format: "%02x", $0) }.joined()
    }

    public func hash(into hasher: inout Hasher) {
        storage.hash(into: &hasher)
    }

    public typealias Element = UInt8
    public typealias Iterator = Array<UInt8>.Iterator
}

/// The output of a SHA-384 hash.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public struct SHA384Digest {
    let storage: DigestBytes

    public static var byteCount: Int { SHA384.byteCount }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try storage.bytes.withUnsafeBytes(body)
    }

    public var description: String {
        "SHA384 digest: " + storage.bytes.map { String(format: "%02x", $0) }.joined()
    }

    public func hash(into hasher: inout Hasher) {
        storage.hash(into: &hasher)
    }

    public typealias Element = UInt8
}

/// The output of a SHA-512 hash.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public struct SHA512Digest {
    let storage: DigestBytes

    public static var byteCount: Int { SHA512.byteCount }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try storage.bytes.withUnsafeBytes(body)
    }

    public var description: String {
        "SHA512 digest: " + storage.bytes.map { String(format: "%02x", $0) }.joined()
    }

    public func hash(into hasher: inout Hasher) {
        storage.hash(into: &hasher)
    }

    public typealias Element = UInt8
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension SHA256Digest: Digest {}
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension SHA384Digest: Digest {}
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension SHA512Digest: Digest {}

// MARK: - Insecure

/// Hash functions kept for older protocols, not for security.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public enum Insecure: Sendable {
    /// The SHA-1 hash function.
    public struct SHA1: HashFunction, Sendable {
        @available(iOS 13.2, macOS 10.15, watchOS 6.1, tvOS 13.2, macCatalyst 13.2, *)
        public static let blockByteCount = 64
        public static let byteCount = 20
        public typealias Digest = SHA1Digest

        private var context = CC_SHA1_CTX()

        public init() {
            CC_SHA1_Init(&context)
        }

        public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
            CC_SHA1_Update(&context, bufferPointer.baseAddress, CC_LONG(bufferPointer.count))
        }

        public func finalize() -> SHA1Digest {
            var copy = context
            var bytes = [UInt8](repeating: 0, count: Self.byteCount)
            CC_SHA1_Final(&bytes, &copy)
            return SHA1Digest(storage: DigestBytes(bytes: bytes))
        }
    }

    /// The MD5 hash function.
    public struct MD5: HashFunction, Sendable {
        @available(iOS 13.2, macOS 10.15, watchOS 6.1, tvOS 13.2, macCatalyst 13.2, *)
        public static let blockByteCount = 64
        public static let byteCount = 16
        public typealias Digest = MD5Digest

        private var context = CC_MD5_CTX()

        public init() {
            CC_MD5_Init(&context)
        }

        public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
            CC_MD5_Update(&context, bufferPointer.baseAddress, CC_LONG(bufferPointer.count))
        }

        public func finalize() -> MD5Digest {
            var copy = context
            var bytes = [UInt8](repeating: 0, count: Self.byteCount)
            CC_MD5_Final(&bytes, &copy)
            return MD5Digest(storage: DigestBytes(bytes: bytes))
        }
    }

    /// The output of a SHA-1 hash.
    public struct SHA1Digest {
        let storage: DigestBytes

        public static var byteCount: Int { SHA1.byteCount }

        public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
            try storage.bytes.withUnsafeBytes(body)
        }

        public var description: String {
            "SHA1 digest: " + storage.bytes.map { String(format: "%02x", $0) }.joined()
        }

        public func hash(into hasher: inout Hasher) {
            storage.hash(into: &hasher)
        }

        public typealias Element = UInt8
    }

    /// The output of an MD5 hash.
    public struct MD5Digest {
        let storage: DigestBytes

        public static var byteCount: Int { MD5.byteCount }

        public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
            try storage.bytes.withUnsafeBytes(body)
        }

        public var description: String {
            "MD5 digest: " + storage.bytes.map { String(format: "%02x", $0) }.joined()
        }

        public func hash(into hasher: inout Hasher) {
            storage.hash(into: &hasher)
        }

        public typealias Element = UInt8
    }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension Insecure.SHA1Digest: Digest {}
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension Insecure.MD5Digest: Digest {}
