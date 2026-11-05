//
//  TextInput.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  TextEditor, as a text field taller than one line, since Perry's
//  UITextView doesn't edit yet; and the keyboard type and text content
//  type text fields take from the environment.

#if os(iOS) || os(visionOS)
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
#endif
