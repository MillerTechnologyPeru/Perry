//
//  TextInput.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  TextEditor, as a text field taller than one line, since Perry's
//  UITextView doesn't edit yet; the keyboard type and text content type
//  text fields take from the environment; submit labels, which the return
//  key doesn't show yet; and text fields that grow along an axis, which
//  stay one line, or that edit a formatted value.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore
public import UIKit

// MARK: - TextEditor

/// A view that can display and edit long-form text.
@available(OpenSwiftUI_v2_0, *)
public struct TextEditor: View {
    var text: Binding<String>

    public init(text: Binding<String>) {
        self.text = text
    }

    public var body: some View {
        PlatformTextField(text: text, placeholder: nil)
            .frame(minHeight: 34, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Keyboard and content types

struct KeyboardTypeKey: EnvironmentKey {
    static let defaultValue: UIKeyboardType = .default
}

struct TextContentTypeKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var keyboardType: UIKeyboardType {
        get { self[KeyboardTypeKey.self] }
        set { self[KeyboardTypeKey.self] = newValue }
    }

    /// The semantic meaning of text fields' content, as a
    /// UITextContentType's raw value.
    @usableFromInline
    var textContentType: String? {
        get { self[TextContentTypeKey.self] }
        set { self[TextContentTypeKey.self] = newValue }
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the keyboard type for this view.
    nonisolated public func keyboardType(_ type: UIKeyboardType) -> some View {
        environment(\.keyboardType, type)
    }

    /// Sets the text content type for this view, which the system uses to
    /// offer suggestions while the user enters text on an iOS or tvOS
    /// device.
    @inlinable
    nonisolated public func textContentType(_ textContentType: UITextContentType?) -> some View {
        environment(\.textContentType, textContentType?.rawValue)
    }
}

// MARK: - Submit labels

/// A semantic label describing the label of submission within a view
/// hierarchy.
@available(OpenSwiftUI_v3_0, *)
public struct SubmitLabel: Sendable {
    enum Role: Sendable { case done, go, send, join, route, search, `return`, next, `continue` }
    let role: Role

    public static var done: SubmitLabel { .init(role: .done) }
    public static var go: SubmitLabel { .init(role: .go) }
    public static var send: SubmitLabel { .init(role: .send) }
    public static var join: SubmitLabel { .init(role: .join) }
    public static var route: SubmitLabel { .init(role: .route) }
    public static var search: SubmitLabel { .init(role: .search) }
    public static var `return`: SubmitLabel { .init(role: .return) }
    public static var next: SubmitLabel { .init(role: .next) }
    public static var `continue`: SubmitLabel { .init(role: .continue) }
}

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Sets the submit label for this view.
    nonisolated public func submitLabel(_ submitLabel: SubmitLabel) -> some View {
        self
    }
}

// MARK: - Text fields along an axis, and of formatted values

@available(OpenSwiftUI_v4_0, *)
extension TextField where Label == Text {
    /// Creates a text field with a preferred axis: one line here.
    nonisolated public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil, axis: Axis) {
        self.init(titleKey, text: text, prompt: prompt)
    }

    /// Creates a text field with a preferred axis: one line here.
    @_disfavoredOverload
    nonisolated public init<S>(_ title: S, text: Binding<String>, prompt: Text? = nil, axis: Axis) where S: StringProtocol {
        self.init(title, text: text)
        self.prompt = prompt
    }
}

@available(OpenSwiftUI_v3_0, *)
extension TextField where Label == Text {
    /// Creates a text field that edits a value, shown in `format`; text
    /// that doesn't parse leaves the value as it was.
    nonisolated public init<F>(_ titleKey: LocalizedStringKey, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil)
    where F: ParseableFormatStyle, F.FormatOutput == String {
        self.init(titleKey, text: TextField.formatted(value, format), prompt: prompt)
    }

    /// Creates a text field that edits a value, shown in `format`.
    @_disfavoredOverload
    nonisolated public init<S, F>(_ title: S, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil)
    where S: StringProtocol, F: ParseableFormatStyle, F.FormatOutput == String {
        self.init(title, text: TextField.formatted(value, format))
        self.prompt = prompt
    }

    /// The text of a value in a format, which sets the value when it parses.
    static func formatted<F>(_ value: Binding<F.FormatInput>, _ format: F) -> Binding<String>
    where F: ParseableFormatStyle, F.FormatOutput == String {
        Binding(
            get: { format.format(value.wrappedValue) },
            set: { text in
                if let parsed = try? format.parseStrategy.parse(text) {
                    value.wrappedValue = parsed
                }
            }
        )
    }
}
#endif
