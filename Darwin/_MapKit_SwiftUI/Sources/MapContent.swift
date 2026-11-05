// Map content: what a Map shows over its tiles. Content resolves to a list
// of items (annotations and the user's location), read through the
// content's body unless it is one of the primitive kinds here, which list
// their items themselves. The graph-making requirements are there for the
// ABI; maps read the items instead.

public import CoreLocation
public import MapKit
public import OpenSwiftUI

// MARK: - MapContent

/// A type that represents parts of a map: annotations, markers, overlays.
@preconcurrency
@MainActor
public protocol MapContent {
    associatedtype Body: MapContent

    @MapContentBuilder
    @MainActor
    @preconcurrency
    var body: Body { get }

    @MainActor
    @preconcurrency
    static func _makeMapContent(content: _GraphValue<Self>, inputs: _MapContentInputs) -> _MapContentOutputs

    @MainActor
    @preconcurrency
    static func _mapContentCount(inputs: _MapContentInputs) -> Int?
}

/// Inputs for making map content; maps read content's items directly.
public struct _MapContentInputs {}

/// Outputs of making map content.
public struct _MapContentOutputs {}

extension MapContent {
    @MainActor
    @preconcurrency
    public static func _makeMapContent(content: _GraphValue<Self>, inputs: _MapContentInputs) -> _MapContentOutputs {
        _MapContentOutputs()
    }

    @MainActor
    @preconcurrency
    public static func _mapContentCount(inputs: _MapContentInputs) -> Int? {
        nil
    }
}

extension MapContent where Body == Never {
    public var body: Never {
        preconditionFailure("\(Self.self) is primitive map content")
    }
}

extension Never {
    public typealias MapContentValue = Never
}

extension Never: MapContent {
    @MainActor
    @preconcurrency
    public static func _mapContentCount(inputs: _MapContentInputs) -> Int? { 0 }
}

// MARK: - Resolving content

/// One thing a map shows over its tiles.
enum MapItem {
    /// A view at a coordinate, its anchor point there, with a title under
    /// it.
    case annotation(coordinate: CLLocationCoordinate2D, anchor: UnitPoint, content: AnyView, label: AnyView?)
    /// A view at the user's location.
    case userLocation(anchor: UnitPoint, content: AnyView)
}

/// Content that lists its items itself.
@MainActor
protocol PrimitiveMapContent {
    var mapItems: [MapItem] { get }
}

extension MapContent {
    /// The items this content shows, through its body when it isn't
    /// primitive.
    @MainActor
    var mapItems: [MapItem] {
        if let primitive = self as? PrimitiveMapContent {
            return primitive.mapItems
        }
        if Body.self == Never.self {
            return []
        }
        return body.mapItems
    }
}

/// The items of content of any type, as tuples and optionals hold it.
@MainActor
func resolvedMapItems(of value: Any) -> [MapItem] {
    if let content = value as? any MapContent {
        return content.mapItems
    }
    return []
}

// MARK: - Builder and its content

/// Constructs map content from multi-expression closures.
@resultBuilder
public struct MapContentBuilder {
    @_alwaysEmitIntoClient
    public static func buildExpression<Content>(_ content: Content) -> Content where Content: MapContent {
        content
    }

    @_alwaysEmitIntoClient
    public static func buildBlock() -> EmptyMapContent {
        EmptyMapContent()
    }

    @_alwaysEmitIntoClient
    public static func buildBlock<C>(_ content: C) -> C where C: MapContent {
        content
    }

    @_alwaysEmitIntoClient
    public static func buildIf<Content>(_ content: Content?) -> Content? where Content: MapContent {
        content
    }

    @_disfavoredOverload
    @_alwaysEmitIntoClient
    public static func buildBlock<each Content>(_ content: repeat each Content) -> TupleMapContent<(repeat each Content)>
    where repeat each Content: MapContent {
        TupleMapContent((repeat each content))
    }
}

/// Map content with no items.
@preconcurrency
@MainActor
public struct EmptyMapContent: MapContent, PrimitiveMapContent {
    public typealias Body = Never

    @preconcurrency
    @MainActor
    public init() {}

    @MainActor
    @preconcurrency
    public static func _makeMapContent(content: _GraphValue<EmptyMapContent>, inputs: _MapContentInputs) -> _MapContentOutputs {
        _MapContentOutputs()
    }

    var mapItems: [MapItem] { [] }
}

/// Several pieces of map content, as the builder makes them: a tuple of
/// them, read by reflection.
@frozen
@preconcurrency
@MainActor
public struct TupleMapContent<T>: MapContent, PrimitiveMapContent {
    public typealias Body = Never

    @MainActor
    @preconcurrency
    public var value: T

    @inlinable
    @MainActor
    @preconcurrency
    init(_ value: T) {
        self.value = value
    }

    @MainActor
    @preconcurrency
    public static func _makeMapContent(content: _GraphValue<TupleMapContent<T>>, inputs: _MapContentInputs) -> _MapContentOutputs {
        _MapContentOutputs()
    }

    @MainActor
    @preconcurrency
    public static func _mapContentCount(inputs: _MapContentInputs) -> Int? {
        nil
    }

    var mapItems: [MapItem] {
        let children = Mirror(reflecting: value).children
        if children.isEmpty {
            return resolvedMapItems(of: value)
        }
        return children.flatMap { resolvedMapItems(of: $0.value) }
    }
}

extension Optional: MapContent where Wrapped: MapContent {
    public typealias Body = Never
}

extension Optional: PrimitiveMapContent where Wrapped: MapContent {
    var mapItems: [MapItem] {
        self?.mapItems ?? []
    }
}

// MARK: - ForEach

extension ForEach: MapContent where Content: MapContent {
    public typealias Body = Never

    @MainActor
    @preconcurrency
    public static func _makeMapContent(content: _GraphValue<ForEach<Data, ID, Content>>, inputs: _MapContentInputs) -> _MapContentOutputs {
        _MapContentOutputs()
    }
}

extension ForEach: PrimitiveMapContent where Content: MapContent {
    var mapItems: [MapItem] {
        data.flatMap { content($0).mapItems }
    }
}

extension ForEach where Content: MapContent {
    @MainActor
    public init(_ data: Data, @MapContentBuilder content: @escaping (Data.Element) -> Content)
    where ID == Data.Element.ID, Data.Element: Identifiable {
        self.init(data, idGenerator: .keyPath(\.id), content: content)
    }

    @MainActor
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @MapContentBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, idGenerator: .keyPath(id), content: content)
    }

    @MainActor
    public init(_ data: Range<Int>, @MapContentBuilder content: @escaping (Int) -> Content)
    where Data == Range<Int>, ID == Int {
        self.init(data, idGenerator: .offset, content: content)
    }
}
