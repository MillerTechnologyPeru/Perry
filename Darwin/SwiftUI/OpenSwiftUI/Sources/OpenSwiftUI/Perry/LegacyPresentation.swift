//
//  LegacyPresentation.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  SwiftUI's first presentation and navigation bar API, which apps still
//  call: Alert and ActionSheet values shown by the newer alert and dialog
//  views, navigationBarTitle and navigationBarItems(leading:), and the
//  text input modifiers UITextField's traits came from, which Perry's
//  hardware-keyboard text fields have no use for.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore
public import UIKit

// MARK: - Alert

/// A representation of an alert presentation.
@available(OpenSwiftUI_v1_0, *)
public struct Alert {
    var title: Text
    var message: Text?
    var buttons: [Button]

    public init(title: Text, message: Text? = nil, dismissButton: Button? = nil) {
        self.title = title
        self.message = message
        self.buttons = dismissButton.map { [$0] } ?? []
    }

    public init(title: Text, message: Text? = nil, primaryButton: Button, secondaryButton: Button) {
        self.title = title
        self.message = message
        self.buttons = [primaryButton, secondaryButton]
    }

    /// A button in an alert or action sheet.
    public struct Button {
        enum Style { case `default`, cancel, destructive }
        var style: Style
        var label: Text
        var action: (() -> Void)?

        public static func `default`(_ label: Text, action: (() -> Void)? = {}) -> Button {
            Button(style: .default, label: label, action: action)
        }

        public static func cancel(_ label: Text, action: (() -> Void)? = {}) -> Button {
            Button(style: .cancel, label: label, action: action)
        }

        public static func cancel(_ action: (() -> Void)? = {}) -> Button {
            Button(style: .cancel, label: Text("Cancel"), action: action)
        }

        public static func destructive(_ label: Text, action: (() -> Void)? = {}) -> Button {
            Button(style: .destructive, label: label, action: action)
        }
    }
}

/// An alert's or action sheet's buttons, as the newer presentations' actions.
struct LegacyButtons: View {
    var buttons: [Alert.Button]

    var body: some View {
        ForEach(buttons.indices, id: \.self) { index in
            let button = buttons[index]
            Button {
                button.action?()
            } label: {
                switch button.style {
                case .cancel: button.label.fontWeight(.semibold)
                case .destructive: button.label.foregroundColor(Color.red)
                case .default: button.label
                }
            }
        }
    }
}

// MARK: - ActionSheet

/// A representation of an action sheet presentation.
@available(OpenSwiftUI_v1_0, *)
public struct ActionSheet {
    var title: Text
    var message: Text?
    var buttons: [Alert.Button]

    public init(title: Text, message: Text? = nil, buttons: [Button] = [.cancel()]) {
        self.title = title
        self.message = message
        self.buttons = buttons
    }

    public typealias Button = Alert.Button
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Presents an alert when a given condition is true.
    nonisolated public func alert(isPresented: Binding<Bool>, content: () -> Alert) -> some View {
        let alert = content()
        return self.alert(title: alert.title, isPresented: isPresented, actions: LegacyButtons(buttons: alert.buttons),
                          message: alert.message)
    }

    /// Presents an alert for the item while it is set.
    nonisolated public func alert<Item>(item: Binding<Item?>, content: (Item) -> Alert) -> some View where Item: Identifiable {
        let alert = item.wrappedValue.map(content)
        return self.alert(title: alert?.title ?? Text(""), isPresented: Binding(
            get: { alert != nil && item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        ), actions: LegacyButtons(buttons: alert?.buttons ?? []), message: alert?.message)
    }

    /// Presents an action sheet when a given condition is true: its title
    /// and buttons as a dialog, with a cancel button.
    nonisolated public func actionSheet(isPresented: Binding<Bool>, content: () -> ActionSheet) -> some View {
        let sheet = content()
        return legacyActionSheet(sheet, isPresented: isPresented)
    }

    /// Presents an action sheet for the item while it is set.
    nonisolated public func actionSheet<T>(item: Binding<T?>, content: (T) -> ActionSheet) -> some View where T: Identifiable {
        let sheet = item.wrappedValue.map(content) ?? ActionSheet(title: Text(""), buttons: [])
        return legacyActionSheet(sheet, isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        ))
    }

    nonisolated func legacyActionSheet(_ sheet: ActionSheet, isPresented: Binding<Bool>) -> some View {
        // The dialog adds its own Cancel.
        let buttons = sheet.buttons.filter { $0.style != .cancel }
        return modifier(PresentationModifier(
            isPresented: isPresented.wrappedValue, style: .dialog,
            dismiss: { isPresented.wrappedValue = false }, onDismiss: nil,
            presented: { ConfirmationDialogView(title: sheet.title, actions: LegacyButtons(buttons: buttons)) }
        ))
    }
}

// MARK: - Navigation bar

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the title and display mode of the navigation bar.
    nonisolated public func navigationBarTitle(_ title: Text, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        navigationTitle(title)
    }

    /// Sets the title of the navigation bar.
    nonisolated public func navigationBarTitle(_ title: Text) -> some View {
        navigationTitle(title)
    }

    /// Sets the title of the navigation bar, from a localized key.
    nonisolated public func navigationBarTitle(_ titleKey: LocalizedStringKey) -> some View {
        navigationTitle(Text(titleKey))
    }

    /// Sets the title of the navigation bar, from a string.
    @_disfavoredOverload
    nonisolated public func navigationBarTitle<S>(_ title: S) -> some View where S: StringProtocol {
        navigationTitle(Text(title))
    }

    /// Sets the title and display mode of the navigation bar, from a
    /// localized key.
    nonisolated public func navigationBarTitle(_ titleKey: LocalizedStringKey, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        navigationTitle(Text(titleKey))
    }

    /// Sets the title and display mode of the navigation bar, from a string.
    @_disfavoredOverload
    nonisolated public func navigationBarTitle<S>(_ title: S, displayMode: NavigationBarItem.TitleDisplayMode) -> some View where S: StringProtocol {
        navigationTitle(Text(title))
    }

    /// Sets the navigation bar items at its leading edge.
    nonisolated public func navigationBarItems<L>(leading: L) -> some View where L: View {
        modifier(NavigationBarItemsModifier(leading: leading, trailing: EmptyView()))
    }
}

// MARK: - Text input traits

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets how text is capitalized as it is typed. Perry's text fields
    /// take hardware keys as typed.
    nonisolated public func autocapitalization(_ style: UITextAutocapitalizationType) -> some View {
        self
    }

    /// Sets whether to correct text as it is typed. Perry corrects none.
    nonisolated public func disableAutocorrection(_ disable: Bool?) -> some View {
        self
    }
}
#endif
