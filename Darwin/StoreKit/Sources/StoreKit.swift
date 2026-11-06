// StoreKit 2's Swift API, as far as apps check what has been bought and
// offer more: there is no App Store here, so nothing has been bought, no
// product is for sale, and a purchase ends as cancelled. The declarations
// follow the iOS SDK's StoreKit interface (frozen types and their cases),
// so apps built against Apple's bind to them by the same symbols.

public import Foundation

// MARK: - Verification

@available(iOS 15.0, *)
@frozen public enum VerificationResult<SignedType> {
    case unverified(SignedType, VerificationResult<SignedType>.VerificationError)
    case verified(SignedType)

    public var payloadValue: SignedType {
        get throws {
            switch self {
            case let .verified(value): return value
            case let .unverified(_, error): throw error
            }
        }
    }

    public var unsafePayloadValue: SignedType {
        switch self {
        case let .verified(value), let .unverified(value, _): return value
        }
    }
}

@available(iOS 15.0, *)
extension VerificationResult {
    public enum VerificationError: Error {
        case revokedCertificate
        case invalidCertificateChain
        case invalidDeviceVerification
        case invalidEncoding
        case invalidSignature
        case missingRequiredProperties
    }
}

@available(iOS 15.0, *)
extension VerificationResult: Sendable where SignedType: Sendable {}

// MARK: - Transaction

/// A purchase. None have been made here.
@available(iOS 15.0, *)
public struct Transaction: Identifiable, Sendable {
    public let id: UInt64
    public let originalID: UInt64
    public let productID: String
    public let purchaseDate: Date
    public let revocationDate: Date?
    public let expirationDate: Date?

    /// Tells the App Store the transaction's content was delivered.
    public func finish() async {}
}

@available(iOS 15.0, *)
extension Transaction {
    /// Transactions as they come: none, here.
    public struct Transactions: AsyncSequence, Sendable {
        public typealias Element = VerificationResult<Transaction>

        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async -> VerificationResult<Transaction>? { nil }
        }

        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }

    public static var all: Transactions { Transactions() }
    public static var currentEntitlements: Transactions { Transactions() }
    public static var unfinished: Transactions { Transactions() }
    public static var updates: Transactions { Transactions() }

    public static func latest(for productID: String) async -> VerificationResult<Transaction>? { nil }
    public static func currentEntitlement(for productID: String) async -> VerificationResult<Transaction>? { nil }
}

// MARK: - Product

/// Something for sale on the App Store. None is offered here.
@available(iOS 15.0, *)
public struct Product: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let displayPrice: String
    public let price: Decimal

    /// The products with these identifiers that are for sale: none.
    public static func products<Identifiers>(for identifiers: Identifiers) async throws -> [Product]
    where Identifiers: Collection, Identifiers.Element == String {
        []
    }

    /// Buys the product: with no App Store, the user is taken to have
    /// cancelled.
    @MainActor
    public func purchase(options: Set<PurchaseOption> = []) async throws -> PurchaseResult {
        .userCancelled
    }
}

@available(iOS 15.0, *)
extension Product {
    public struct PurchaseOption: Equatable, Hashable, Sendable {
        let key: String

        public static func appAccountToken(_ token: UUID) -> PurchaseOption { PurchaseOption(key: "appAccountToken") }
        public static func quantity(_ quantity: Int) -> PurchaseOption { PurchaseOption(key: "quantity") }
    }

    public enum PurchaseResult: Sendable {
        case success(VerificationResult<Transaction>)
        case userCancelled
        case pending
    }

    public enum PurchaseError: Error {
        case invalidQuantity
        case productUnavailable
        case purchaseNotAllowed
        case ineligibleForOffer
        case invalidOfferIdentifier
        case invalidOfferPrice
        case invalidOfferSignature
        case missingOfferParameters
    }
}

// MARK: - AppStore

@available(iOS 15.0, *)
public enum AppStore {
    /// Whether the user may pay: there is no App Store to pay.
    public static var canMakePayments: Bool { false }

    public static var deviceVerificationID: UUID? { nil }

    /// Brings the transactions up to date with the App Store: there are none.
    public static func sync() async throws {}
}
