// Symmetric keys, CryptoKit's errors, and the Secure Enclave, which there
// isn't one of.

public import Foundation
import Security

/// General cryptography errors used by CryptoKit.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public enum CryptoKitError: Error {
    case incorrectKeySize
    case incorrectParameterSize
    case authenticationFailure
    case underlyingCoreCryptoError(error: Int32)
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *)
    case wrapFailure
    @available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, macCatalyst 15.0, *)
    case unwrapFailure
    @available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, macCatalyst 16.0, *)
    case invalidParameter
}

@available(iOS 17.4, macOS 14.4, watchOS 10.4, tvOS 17.4, macCatalyst 17.4, *)
extension CryptoKitError: Equatable, Hashable {}

/// The sizes that a symmetric cryptographic key can take.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public struct SymmetricKeySize: Sendable {
    public let bitCount: Int

    public static var bits128: SymmetricKeySize { SymmetricKeySize(bitCount: 128) }
    public static var bits192: SymmetricKeySize { SymmetricKeySize(bitCount: 192) }
    public static var bits256: SymmetricKeySize { SymmetricKeySize(bitCount: 256) }

    public init(bitCount: Int) {
        precondition(bitCount > 0 && bitCount % 8 == 0)
        self.bitCount = bitCount
    }
}

/// A symmetric cryptographic key: its bytes.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public struct SymmetricKey: ContiguousBytes, Sendable {
    let bytes: [UInt8]

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }

    public init<D>(data: D) where D: ContiguousBytes {
        bytes = data.withUnsafeBytes { Array($0) }
    }

    /// A key of random bytes.
    public init(size: SymmetricKeySize) {
        var bytes = [UInt8](repeating: 0, count: size.bitCount / 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        self.bytes = bytes
    }

    public var bitCount: Int { bytes.count * 8 }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension SymmetricKey: Equatable {
    public static func == (lhs: SymmetricKey, rhs: SymmetricKey) -> Bool {
        lhs.bytes.count == rhs.bytes.count && zip(lhs.bytes, rhs.bytes).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

/// A representation of a device's hardware-based key manager: there is
/// none.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public enum SecureEnclave: Sendable {}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension SecureEnclave {
    public static var isAvailable: Bool { false }
}
