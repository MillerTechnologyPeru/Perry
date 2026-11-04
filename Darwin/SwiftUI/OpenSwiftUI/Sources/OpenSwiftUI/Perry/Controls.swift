//
//  Controls.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  Picker, as a row that steps through its options when tapped; sheets,
//  drawn over the presenting view; and the modifiers that have no effect
//  yet (refresh, file import).

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore
public import UniformTypeIdentifiers

// MARK: - Picker

/// A control for selecting from a set of mutually exclusive values.
@available(OpenSwiftUI_v1_0, *)
public struct Picker<Label, SelectionValue, Content>: View where Label: View, SelectionValue: Hashable, Content: View {
    var selection: Binding<SelectionValue>
    var label: Label
    var content: Content

    public var body: some View {
        _VariadicView.Tree(PickerRoot(selection: selection, label: label)) { content }
    }
}

@available(OpenSwiftUI_v1_0, *)
extension Picker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.label = Text(titleKey)
        self.content = content()
    }

    @_disfavoredOverload
    public init<S>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) where S: StringProtocol {
        self.selection = selection
        self.label = Text(title)
        self.content = content()
    }
}

/// The label, and the option whose tag is the selection; a tap selects the
/// next option.
struct PickerRoot<SelectionValue: Hashable, Label: View>: _VariadicView.UnaryViewRoot {
    var selection: Binding<SelectionValue>
    var label: Label

    func body(children: _VariadicView.Children) -> some View {
        let tags = children.map { $0.traits.tag(for: SelectionValue.self) }
        let index = tags.firstIndex { $0 == selection.wrappedValue }
        Button {
            let start = index.map { $0 + 1 } ?? 0
            let order = Array(tags[start...]) + Array(tags[..<start])
            if let next = order.lazy.compactMap({ $0 }).first {
                selection.wrappedValue = next
            }
        } label: {
            HStack {
                label
                Spacer(minLength: 8)
                if let index {
                    children[index].foregroundColor(Color.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - sheet

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Presents a sheet when a binding to a Boolean value that you provide
    /// is true; here, drawn over this view.
    public func sheet<Content>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View where Content: View {
        modifier(SheetModifier(isPresented: isPresented, onDismiss: onDismiss, sheet: content))
    }
}

struct SheetModifier<Sheet: View>: ViewModifier {
    var isPresented: Binding<Bool>
    var onDismiss: (() -> Void)?
    var sheet: () -> Sheet

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented.wrappedValue {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Done") { isPresented.wrappedValue = false }
                            .padding(16)
                    }
                    sheet()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .background(Color.white)
                .onDisappear { onDismiss?() }
            }
        }
    }
}

// MARK: - Modifiers without an effect yet

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Marks this view as refreshable. Nothing pulls to refresh yet.
    nonisolated public func refreshable(action: @escaping @Sendable () async -> Void) -> some View {
        self
    }
}

@available(OpenSwiftUI_v2_0, *)
extension View {
    /// Presents a system interface for allowing the user to import an
    /// existing file. No interface is shown yet.
    public func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (_ result: Result<[URL], any Error>) -> Void
    ) -> some View {
        self
    }
}

// MARK: - _TaskModifier2

/// The modifier `task` uses from iOS 26, which names its task and may give
/// it an executor; it runs the action as `_TaskModifier` does.
@available(OpenSwiftUI_v3_0, *)
public struct _TaskModifier2: ViewModifier {
    var name: String
    var priority: TaskPriority
    nonisolated(unsafe) var action: @isolated(any) () async -> Void

    @usableFromInline
    nonisolated init(
        name: String,
        executorPreference taskExecutor: (any TaskExecutor)?,
        priority: TaskPriority,
        action: sending @escaping @isolated(any) () async -> Void
    ) {
        self.name = name
        self.priority = priority
        self.action = action
    }

    public func body(content: Content) -> some View {
        nonisolated(unsafe) let action = action
        return content.modifier(_TaskModifier(priority: priority) { await action() })
    }
}
#endif
