// StoreKit 2's Swift API, as far as apps check what has been bought and
// offer more: there is no App Store here, so nothing has been bought, no
// product is for sale, and a purchase ends as cancelled. The declarations
// follow the iOS SDK's StoreKit interface (frozen types and their cases),
// so apps built against Apple's bind to them by the same symbols.

public import Foundation
import UIKit

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

// MARK: - Errors

public struct InvalidRequestError: Error {
    public let code: Int64
    public let message: String
}

public enum StoreKitError: Error {
    case unknown
    case userCancelled
    case networkError(URLError)
    case systemError(any Error)
    case notAvailableInStorefront
    case notEntitled
    case unsupported
    case invalidPresentationContext
}

extension StoreKitError: Sendable {}

extension StoreKitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknown: return "An unknown error occurred."
        case .userCancelled: return "The user cancelled the request."
        case .networkError: return "A network error occurred."
        case .systemError: return "A system error occurred."
        case .notAvailableInStorefront: return "The item is not available in the storefront."
        case .notEntitled: return "The user is not entitled to the item."
        case .unsupported: return "The request is not supported."
        case .invalidPresentationContext: return "The presentation context is not valid."
        }
    }

    public var failureReason: String? { errorDescription }
    public var recoverySuggestion: String? { nil }
}

// MARK: - Storefront

/// The App Store's storefront: none is known, as there is no App Store.
public struct Storefront: Identifiable, Sendable {
    public let countryCode: String
    public let id: String

    public static var current: Storefront? {
        get async { nil }
    }

    public typealias ID = String
}

extension Storefront {
    public struct Storefronts: AsyncSequence, Sendable {
        public typealias Element = Storefront

        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async -> Storefront? { nil }
            public typealias Element = Storefront
        }

        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }

    public static var updates: Storefronts { Storefronts() }
}

// MARK: - Subscriptions and representations

@available(iOS 15.0, *)
extension Transaction {
    public var jsonRepresentation: Data { Data() }
}

@available(iOS 15.0, *)
extension VerificationResult where SignedType == Transaction {
    public var jwsRepresentation: String { "" }
}

@available(iOS 15.0, *)
extension Product.PurchaseOption {
    public static func custom(key: String, value: Data) -> Product.PurchaseOption { Product.PurchaseOption(key: key) }
}

@available(iOS 15.0, *)
extension Product {
    /// What a subscription renews to: no subscription is held, so no
    /// renewal is known.
    public struct SubscriptionInfo {
        public let subscriptionGroupID: String

        public struct RenewalInfo {
            public var currentProductID: String { "" }
            public var jsonRepresentation: Data { Data() }
        }

        public struct Status {
            public let transaction: VerificationResult<Transaction>
            public let renewalInfo: VerificationResult<RenewalInfo>

            /// The changes to subscriptions' statuses: none.
            public struct Statuses: AsyncSequence {
                public typealias Element = Status

                public struct AsyncIterator: AsyncIteratorProtocol {
                    public mutating func next() async -> Status? { nil }
                    public typealias Element = Status
                }

                public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
            }

            public static var updates: Statuses { Statuses() }
        }
    }
}

@available(iOS 15.0, *)
extension AppStore {
    /// Asks for a review: there is no App Store to review in.
    @MainActor public static func requestReview(in scene: UIWindowScene) {}
}

// MARK: - The app's own transaction

@available(iOS 16.0, *)
extension AppStore {
    /// Where the app was bought: nowhere here, so production.
    public struct Environment: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let production = Environment(rawValue: "Production")
        public static let sandbox = Environment(rawValue: "Sandbox")
        public static let xcode = Environment(rawValue: "Xcode")
    }
}

@available(iOS 16.0, *)
extension Transaction {
    public var environment: AppStore.Environment { .production }
}

/// The record of the app's purchase. There is no App Store here to sign
/// one, so asking for it fails, as it does with no network.
@available(iOS 16.0, *)
public struct AppTransaction: Sendable {
    public var jsonRepresentation: Data { Data() }
    public let appID: UInt64?
    public let appVersion: String
    public let appVersionID: UInt64?
    public let bundleID: String
    public let environment: AppStore.Environment
    public let originalAppVersion: String
    public let originalPurchaseDate: Date
    public let preorderDate: Date?
    public let deviceVerification: Data
    public let deviceVerificationNonce: UUID
    public let signedDate: Date

    public static var shared: VerificationResult<AppTransaction> {
        get async throws { throw StoreKitError.notAvailableInStorefront }
    }

    public static func refresh() async throws -> VerificationResult<AppTransaction> {
        throw StoreKitError.notAvailableInStorefront
    }
}

@available(iOS 16.0, *)
extension AppTransaction: Equatable {
    public static func == (lhs: AppTransaction, rhs: AppTransaction) -> Bool {
        lhs.bundleID == rhs.bundleID && lhs.appVersion == rhs.appVersion && lhs.signedDate == rhs.signedDate
    }
}

@available(iOS 16.0, *)
extension AppTransaction: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
        hasher.combine(appVersion)
        hasher.combine(signedDate)
    }
}

@available(iOS 16.0, *)
extension AppTransaction: CustomDebugStringConvertible {
    public var debugDescription: String { "AppTransaction(\(bundleID) \(appVersion))" }
}

@available(iOS 16.0, *)
extension VerificationResult where SignedType == AppTransaction {
    public var jwsRepresentation: String { "" }
    public var headerData: Data { Data() }
    public var payloadData: Data { Data() }
}
