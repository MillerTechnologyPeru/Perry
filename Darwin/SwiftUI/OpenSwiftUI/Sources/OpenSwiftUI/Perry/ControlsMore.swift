//
//  ControlsMore.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  More controls and their styles: buttons labelled by their role, the
//  prominent glass button style, menus with a primary action, command
//  menus, control groups, and form styles. A button made from a role alone
//  is labelled with a word for the role, where iOS may draw a symbol. The
//  prominent glass style is the bordered prominent one. A menu with a
//  primary action opens on a tap as any menu does here, and the primary
//  action is not run. Command menus add nothing, as there is no menu bar.
//  A control group lays its controls out in a row, and a form is always
//  grouped: neither asks its style for a body, so the styles' bodies and
//  configurations are there for apps that name them, and draw nothing.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - Buttons labelled by their role

@available(OpenSwiftUI_v1_0, *)
extension Button where Label == DefaultButtonLabel {
    /// Creates a button whose label follows from its role.
    @preconcurrency
    nonisolated public init(role: ButtonRole, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) {
            DefaultButtonLabel(role: role)
        }
    }
}

/// The label of a button made from a role alone: a word for the role, in
/// English.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct DefaultButtonLabel: View {
    var role: ButtonRole?

    nonisolated public var body: some View {
        Text(verbatim: title)
    }

    private var title: String {
        if role == .cancel {
            "Cancel"
        } else if role == .destructive {
            "Delete"
        } else if role == .confirm {
            "Done"
        } else if role == .close {
            "Close"
        } else {
            ""
        }
    }
}

@available(*, unavailable)
extension DefaultButtonLabel: Sendable {}

// MARK: - Prominent glass buttons

/// A button style of tinted Liquid Glass. Here it is the bordered prominent
/// style: the button's tint as a filled background.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct GlassProminentButtonStyle: PrimitiveButtonStyle {
    /// Creates a prominent glass button style.
    nonisolated public init() {}

    nonisolated public func makeBody(configuration: GlassProminentButtonStyle.Configuration) -> some View {
        Button(configuration)
            .buttonStyle(BorderedProminentButtonStyle())
    }
}

@available(*, unavailable)
extension GlassProminentButtonStyle: Sendable {}

// MARK: - Menus

@available(OpenSwiftUI_v1_0, *)
extension Menu {
    /// Creates a menu with a primary action, which iOS runs on a tap,
    /// opening the menu on a long press. Here a tap opens the menu, and the
    /// primary action is not run.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label,
        primaryAction: @escaping () -> Void
    ) {
        self.init(content: content, label: label)
    }
}

@available(OpenSwiftUI_v1_0, *)
extension Menu where Label == MenuStyleConfiguration.Label, Content == MenuStyleConfiguration.Content {
    /// Creates a menu from a style's configuration, for a style that
    /// changes another. Menus draw themselves here and call no style, so
    /// nothing makes a configuration to pass in.
    public init(_ configuration: MenuStyleConfiguration) {
        self.init(content: { configuration.content }, label: { configuration.label })
    }
}

// MARK: - Command menus

/// A menu of commands in the app's menu bar. Perry has no menu bar and
/// reads no key commands from it: a command menu adds nothing, and its
/// content is kept but not shown.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct CommandMenu<Content>: Commands where Content: View {
    var name: Text
    var content: Content

    nonisolated public static func _makeCommands(content: _GraphValue<CommandMenu<Content>>, inputs: _CommandsInputs) -> _CommandsOutputs {
        .init()
    }

    /// Creates a command menu with the given name and commands.
    nonisolated public init(_ name: Text, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }

    nonisolated public var body: some Commands {
        EmptyCommands()
    }

    nonisolated public func _resolve(into resolved: inout _ResolvedCommands) {}
}

@available(*, unavailable)
extension CommandMenu: Sendable {}

// MARK: - Control groups

/// A type that draws the control groups in a view hierarchy. Perry's
/// control groups draw themselves and don't ask a style.
@available(OpenSwiftUI_v1_0, *)
@preconcurrency
@MainActor
public protocol ControlGroupStyle {
    /// The view a control group of this style shows.
    associatedtype Body: View

    /// Makes the view for a control group.
    @ViewBuilder
    @MainActor
    @preconcurrency
    func makeBody(configuration: Self.Configuration) -> Self.Body

    /// The properties of a control group.
    typealias Configuration = ControlGroupStyleConfiguration
}

/// The properties of a control group: stand-ins for its controls and its
/// label, which draw nothing as no control group resolves them.
@available(OpenSwiftUI_v1_0, *)
public struct ControlGroupStyleConfiguration {
    /// The controls of the group.
    @MainActor
    @preconcurrency
    public struct Content: ViewAlias {
        nonisolated init() {}
    }

    /// The controls of the group.
    public let content: ControlGroupStyleConfiguration.Content

    /// The label of the group.
    @MainActor
    @preconcurrency
    public struct Label: ViewAlias {
        nonisolated init() {}
    }

    /// The label of the group.
    public let label: ControlGroupStyleConfiguration.Label

    nonisolated init() {
        content = Content()
        label = Label()
    }
}

@available(*, unavailable)
extension ControlGroupStyleConfiguration: Sendable {}

@available(*, unavailable)
extension ControlGroupStyleConfiguration.Content: Sendable {}

@available(*, unavailable)
extension ControlGroupStyleConfiguration.Label: Sendable {}

/// Controls that belong together, drawn as one unit: here, side by side in
/// a row.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct ControlGroup<Content>: View where Content: View {
    var content: Content

    /// Creates a group of the given controls.
    nonisolated public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    nonisolated public var body: some View {
        HStack {
            content
        }
    }
}

@available(*, unavailable)
extension ControlGroup: Sendable {}

/// A control group style that shows its controls as a palette. No control
/// group asks it for a body here; the body is the configuration's content.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct PaletteControlGroupStyle: ControlGroupStyle {
    /// Creates a palette control group style.
    nonisolated public init() {}

    nonisolated public func makeBody(configuration: PaletteControlGroupStyle.Configuration) -> some View {
        configuration.content
    }
}

@available(*, unavailable)
extension PaletteControlGroupStyle: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the style of control groups in this view; Perry's control
    /// groups are rows whatever the style.
    nonisolated public func controlGroupStyle<S>(_ style: S) -> some View where S: ControlGroupStyle {
        self
    }
}

// MARK: - Form styles

/// A type that draws the forms in a view hierarchy. Perry's forms draw
/// themselves, grouped, and don't ask a style.
@available(OpenSwiftUI_v1_0, *)
@preconcurrency
@MainActor
public protocol FormStyle {
    /// The view a form of this style shows.
    associatedtype Body: View

    /// Makes the view for a form.
    @ViewBuilder
    @MainActor
    @preconcurrency
    func makeBody(configuration: Self.Configuration) -> Self.Body

    /// The properties of a form.
    typealias Configuration = FormStyleConfiguration
}

/// The properties of a form: a stand-in for its content, which draws
/// nothing as no form resolves it.
@available(OpenSwiftUI_v1_0, *)
public struct FormStyleConfiguration {
    /// The content of the form.
    @MainActor
    @preconcurrency
    public struct Content: ViewAlias {
        nonisolated init() {}
    }

    /// The content of the form.
    public let content: FormStyleConfiguration.Content

    nonisolated init() {
        content = Content()
    }
}

@available(*, unavailable)
extension FormStyleConfiguration: Sendable {}

@available(*, unavailable)
extension FormStyleConfiguration.Content: Sendable {}

/// A form style with grouped rows, which is how every form is drawn here.
/// No form asks it for a body; the body is the configuration's content.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct GroupedFormStyle: FormStyle {
    /// Creates a grouped form style.
    nonisolated public init() {}

    nonisolated public func makeBody(configuration: GroupedFormStyle.Configuration) -> some View {
        configuration.content
    }
}

@available(*, unavailable)
extension GroupedFormStyle: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension FormStyle where Self == GroupedFormStyle {
    /// A form style with grouped rows.
    nonisolated public static var grouped: GroupedFormStyle {
        GroupedFormStyle()
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the style of forms in this view; Perry's forms are grouped
    /// whatever the style.
    nonisolated public func formStyle<S>(_ style: S) -> some View where S: FormStyle {
        self
    }
}

#endif
