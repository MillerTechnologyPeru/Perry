//
//  ScrollViewReader.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  ScrollViewReader and its proxy. The reader gives the scroll views in it
//  a registry they put themselves in; a proxy's scrollTo asks each for the
//  view with the identifier and moves the first that has it. A scroll view
//  finds views through the containers in it that know where their children
//  are: lazy stacks, lists and forms (a child's identifier is its ForEach
//  element's, or the one .id gives it).

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - ScrollViewReader

/// A view that provides programmatic scrolling, by working with a proxy to
/// scroll to known child views.
@available(OpenSwiftUI_v2_0, *)
@frozen
public struct ScrollViewReader<Content>: View where Content: View {
    public var content: (ScrollViewProxy) -> Content

    @inlinable
    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content
    }

    public var body: some View {
        ScrollReaderBody(content: content)
    }
}

struct ScrollReaderBody<Content: View>: View {
    var content: (ScrollViewProxy) -> Content
    @State private var registry = ScrollRegistry()

    var body: some View {
        content(ScrollViewProxy(registry: registry))
            .environment(\.scrollRegistry, registry)
    }
}

// MARK: - ScrollViewProxy

/// A proxy value that supports programmatic scrolling of the scrollable
/// views within a view hierarchy.
@available(OpenSwiftUI_v2_0, *)
public struct ScrollViewProxy {
    let registry: ScrollRegistry

    /// Scans the scroll views in the reader for the first view with the
    /// identifier, and scrolls it: to put the view's anchor point at the
    /// viewport's, or, with no anchor, just far enough to show the view.
    public func scrollTo<ID>(_ id: ID, anchor: UnitPoint? = nil) where ID: Hashable {
        for scroller in registry.scrollers {
            if scroller.scroll(to: id, anchor: anchor) { return }
        }
    }
}

// MARK: - Registries

/// The scroll views in a reader, as they register.
final class ScrollRegistry {
    private var entries: [ObjectIdentifier: Weak] = [:]

    private struct Weak { weak var scroller: ScrollTargetScroller? }

    var scrollers: [ScrollTargetScroller] { entries.values.compactMap(\.scroller) }

    func register(_ scroller: ScrollTargetScroller) { entries[ObjectIdentifier(scroller)] = Weak(scroller: scroller) }
}

/// What a container knows of where its children are.
protocol ScrollTargetSource: AnyObject {
    /// The frame of the child with the identifier, in the scroll view's
    /// content; nil when it has none.
    func frame<ID: Hashable>(of id: ID) -> CGRect?
}

/// A scroll view's containers that can find children, and its way to move
/// to one.
final class ScrollTargetScroller {
    private var sources: [ObjectIdentifier: Weak] = [:]
    private struct Weak { weak var source: ScrollTargetSource? }

    /// Moves the content to an offset, clamped; set by the scroll view.
    var move: ((CGSize) -> Void)?
    /// The viewport's size and the offset, as they are when asked.
    var current: () -> (viewport: CGSize, offset: CGSize) = { (.zero, .zero) }
    var axes: Axis.Set = .vertical

    func add(_ source: ScrollTargetSource) { sources[ObjectIdentifier(source)] = Weak(source: source) }

    func scroll<ID: Hashable>(to id: ID, anchor: UnitPoint?) -> Bool {
        guard let move else { return false }
        for entry in sources.values {
            guard let frame = entry.source?.frame(of: id) else { continue }
            move(target(showing: frame, anchor: anchor))
            return true
        }
        return false
    }

    /// The offset that puts the frame's anchor at the viewport's, or that
    /// moves least to show it all.
    func target(showing frame: CGRect, anchor: UnitPoint?) -> CGSize {
        let (viewport, offset) = current()
        func axis(_ minimum: CGFloat, _ length: CGFloat, _ viewportLength: CGFloat, _ current: CGFloat, _ unit: CGFloat?) -> CGFloat {
            if let unit { return minimum + length * unit - viewportLength * unit }
            if minimum < current { return minimum }
            if minimum + length > current + viewportLength { return minimum + length - viewportLength }
            return current
        }
        return CGSize(
            width: axes.contains(.horizontal) ? axis(frame.minX, frame.width, viewport.width, offset.width, anchor?.x) : 0,
            height: axes.contains(.vertical) ? axis(frame.minY, frame.height, viewport.height, offset.height, anchor?.y) : 0
        )
    }
}

struct ScrollRegistryKey: EnvironmentKey {
    static let defaultValue: ScrollRegistry? = nil
}

struct ScrollTargetScrollerKey: EnvironmentKey {
    static let defaultValue: ScrollTargetScroller? = nil
}

extension EnvironmentValues {
    var scrollRegistry: ScrollRegistry? {
        get { self[ScrollRegistryKey.self] }
        set { self[ScrollRegistryKey.self] = newValue }
    }

    /// The scroll view the views are in, for containers to tell where
    /// their children are.
    var scrollTargetScroller: ScrollTargetScroller? {
        get { self[ScrollTargetScrollerKey.self] }
        set { self[ScrollTargetScrollerKey.self] = newValue }
    }
}

// MARK: - Children's frames

/// The frames rows were last laid out at, in the scroll view's content,
/// with the children they are; for lists and forms, whose rows a stack
/// places.
final class RowFrames: ScrollTargetSource {
    var children: [_VariadicView.Children.Element] = []
    var frames: [Int: CGRect] = [:]

    func frame<ID: Hashable>(of id: ID) -> CGRect? {
        for (index, child) in children.enumerated() where child.id(as: ID.self) == id {
            return frames[index]
        }
        return nil
    }
}
#endif
