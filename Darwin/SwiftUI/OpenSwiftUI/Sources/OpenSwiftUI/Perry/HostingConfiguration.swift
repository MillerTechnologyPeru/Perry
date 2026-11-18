//
//  HostingConfiguration.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  A content configuration that shows a view hierarchy in a UIKit cell:
//  its content view hosts the content over the background, inset by the
//  margins set, or by the layout margins of the view it is put in for the
//  edges left alone, and no smaller than the minimum size set. The view
//  answers UIKit's fitting questions with the hosted content's size. The
//  cell's state (selected, highlighted…) isn't passed to the content, and
//  no minimum size is assumed where none is set.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore
public import UIKit

// MARK: - UIHostingConfiguration

/// A content configuration suitable for hosting a hierarchy of views.
@available(OpenSwiftUI_v1_0, *)
public struct UIHostingConfiguration<Content, Background>: UIContentConfiguration where Content: View, Background: View {
    var content: Content
    var background: Background
    var insets = HostingConfigurationInsets()
    var minWidth: CGFloat?
    var minHeight: CGFloat?

    /// Sets the margins around the content of the configuration, on the
    /// given edges, to a length.
    public func margins(_ edges: Edge.Set = .all, _ length: CGFloat) -> UIHostingConfiguration<Content, Background> {
        margins(edges, EdgeInsets(top: length, leading: length, bottom: length, trailing: length))
    }

    /// Sets the margins around the content of the configuration, on the
    /// given edges, to those of the insets.
    public func margins(_ edges: Edge.Set = .all, _ insets: EdgeInsets) -> UIHostingConfiguration<Content, Background> {
        var configuration = self
        if edges.contains(.top) { configuration.insets.top = insets.top }
        if edges.contains(.leading) { configuration.insets.leading = insets.leading }
        if edges.contains(.bottom) { configuration.insets.bottom = insets.bottom }
        if edges.contains(.trailing) { configuration.insets.trailing = insets.trailing }
        return configuration
    }

    /// Sets the minimum size for the configuration; nil leaves a
    /// dimension with no minimum.
    public func minSize(width: CGFloat? = nil, height: CGFloat? = nil) -> UIHostingConfiguration<Content, Background> {
        var configuration = self
        configuration.minWidth = width
        configuration.minHeight = height
        return configuration
    }

    /// Makes a view that hosts the configuration's content.
    @MainActor
    public func makeContentView() -> any UIView & UIContentView {
        HostingConfigurationContentView(configuration: self)
    }

    /// The configuration for a state: the same one, as the state isn't
    /// passed to the content.
    public func updated(for state: any UIConfigurationState) -> UIHostingConfiguration<Content, Background> {
        self
    }
}

@available(*, unavailable)
extension UIHostingConfiguration: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension UIHostingConfiguration where Background == EmptyView {
    /// Creates a hosting configuration with the given contents.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.background = EmptyView()
    }
}

/// The margins a hosting configuration was given, by edge; an edge left
/// nil takes the layout margin of the view the content is put in.
struct HostingConfigurationInsets {
    var top: CGFloat?
    var leading: CGFloat?
    var bottom: CGFloat?
    var trailing: CGFloat?

    func resolved(defaults: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: top ?? defaults.top,
            leading: leading ?? defaults.leading,
            bottom: bottom ?? defaults.bottom,
            trailing: trailing ?? defaults.trailing
        )
    }
}

// MARK: - Hosted content

/// What a hosting configuration's content view hosts: the content inside
/// its margins, at least the minimum size, over the background.
struct HostingConfigurationRoot<Content, Background>: View where Content: View, Background: View {
    var content: Content
    var background: Background
    var margins: EdgeInsets
    var minWidth: CGFloat?
    var minHeight: CGFloat?

    var body: some View {
        content
            .padding(margins)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .background(background)
    }
}

/// The view a hosting configuration makes: a hosting view filling it.
final class HostingConfigurationContentView<Content, Background>: UIView, UIContentView where Content: View, Background: View {
    typealias Configuration = UIHostingConfiguration<Content, Background>

    private var hosted: Configuration
    private let host: _UIHostingView<HostingConfigurationRoot<Content, Background>>
    /// The margins the hosted root was last made with.
    private var appliedMargins: EdgeInsets

    init(configuration: Configuration) {
        let margins = configuration.insets.resolved(defaults: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        hosted = configuration
        appliedMargins = margins
        host = _UIHostingView(rootView: HostingConfigurationContentView.root(configuration, margins: margins))
        super.init(frame: .zero)
        host.frame = bounds
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(host)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private static func root(_ configuration: Configuration, margins: EdgeInsets) -> HostingConfigurationRoot<Content, Background> {
        HostingConfigurationRoot(
            content: configuration.content,
            background: configuration.background,
            margins: margins,
            minWidth: configuration.minWidth,
            minHeight: configuration.minHeight
        )
    }

    /// The margins for the edges the configuration leaves alone: those of
    /// the view this one is in, a cell's content view, or its own.
    private var defaultMargins: EdgeInsets {
        let margins = (superview ?? self).layoutMargins
        return EdgeInsets(top: margins.top, leading: margins.left, bottom: margins.bottom, trailing: margins.right)
    }

    /// Hosts the configuration again when it or the margins have changed.
    private func updateRoot(configurationChanged: Bool = false) {
        let margins = hosted.insets.resolved(defaults: defaultMargins)
        guard configurationChanged || margins != appliedMargins else { return }
        appliedMargins = margins
        host.rootView = Self.root(hosted, margins: margins)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    // MARK: UIContentView

    var configuration: any UIContentConfiguration {
        get { hosted }
        set {
            guard let configuration = newValue as? Configuration else { return }
            hosted = configuration
            updateRoot(configurationChanged: true)
        }
    }

    func supports(_ configuration: any UIContentConfiguration) -> Bool {
        configuration is Configuration
    }

    // MARK: Layout

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        updateRoot()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateRoot()
    }

    /// The hosted content's size for a size offered, where a dimension of
    /// zero or less, or one too large to be meant, asks for the content's
    /// own.
    private func fittingSize(_ size: CGSize) -> CGSize {
        let unbounded = CGFloat.greatestFiniteMagnitude
        return host.sizeThatFits(CGSize(
            width: size.width > 0 ? size.width : unbounded,
            height: size.height > 0 ? size.height : unbounded
        ))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        fittingSize(size)
    }

    override var intrinsicContentSize: CGSize {
        fittingSize(CGSize(width: bounds.width, height: 0))
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        fittingSize(targetSize)
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        // A required priority keeps the target's dimension; any other
        // lets the content choose.
        let keepsWidth = horizontalFittingPriority == .required
        let keepsHeight = verticalFittingPriority == .required
        var size = fittingSize(CGSize(
            width: keepsWidth ? targetSize.width : 0,
            height: keepsHeight ? targetSize.height : 0
        ))
        if keepsWidth { size.width = targetSize.width }
        if keepsHeight { size.height = targetSize.height }
        return size
    }
}
#endif
