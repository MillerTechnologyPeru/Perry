import Foundation

// CLLocationUpdate: a live stream of location updates as an async
// sequence, over CLLocationUpdater.

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct CLLocationUpdate: Sendable {
    private let update: Update

    /// Core Location's update, which it doesn't change once delivered.
    private struct Update: @unchecked Sendable {
        let object: __CLUpdate?
    }

    init(_ update: __CLUpdate?) {
        self.update = Update(object: update)
    }

    public var location: CLLocation? { update.object?.location }

    @available(*, deprecated, renamed: "stationary")
    public var isStationary: Bool { update.object?.isStationary ?? false }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public var stationary: Bool { update.object?.stationary ?? false }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public var authorizationDenied: Bool { update.object?.authorizationDenied ?? false }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public var authorizationDeniedGlobally: Bool { update.object?.authorizationDeniedGlobally ?? false }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public var authorizationRestricted: Bool { update.object?.authorizationRestricted ?? false }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public var insufficientlyInUse: Bool { update.object?.insufficientlyInUse ?? false }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public var locationUnavailable: Bool { update.object?.locationUnavailable ?? (update.object == nil) }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public var accuracyLimited: Bool { update.object?.accuracyLimited ?? false }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public var serviceSessionRequired: Bool { update.object?.serviceSessionRequired ?? false }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
    public var authorizationRequestInProgress: Bool { update.object?.authorizationRequestInProgress ?? false }

    public enum LiveConfiguration {
        case `default`
        case automotiveNavigation
        case otherNavigation
        case fitness
        case airborne
        @available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
        case maritime

        public static func == (a: CLLocationUpdate.LiveConfiguration, b: CLLocationUpdate.LiveConfiguration) -> Bool {
            a.rawConfiguration == b.rawConfiguration
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(rawConfiguration)
        }

        public var hashValue: Int {
            var hasher = Hasher()
            hash(into: &hasher)
            return hasher.finalize()
        }

        /// CLLiveUpdateConfiguration's value.
        var rawConfiguration: Int {
            switch self {
            case .default: return 0
            case .automotiveNavigation: return 1
            case .otherNavigation: return 2
            case .fitness: return 3
            case .airborne: return 4
            case .maritime: return 5
            }
        }
    }

    public static func liveUpdates(_ configuration: CLLocationUpdate.LiveConfiguration = .default) -> CLLocationUpdate.Updates {
        Updates(rawConfiguration: configuration.rawConfiguration)
    }

    public struct Updates: AsyncSequence, Sendable {
        public typealias Element = CLLocationUpdate

        /// The configuration's CLLiveUpdateConfiguration value.
        let rawConfiguration: Int

        public struct Iterator: AsyncIteratorProtocol {
            let updater: Updater

            public mutating func next() async throws -> CLLocationUpdate.Updates.Element? {
                try Task.checkCancellation()
                return await updater.iterator.next()
            }

            @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
            public typealias Element = CLLocationUpdate.Updates.Element
        }

        public func makeAsyncIterator() -> CLLocationUpdate.Updates.Iterator {
            Iterator(updater: Updater(rawConfiguration: rawConfiguration))
        }

        @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
        public typealias AsyncIterator = CLLocationUpdate.Updates.Iterator
    }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension CLLocationUpdate.LiveConfiguration: Equatable {}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension CLLocationUpdate.LiveConfiguration: Hashable {}

@available(*, unavailable)
extension CLLocationUpdate.Updates.Iterator: Sendable {}

/// One iteration's live updater: Core Location's updater delivering into a
/// stream, invalidated when the iteration ends.
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class Updater {
    private var updater: __CLLocationUpdater?
    var iterator: AsyncStream<CLLocationUpdate>.Iterator

    init(rawConfiguration: Int) {
        let (stream, continuation) = AsyncStream<CLLocationUpdate>.makeStream()
        iterator = stream.makeAsyncIterator()
        let queue = DispatchQueue(label: "CLLocationUpdate.liveUpdates")
        let rawConfiguration = __CLLiveUpdateConfiguration(rawValue: rawConfiguration) ?? .default
        updater = __CLLocationUpdater.__live(with: rawConfiguration, queue: queue) { update in
            continuation.yield(CLLocationUpdate(update))
        }
        if updater == nil {
            continuation.finish()
        }
    }

    deinit {
        updater?.invalidate()
    }
}
