//
//  AttributedTextEditing.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  Text input beyond the plain text field: secure fields, which are text
//  fields that hide what is typed; more of the text field's initializers,
//  whose fields stay one line whatever axis they are given; and editing
//  attributed text. Perry's editor edits plain text, so a text editor
//  on an attributed string shows and edits its characters, a selection
//  holds nothing and is never written, formatting definitions are taken
//  and constrain nothing, and no formatting controls are shown.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore

// MARK: - SecureField

/// A control into which people securely enter private text.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct SecureField<Label>: View where Label: View {
    var text: Binding<String>
    var label: Label
    var prompt: Text?
    var onCommit: () -> Void

    nonisolated public var body: some View {
        PlatformTextField(
            text: text, placeholder: prompt ?? (label as? Text),
            onCommit: onCommit, isSecure: true
        )
        .frame(minHeight: 34)
    }
}

@available(*, unavailable)
extension SecureField: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension SecureField where Label == Text {
    /// Creates a secure field from a title string, with an action to
    /// perform when the user presses return.
    @_disfavoredOverload
    nonisolated public init<S>(_ title: S, text: Binding<String>, onCommit: @escaping () -> Void) where S: StringProtocol {
        self.text = text
        self.label = Text(title)
        self.prompt = nil
        self.onCommit = onCommit
    }
}

// MARK: - TextField

@available(OpenSwiftUI_v1_0, *)
extension TextField where Label == Text {
    /// Creates a text field with a preferred axis and a title string: one
    /// line here.
    @_disfavoredOverload
    nonisolated public init<S>(_ title: S, text: Binding<String>, axis: Axis) where S: StringProtocol {
        self.init(title, text: text)
    }

    /// Creates a text field with a title string and a prompt.
    @_disfavoredOverload
    nonisolated public init<S>(_ title: S, text: Binding<String>, prompt: Text?) where S: StringProtocol {
        self.init(title, text: text)
        self.prompt = prompt
    }
}

@available(OpenSwiftUI_v1_0, *)
extension TextField {
    /// Creates a text field with a preferred axis, a prompt and a label
    /// view: one line here.
    nonisolated public init(text: Binding<String>, prompt: Text? = nil, axis: Axis, @ViewBuilder label: () -> Label) {
        self.init(text: text, prompt: prompt, label: label)
    }
}

// MARK: - AttributedTextSelection

/// A selection of attributed text. No editor here reports one, so it
/// holds nothing: every selection equals every other.
@available(OpenSwiftUI_v1_0, *)
public struct AttributedTextSelection: Equatable, Sendable {
    /// Creates a selection with nothing selected.
    public init() {}

    public static func == (a: AttributedTextSelection, b: AttributedTextSelection) -> Bool {
        true
    }
}

@available(OpenSwiftUI_v1_0, *)
extension AttributedString {
    /// Changes the text in `body`, keeping `selection` on the same
    /// characters where they remain. The text is changed; the selection,
    /// which holds nothing, is left as it was.
    public mutating func transform<E>(
        updating selection: inout AttributedTextSelection,
        body: (inout AttributedString) throws(E) -> Void
    ) throws(E) where E: Error {
        try body(&self)
    }
}

// MARK: - TextEditor

@available(OpenSwiftUI_v1_0, *)
extension TextEditor {
    /// Creates a styled multiline text editor. It shows and edits the
    /// text's characters: an edit replaces the text, with the attributes
    /// its first run had. The selection binding is neither read nor
    /// written.
    nonisolated public init(text: Binding<AttributedString>, selection: Binding<AttributedTextSelection>? = nil) {
        self.text = Binding<String>(
            get: { String(text.wrappedValue.characters) },
            set: { characters in
                let current = text.wrappedValue
                guard String(current.characters) != characters else { return }
                if let attributes = current.runs.first?.attributes {
                    text.wrappedValue = AttributedString(characters, attributes: attributes)
                } else {
                    text.wrappedValue = AttributedString(characters)
                }
            }
        )
    }
}

// MARK: - Attribute scope

@available(OpenSwiftUI_v1_0, *)
extension AttributeDynamicLookup {
    /// An attribute of SwiftUI's scope, by its name there.
    public subscript<T>(
        dynamicMember keyPath: KeyPath<AttributeScopes.SwiftUIAttributes, T>
    ) -> T where T: AttributedStringKey {
        self[T.self]
    }
}

// MARK: - Formatting definitions

/// A namespace for types related to attributed text formatting
/// definitions.
@available(OpenSwiftUI_v1_0, *)
public enum AttributedTextFormatting {}

@available(*, unavailable)
extension AttributedTextFormatting: Sendable {}

/// A type that says which attributes, and which of their values, the text
/// of an editor may have. Editors here apply no definition. A definition's
/// body is written without a result builder here: one definition, or the
/// empty one.
@available(OpenSwiftUI_v1_0, *)
public protocol AttributedTextFormattingDefinition<Scope> {
    /// The body of the definition.
    associatedtype Body: AttributedTextFormattingDefinition

    /// The attribute scope the definition's attributes come from.
    associatedtype Scope: AttributeScope where Scope == Body.Scope

    /// The definition's constraints.
    var body: Body { get }

    static func _makeDefinition(_ inputs: AttributedTextFormatting._Inputs<Self>) -> AttributedTextFormatting._Outputs<Self>
}

@available(OpenSwiftUI_v1_0, *)
extension AttributedTextFormatting {
    /// Inputs for resolving a definition; nothing resolves one here.
    public struct _Inputs<Definition> {}
}

@available(*, unavailable)
extension AttributedTextFormatting._Inputs: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension AttributedTextFormatting {
    /// Outputs of resolving a definition; empty here.
    public struct _Outputs<Definition> {}
}

@available(*, unavailable)
extension AttributedTextFormatting._Outputs: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension AttributedTextFormattingDefinition {
    /// Resolves nothing.
    public static func _makeDefinition(_ inputs: AttributedTextFormatting._Inputs<Self>) -> AttributedTextFormatting._Outputs<Self> {
        AttributedTextFormatting._Outputs<Self>()
    }
}

@available(OpenSwiftUI_v1_0, *)
extension AttributedTextFormatting {
    /// A definition that allows every attribute of its scope and
    /// constrains none.
    public struct EmptyDefinition<Scope>: AttributedTextFormattingDefinition where Scope: AttributeScope {
        public init() {}

        public static func _makeDefinition(
            _ inputs: AttributedTextFormatting._Inputs<AttributedTextFormatting.EmptyDefinition<Scope>>
        ) -> AttributedTextFormatting._Outputs<AttributedTextFormatting.EmptyDefinition<Scope>> {
            AttributedTextFormatting._Outputs<AttributedTextFormatting.EmptyDefinition<Scope>>()
        }

        public var body: AttributedTextFormatting.EmptyDefinition<Scope> {
            self
        }

        public typealias Body = AttributedTextFormatting.EmptyDefinition<Scope>
    }
}

@available(*, unavailable)
extension AttributedTextFormatting.EmptyDefinition: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Applies a formatting definition to the text editors in this view.
    /// Not applied: editors here keep whatever attributes their text has.
    nonisolated public func attributedTextFormattingDefinition<D>(_ definition: D) -> some View where D: AttributedTextFormattingDefinition {
        self
    }
}

// MARK: - Formatting controls

/// The places a text input's formatting controls can appear in.
@available(OpenSwiftUI_v1_0, *)
public struct TextInputFormattingControlPlacement: Sendable {
    /// A set of formatting control placements.
    public struct Set: OptionSet, Sendable {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        /// Every placement: a bit each for the accessory bar, the context
        /// menu, the input assistant and the font panel.
        public static var all: TextInputFormattingControlPlacement.Set {
            TextInputFormattingControlPlacement.Set(rawValue: 0b1111)
        }
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the visibility of text formatting controls in the given
    /// placements. Perry shows no formatting controls in any of them.
    nonisolated public func textInputFormattingControlVisibility(
        _ visibility: Visibility,
        for placement: TextInputFormattingControlPlacement.Set
    ) -> some View {
        self
    }
}
#endif
