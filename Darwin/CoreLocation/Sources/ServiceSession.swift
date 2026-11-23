import Foundation

// CLServiceSession and CLBackgroundActivitySession, which Core Location
// has for iOS, watchOS and tvOS only: unavailable on macOS, as in the SDK,
// so a Mac app can't call them, but present for the symbols the SDK's stub
// lists for the zippered library.

@_hasMissingDesignatedInitializers
@available(iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@available(macOS, unavailable)
public final class CLServiceSession: Sendable {
    public init(authorization: CLServiceSession.AuthorizationRequirement) {
        fatalError("CLServiceSession is unavailable on macOS")
    }

    public init(authorization: CLServiceSession.AuthorizationRequirement, fullAccuracyPurposeKey: String) {
        fatalError("CLServiceSession is unavailable on macOS")
    }

    public final func invalidate() {}

    public final var diagnostics: CLServiceSession.Diagnostics {
        fatalError("CLServiceSession is unavailable on macOS")
    }
}

@available(iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@available(macOS, unavailable)
extension CLServiceSession {
    public struct Diagnostic {
        public var authorizationDenied: Bool { false }
        public var authorizationDeniedGlobally: Bool { false }
        public var authorizationRestricted: Bool { false }
        public var insufficientlyInUse: Bool { false }
        public var fullAccuracyDenied: Bool { false }
        public var alwaysAuthorizationDenied: Bool { false }
        public var serviceSessionRequired: Bool { false }
        public var authorizationRequestInProgress: Bool { false }
    }

    @_hasMissingDesignatedInitializers
    public final class Diagnostics: AsyncSequence {
        public typealias Element = CLServiceSession.Diagnostic

        public struct Iterator: AsyncIteratorProtocol {
            public mutating func next() async throws -> CLServiceSession.Diagnostics.Element? { nil }

            @available(iOS 18.0, tvOS 18.0, watchOS 11.0, *)
            @available(macOS, unavailable)
            public typealias Element = CLServiceSession.Diagnostics.Element
        }

        public final func makeAsyncIterator() -> CLServiceSession.Diagnostics.Iterator { Iterator() }

        @available(iOS 18.0, tvOS 18.0, watchOS 11.0, *)
        @available(macOS, unavailable)
        public typealias AsyncIterator = CLServiceSession.Diagnostics.Iterator
    }

    public enum AuthorizationRequirement {
        case none
        case whenInUse
        @available(tvOS, unavailable)
        case always

        public static func == (a: CLServiceSession.AuthorizationRequirement, b: CLServiceSession.AuthorizationRequirement) -> Bool {
            a.index == b.index
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(index)
        }

        public var hashValue: Int {
            var hasher = Hasher()
            hash(into: &hasher)
            return hasher.finalize()
        }

        private var index: Int {
            switch self {
            case .none: return 0
            case .whenInUse: return 1
            case .always: return 2
            }
        }
    }
}

@available(iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@available(macOS, unavailable)
extension CLServiceSession.AuthorizationRequirement: Equatable {}
@available(iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@available(macOS, unavailable)
extension CLServiceSession.AuthorizationRequirement: Hashable {}

@_hasMissingDesignatedInitializers
@available(iOS 17.0, watchOS 10.0, *)
@available(tvOS, unavailable)
@available(macOS, unavailable)
public final class CLBackgroundActivitySession: Sendable {
    public init() {
        fatalError("CLBackgroundActivitySession is unavailable on macOS")
    }

    public final func invalidate() {}
}
