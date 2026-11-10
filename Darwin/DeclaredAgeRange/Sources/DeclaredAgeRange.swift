// DeclaredAgeRange: the age range a person's account shares with an app. There
// is no account behind this device, so no range is ever shared: a request
// fails as unavailable, and the device is not eligible for age features and
// has no regulatory feature to meet. The declarations are the framework's own
// (what apps bind to by Swift symbol), so library evolution is on and the
// types are resilient.
import Foundation
import SwiftUI
import UIKit

@available(iOS 26.0, macOS 26.0, *)
@available(visionOS, unavailable)
public struct AgeRangeService {
    public static let shared = AgeRangeService()

    private init() {}

    public enum Error: LocalizedError {
        case notAvailable
        case invalidRequest
        @available(iOS 27.0, macOS 27.0, *)
        case invalidAccount
        @available(iOS 27.0, macOS 27.0, *)
        case declinedOnboarding
        @available(iOS 27.0, macOS 27.0, *)
        case network
    }

    public enum AgeRangeDeclaration: Sendable {
        case selfDeclared
        case guardianDeclared
        @available(iOS 26.2, macOS 26.2, *)
        @available(*, deprecated, renamed: "confirmed")
        case checkedByOtherMethod
        @available(iOS 26.2, macOS 26.2, *)
        @available(*, deprecated, renamed: "confirmed")
        case guardianCheckedByOtherMethod
        @available(iOS 26.2, macOS 26.2, *)
        @available(*, deprecated, renamed: "confirmed")
        case governmentIDChecked
        @available(iOS 26.2, macOS 26.2, *)
        @available(*, deprecated, renamed: "confirmed")
        case guardianGovernmentIDChecked
        @available(iOS 26.2, macOS 26.2, *)
        @available(*, deprecated, renamed: "confirmed")
        case paymentChecked
        @available(iOS 26.2, macOS 26.2, *)
        @available(*, deprecated, renamed: "confirmed")
        case guardianPaymentChecked
        @available(iOS 26.5, macOS 26.5, *)
        case confirmed
    }

    public struct ParentalControls: OptionSet, Sendable {
        public let rawValue: Int

        public static let communicationLimits = ParentalControls(rawValue: 1 << 0)
        @available(iOS 26.2, macOS 26.2, *)
        @available(visionOS, unavailable)
        @available(iOS, deprecated: 26.4, message: "Use requiredRegulatoryFeatures to check for significantAppChangeRequiresParentalConsent instead")
        @available(macOS, deprecated: 26.4, message: "Use requiredRegulatoryFeatures to check for significantAppChangeRequiresParentalConsent instead")
        public static let significantAppChangeApprovalRequired = ParentalControls(rawValue: 1 << 1)

        public init(rawValue: Int) { self.rawValue = rawValue }

        public var description: String { "ParentalControls(\(rawValue))" }
    }

    public struct AgeRange: Sendable {
        public var lowerBound: Int?
        public var upperBound: Int?
        public var ageRangeDeclaration: AgeRangeDeclaration?
        public var activeParentalControls: ParentalControls
    }

    public enum Response {
        case declinedSharing
        case sharing(range: AgeRange)
    }

    @available(iOS 26.4, macOS 26.4, *)
    public enum RegulatoryFeature: Hashable, Sendable {
        case significantAppChangeRequiresAdultNotification
        case significantAppChangeRequiresParentalConsent
        case declaredAgeRangeRequired
    }

    public func requestAgeRange(ageGates threshold1: Int, _ threshold2: Int? = nil, _ threshold3: Int? = nil,
                                in viewController: UIViewController) async throws -> Response {
        throw Error.notAvailable
    }

    @available(iOS 26.2, macOS 26.2, *)
    public var isEligibleForAgeFeatures: Bool {
        get async throws { false }
    }

    @available(iOS 26.4, macOS 26.4, *)
    public var requiredRegulatoryFeatures: Set<RegulatoryFeature> {
        get async throws { [] }
    }

    @available(iOS 26.4, *)
    @available(macOS, unavailable)
    @available(visionOS, unavailable)
    @MainActor public func showSignificantUpdateAcknowledgment(in windowScene: UIWindowScene,
                                                              updateDescription: String) async throws {
        throw Error.notAvailable
    }
}

@available(iOS 26.0, macOS 26.0, *)
@available(visionOS, unavailable)
extension AgeRangeService.Error: Equatable {}
@available(iOS 26.0, macOS 26.0, *)
@available(visionOS, unavailable)
extension AgeRangeService.Error: Hashable {}
@available(iOS 26.0, macOS 26.0, *)
@available(visionOS, unavailable)
extension AgeRangeService.AgeRangeDeclaration: Equatable {}
@available(iOS 26.0, macOS 26.0, *)
@available(visionOS, unavailable)
extension AgeRangeService.AgeRangeDeclaration: Hashable {}

@available(iOS 26.0, macOS 26.0, *)
@available(visionOS, unavailable)
public struct DeclaredAgeRangeAction {
    public func callAsFunction(ageGates threshold1: Int, _ threshold2: Int? = nil,
                               _ threshold3: Int? = nil) async throws -> AgeRangeService.Response {
        throw AgeRangeService.Error.notAvailable
    }
}

@available(iOS 26.0, macOS 26.0, *)
@available(visionOS, unavailable)
extension EnvironmentValues {
    public var requestAgeRange: DeclaredAgeRangeAction { DeclaredAgeRangeAction() }
}

@available(iOS 26.4, *)
@available(macOS, unavailable)
@available(visionOS, unavailable)
public struct SignificantUpdateAction {
    public func callAsFunction(updateDescription: String) async throws {
        throw AgeRangeService.Error.notAvailable
    }
}

@available(iOS 26.4, *)
@available(macOS, unavailable)
@available(visionOS, unavailable)
extension EnvironmentValues {
    public var showSignificantUpdateAcknowledgment: SignificantUpdateAction { SignificantUpdateAction() }
}
