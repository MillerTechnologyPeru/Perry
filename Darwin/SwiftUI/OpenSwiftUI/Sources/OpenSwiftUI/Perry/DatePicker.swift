//
//  DatePicker.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  DatePicker, as a row with its label and the selected date and time;
//  tapping them shows steppers for each component displayed, kept within
//  the picker's range. Date picker styles' requirements are there for the
//  ABI; pickers look the same whatever the style.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore

// MARK: - DatePickerComponents

/// The components of a date a date picker shows.
@available(OpenSwiftUI_v1_0, *)
public struct DatePickerComponents: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let hourAndMinute = DatePickerComponents(rawValue: 1 << 2 | 1 << 3)
    public static let date = DatePickerComponents(rawValue: 1 << 4 | 1 << 5 | 1 << 6)
}

// MARK: - DatePicker

/// A control for selecting an absolute date.
@available(OpenSwiftUI_v1_0, *)
public struct DatePicker<Label>: View where Label: View {
    public typealias Components = DatePickerComponents

    var selection: Binding<Date>
    var range: ClosedRange<Date>?
    var displayedComponents: DatePickerComponents
    var label: Label
    @State private var isEditing = false

    public init(
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.selection = selection
        self.displayedComponents = displayedComponents
        self.label = label()
    }

    public init(
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.selection = selection
        self.range = range
        self.displayedComponents = displayedComponents
        self.label = label()
    }

    public init(
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.selection = selection
        self.range = range.lowerBound ... .distantFuture
        self.displayedComponents = displayedComponents
        self.label = label()
    }

    public init(
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.selection = selection
        self.range = .distantPast ... range.upperBound
        self.displayedComponents = displayedComponents
        self.label = label()
    }

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = displayedComponents.contains(.date) ? .medium : .none
        formatter.timeStyle = displayedComponents.contains(.hourAndMinute) ? .short : .none
        return formatter.string(from: selection.wrappedValue)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isEditing.toggle()
            } label: {
                HStack {
                    label
                    Spacer(minLength: 8)
                    Text(formatted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.46, opacity: 0.12))
                        .cornerRadius(6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isEditing {
                DateSteppers(selection: selection, range: range, displayedComponents: displayedComponents)
            }
        }
    }
}

@available(OpenSwiftUI_v1_0, *)
extension DatePicker where Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date]
    ) {
        self.init(selection: selection, displayedComponents: displayedComponents) { Text(titleKey) }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date]
    ) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) { Text(titleKey) }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date]
    ) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) { Text(titleKey) }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date]
    ) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date]
    ) where S: StringProtocol {
        self.init(selection: selection, displayedComponents: displayedComponents) { Text(title) }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date]
    ) where S: StringProtocol {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) { Text(title) }
    }
}

/// A stepper for each displayed component: day, hour and minute.
struct DateSteppers: View {
    var selection: Binding<Date>
    var range: ClosedRange<Date>?
    var displayedComponents: DatePickerComponents

    var body: some View {
        VStack(spacing: 6) {
            if displayedComponents.contains(.date) {
                row("Day", .day, 1)
                row("Month", .month, 1)
            }
            if displayedComponents.contains(.hourAndMinute) {
                row("Hour", .hour, 1)
                row("Minute", .minute, 5)
            }
        }
    }

    private func row(_ name: String, _ component: Calendar.Component, _ step: Int) -> some View {
        HStack {
            Text(name).foregroundColor(.secondary)
            Spacer()
            Button("−") { move(component, by: -step) }.buttonStyle(.bordered)
            Button("+") { move(component, by: step) }.buttonStyle(.bordered)
        }
    }

    private func move(_ component: Calendar.Component, by amount: Int) {
        guard var date = Calendar.current.date(byAdding: component, value: amount, to: selection.wrappedValue) else { return }
        if let range {
            date = min(max(date, range.lowerBound), range.upperBound)
        }
        selection.wrappedValue = date
    }
}

// MARK: - Styles

/// The properties of a date picker.
@available(OpenSwiftUI_v4_0, *)
public struct DatePickerStyleConfiguration {
    /// A type-erased label of a date picker.
    @MainActor
    @preconcurrency
    public struct Label: View {
        public typealias Body = Never
        public var body: Never { fatalError("DatePickerStyleConfiguration.Label has no body") }
    }

    public let label: DatePickerStyleConfiguration.Label
    @Binding public var selection: Date
    public var minimumDate: Date?
    public var maximumDate: Date?
    public var displayedComponents: DatePickerComponents
}

/// The label a date picker style's body is given.
@available(OpenSwiftUI_v1_0, *)
public struct _DatePickerStyleLabel: View {
    public typealias Body = Never
    public var body: Never { fatalError("_DatePickerStyleLabel has no body") }
}

/// A type that specifies the appearance and interaction of all date pickers
/// within a view hierarchy.
@available(OpenSwiftUI_v1_0, *)
@preconcurrency
@MainActor
public protocol DatePickerStyle {
    associatedtype Body: View

    @available(OpenSwiftUI_v4_0, *)
    @ViewBuilder
    @MainActor
    @preconcurrency
    func makeBody(configuration: Configuration) -> Body

    @available(OpenSwiftUI_v4_0, *)
    typealias Configuration = DatePickerStyleConfiguration

    associatedtype _Body: View = EmptyView

    @ViewBuilder
    @MainActor
    @preconcurrency
    func _body(configuration: DatePicker<_Label>) -> _Body

    typealias _Label = _DatePickerStyleLabel
}

@available(OpenSwiftUI_v1_0, *)
extension DatePickerStyle where _Body == EmptyView {
    public func _body(configuration: DatePicker<_Label>) -> EmptyView { EmptyView() }
}

@available(OpenSwiftUI_v1_0, *)
extension DatePickerStyle where Body == EmptyView {
    public func makeBody(configuration: Configuration) -> EmptyView { EmptyView() }
}

/// A date picker style that displays the components in a compact, textual
/// format.
@available(OpenSwiftUI_v2_0, *)
public struct CompactDatePickerStyle: DatePickerStyle {
    public typealias _Body = EmptyView
    public init() {}

    @available(OpenSwiftUI_v4_0, *)
    public func makeBody(configuration: CompactDatePickerStyle.Configuration) -> some View {
        EmptyView()
    }
}

/// The default style for date pickers.
@available(OpenSwiftUI_v1_0, *)
public struct DefaultDatePickerStyle: DatePickerStyle {
    public typealias _Body = EmptyView
    public init() {}

    @available(OpenSwiftUI_v4_0, *)
    public func makeBody(configuration: DefaultDatePickerStyle.Configuration) -> some View {
        EmptyView()
    }
}

/// A date picker style that displays an interactive calendar or clock.
@available(OpenSwiftUI_v2_0, *)
public struct GraphicalDatePickerStyle: DatePickerStyle {
    public typealias _Body = EmptyView
    public init() {}

    @available(OpenSwiftUI_v4_0, *)
    public func makeBody(configuration: GraphicalDatePickerStyle.Configuration) -> some View {
        EmptyView()
    }
}

/// A date picker style that displays each component as columns in a
/// scrollable wheel.
@available(OpenSwiftUI_v1_0, *)
public struct WheelDatePickerStyle: DatePickerStyle {
    public typealias _Body = EmptyView
    public init() {}

    @available(OpenSwiftUI_v4_0, *)
    public func makeBody(configuration: WheelDatePickerStyle.Configuration) -> some View {
        EmptyView()
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the style for date pickers within this view; they look the
    /// same whatever the style.
    nonisolated public func datePickerStyle<S>(_ style: S) -> some View where S: DatePickerStyle {
        self
    }
}
#endif
