//
//  ConformancesMore.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Smaller pieces of API with little or nothing behind them yet: paste
//  buttons and share links, which show their labels and do nothing when
//  tapped, as Perry has no pasteboard bridge or share sheet here; rotor
//  content and preview modifiers, which nothing reads; conformances of
//  tab and toolbar content; environment values that hold what is set and
//  that lists and navigation don't read; and moving a collection's
//  elements by their offsets.

#if os(iOS) || os(visionOS)
public import CoreTransferable
public import Foundation
public import OpenSwiftUICore

// MARK: - PasteButton

/// A system button that reads items from the pasteboard and delivers it to
/// a closure. Nothing is read here: the button is its title, and the
/// closure is never called.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct PasteButton: View {
    /// Creates an instance that accepts values of the specified type.
    nonisolated public init<T>(payloadType: T.Type, onPaste: @escaping ([T]) -> Void) where T: Transferable {}

    nonisolated public var body: some View {
        Text(verbatim: "Paste")
    }
}

@available(*, unavailable)
extension PasteButton: Sendable {}

// MARK: - ShareLink

/// A view that controls a sharing presentation. No share sheet is
/// presented here: the link is its label.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct ShareLink<Data, PreviewImage, PreviewIcon, Label>: View
where Data: RandomAccessCollection, PreviewImage: Transferable, PreviewIcon: Transferable, Label: View, Data.Element: Transferable {
    var items: Data
    var subject: Text?
    var message: Text?
    var label: Label

    nonisolated public var body: some View {
        label
    }
}

@available(*, unavailable)
extension ShareLink: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension ShareLink where PreviewImage == Never, PreviewIcon == Never {
    /// Creates an instance that presents the share interface for a URL.
    nonisolated public init(
        item: URL,
        subject: Text? = nil,
        message: Text? = nil,
        @ViewBuilder label: () -> Label
    ) where Data == CollectionOfOne<URL> {
        self.items = CollectionOfOne(item)
        self.subject = subject
        self.message = message
        self.label = label()
    }
}

// MARK: - AccessibilityRotorContent

/// Content within an accessibility rotor. Perry's accessibility has no
/// rotors, so content makes no entries. A body is written without a
/// result builder here.
@available(OpenSwiftUI_v1_0, *)
@preconcurrency
@MainActor
public protocol AccessibilityRotorContent {
    nonisolated static func _makeEntries(content: _GraphValue<Self>, inputs: _AccessibilityRotorEntryInputs) -> _AccessibilityRotorEntryOutputs

    nonisolated static func _entryCount(inputs: _AccessibilityRotorEntryInputs) -> Int?

    /// The type for the internal content of this rotor content.
    associatedtype Body: AccessibilityRotorContent

    /// The internal content of this rotor content.
    @MainActor
    @preconcurrency
    var body: Body { get }
}

@available(OpenSwiftUI_v1_0, *)
extension AccessibilityRotorContent {
    /// Makes no entries.
    nonisolated public static func _makeEntries(content: _GraphValue<Self>, inputs: _AccessibilityRotorEntryInputs) -> _AccessibilityRotorEntryOutputs {
        _AccessibilityRotorEntryOutputs()
    }

    /// The number of entries, which isn't known without making them.
    nonisolated public static func _entryCount(inputs: _AccessibilityRotorEntryInputs) -> Int? {
        nil
    }
}

/// Inputs for making a rotor's entries; nothing makes them here.
@available(OpenSwiftUI_v1_0, *)
public struct _AccessibilityRotorEntryInputs {}

@available(*, unavailable)
extension _AccessibilityRotorEntryInputs: Sendable {}

/// Outputs of making a rotor's entries; empty here.
@available(OpenSwiftUI_v1_0, *)
public struct _AccessibilityRotorEntryOutputs: Sendable {}

// MARK: - PreviewModifier

/// A type that defines an environment in which previews can appear.
/// Previews aren't run here, so nothing asks a modifier for its shared
/// context or its body.
@available(OpenSwiftUI_v1_0, *)
@MainActor
public protocol PreviewModifier {
    /// The type of the shared context.
    associatedtype Context = Void

    /// The type of view the modifier produces.
    associatedtype Body: View

    /// The type-erased content the modifier is applied to.
    typealias Content = PreviewModifierContent

    /// Creates the context shared by the previews that use the modifier.
    @MainActor
    static func makeSharedContext() async throws -> Context

    /// Modifies the preview's content, with the shared context.
    @ViewBuilder
    @MainActor
    func body(content: Content, context: Context) -> Body
}

@available(OpenSwiftUI_v1_0, *)
extension PreviewModifier where Context == () {
    @MainActor
    public static func makeSharedContext() async throws -> Context { () }
}

/// The type-erased content of a preview that a preview modifier is
/// applied to. None is made here; one would draw nothing.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct PreviewModifierContent: View, PrimitiveView, UnaryView {
    public typealias Body = Never

    nonisolated public static func _makeView(
        view: _GraphValue<PreviewModifierContent>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        _ViewOutputs()
    }
}

@available(*, unavailable)
extension PreviewModifierContent: Sendable {}

// MARK: - Tab content

/// The tabs made for each element of a collection.
@available(OpenSwiftUI_v6_0, *)
extension ForEach: TabContent where Content: TabContent {
    public typealias TabValue = Content.TabValue

    @MainActor
    @preconcurrency
    public var _identifiedView: ForEach<Data, ID, Content._IdentifiedView> {
        ForEach<Data, ID, Content._IdentifiedView>(self, transform: { $0._identifiedView })
    }

    public typealias Body = ForEach<Data, ID, Content>

    @MainActor
    @preconcurrency
    public var body: ForEach<Data, ID, Content> {
        // A plain return, so the tab content builder does not wrap it.
        return self
    }

    public typealias _IdentifiedView = ForEach<Data, ID, Content._IdentifiedView>
}

@available(OpenSwiftUI_v6_0, *)
extension TabContent {
    /// Adds a label to the tab that describes its contents. Perry's tab
    /// bars don't take accessibility labels: the tab is returned as it
    /// is.
    nonisolated public func accessibilityLabel(_ label: Text, isEnabled: Bool = true) -> some TabContent<TabValue> {
        self
    }
}

// MARK: - ForEach

@available(OpenSwiftUI_v1_0, *)
extension ForEach where Data == Range<Int>, ID == Int {
    /// The views of a constant range, identified by their offsets.
    @usableFromInline
    static func create(_ data: Range<Int>, content: @escaping (Int) -> Content) -> ForEach<Data, ID, Content> {
        ForEach(data, idGenerator: .offset, content: content)
    }
}

// MARK: - Toolbar content

/// Toolbar content an `if` without an `else` in a builder may leave out.
@available(OpenSwiftUI_v4_0, *)
extension Optional: ToolbarContent where Wrapped: ToolbarContent {
    nonisolated public static func _makeToolbar(content: _GraphValue<Optional<Wrapped>>, inputs: _ToolbarInputs) -> _ToolbarOutputs {
        _ToolbarOutputs()
    }

    public typealias Body = Never
}

extension Optional: ResolvedToolbarContent where Wrapped: ToolbarContent {
    /// The wrapped content's items, or none.
    var resolvedItems: [ResolvedToolbarItem] {
        MainActor.assumeIsolated {
            switch self {
            case let .some(content): content.resolvedItems
            case .none: []
            }
        }
    }
}

// These two conformances are to the protocol ToolbarBehaviors.swift
// declares, with Never's conformance to it, which their bodies need.

@available(OpenSwiftUI_v5_0, *)
extension LimitedAvailabilityToolbarContent: CustomizableToolbarContent {}

@available(OpenSwiftUI_v2_0, *)
extension TupleToolbarContent: CustomizableToolbarContent {}

// MARK: - Environment values

private struct DefaultMinListRowHeightKey: EnvironmentKey {
    static var defaultValue: CGFloat { ListRowMetrics.minimumHeight }
}

private struct DefaultMinListHeaderHeightKey: EnvironmentKey {
    static var defaultValue: CGFloat? { nil }
}

private struct IsSceneCapturedKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

private struct NavigationIndicatorVisibilityKey: EnvironmentKey {
    static var defaultValue: Visibility { .automatic }
}

@available(OpenSwiftUI_v1_0, *)
extension EnvironmentValues {
    /// The default minimum height of a row in a list. The value set is
    /// kept; lists here size their rows without reading it.
    public var defaultMinListRowHeight: CGFloat {
        get { self[DefaultMinListRowHeightKey.self] }
        set { self[DefaultMinListRowHeightKey.self] = newValue }
    }

    /// The default minimum height of a header in a list, or nil for the
    /// system's. The value set is kept; lists here don't read it.
    public var defaultMinListHeaderHeight: CGFloat? {
        get { self[DefaultMinListHeaderHeightKey.self] }
        set { self[DefaultMinListHeaderHeightKey.self] = newValue }
    }

    /// Whether the scene is being captured, by a screen recording for
    /// one. Perry never reports a capture: false unless set.
    public var isSceneCaptured: Bool {
        get { self[IsSceneCapturedKey.self] }
        set { self[IsSceneCapturedKey.self] = newValue }
    }

    /// The visibility of the indicators of navigation links. The value
    /// set is kept; links here draw their indicators without reading it.
    @usableFromInline
    var navigationIndicatorVisibility: Visibility {
        get { self[NavigationIndicatorVisibilityKey.self] }
        set { self[NavigationIndicatorVisibilityKey.self] = newValue }
    }

    /// The undo manager used to register a view's undo operations. Perry's
    /// windows give views none.
    public var undoManager: UndoManager? {
        nil
    }
}

// MARK: - Selection trait

/// Whether a row of a selectable container can be selected: written by
/// the selection-disabling modifier, and not read by lists here.
@available(OpenSwiftUI_v1_0, *)
@usableFromInline
struct IsSelectionEnabledTraitKey: _ViewTraitKey {
    @usableFromInline
    static let defaultValue: Bool = true

    @usableFromInline
    typealias Value = Bool
}

// MARK: - Moving elements

@available(OpenSwiftUI_v1_0, *)
extension MutableCollection {
    /// Moves all the elements at the specified offsets to the specified
    /// destination offset, preserving ordering. Offsets outside the
    /// collection are ignored, as is a destination outside it.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, destination >= 0, destination <= count else { return }
        var before: [Element] = []
        var moved: [Element] = []
        var after: [Element] = []
        var offset = 0
        for element in self {
            if source.contains(offset) {
                moved.append(element)
            } else if offset < destination {
                before.append(element)
            } else {
                after.append(element)
            }
            offset += 1
        }
        guard !moved.isEmpty else { return }
        var index = startIndex
        for element in before + moved + after {
            self[index] = element
            formIndex(after: &index)
        }
    }
}
#endif
