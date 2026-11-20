// TipKit's Swift API, as far as apps declare tips with it: there is no
// datastore here, so no rule is ever met, every tip stays pending and a
// tip's view shows nothing. The declarations follow the iOS SDK's TipKit
// interface, so apps built against Apple's bind to them by the same symbols.

public import Foundation
@_exported public import SwiftUI
public import UIKit

// MARK: - Tips

@available(iOS 17.0, *)
@frozen public enum Tips {}

@available(iOS 17.0, *)
extension Tips: @unchecked Sendable {}

@available(iOS 17.0, *)
extension Tips {
    /// Loads the datastore: there is none.
    public static func configure(_ configuration: [ConfigurationOption] = []) throws {}

    public static func resetDatastore() throws {}
    public static func showAllTipsForTesting() {}
    public static func showTipsForTesting(_ tips: [any Tip.Type]) {}
    public static func hideAllTipsForTesting() {}
    public static func hideTipsForTesting(_ tips: [any Tip.Type]) {}
}

@available(iOS 17.0, *)
extension Tips {
    public struct ConfigurationOption: Sendable {
        init() {}
    }
}

@available(iOS 17.0, *)
extension Tips.ConfigurationOption {
    public static func datastoreLocation(_ storeLocation: DatastoreLocation) -> Tips.ConfigurationOption { Tips.ConfigurationOption() }

    public struct DatastoreLocation: Equatable, Sendable {
        let url: URL?

        public static var applicationDefault: DatastoreLocation { DatastoreLocation(url: nil) }
        public static func groupContainer(identifier: String) throws -> DatastoreLocation { DatastoreLocation(url: nil) }
        public static func url(_ url: URL) -> DatastoreLocation { DatastoreLocation(url: url) }
    }

    public static func cloudKitContainer(_ cloudKitContainer: CloudKitContainer?) -> Tips.ConfigurationOption { Tips.ConfigurationOption() }

    public struct CloudKitContainer: Equatable, Sendable {
        let name: String?

        public static var automatic: CloudKitContainer { CloudKitContainer(name: nil) }
        public static func named(_ containerName: String) -> CloudKitContainer { CloudKitContainer(name: containerName) }
    }

    public static func displayFrequency(_ displayFrequency: DisplayFrequency) -> Tips.ConfigurationOption { Tips.ConfigurationOption() }

    public struct DisplayFrequency: Equatable, Sendable {
        let interval: TimeInterval

        public static var immediate: DisplayFrequency { DisplayFrequency(interval: 0) }
        public static var hourly: DisplayFrequency { DisplayFrequency(interval: 3600) }
        public static var daily: DisplayFrequency { DisplayFrequency(interval: 86400) }
        public static var weekly: DisplayFrequency { DisplayFrequency(interval: 604_800) }
        public static var monthly: DisplayFrequency { DisplayFrequency(interval: 2_592_000) }
    }
}

// MARK: - Status

@available(iOS 17.0, *)
extension Tips {
    public enum Status: Hashable, Sendable {
        case pending
        case available
        case invalidated(InvalidationReason)
    }

    public enum InvalidationReason: Hashable, Sendable {
        case actionPerformed
        case displayCountExceeded
        case displayDurationExceeded
        case tipClosed
    }
}

// MARK: - Events

@available(iOS 17.0, *)
extension Tips {
    public struct EmptyDonation: Codable, Sendable {
        public func encode(to encoder: any Encoder) throws {}
        public init(from decoder: any Decoder) throws {}
        init() {}
    }

    public struct DonationTimeRange: Hashable, Codable, Sendable {
        let seconds: Int

        public static var minute: DonationTimeRange { DonationTimeRange(seconds: 60) }
        public static var hour: DonationTimeRange { DonationTimeRange(seconds: 3600) }
        public static var day: DonationTimeRange { DonationTimeRange(seconds: 86400) }
        public static var week: DonationTimeRange { DonationTimeRange(seconds: 604_800) }
        public static func minutes(_ value: Int) -> DonationTimeRange { DonationTimeRange(seconds: value * 60) }
        public static func hours(_ value: Int) -> DonationTimeRange { DonationTimeRange(seconds: value * 3600) }
        public static func days(_ value: Int) -> DonationTimeRange { DonationTimeRange(seconds: value * 86400) }
        public static func weeks(_ value: Int) -> DonationTimeRange { DonationTimeRange(seconds: value * 604_800) }
    }

    public struct DonationLimit: Sendable {
        public let maximumCount: Int
        public let maximumAge: DonationTimeRange?

        public init(maximumCount: Int, maximumAge: DonationTimeRange? = nil) {
            self.maximumCount = maximumCount
            self.maximumAge = maximumAge
        }
    }

    /// Something the user did, which rules count: its donations aren't kept.
    public struct Event<DonationInfo>: Identifiable, Sendable where DonationInfo: Decodable, DonationInfo: Encodable, DonationInfo: Sendable {
        public var id: String { name }
        let name: String

        public var donations: [Donation] { [] }

        public init(id: String) where DonationInfo == EmptyDonation { name = id }
        public init(id: String) { name = id }
        public init(id: String, donationLimit: DonationLimit) where DonationInfo == EmptyDonation { name = id }
        public init(id: String, donationLimit: DonationLimit) { name = id }
        public typealias ID = String
    }
}

@available(iOS 17.0, *)
extension Tips.Event {
    @dynamicMemberLookup public struct Donation: Codable, Sendable {
        public let date: Date
        let info: DonationInfo

        public subscript<Value>(dynamicMember keyPath: KeyPath<DonationInfo, Value>) -> Value { info[keyPath: keyPath] }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(date)
            try container.encode(info)
        }

        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            date = try container.decode(Date.self)
            info = try container.decode(DonationInfo.self)
        }
    }
}

@available(iOS 17.0, *)
extension Tips.Event {
    public func donate() async where DonationInfo == Tips.EmptyDonation {}
    public func donate(_ donation: DonationInfo) async {}
    public func sendDonation(_ completion: (@Sendable () -> Void)? = nil) where DonationInfo == Tips.EmptyDonation { completion?() }
    public func sendDonation(_ donation: DonationInfo, _ completion: (@Sendable () -> Void)? = nil) { completion?() }
    public func deleteDonations() async throws {}
}

// MARK: - Predicates

@available(iOS 17.0, *)
public protocol EventPredicateExpression<Output>: PredicateExpression {}

@available(iOS 17.0, *)
extension PredicateExpressions.Equal: EventPredicateExpression where LHS: EventPredicateExpression, RHS: EventPredicateExpression {}
@available(iOS 17.0, *)
extension PredicateExpressions.NotEqual: EventPredicateExpression where LHS: EventPredicateExpression, RHS: EventPredicateExpression {}
@available(iOS 17.0, *)
extension PredicateExpressions.Comparison: EventPredicateExpression where LHS: EventPredicateExpression, RHS: EventPredicateExpression {}
@available(iOS 17.0, *)
extension PredicateExpressions.KeyPath: EventPredicateExpression where Root: EventPredicateExpression {}
@available(iOS 17.0, *)
extension PredicateExpressions.Value: EventPredicateExpression {}
@available(iOS 17.0, *)
extension PredicateExpressions.Variable: EventPredicateExpression {}

// MARK: - Parameters

@available(iOS 17.0, *)
extension Tips {
    public struct ParameterOption: Sendable {
        init() {}
    }

    /// A value of the app's that rules read. It is kept in memory only.
    public struct Parameter<Value>: Identifiable, Sendable where Value: Decodable, Value: Encodable, Value: Sendable {
        public var id: String { name }
        let name: String
        let box: ParameterBox<Value>

        public var wrappedValue: Value {
            get { box.value }
            nonmutating set { box.value = newValue }
        }

        public init(_ enclosingInstance: (some Any).Type, _ name: String, _ initialValue: Value, _ options: ParameterOption...) {
            self.name = name
            box = ParameterBox(initialValue)
        }

        @_disfavoredOverload
        public init<T>(_ keyPath: KeyPath<T, Value>, _ initialValue: Value, _ options: ParameterOption...) {
            name = "\(keyPath)"
            box = ParameterBox(initialValue)
        }

        public typealias ID = String
    }
}

@available(iOS 17.0, *)
extension Tips.ParameterOption {
    public static var transient: Tips.ParameterOption { Tips.ParameterOption() }
}

@available(iOS 17.0, *)
final class ParameterBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

// MARK: - Rules

@available(iOS 17.0, *)
extension Tips {
    /// A condition for showing a tip: kept, never evaluated.
    public struct Rule: Sendable {
        public init(_ operation: CompoundOperation, _ rules: [Rule]) {}

        public init<Donation>(_ event: Tips.Event<Donation>,
                              _ eventBuilder: (PredicateExpressions.Variable<Tips.Event<Donation>>) -> any EventPredicateExpression<Bool>)
        where Donation: Decodable, Donation: Encodable, Donation: Sendable {}

        public init<Value>(_ parameter: Tips.Parameter<Value>,
                           _ parameterBuilder: (PredicateExpressions.Variable<Value>) -> any StandardPredicateExpression<Bool>)
        where Value: Decodable, Value: Encodable, Value: Sendable {}
    }

    public protocol RuleInput {
        associatedtype Value
    }

    @resultBuilder public struct RuleBuilder {
        public static func buildBlock() -> [Rule] { [] }
        public static func buildExpression(_ child: Rule) -> [Rule] { [child] }
        @_disfavoredOverload public static func buildExpression(_ child: Rule?) -> [Rule] { child.map { [$0] } ?? [] }
        public static func buildExpression(_ child: [Rule]) -> [Rule] { child }
        @_disfavoredOverload public static func buildExpression(_ child: [Rule?]) -> [Rule] { child.compactMap { $0 } }
        public static func buildEither(first: [Rule]) -> [Rule] { first }
        public static func buildEither(second: [Rule]) -> [Rule] { second }
        public static func buildOptional(_ component: Rule?) -> [Rule] { component.map { [$0] } ?? [] }
        public static func buildOptional(_ component: [Rule?]) -> [Rule] { component.compactMap { $0 } }
        public static func buildPartialBlock(first: [Rule]) -> [Rule] { first }
        public static func buildPartialBlock(accumulated: [Rule], next: [Rule]) -> [Rule] { accumulated + next }
    }
}

@available(iOS 17.0, *)
extension Tips.Rule {
    public enum CompoundOperation: Sendable {
        case disjunction
        case conjunction
    }
}

@available(iOS 17.0, *)
extension Tips.RuleBuilder: Sendable {}

@available(iOS 17.0, *)
extension Tips.Parameter: Tips.RuleInput {
    public typealias Value = Value
}

@available(iOS 17.0, *)
extension Tips.Event: Tips.RuleInput {
    public typealias Value = Tips.Event<DonationInfo>
}

// MARK: - Actions

@available(iOS 17.0, *)
extension Tips {
    public struct Action: Identifiable {
        public let id: String
        public let index: Int?
        public let label: @Sendable () -> Text
        @preconcurrency public let handler: @MainActor @Sendable () -> Void

        @preconcurrency public init(id: String? = nil, perform handler: @escaping @MainActor @Sendable () -> Void = {},
                                    _ label: @escaping @Sendable () -> Text) {
            self.id = id ?? UUID().uuidString
            index = nil
            self.label = label
            self.handler = handler
        }

        @preconcurrency nonisolated public init(id: String? = nil, title: some StringProtocol,
                                                perform handler: @escaping @MainActor @Sendable () -> Void = {}) {
            let title = String(title)
            self.id = id ?? UUID().uuidString
            index = nil
            label = { Text(title) }
            self.handler = handler
        }

        init(id: String, index: Int?, label: @escaping @Sendable () -> Text, handler: @escaping @MainActor @Sendable () -> Void) {
            self.id = id
            self.index = index
            self.label = label
            self.handler = handler
        }

        @usableFromInline
        internal func with(index: Int) -> Action { Action(id: id, index: index, label: label, handler: handler) }

        public typealias ID = String
    }

    @resultBuilder public struct ActionBuilder {
        @inlinable public static func buildExpression(_ element: Action) -> [Action] { [element] }
        @inlinable public static func buildExpression(_ component: [Action]) -> [Action] { component }
        @inlinable public static func buildPartialBlock(first: [Action]) -> [Action] { first }
        @inlinable public static func buildPartialBlock(accumulated: [Action], next: [Action]) -> [Action] { accumulated + next }
        @inlinable public static func buildArray(_ components: [[Action]]) -> [Action] {
            components.reduce(into: []) { $0.append(contentsOf: $1) }
        }
        @inlinable public static func buildEither(first component: [Action]) -> [Action] { component }
        @inlinable public static func buildEither(second component: [Action]) -> [Action] { component }
        @inlinable public static func buildLimitedAvailability(_ component: [Action]) -> [Action] { component }
        @inlinable public static func buildOptional(_ component: [Action]?) -> [Action] { component ?? [] }
        @inlinable public static func buildFinalResult(_ component: [Action]) -> [Action] {
            component.enumerated().map { idx, action in action.with(index: idx) }
        }
    }
}

@available(iOS 17.0, *)
extension Tips.Action: Sendable {}

@available(iOS 17.0, *)
extension Tips.ActionBuilder: Sendable {}

// MARK: - Options

@available(iOS 17.0, *)
public protocol TipOption: Sendable {}

@available(iOS 17.0, *)
extension Tips {
    public struct IgnoresDisplayFrequency: TipOption {
        public init(_ ignoresDisplayFrequency: Bool) {}
    }

    public struct MaxDisplayCount: TipOption {
        public init(_ maxDisplayCount: Int) {}
    }

    public struct MaxDisplayDuration: TipOption {
        public init(_ maxDisplayDuration: TimeInterval) {}
    }

    /// The options a tip's builder has gathered.
    struct OptionList: TipOption {
        var options: [any TipOption]

        init(_ options: [any TipOption?]) {
            self.options = options.compactMap { $0 }.flatMap { ($0 as? OptionList)?.options ?? [$0] }
        }
    }

    @resultBuilder public struct OptionsBuilder {
        public static func buildExpression(_ child: some TipOption) -> some TipOption { OptionList([child]) }
        @_disfavoredOverload public static func buildExpression(_ child: (any TipOption)?) -> some TipOption { OptionList([child]) }
        public static func buildExpression(_ child: [some TipOption]) -> some TipOption { OptionList(child) }
        @_disfavoredOverload public static func buildExpression(_ child: [(any TipOption)?]) -> some TipOption { OptionList(child) }
        public static func buildEither(first: some TipOption) -> some TipOption { OptionList([first]) }
        public static func buildEither(second: some TipOption) -> some TipOption { OptionList([second]) }
        public static func buildOptional(_ component: (any TipOption)?) -> some TipOption { OptionList([component]) }
        public static func buildOptional(_ component: [(any TipOption)?]) -> some TipOption { OptionList(component) }
        public static func buildBlock() -> some TipOption { OptionList([]) }
        public static func buildPartialBlock(first: some TipOption) -> some TipOption { OptionList([first]) }
        public static func buildPartialBlock(accumulated: some TipOption, next: some TipOption) -> some TipOption {
            OptionList([accumulated, next])
        }
        public static func buildFinalResult(_ component: some TipOption) -> [any TipOption] { OptionList([component]).options }
    }
}

@available(iOS 17.0, *)
extension Tips.OptionsBuilder: Sendable {}

// MARK: - Tip

@available(iOS 17.0, *)
@_typeEraser(AnyTip) public protocol Tip: Identifiable, Sendable {
    var id: String { get }
    var title: Text { get }
    var message: Text? { get }
    var image: Image? { get }
    @Tips.ActionBuilder var actions: [Action] { get }
    @Tips.RuleBuilder var rules: [Rule] { get }
    @Tips.OptionsBuilder var options: [any TipOption] { get }
}

@available(iOS 17.0, *)
extension Tip {
    public typealias Status = Tips.Status
    public typealias InvalidationReason = Tips.InvalidationReason
    public typealias Action = Tips.Action
    public typealias Rule = Tips.Rule
    public typealias Event = Tips.Event
    public typealias Option = TipOption
    public typealias IgnoresDisplayFrequency = Tips.IgnoresDisplayFrequency
    public typealias MaxDisplayCount = Tips.MaxDisplayCount
    public typealias MaxDisplayDuration = Tips.MaxDisplayDuration
}

@available(iOS 17.0, *)
extension Tip {
    /// No rule is ever met without a datastore: the tip waits.
    public var status: Status { .pending }
    public var shouldDisplay: Bool { false }

    public var statusUpdates: AsyncStream<Status> {
        AsyncStream { continuation in continuation.yield(.pending) }
    }

    public var shouldDisplayUpdates: AsyncMapSequence<AsyncStream<Status>, Bool> {
        statusUpdates.map { $0 == .available }
    }

    public func invalidate(reason: InvalidationReason) {}
    public func resetEligibility() async {}
}

@available(iOS 17.0, *)
extension Tip {
    public var id: String { String(reflecting: Self.self) }
    public var message: Text? { nil }
    public var image: Image? { nil }
    public var rules: [Rule] { [] }
    public var actions: [Action] { [] }
    public var options: [any TipOption] { [] }
}

@available(iOS 17.0, *)
public struct AnyTip: Tip {
    let base: any Tip

    public var id: String { base.id }
    public var title: Text { base.title }
    public var message: Text? { base.message }
    public var image: Image? { base.image }
    public var actions: [Action] { base.actions }
    public var rules: [Rule] { base.rules }
    public var options: [any TipOption] { base.options }

    public init(_ tip: some Tip) { base = tip }
    public init(erasing tip: some Tip) { base = tip }
    public typealias ID = String
}

// MARK: - Errors

@available(iOS 17.0, *)
public struct TipKitError: Error, LocalizedError, Hashable {
    let code: Int

    public var description: String {
        switch code {
        case 1: "Invalid predicate value type"
        case 2: "Missing group container entitlements"
        default: "Tips datastore already configured"
        }
    }

    public var errorDescription: String? { description }
}

@available(iOS 17.0, *)
extension TipKitError {
    public static let invalidPredicateValueType = TipKitError(code: 1)
    public static let missingGroupContainerEntitlements = TipKitError(code: 2)
    public static let tipsDatastoreAlreadyConfigured = TipKitError(code: 3)

    public static func ~= (lhs: TipKitError, rhs: any Error) -> Bool { (rhs as? TipKitError) == lhs }
}

// MARK: - UIKit

/// A tip's view for UIKit: with no tip ever eligible, it draws nothing and
/// takes no room.
@available(iOS 17.0, *)
@objc @MainActor @preconcurrency final public class TipUIView: UIView {
    public var backgroundStyle: any ShapeStyle = Color.clear
    public var cornerRadius: CGFloat = 0
    public var imageSize: CGSize = .zero
    public var imageStyle: (any ShapeStyle)?

    let tip: any Tip
    let actionHandler: @MainActor @Sendable (Tips.Action) -> Void

    @preconcurrency public init(_ tip: any Tip, arrowEdge: Edge? = nil,
                                actionHandler: @escaping @MainActor @Sendable (Tips.Action) -> Void = { _ in }) {
        self.tip = tip
        self.actionHandler = actionHandler
        super.init(frame: .zero)
    }

    @_disfavoredOverload
    @preconcurrency public init(_ tip: some Tip, arrowEdge: Edge? = nil,
                                actionHandler: @escaping @MainActor @Sendable (Tips.Action) -> Void = { _ in }) {
        self.tip = tip
        self.actionHandler = actionHandler
        super.init(frame: .zero)
    }

    @objc required dynamic public init?(coder: NSCoder) { nil }

    @objc override public var intrinsicContentSize: CGSize { .zero }
    @objc override public func sizeThatFits(_ size: CGSize) -> CGSize { .zero }
}
