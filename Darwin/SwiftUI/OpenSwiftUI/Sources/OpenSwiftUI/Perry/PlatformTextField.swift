//
//  PlatformTextField.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  TextField's editor: a UITextField, kept in step with the text binding,
//  with the keyboard the environment asks for, telling the field when
//  editing begins and ends and when return is pressed. Under focused(_:),
//  editing sets the focus binding and the binding moves the keyboard:
//  the field becomes first responder when it is set, and resigns when
//  it is cleared.

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
        coordinator.focus = environment.perryFocusBinding
        // The keyboard follows the binding's changes, not its value: the
        // field's own focus reaches the binding a transaction later.
        if let focus = coordinator.focus {
            let wanted = focus.isFocused
            PerryFocusBinding.trace("update \(ObjectIdentifier(field)) wanted \(wanted) last \(String(describing: coordinator.lastFocus)) first responder \(field.isFirstResponder)")
            if let last = coordinator.lastFocus, wanted != last {
                if wanted, !field.isFirstResponder {
                    DispatchQueue.main.async { _ = field.becomeFirstResponder() }
                } else if !wanted, field.isFirstResponder {
                    DispatchQueue.main.async { _ = field.resignFirstResponder() }
                }
            }
            coordinator.lastFocus = wanted
        }
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

    /// The width offered, and a line of text high, as SwiftUI's own text
    /// fields are: a field doesn't grow to the height it is offered.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: UITextField, context: Context) -> CGSize? {
        let intrinsic = field.intrinsicContentSize
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? intrinsic.width
        return CGSize(width: width, height: intrinsic.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: text) }

    final class Coordinator: NSObject {
        var text: Binding<String>
        var onEditingChanged: (Bool) -> Void = { _ in }
        var onCommit: () -> Void = {}
        var focus: PerryFocusBinding?
        /// The focus binding's value as last seen, so only its changes
        /// move the keyboard.
        var lastFocus: Bool?

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func editingChanged(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }

        @objc func editingDidBegin(_ field: UITextField) {
            focus?.setFocused(true)
            PerryFocusBinding.trace("began \(ObjectIdentifier(field)), binding has focus \(String(describing: focus?.isFocused))")
            onEditingChanged(true)
        }

        @objc func editingDidEnd(_ field: UITextField) {
            PerryFocusBinding.trace("ended \(ObjectIdentifier(field))")
            focus?.setFocused(false)
            onEditingChanged(false)
        }

        @objc func editingDidEndOnExit(_ field: UITextField) {
            onCommit()
        }
    }
}

/// A focused(_:equals:) binding, as text fields under it follow it: whether
/// it is set to the field's value, and setting or clearing it.
struct PerryFocusBinding {
    let isFocusedValue: () -> Bool
    let setFocused: (Bool) -> Void

    var isFocused: Bool { isFocusedValue() }

    /// With PERRY_SWIFTUI_FOCUS_TRACE set, text fields' focus is logged.
    nonisolated(unsafe) static let tracing = ProcessInfo.processInfo.environment["PERRY_SWIFTUI_FOCUS_TRACE"] != nil

    static func trace(_ message: @autoclosure () -> String) {
        guard tracing else { return }
        print("perry: SwiftUI: focus: \(message())")
    }

    init<Value: Hashable>(binding: FocusState<Value>.Binding, value: Value) {
        isFocusedValue = { binding.wrappedValue == value }
        setFocused = { focused in
            if focused {
                if binding.wrappedValue != value { binding.wrappedValue = value }
            } else if binding.wrappedValue == value, let cleared = PerryFocusBinding.cleared(Value.self) {
                binding.wrappedValue = cleared
            }
        }
    }

    /// No focus, as FocusState's values say it: false, or nil.
    static func cleared<Value>(_ type: Value.Type) -> Value? {
        if let value = false as? Value { return value }
        return (type as? PerryFocusClearable.Type)?.perryCleared as? Value
    }
}

protocol PerryFocusClearable {
    static var perryCleared: Self { get }
}

extension Optional: PerryFocusClearable {
    static var perryCleared: Optional { nil }
}

private struct PerryFocusBindingKey: EnvironmentKey {
    static let defaultValue: PerryFocusBinding? = nil
}

extension EnvironmentValues {
    var perryFocusBinding: PerryFocusBinding? {
        get { self[PerryFocusBindingKey.self] }
        set { self[PerryFocusBindingKey.self] = newValue }
    }
}
#endif
