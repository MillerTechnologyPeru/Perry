//
//  PresentationOptions.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, mostly inert
//
//  Options of presentations, and more ways to present dialogs. Perry's
//  sheets take the screen, with square corners and no drag indicator, so
//  sizings, custom detents, the corner radius and the indicator's
//  visibility are taken and ignored; no sizing is ever asked for a size and
//  no custom detent for a height. Alerts and confirmation dialogs titled
//  with a `Text` are presented as the ones titled with a string are; a
//  confirmation dialog's message is the first row of its card. Popovers for
//  an item are sheets, as the other popovers.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore

// MARK: - PresentationSizing

/// A type that says how large a presentation, such as a sheet, should be.
@available(OpenSwiftUI_v1_0, *)
public protocol PresentationSizing {
    /// The size to propose to the presentation's content.
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize
}

/// The content of a presentation that a sizing measures. Nothing makes one
/// here.
@available(OpenSwiftUI_v1_0, *)
public struct PresentationSizingRoot {
}

@available(*, unavailable)
extension PresentationSizingRoot: Sendable {}

/// What a sizing knows about where its presentation is shown. Nothing makes
/// one here.
@available(OpenSwiftUI_v1_0, *)
public struct PresentationSizingContext {
}

@available(*, unavailable)
extension PresentationSizingContext: Sendable {}

/// The sizing of forms: on larger screens, a sheet narrower than a page.
/// It proposes no size here.
@available(OpenSwiftUI_v1_0, *)
public struct FormPresentationSizing: PresentationSizing, Sendable {
    public func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        .unspecified
    }
}

@available(OpenSwiftUI_v1_0, *)
extension PresentationSizing where Self == FormPresentationSizing {
    /// The sizing of forms.
    public static var form: FormPresentationSizing {
        FormPresentationSizing()
    }
}

/// The sizing of pages: on larger screens, a sheet about as large as a page
/// of text. It proposes no size here.
@available(OpenSwiftUI_v1_0, *)
public struct PagePresentationSizing: PresentationSizing, Sendable {
    public func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        .unspecified
    }
}

@available(OpenSwiftUI_v1_0, *)
extension PresentationSizing where Self == PagePresentationSizing {
    /// The sizing of pages.
    public static var page: PagePresentationSizing {
        PagePresentationSizing()
    }
}

/// The sizing the system picks for a presentation. It proposes no size
/// here.
@available(OpenSwiftUI_v1_0, *)
public struct AutomaticPresentationSizing: PresentationSizing, Sendable {
    public func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        .unspecified
    }
}

@available(OpenSwiftUI_v1_0, *)
extension PresentationSizing where Self == AutomaticPresentationSizing {
    /// The sizing the system picks.
    public static var automatic: AutomaticPresentationSizing {
        AutomaticPresentationSizing()
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the sizing of the presentation this view is the content of;
    /// Perry's sheets take the screen whatever the sizing.
    nonisolated public func presentationSizing(_ sizing: some PresentationSizing) -> some View {
        self
    }
}

// MARK: - Custom detents

/// A type that works out the height of a detent of its own.
@available(OpenSwiftUI_v1_0, *)
public protocol CustomPresentationDetent {
    /// The height of the detent in the given context, or nil where the
    /// detent doesn't apply.
    static func height(in context: Self.Context) -> CGFloat?
}

@available(OpenSwiftUI_v1_0, *)
extension CustomPresentationDetent {
    public typealias Context = PresentationDetent.Context
}

@available(OpenSwiftUI_v1_0, *)
extension PresentationDetent {
    /// What a custom detent may read to work out its height: the tallest a
    /// sheet can be, and the environment of the sheet. Perry's sheets don't
    /// rest at detents, so nothing makes one here.
    @dynamicMemberLookup
    public struct Context {
        var maximumHeight: CGFloat
        var environment: EnvironmentValues

        /// The height of the tallest detent a sheet may rest at.
        public var maxDetentValue: CGFloat {
            maximumHeight
        }

        /// A value of the sheet's environment.
        public subscript<T>(dynamicMember keyPath: KeyPath<EnvironmentValues, T>) -> T {
            environment[keyPath: keyPath]
        }
    }

    /// A detent whose height the given type works out. It is told apart
    /// from other detents by the type; its height is never asked for.
    public static func custom<D>(_ type: D.Type) -> PresentationDetent where D: CustomPresentationDetent {
        PresentationDetent(identifier: .custom(ObjectIdentifier(type)))
    }
}

@available(*, unavailable)
extension PresentationDetent.Context: Sendable {}

// MARK: - Corner radius and drag indicator

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Shows or hides the indicator along the top of a sheet that tells it
    /// can be dragged; Perry's sheets draw none.
    nonisolated public func presentationDragIndicator(_ visibility: Visibility) -> some View {
        self
    }

    /// Rounds the corners of the presentation; Perry's sheets take the
    /// screen with square corners.
    nonisolated public func presentationCornerRadius(_ cornerRadius: CGFloat?) -> some View {
        self
    }
}

// MARK: - Alerts titled with a Text

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Presents an alert with a message, its actions and message made from
    /// the given data: only while there is data.
    nonisolated public func alert<A, M, T>(
        _ title: Text,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: (T) -> A,
        @ViewBuilder message: (T) -> M
    ) -> some View where A: View, M: View {
        let shown = data.map { (actions($0), message($0)) }
        return alert(title: title, isPresented: Binding(
            get: { isPresented.wrappedValue && shown != nil },
            set: { isPresented.wrappedValue = $0 }
        ), actions: shown?.0, message: shown?.1)
    }
}

// MARK: - Confirmation dialogs with a message

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Presents a confirmation dialog with a message when a given condition
    /// is true.
    nonisolated public func confirmationDialog<A, M>(
        _ title: Text,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> A,
        @ViewBuilder message: () -> M
    ) -> some View where A: View, M: View {
        messagedConfirmationDialog(
            title: titleVisibility == .visible ? title : nil,
            isPresented: isPresented.wrappedValue,
            dismiss: { isPresented.wrappedValue = false },
            actions: actions(),
            message: message()
        )
    }

    /// Presents a confirmation dialog with a message, its actions and
    /// message made from the given data: only while there is data.
    nonisolated public func confirmationDialog<A, M, T>(
        _ title: Text,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        presenting data: T?,
        @ViewBuilder actions: (T) -> A,
        @ViewBuilder message: (T) -> M
    ) -> some View where A: View, M: View {
        messagedConfirmationDialog(
            title: titleVisibility == .visible ? title : nil,
            isPresented: isPresented.wrappedValue && data != nil,
            dismiss: { isPresented.wrappedValue = false },
            actions: data.map(actions),
            message: data.map(message)
        )
    }

    /// The dialog's card along the bottom of the screen: the title, then
    /// the message as the first row, small and gray, then the actions.
    nonisolated func messagedConfirmationDialog<A: View, M: View>(
        title: Text?,
        isPresented: Bool,
        dismiss: @escaping () -> Void,
        actions: A?,
        message: M?
    ) -> some View {
        modifier(PresentationModifier(
            isPresented: isPresented, style: .dialog,
            dismiss: dismiss, onDismiss: nil,
            presented: {
                ConfirmationDialogView(title: title, actions: Group {
                    message.font(.footnote).foregroundColor(.secondary)
                    actions
                })
            }
        ))
    }
}

// MARK: - Popovers for an item

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Presents a popover for an item, its arrow on the given edge: here,
    /// as a sheet.
    @usableFromInline
    nonisolated func popover<Item, Content>(
        item: Binding<Item?>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View where Item: Identifiable, Content: View {
        popoverCore(item: item, attachmentAnchor: attachmentAnchor,
                    arrowEdges: Edge.Set(arrowEdge), content: content)
    }

    /// Presents a popover for an item, its arrow where the system puts it:
    /// here, as a sheet.
    @usableFromInline
    nonisolated func popover<Item, Content>(
        item: Binding<Item?>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View where Item: Identifiable, Content: View {
        popoverCore(item: item, attachmentAnchor: attachmentAnchor,
                    arrowEdges: nil, content: content)
    }
}

#endif
