//
//  TransformedShapes.swift
//  OpenSwiftUICore
//
//  Status: Perry's implementation
//
//  Shapes made from other shapes: offset, scaled, and type-erased; text
//  renderers; the color invert effect's type; and the shading of a shape
//  style. These sit in the core module beside the types they extend.

public import Foundation
public import OpenCoreGraphicsShims

// MARK: - OffsetShape

/// A shape moved by an offset.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct OffsetShape<Content>: Shape where Content: Shape {
    public var shape: Content
    public var offset: CGSize

    @inlinable
    public init(shape: Content, offset: CGSize) {
        self.shape = shape
        self.offset = offset
    }

    nonisolated public func path(in rect: CGRect) -> Path {
        shape.path(in: rect).offsetBy(dx: offset.width, dy: offset.height)
    }

    nonisolated public static var role: ShapeRole { Content.role }

    public var animatableData: AnimatablePair<Content.AnimatableData, CGSize.AnimatableData> {
        get { AnimatablePair(shape.animatableData, offset.animatableData) }
        set {
            shape.animatableData = newValue.first
            offset.animatableData = newValue.second
        }
    }
}

// MARK: - ScaledShape

/// A shape scaled about an anchor point of the rectangle it fills.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct ScaledShape<Content>: Shape where Content: Shape {
    public var shape: Content
    public var scale: CGSize
    public var anchor: UnitPoint

    @inlinable
    public init(shape: Content, scale: CGSize, anchor: UnitPoint = .center) {
        self.shape = shape
        self.scale = scale
        self.anchor = anchor
    }

    nonisolated public func path(in rect: CGRect) -> Path {
        let x = rect.minX + rect.width * anchor.x
        let y = rect.minY + rect.height * anchor.y
        let transform = CGAffineTransform(translationX: x, y: y)
            .scaledBy(x: scale.width, y: scale.height)
            .translatedBy(x: -x, y: -y)
        return shape.path(in: rect).applying(transform)
    }

    nonisolated public static var role: ShapeRole { Content.role }

    public var animatableData: AnimatablePair<Content.AnimatableData, AnimatablePair<CGSize.AnimatableData, UnitPoint.AnimatableData>> {
        get { AnimatablePair(shape.animatableData, AnimatablePair(scale.animatableData, anchor.animatableData)) }
        set {
            shape.animatableData = newValue.first
            scale.animatableData = newValue.second.first
            anchor.animatableData = newValue.second.second
        }
    }
}

// MARK: - AnyShape

/// The shape an AnyShape wraps.
@available(OpenSwiftUI_v1_0, *)
@usableFromInline
class AnyShapeBox: @unchecked Sendable {
    let makePath: @Sendable (CGRect) -> Path
    let fitting: @Sendable (ProposedViewSize) -> CGSize

    init<S>(_ shape: S) where S: Shape {
        makePath = { shape.path(in: $0) }
        fitting = { shape.sizeThatFits($0) }
    }
}

/// A type-erased shape.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct AnyShape: Shape, @unchecked Sendable {
    var storage: AnyShapeBox

    public init<S>(_ shape: S) where S: Shape {
        storage = AnyShapeBox(shape)
    }

    nonisolated public func path(in rect: CGRect) -> Path {
        storage.makePath(rect)
    }

    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        storage.fitting(proposal)
    }

    /// The wrapped shape is not animated: its animatable data is empty.
    public var animatableData: _AnyAnimatableData {
        get { .zero }
        set {}
    }
}

// MARK: - Color inversion

/// The effect that inverts a view's colors; Perry draws the view as it is.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _ColorInvertEffect: Equatable, ViewModifier, PrimitiveViewModifier, Sendable {
    @inlinable
    nonisolated public init() {}

    public typealias AnimatableData = EmptyAnimatableData

    nonisolated public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
}

// MARK: - Text renderers

/// A value that draws a text view's laid-out lines in place of the
/// default drawing. Perry draws text itself: a renderer set on a view is
/// kept and not asked to draw.
@available(OpenSwiftUI_v1_0, *)
public protocol TextRenderer: Animatable {
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext)
    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize
    var displayPadding: EdgeInsets { get }
}

@available(OpenSwiftUI_v1_0, *)
extension TextRenderer {
    public func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
        text.sizeThatFits(proposal)
    }

    public var displayPadding: EdgeInsets { EdgeInsets() }
}

/// The modifier that sets a text renderer; the view is drawn as it is.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _TextRendererViewModifier<Renderer>: ViewModifier, PrimitiveViewModifier where Renderer: TextRenderer {
    @usableFromInline
    var renderer: Renderer

    @usableFromInline
    nonisolated init(renderer: Renderer) {
        self.renderer = renderer
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
}

@available(*, unavailable)
extension _TextRendererViewModifier: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Draws the text in this view with a renderer; Perry draws it as usual.
    nonisolated public func textRenderer<T>(_ renderer: T) -> some View where T: TextRenderer {
        modifier(_TextRendererViewModifier(renderer: renderer))
    }
}

// MARK: - Graphics context

@available(OpenSwiftUI_v1_0, *)
extension GraphicsContext.Shading {
    /// A shading that fills with a shape style. Perry's contexts fill only
    /// with colors: a style shading fills with nothing.
    public static func style<S>(_ style: S) -> GraphicsContext.Shading where S: ShapeStyle {
        GraphicsContext.Shading(storage: .style(AnyShapeStyle(style)))
    }
}

@available(OpenSwiftUI_v1_0, *)
extension GraphicsContext {
    /// Draws a line of laid-out text. Perry lays out no text for a
    /// renderer, so no line reaches this, and it draws nothing.
    public func draw(_ line: Text.Layout.Line, options: Text.Layout.DrawingOptions = .init()) {}

    /// Draws part of a run of laid-out text; nothing, as for a line.
    public func draw(_ slice: Text.Layout.RunSlice, options: Text.Layout.DrawingOptions = .init()) {}
}

// MARK: - Corner geometry

/// The corner sizes by which a container's corners cut into a rectangle.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct RectangleCornerInsets: Hashable, Sendable {
    public var topLeading: CGSize
    public var topTrailing: CGSize
    public var bottomLeading: CGSize
    public var bottomTrailing: CGSize

    public init() {
        self.init(topLeading: .zero, topTrailing: .zero, bottomLeading: .zero, bottomTrailing: .zero)
    }

    public init(topLeading: CGSize, topTrailing: CGSize, bottomLeading: CGSize, bottomTrailing: CGSize) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }

    public static func == (a: RectangleCornerInsets, b: RectangleCornerInsets) -> Bool {
        a.topLeading == b.topLeading && a.topTrailing == b.topTrailing
            && a.bottomLeading == b.bottomLeading && a.bottomTrailing == b.bottomTrailing
    }

    public func hash(into hasher: inout Hasher) {
        for size in [topLeading, topTrailing, bottomLeading, bottomTrailing] {
            hasher.combine(size.width)
            hasher.combine(size.height)
        }
    }
}
