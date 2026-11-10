// WidgetKit: the home screen's widgets. Apps ask the center to reload their
// widgets' timelines and which widgets are on the home screen, and mark views
// accentable for them. There is no home screen here, so no widget is
// installed, and a reload has nothing to reload. The declarations are the
// framework's own (what apps bind to by Swift symbol), so library evolution
// is on and the types are resilient.
import Foundation
import SwiftUI

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
public enum WidgetFamily: Int, RawRepresentable, CustomDebugStringConvertible, CustomStringConvertible, Sendable {
    case systemSmall = 0
    case systemMedium = 1
    case systemLarge = 2
    @available(watchOS 9.0, *)
    @available(iOS, unavailable)
    @available(macOS, unavailable)
    case accessoryCorner = 3
    @available(iOS 16.0, watchOS 9.0, *)
    @available(macOS, unavailable)
    case accessoryCircular = 4
    @available(iOS 16.0, watchOS 9.0, *)
    @available(macOS, unavailable)
    case accessoryRectangular = 5
    @available(iOS 16.0, watchOS 9.0, *)
    @available(macOS, unavailable)
    case accessoryInline = 6
    @available(iOS 15.0, macOS 14.0, *)
    @available(watchOS, unavailable)
    case systemExtraLarge = 7
    @available(iOS 27.0, macOS 27.0, *)
    @available(watchOS, unavailable)
    case systemExtraLargePortrait = 8

    public var description: String { "\(self)" }
    public var debugDescription: String { "\(self)" }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
public struct WidgetInfo: Sendable {
    public let family: WidgetFamily
    public let kind: String
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
extension WidgetInfo: Identifiable, Hashable, Equatable {
    public var id: WidgetInfo { self }
    public static func == (a: WidgetInfo, b: WidgetInfo) -> Bool { a.kind == b.kind && a.family == b.family }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(family)
    }
    public typealias ID = WidgetInfo
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
public class WidgetCenter {
    public static let shared = WidgetCenter()

    private init() {}

    public struct UserInfoKey {
        public static let kind = "kind"
        public static let family = "family"
        public static let activityID = "activityID"
    }

    @available(iOS 16.0, macOS 13.0, watchOS 9.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    public func invalidateConfigurationRecommendations() {}

    @preconcurrency
    public func getCurrentConfigurations(_ completion: @escaping @Sendable (Result<[WidgetInfo], any Error>) -> Void) {
        completion(.success([]))
    }

    @available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    public func currentConfigurations() async throws -> [WidgetInfo] { [] }

    public func reloadTimelines(ofKind kind: String) {}
    public func reloadAllTimelines() {}
}

@available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 26.0, *)
@available(tvOS, unavailable)
extension WidgetCenter {
    public func invalidateRelevance(ofKind kind: String) {}
}

@available(iOS 16.0, watchOS 9.0, macOS 13.0, visionOS 26.0, *)
@available(tvOS, unavailable)
extension View {
    @MainActor @preconcurrency public func widgetAccentable(_ accentable: Bool = true) -> some View { self }
}
