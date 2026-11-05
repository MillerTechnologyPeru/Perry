//
//  Presentation.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Sheets, full-screen covers, popovers, confirmation dialogs and alerts, presented
//  as UIKit presents view controllers: a hosting controller over the
//  window's topmost one, whose views have the presenting view's
//  environment, with a dismiss action that ends the presentation. Popovers
//  are presented as sheets are, as iPhones adapt them. Pushed navigation
//  pages get a dismiss action that pops them.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore
public import UIKit

// MARK: - DismissAction

/// An action that dismisses a presentation.
@available(OpenSwiftUI_v3_0, *)
@preconcurrency
@MainActor
public struct DismissAction {
    var action: () -> Void

    /// Dismisses the view if it is currently presented.
    public func callAsFunction() {
        action()
    }
}

struct DismissActionKey: EnvironmentKey {
    static let defaultValue: DismissAction? = nil
}

/// An indication whether a view is currently presented by another view.
@available(OpenSwiftUI_v1_0, *)
public struct PresentationMode {
    var isPresentedValue: Bool
    var dismissAction: (() -> Void)?

    /// Indicates whether a view is currently presented.
    public var isPresented: Bool { isPresentedValue }

    /// Dismisses the view if it is currently presented.
    public mutating func dismiss() {
        dismissAction?()
    }
}

@available(OpenSwiftUI_v1_0, *)
extension EnvironmentValues {
    var dismissAction: DismissAction? {
        get { self[DismissActionKey.self] }
        set { self[DismissActionKey.self] = newValue }
    }

    /// An action that dismisses the current presentation.
    @available(OpenSwiftUI_v3_0, *)
    public var dismiss: DismissAction {
        get { self[DismissActionKey.self] ?? DismissAction {} }
    }

    /// A Boolean value that indicates whether the view associated with this
    /// environment is currently presented.
    @available(OpenSwiftUI_v3_0, *)
    public var isPresented: Bool {
        get { self[DismissActionKey.self] != nil }
    }

    /// A binding to the current presentation mode of the view associated
    /// with this environment.
    public var presentationMode: Binding<PresentationMode> {
        get {
            let action = self[DismissActionKey.self]
            let mode = PresentationMode(isPresentedValue: action != nil, dismissAction: action.map { action in
                { MainActor.assumeIsolated { action() } }
            })
            return Binding(get: { mode }, set: { _ in })
        }
    }
}

// MARK: - Presenting

/// How a presentation covers the screen.
enum PresentationStyle {
    case sheet, fullScreenCover, dialog
}

/// Presents its content while presented, from the window this view is in.
struct PresentationModifier<Presented: View>: ViewModifier {
    var isPresented: Bool
    var style: PresentationStyle
    var dismiss: () -> Void
    var onDismiss: (() -> Void)?
    var presented: () -> Presented
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        content.background(PresenterRepresentable(
            isPresented: isPresented,
            style: style,
            content: isPresented ? AnyView(presented()) : nil,
            environment: environment,
            dismiss: dismiss,
            onDismiss: onDismiss
        ))
    }
}

/// An empty view, the anchor a presentation is presented from.
struct PresenterRepresentable: UIViewRepresentable {
    var isPresented: Bool
    var style: PresentationStyle
    var content: AnyView?
    var environment: EnvironmentValues
    var dismiss: () -> Void
    var onDismiss: (() -> Void)?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onDismiss = onDismiss
        if let content, isPresented {
            let root = rootView(content)
            if let controller = coordinator.controller {
                controller.host.inheritedEnvironment = environment
                controller.rootView = root
            } else {
                let controller = UIHostingController(rootView: root)
                controller.host.inheritedEnvironment = environment
                controller.modalPresentationStyle = style == .sheet ? .pageSheet : .overFullScreen
                coordinator.controller = controller
                coordinator.present(controller, from: view)
            }
        } else if coordinator.controller != nil {
            coordinator.dismiss()
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    private func rootView(_ content: AnyView) -> AnyView {
        let dismiss = dismiss
        let view = content
            .environment(\.dismissAction, DismissAction { dismiss() })
        switch style {
        case .sheet, .fullScreenCover:
            return AnyView(view
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(uiColor: .systemBackground)))
        case .dialog:
            return AnyView(view)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var controller: UIHostingController<AnyView>?
        var onDismiss: (() -> Void)?

        /// Presents from the window's topmost view controller, once the
        /// view is in a window.
        func present(_ controller: UIViewController, from view: UIView, attempts: Int = 20) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, self.controller === controller, let view else { return }
                guard var top = view.window?.rootViewController else {
                    if attempts > 0 { self.present(controller, from: view, attempts: attempts - 1) }
                    return
                }
                while let presented = top.presentedViewController, presented !== controller {
                    top = presented
                }
                if top !== controller {
                    top.present(controller, animated: true)
                }
            }
        }

        func dismiss() {
            guard let controller else { return }
            self.controller = nil
            let onDismiss = onDismiss
            if controller.presentingViewController != nil {
                controller.dismiss(animated: true) { onDismiss?() }
            } else {
                onDismiss?()
            }
        }
    }
}

// MARK: - sheet and fullScreenCover

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Presents a sheet when a binding to a Boolean value that you provide
    /// is true.
    nonisolated public func sheet<Content>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View where Content: View {
        modifier(PresentationModifier(
            isPresented: isPresented.wrappedValue, style: .sheet,
            dismiss: { isPresented.wrappedValue = false }, onDismiss: onDismiss, presented: content
        ))
    }

    /// Presents a sheet using the given item as a data source for the
    /// sheet's content.
    nonisolated public func sheet<Item, Content>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View where Item: Identifiable, Content: View {
        modifier(PresentationModifier(
            isPresented: item.wrappedValue != nil, style: .sheet,
            dismiss: { item.wrappedValue = nil }, onDismiss: onDismiss,
            presented: { item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView()) }
        ))
    }

    /// Presents a modal view that covers as much of the screen as possible
    /// when binding to a Boolean value you provide is true.
    nonisolated public func fullScreenCover<Content>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View where Content: View {
        modifier(PresentationModifier(
            isPresented: isPresented.wrappedValue, style: .fullScreenCover,
            dismiss: { isPresented.wrappedValue = false }, onDismiss: onDismiss, presented: content
        ))
    }

    /// Presents a modal view that covers as much of the screen as possible
    /// using the binding you provide as a data source for the sheet's
    /// content.
    nonisolated public func fullScreenCover<Item, Content>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View where Item: Identifiable, Content: View {
        modifier(PresentationModifier(
            isPresented: item.wrappedValue != nil, style: .fullScreenCover,
            dismiss: { item.wrappedValue = nil }, onDismiss: onDismiss,
            presented: { item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView()) }
        ))
    }

    /// Conditionally prevents interactive dismissal of presentations like
    /// popovers, sheets, and inspectors; they have none here.
    nonisolated public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View {
        self
    }
}

// MARK: - Popovers

/// An attachment anchor for a popover.
@available(OpenSwiftUI_v1_0, *)
public enum PopoverAttachmentAnchor {
    /// The anchor point for the popover relative to the source's frame.
    case rect(Anchor<CGRect>.Source)
    /// The anchor point for the popover expressed as a unit point that
    /// describes possible alignments relative to a OpenSwiftUI view.
    case point(UnitPoint)
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Presents a popover when a given condition is true: here, as a sheet.
    nonisolated public func popover<Content>(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View where Content: View {
        popoverCore(isPresented: isPresented, attachmentAnchor: attachmentAnchor,
                    arrowEdges: arrowEdge.map { Edge.Set($0) }, isDetachable: false, content: content)
    }

    @usableFromInline
    nonisolated func popover<Content>(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View where Content: View {
        popoverCore(isPresented: isPresented, attachmentAnchor: attachmentAnchor,
                    arrowEdges: Edge.Set(arrowEdge), isDetachable: false, content: content)
    }

    @usableFromInline
    nonisolated func popover<Content>(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        @ViewBuilder content: @escaping () -> Content
    ) -> some View where Content: View {
        popoverCore(isPresented: isPresented, attachmentAnchor: attachmentAnchor,
                    arrowEdges: nil, isDetachable: false, content: content)
    }

    @usableFromInline
    nonisolated func popoverCore<Content>(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor,
        arrowEdges: Edge.Set?,
        isDetachable: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View where Content: View {
        sheet(isPresented: isPresented, content: content)
    }

    @usableFromInline
    nonisolated func popoverCore<Item, Content>(
        item: Binding<Item?>,
        attachmentAnchor: PopoverAttachmentAnchor,
        arrowEdges: Edge.Set?,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View where Item: Identifiable, Content: View {
        sheet(item: item, content: content)
    }
}

// MARK: - Detents and adaptations

/// A type that represents a height where a sheet naturally rests.
@available(OpenSwiftUI_v4_0, *)
public struct PresentationDetent: Hashable, Sendable {
    enum Identifier: Hashable, Sendable {
        case medium, large, fraction(CGFloat), height(CGFloat)
    }

    var identifier: Identifier

    public static let medium = PresentationDetent(identifier: .medium)
    public static let large = PresentationDetent(identifier: .large)

    public static func fraction(_ fraction: CGFloat) -> PresentationDetent {
        PresentationDetent(identifier: .fraction(fraction))
    }

    public static func height(_ height: CGFloat) -> PresentationDetent {
        PresentationDetent(identifier: .height(height))
    }
}

/// Strategies for adapting a presentation to a different size class.
@available(OpenSwiftUI_v4_0, *)
public struct PresentationAdaptation: Sendable {
    enum Kind: Sendable { case automatic, none, popover, sheet, fullScreenCover }
    var kind: Kind

    public static var automatic: PresentationAdaptation { PresentationAdaptation(kind: .automatic) }
    public static var none: PresentationAdaptation { PresentationAdaptation(kind: .none) }
    public static var popover: PresentationAdaptation { PresentationAdaptation(kind: .popover) }
    public static var sheet: PresentationAdaptation { PresentationAdaptation(kind: .sheet) }
    public static var fullScreenCover: PresentationAdaptation { PresentationAdaptation(kind: .fullScreenCover) }
}

@available(OpenSwiftUI_v4_0, *)
extension View {
    /// Sets the available detents for the enclosing sheet; sheets take the
    /// screen here.
    nonisolated public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        self
    }

    /// Sets the available detents for the enclosing sheet, with a binding
    /// to the selected one.
    nonisolated public func presentationDetents(_ detents: Set<PresentationDetent>, selection: Binding<PresentationDetent>) -> some View {
        self
    }

    /// Specifies how to adapt a presentation to compact size classes.
    nonisolated public func presentationCompactAdaptation(_ adaptation: PresentationAdaptation) -> some View {
        self
    }
}

// MARK: - confirmationDialog

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Presents a confirmation dialog when a given condition is true: the
    /// title and the actions along the bottom of the screen, over a dimmed
    /// background, with a cancel button.
    nonisolated public func confirmationDialog<A>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> A
    ) -> some View where A: View {
        let actions = actions()
        let title = titleVisibility == .visible ? Text(titleKey) : nil
        return modifier(PresentationModifier(
            isPresented: isPresented.wrappedValue, style: .dialog,
            dismiss: { isPresented.wrappedValue = false }, onDismiss: nil,
            presented: { ConfirmationDialogView(title: title, actions: actions) }
        ))
    }

    nonisolated public func confirmationDialog<S, A>(
        _ title: S,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> A
    ) -> some View where S: StringProtocol, A: View {
        let actions = actions()
        let title = titleVisibility == .visible ? Text(title) : nil
        return modifier(PresentationModifier(
            isPresented: isPresented.wrappedValue, style: .dialog,
            dismiss: { isPresented.wrappedValue = false }, onDismiss: nil,
            presented: { ConfirmationDialogView(title: title, actions: actions) }
        ))
    }
}

/// A dialog's actions in a card along the bottom; tapping any of them, or
/// outside, dismisses it.
struct ConfirmationDialogView<Actions: View>: View {
    var title: Text?
    var actions: Actions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                if let title {
                    title
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(14)
                    Divider()
                }
                _VariadicView.Tree(DialogActionsRoot()) { actions }
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(14)
            .simultaneousGesture(TapGesture().onEnded { dismiss() })
            Button { dismiss() } label: {
                Text("Cancel").fontWeight(.semibold).frame(maxWidth: .infinity).padding(16)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(14)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3).onTapGesture { dismiss() })
    }
}

/// The dialog's actions, a row each, between dividers.
struct DialogActionsRoot: _VariadicView.UnaryViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                    .frame(maxWidth: .infinity)
                    .padding(16)
                if child.id != children.last?.id {
                    Divider()
                }
            }
        }
    }
}

// MARK: - alert

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Presents an alert with a message when a given condition is true.
    @_disfavoredOverload
    nonisolated public func alert<S, A, M>(
        _ title: S,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> A,
        @ViewBuilder message: () -> M
    ) -> some View where S: StringProtocol, A: View, M: View {
        alert(title: Text(title), isPresented: isPresented, actions: actions(), message: message())
    }

    /// Presents an alert with a message when a given condition is true.
    nonisolated public func alert<A, M>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> A,
        @ViewBuilder message: () -> M
    ) -> some View where A: View, M: View {
        alert(title: Text(titleKey), isPresented: isPresented, actions: actions(), message: message())
    }

    /// Presents an alert using the given data to produce its actions and
    /// message.
    nonisolated public func alert<A, M, T>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: (T) -> A,
        @ViewBuilder message: (T) -> M
    ) -> some View where A: View, M: View {
        let shown = data.map { (actions($0), message($0)) }
        return alert(title: Text(titleKey), isPresented: Binding(
            get: { isPresented.wrappedValue && shown != nil },
            set: { isPresented.wrappedValue = $0 }
        ), actions: shown?.0, message: shown?.1)
    }

    /// Presents an alert when a given condition is true.
    nonisolated public func alert<A>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> A
    ) -> some View where A: View {
        alert(title: Text(titleKey), isPresented: isPresented, actions: actions(), message: EmptyView?.none)
    }

    /// Presents an alert when a given condition is true.
    @_disfavoredOverload
    nonisolated public func alert<S, A>(
        _ title: S,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> A
    ) -> some View where S: StringProtocol, A: View {
        alert(title: Text(title), isPresented: isPresented, actions: actions(), message: EmptyView?.none)
    }

    nonisolated func alert<A: View, M: View>(title: Text, isPresented: Binding<Bool>, actions: A?, message: M?) -> some View {
        modifier(PresentationModifier(
            isPresented: isPresented.wrappedValue, style: .dialog,
            dismiss: { isPresented.wrappedValue = false }, onDismiss: nil,
            presented: { AlertView(title: title, message: message, actions: actions) }
        ))
    }
}

/// An alert: its title, message and actions in a card in the middle of the
/// screen, over a dimmed background; an OK button when it has no actions.
/// Tapping an action dismisses it.
struct AlertView<Actions: View, Message: View>: View {
    var title: Text
    var message: Message?
    var actions: Actions?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                title.font(.headline).multilineTextAlignment(.center)
                if let message {
                    message.font(.footnote).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            Divider()
            Group {
                if let actions {
                    _VariadicView.Tree(DialogActionsRoot()) { actions }
                } else {
                    Button { dismiss() } label: {
                        Text("OK").fontWeight(.semibold).frame(maxWidth: .infinity).padding(14)
                    }
                }
            }
            .simultaneousGesture(TapGesture().onEnded { dismiss() })
        }
        .frame(width: 270)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
    }
}

// MARK: - presentationBackground

@available(OpenSwiftUI_v4_0, *)
extension View {
    /// Sets the presentation background of the enclosing sheet using a
    /// shape style: behind this view, the sheet's content.
    nonisolated public func presentationBackground<S>(_ style: S) -> some View where S: ShapeStyle {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Rectangle().fill(style).ignoresSafeArea())
    }

    /// Sets the presentation background of the enclosing sheet to a custom
    /// view.
    nonisolated public func presentationBackground<V>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View where V: View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(content().ignoresSafeArea(), alignment: alignment)
    }
}
#endif
