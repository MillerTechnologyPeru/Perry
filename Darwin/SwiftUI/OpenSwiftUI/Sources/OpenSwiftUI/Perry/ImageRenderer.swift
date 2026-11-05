//
//  ImageRenderer.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  An image of a view: the view in a hosting view of its ideal size, or the
//  size proposed, whose layer is drawn into a bitmap.

#if os(iOS) || os(visionOS)
public import Combine
public import CoreGraphics
public import OpenSwiftUICore
public import UIKit

/// An object that creates images from SwiftUI views.
@available(OpenSwiftUI_v4_0, *)
final public class ImageRenderer<Content>: Combine.ObservableObject where Content: View {
    final public let objectWillChange = PassthroughSubject<Void, Never>()

    /// The root view rendered by this image renderer.
    @MainActor
    final public var content: Content {
        didSet { objectWillChange.send() }
    }

    /// The size proposed to the root view.
    @MainActor
    final public var proposedSize: ProposedViewSize = .unspecified {
        didSet { objectWillChange.send() }
    }

    /// The scale at which to render the image.
    @MainActor
    final public var scale: CGFloat = 1 {
        didSet { objectWillChange.send() }
    }

    /// A Boolean value that indicates whether the alpha channel of the
    /// image is fully opaque.
    @MainActor
    final public var isOpaque: Bool = false {
        didSet { objectWillChange.send() }
    }

    /// Creates a renderer object with a source content view.
    @MainActor
    public init(content view: Content) {
        content = view
    }

    /// The current contents of the view, rasterized as a Core Graphics
    /// image.
    @MainActor
    final public var cgImage: CGImage? { uiImage?.cgImage }

    /// The current contents of the view, rasterized as a UIKit image.
    @MainActor
    final public var uiImage: UIImage? {
        let host = _UIHostingView(rootView: content)
        let proposal = CGSize(
            width: proposedSize.width ?? .greatestFiniteMagnitude,
            height: proposedSize.height ?? .greatestFiniteMagnitude
        )
        let fitting = host.sizeThatFits(proposal)
        let size = CGSize(width: max(fitting.width.rounded(.up), 1), height: max(fitting.height.rounded(.up), 1))
        host.frame = CGRect(origin: .zero, size: size)
        host.backgroundColor = .clear
        host.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = isOpaque
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            host.layer.render(in: context.cgContext)
        }
    }

    /// Draws the renderer's current contents to an arbitrary Core Graphics
    /// context.
    @MainActor
    final public func render(rasterizationScale: CGFloat = 1, renderer: (CGSize, (CGContext) -> Void) -> Void) {
        let saved = scale
        scale = rasterizationScale
        let image = uiImage
        scale = saved
        guard let image, let cgImage = image.cgImage else { return }
        renderer(image.size) { context in
            context.draw(cgImage, in: CGRect(origin: .zero, size: image.size))
        }
    }
}
#endif
