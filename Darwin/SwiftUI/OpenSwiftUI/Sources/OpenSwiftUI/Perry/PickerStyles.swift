//
//  PickerStyles.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Picker styles. pickerStyle puts the style's kind in the environment,
//  where pickers read it: a segmented picker shows its options side by
//  side; the others show a row that steps through them. Styles'
//  view-making requirements are there for the ABI; pickers never call
//  them.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - PickerStyle

/// A type that specifies the appearance and interaction of all pickers
/// within a view hierarchy.
@available(OpenSwiftUI_v1_0, *)
public protocol PickerStyle {
    static func _makeView<SelectionValue>(value: _GraphValue<_PickerValue<Self, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable
    static func _makeViewList<SelectionValue>(value: _GraphValue<_PickerValue<Self, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable
}

@available(OpenSwiftUI_v1_0, *)
public struct _PickerValue<Style, SelectionValue> where Style: PickerStyle, SelectionValue: Hashable {}

/// How a picker shows its options.
enum PickerKind {
    case automatic, segmented
}

/// The kinds of pickers styles make.
protocol PickerKindProviding {
    static var pickerKind: PickerKind { get }
}

struct PickerKindKey: EnvironmentKey {
    static let defaultValue: PickerKind = .automatic
}

extension EnvironmentValues {
    var pickerKind: PickerKind {
        get { self[PickerKindKey.self] }
        set { self[PickerKindKey.self] = newValue }
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the style for pickers within this view.
    nonisolated public func pickerStyle<S>(_ style: S) -> some View where S: PickerStyle {
        environment(\.pickerKind, (S.self as? PickerKindProviding.Type)?.pickerKind ?? .automatic)
    }
}

/// Generates a style's requirements, which no picker calls.
private func unusedPickerMakeView() -> Never {
    preconditionFailure("Picker styles' views are made by the picker")
}

// MARK: - The styles

/// The default picker style, based on the picker's context.
@available(OpenSwiftUI_v1_0, *)
public struct DefaultPickerStyle: PickerStyle {
    public init() {}
    public static func _makeView<SelectionValue>(value: _GraphValue<_PickerValue<DefaultPickerStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedPickerMakeView() }
    public static func _makeViewList<SelectionValue>(value: _GraphValue<_PickerValue<DefaultPickerStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedPickerMakeView() }
}

/// A picker style that presents the options in a segmented control.
@available(OpenSwiftUI_v1_0, *)
public struct SegmentedPickerStyle: PickerStyle, PickerKindProviding {
    public init() {}
    static var pickerKind: PickerKind { .segmented }
    public static func _makeView<SelectionValue>(value: _GraphValue<_PickerValue<SegmentedPickerStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedPickerMakeView() }
    public static func _makeViewList<SelectionValue>(value: _GraphValue<_PickerValue<SegmentedPickerStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedPickerMakeView() }
}

/// A picker style that presents the options in a scrollable wheel; here,
/// a row that steps through them.
@available(OpenSwiftUI_v1_0, *)
public struct WheelPickerStyle: PickerStyle {
    public init() {}
    public static func _makeView<SelectionValue>(value: _GraphValue<_PickerValue<WheelPickerStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedPickerMakeView() }
    public static func _makeViewList<SelectionValue>(value: _GraphValue<_PickerValue<WheelPickerStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedPickerMakeView() }
}

/// A picker style that presents the options as a menu; here, a row that
/// steps through them.
@available(OpenSwiftUI_v2_0, *)
public struct MenuPickerStyle: PickerStyle {
    public init() {}
    public static func _makeView<SelectionValue>(value: _GraphValue<_PickerValue<MenuPickerStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedPickerMakeView() }
    public static func _makeViewList<SelectionValue>(value: _GraphValue<_PickerValue<MenuPickerStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedPickerMakeView() }
}

// MARK: - The segmented control

/// The options side by side on a gray track, the selected one on a white
/// thumb; a tap selects one.
struct SegmentedPickerRoot<SelectionValue: Hashable>: _VariadicView.UnaryViewRoot {
    var selection: Binding<SelectionValue>

    func body(children: _VariadicView.Children) -> some View {
        HStack(spacing: 2) {
            ForEach(children) { child in
                let tag = child.traits.tag(for: SelectionValue.self)
                let isSelected = tag == selection.wrappedValue
                Button {
                    if let tag { selection.wrappedValue = tag }
                } label: {
                    child
                        .font(.footnote.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(isSelected ? Color.white : Color.clear)
                        .cornerRadius(7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(white: 0.46, opacity: 0.12))
        .cornerRadius(9)
    }
}
#endif
