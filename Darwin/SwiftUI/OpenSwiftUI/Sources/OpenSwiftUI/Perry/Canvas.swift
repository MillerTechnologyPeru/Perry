//
//  Canvas.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  A view drawn by a closure: a UIKit view whose drawRect: hands the
//  renderer a graphics context on the current Core Graphics context, and
//  redraws whenever the canvas is updated. Symbols aren't resolved here.

#if os(iOS) || os(visionOS)
public import CoreGraphics
public import OpenSwiftUICore
public import UIKit

/// A view type that supports immediate mode drawing.
@available(OpenSwiftUI_v3_0, *)
nonisolated public struct Canvas<Symbols>: View where Symbols: View {
    public var symbols: Symbols
    public var renderer: (inout GraphicsContext, CGSize) -> Void
    public var isOpaque: Bool
    public var colorMode: ColorRenderingMode
    public var rendersAsynchronously: Bool

    public init(
        opaque: Bool = false,
        colorMode: ColorRenderingMode = .nonLinear,
        rendersAsynchronously: Bool = false,
        renderer: @escaping (inout GraphicsContext, CGSize) -> Void,
        @ViewBuilder symbols: () -> Symbols
    ) {
        self.symbols = symbols()
        self.renderer = renderer
        self.isOpaque = opaque
        self.colorMode = colorMode
        self.rendersAsynchronously = rendersAsynchronously
    }

    public var body: some View {
        CanvasRepresentable(renderer: renderer, isOpaque: isOpaque)
    }
}

@available(OpenSwiftUI_v3_0, *)
extension Canvas where Symbols == EmptyView {
    public init(
        opaque: Bool = false,
        colorMode: ColorRenderingMode = .nonLinear,
        rendersAsynchronously: Bool = false,
        renderer: @escaping (inout GraphicsContext, CGSize) -> Void
    ) {
        self.init(opaque: opaque, colorMode: colorMode, rendersAsynchronously: rendersAsynchronously, renderer: renderer) {
            EmptyView()
        }
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    var renderer: (inout GraphicsContext, CGSize) -> Void
    var isOpaque: Bool

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.contentMode = .redraw
        return view
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        view.renderer = renderer
        view.environment = context.environment
        view.isOpaque = isOpaque
        view.backgroundColor = isOpaque ? .black : .clear
        view.setNeedsDisplay()
    }
}

/// The canvas's drawing: the renderer, given a context on the view's.
final class CanvasView: UIView {
    var renderer: ((inout GraphicsContext, CGSize) -> Void)?
    var environment = EnvironmentValues()

    override func draw(_ rect: CGRect) {
        guard let renderer, let cgContext = UIGraphicsGetCurrentContext() else { return }
        var context = GraphicsContext(cgContext: cgContext, environment: environment)
        renderer(&context, bounds.size)
    }
}
#endif
