//
//  PlatformTextField.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  TextField's editor: a UITextField, kept in step with the text binding.

#if os(iOS) || os(visionOS)
import OpenSwiftUICore
import UIKit

struct PlatformTextField: UIViewRepresentable {
    var text: Binding<String>
    var placeholder: Text?
    @Environment(\.self) private var environment

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = text
        if field.text != text.wrappedValue {
            field.text = text.wrappedValue
        }
        let placeholder = placeholder?._resolveText(in: environment)
        if field.placeholder != placeholder {
            field.placeholder = placeholder
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: text) }

    final class Coordinator: NSObject {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func editingChanged(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }
    }
}
#endif
