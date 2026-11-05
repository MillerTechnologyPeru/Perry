//
//  PlatformTextField.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  TextField's editor: a UITextField, kept in step with the text binding,
//  with the keyboard the environment asks for, telling the field when
//  editing begins and ends and when return is pressed.

#if os(iOS) || os(visionOS)
import OpenSwiftUICore
import UIKit

struct PlatformTextField: UIViewRepresentable {
    var text: Binding<String>
    var placeholder: Text?
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onCommit: () -> Void = {}
    @Environment(\.self) private var environment

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        let coordinator = context.coordinator
        field.addTarget(coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.addTarget(coordinator, action: #selector(Coordinator.editingDidBegin(_:)), for: .editingDidBegin)
        field.addTarget(coordinator, action: #selector(Coordinator.editingDidEnd(_:)), for: .editingDidEnd)
        field.addTarget(coordinator, action: #selector(Coordinator.editingDidEndOnExit(_:)), for: .editingDidEndOnExit)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = text
        coordinator.onEditingChanged = onEditingChanged
        coordinator.onCommit = onCommit
        if field.text != text.wrappedValue {
            field.text = text.wrappedValue
        }
        let placeholder = placeholder?._resolveText(in: environment)
        if field.placeholder != placeholder {
            field.placeholder = placeholder
        }
        if field.keyboardType != environment.keyboardType {
            field.keyboardType = environment.keyboardType
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: text) }

    final class Coordinator: NSObject {
        var text: Binding<String>
        var onEditingChanged: (Bool) -> Void = { _ in }
        var onCommit: () -> Void = {}

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func editingChanged(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }

        @objc func editingDidBegin(_ field: UITextField) {
            onEditingChanged(true)
        }

        @objc func editingDidEnd(_ field: UITextField) {
            onEditingChanged(false)
        }

        @objc func editingDidEndOnExit(_ field: UITextField) {
            onCommit()
        }
    }
}
#endif
