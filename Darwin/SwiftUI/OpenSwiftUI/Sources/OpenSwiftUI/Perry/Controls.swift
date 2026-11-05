//
//  Controls.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  Picker, as a row that steps through its options when tapped; the
//  refresh action scroll views run; and file import, which shows nothing
//  yet.

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
    @Environment(\.pickerKind) private var kind

    @available(*, deprecated, renamed: "Picker(selection:content:label:)")
    public init(selection: Binding<SelectionValue>, label: Label, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.label = label
        self.content = content()
    }

    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.selection = selection
        self.label = label()
        self.content = content()
    }

    public var body: some View {
        switch kind {
        case .segmented:
            _VariadicView.Tree(SegmentedPickerRoot(selection: selection)) { content }
        case .automatic:
            _VariadicView.Tree(PickerRoot(selection: selection, label: label)) { content }
        }
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

// MARK: - Modifiers without an effect yet

// MARK: - refreshable

/// An action that initiates a refresh operation: the action a view's
/// `refreshable` modifier gives the views in it. A scroll view pulled down
/// past its top runs it.
@available(OpenSwiftUI_v3_0, *)
public struct RefreshAction: Sendable {
    let action: @Sendable () async -> Void

    public func callAsFunction() async {
        await action()
    }
}

struct RefreshActionKey: EnvironmentKey {
    static let defaultValue: RefreshAction? = nil
}

@available(OpenSwiftUI_v3_0, *)
extension EnvironmentValues {
    /// A refresh action stored in a view's environment.
    public var refresh: RefreshAction? {
        get { self[RefreshActionKey.self] }
    }

    var refreshAction: RefreshAction? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
    }
}

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Marks this view as refreshable: scroll views in it run the action
    /// when pulled down past their top.
    nonisolated public func refreshable(@_inheritActorContext action: @escaping @Sendable () async -> Void) -> some View {
        environment(\.refreshAction, RefreshAction(action: action))
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
// MARK: - _TaskValueModifier2

/// The modifier `task(id:)` uses from iOS 26.4, which names its task and
/// may give it an executor; it runs the action as `_TaskValueModifier`
/// does, again whenever the identity changes.
@available(OpenSwiftUI_v3_0, *)
public struct _TaskValueModifier2<ID>: ViewModifier where ID: Equatable {
    var id: ID
    var priority: TaskPriority
    nonisolated(unsafe) var action: @isolated(any) () async -> Void

    @usableFromInline
    nonisolated init(
        id: ID,
        name: String,
        executorPreference taskExecutor: (any TaskExecutor)?,
        priority: TaskPriority,
        action: sending @escaping @isolated(any) () async -> Void
    ) {
        self.id = id
        self.priority = priority
        self.action = action
    }

    public func body(content: Content) -> some View {
        nonisolated(unsafe) let action = action
        return content.modifier(_TaskValueModifier(value: id, priority: priority) { await action() })
    }
}

/// `_TaskValueModifier.init(value:priority:action:)` under the name apps
/// built against Apple's SDK call, whose action is `@Sendable` in the
/// mangling; this module's own initializer mangles without it.
@available(OpenSwiftUI_v3_0, *)
@_silgen_name("$s7SwiftUI18_TaskValueModifierV5value8priority6actionACyxGx_ScPyyYaYbctcfC")
public func _perryTaskValueModifierInit<Value>(
    value: Value,
    priority: TaskPriority,
    action: @escaping @Sendable () async -> Void
) -> _TaskValueModifier<Value> where Value: Equatable {
    _TaskValueModifier(value: value, priority: priority, action: action)
}
#endif
