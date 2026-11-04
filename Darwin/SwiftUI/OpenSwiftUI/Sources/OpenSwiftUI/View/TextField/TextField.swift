//
//  TextField.swift
//  OpenSwiftUI
//
//  Audited for 6.5.4
//  Status: Stub

public import Foundation
public import OpenSwiftUICore

// MARK: - TextField [TBA]

@available(OpenSwiftUI_v1_0, *)
public struct TextField<Label>: View where Label: View {
    var text: Binding<String>
    var label: Label
    var prompt: Text?

    public var body: some View {
        #if os(iOS) || os(visionOS)
        PlatformTextField(text: text, placeholder: prompt ?? (label as? Text))
            .frame(minHeight: 34)
        #else
        _openSwiftUIUnimplementedFailure()
        #endif
    }
}

// MARK: - TextField + Text

extension TextField where Label == Text {
    @available(OpenSwiftUI_v3_0, *)
    nonisolated public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) {
        self.text = text
        self.label = Text(titleKey)
        self.prompt = prompt
    }

    nonisolated public init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.init(titleKey, text: text, prompt: nil)
    }

    @_disfavoredOverload
    nonisolated public init<S>(_ title: S, text: Binding<String>) where S: StringProtocol {
        self.text = text
        self.label = Text(title)
        self.prompt = nil
    }
}

@available(*, unavailable)
extension TextField: Sendable {}

// MARK: - TextField + Format [TBA]

extension TextField {
    @available(OpenSwiftUI_v3_0, *)
    nonisolated public init<F>(
        value: Binding<F.FormatInput>,
        format: F,
        prompt: Text? = nil,
        @ViewBuilder label: () -> Label
    ) where F: ParseableFormatStyle, F.FormatOutput == String {
        _openSwiftUIUnimplementedFailure()
    }
}
