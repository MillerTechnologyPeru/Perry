//
//  Menu.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Menu, as its label; tapping it presents the menu's items as a
//  confirmation dialog presents its actions, along the bottom of the
//  screen.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

/// A control for presenting a menu of actions.
@available(OpenSwiftUI_v2_0, *)
public struct Menu<Label, Content>: View where Label: View, Content: View {
    var label: Label
    var content: Content
    @State private var isPresented = false

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            label
        }
        .modifier(PresentationModifier(
            isPresented: isPresented, style: .dialog,
            dismiss: { isPresented = false }, onDismiss: nil,
            presented: { ConfirmationDialogView(title: nil, actions: content) }
        ))
    }
}

@available(OpenSwiftUI_v2_0, *)
extension Menu where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S>(_ title: S, @ViewBuilder content: () -> Content) where S: StringProtocol {
        self.init(content: content) { Text(title) }
    }
}
#endif
