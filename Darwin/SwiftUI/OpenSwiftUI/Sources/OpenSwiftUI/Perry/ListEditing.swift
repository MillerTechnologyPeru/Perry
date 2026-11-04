//
//  ListEditing.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Lists' rows as the user edits them: selecting rows, swiping a row to
//  delete it, and edit mode, which puts a delete button or a selection
//  circle before each row. A row's selection value is its tag or its
//  identifier; it can be deleted when the ForEach that made it has an
//  onDelete action.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore
import Foundation

// MARK: - Selection

/// A list's selection, type-erased: the value of a row, whether a value is
/// selected, and choosing one.
struct ListSelection {
    /// Whether several rows are selected at once, in edit mode, rather
    /// than one by a tap.
    var multiple: Bool
    var value: (_VariadicView.Children.Element) -> AnyHashable?
    var isSelected: (AnyHashable) -> Bool
    /// Selects the value, or for a multiple selection toggles it.
    var choose: (AnyHashable) -> Void

    static func values<V: Hashable>(_ type: V.Type) -> (_VariadicView.Children.Element) -> AnyHashable? {
        { child in
            if let tag = child.traits.tag(for: V.self) { return AnyHashable(tag) }
            return child.id(as: V.self).map { AnyHashable($0) }
        }
    }

    init<V: Hashable>(single binding: Binding<V?>) {
        multiple = false
        value = Self.values(V.self)
        isSelected = { binding.wrappedValue.map(AnyHashable.init) == $0 }
        choose = { if let value = $0.base as? V { binding.wrappedValue = value } }
    }

    init<V: Hashable>(exact binding: Binding<V>) {
        multiple = false
        value = Self.values(V.self)
        isSelected = { AnyHashable(binding.wrappedValue) == $0 }
        choose = { if let value = $0.base as? V { binding.wrappedValue = value } }
    }

    init<V: Hashable>(set binding: Binding<Set<V>>) {
        multiple = true
        value = Self.values(V.self)
        isSelected = { ($0.base as? V).map(binding.wrappedValue.contains) ?? false }
        choose = { value in
            guard let value = value.base as? V else { return }
            if binding.wrappedValue.contains(value) {
                binding.wrappedValue.remove(value)
            } else {
                binding.wrappedValue.insert(value)
            }
        }
    }
}

@available(OpenSwiftUI_v1_0, *)
extension List {
    public init(selection: Binding<Set<SelectionValue>>?, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = selection.map { ListSelection(set: $0) }
    }

    public init(selection: Binding<SelectionValue?>?, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = selection.map { ListSelection(single: $0) }
    }

    @_disfavoredOverload
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = ListSelection(exact: selection)
    }
}

// MARK: - Rows

/// A row of a list: its child, with the controls edit mode puts before it,
/// highlighted when selected, and swiped to delete.
struct ListRow: View {
    var child: _VariadicView.Children.Element
    var selection: ListSelection?
    var inset: CGFloat
    @Environment(\.editMode) private var editMode
    @State private var swipe = RowSwipe()

    var body: some View {
        let editing = editMode?.wrappedValue.isEditing ?? false
        let deletion = child.traits.deleteInteraction.flatMap { $0.onDelete == nil ? nil : $0 }
        let value = selection?.value(child)
        let selected = value.map { selection?.isSelected($0) ?? false } ?? false
        let choosing = value != nil && (selection?.multiple == true ? editing : true)
        HStack(spacing: 12) {
            if editing, selection?.multiple == true, value != nil {
                SelectionCircle(selected: selected)
            } else if editing, deletion != nil {
                DeleteMinus { swipe.open?() }
            }
            child
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, inset)
        .background(selected && selection?.multiple == false ? Color(white: 0.82) : Color.clear)
        .modifier(RowChoosing(action: choosing ? { if let value { selection?.choose(value) } } : nil))
        .modifier(SwipeToDelete(deletion: deletion, swipe: swipe))
    }
}

/// A tap on the row that selects it, when it can be selected.
struct RowChoosing: ViewModifier {
    var action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.contentShape(Rectangle()).onTapGesture(perform: action)
        } else {
            content
        }
    }
}

/// The circle before a row in edit mode, filled with a check when the row
/// is selected.
struct SelectionCircle: View {
    var selected: Bool

    var body: some View {
        ZStack {
            // A ring: a gray circle with a white one inside.
            Circle()
                .fill(selected ? Color.accentColor : Color(white: 0.78))
            Circle()
                .fill(Color.white)
                .padding(1.5)
                .opacity(selected ? 0 : 1)
            Text("✓")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color.white)
                .opacity(selected ? 1 : 0)
        }
        .frame(width: 22, height: 22)
    }
}

/// The red minus before a deletable row in edit mode, which shows its
/// delete button.
struct DeleteMinus: View {
    var action: () -> Void

    var body: some View {
        ZStack {
            Circle().fill(Color.red)
            Rectangle().fill(Color.white).frame(width: 10, height: 2)
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

// MARK: - Swipe to delete

/// A row's swipe, which edit mode's minus opens too.
final class RowSwipe {
    var width: CGFloat = 0
    var open: (() -> Void)?
}

/// Slides a deletable row left over a red Delete button: released past
/// half the button it stays open, and swiped most of the way across it
/// deletes the row. A tap on an open row closes it.
struct SwipeToDelete: ViewModifier {
    var deletion: DeleteInteraction?
    var swipe: RowSwipe
    @State private var offset: CGFloat = 0
    @State private var origin: CGFloat?

    static var buttonWidth: CGFloat { 80 }

    func body(content: Content) -> some View {
        if let deletion {
            let _ = { swipe.open = { withAnimation(.easeOut(duration: 0.25)) { offset = -Self.buttonWidth } } }()
            content
                .overlay {
                    if offset < 0, origin == nil {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                }
                .offset(x: offset)
                .background(alignment: .trailing) {
                    Text("Delete")
                        .foregroundColor(Color.white)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: max(-offset, 0))
                        .frame(maxHeight: .infinity)
                        .background(Color.red)
                        .contentShape(Rectangle())
                        .onTapGesture { delete(deletion) }
                }
                .clipped()
                .background(
                    GeometryReader { proxy in
                        let _ = { swipe.width = proxy.size.width }()
                        Color.clear
                    }
                )
                .background(
                    ScrollPanRecognizer(
                        axes: .horizontal,
                        changed: { changed($0.width) },
                        ended: { ended($0.width, velocity: $1.width, deletion) }
                    )
                )
        } else {
            content
        }
    }

    func changed(_ translation: CGFloat) {
        if origin == nil { origin = offset }
        offset = min(0, (origin ?? 0) + translation)
    }

    func ended(_ translation: CGFloat, velocity: CGFloat, _ deletion: DeleteInteraction) {
        let released = min(0, (origin ?? offset) + translation)
        origin = nil
        let projected = released + velocity * 0.2
        if swipe.width > 0, projected < -swipe.width * 0.6 {
            delete(deletion)
        } else if projected < -Self.buttonWidth / 2 {
            withAnimation(.easeOut(duration: 0.25)) { offset = -Self.buttonWidth }
        } else {
            close()
        }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.25)) { offset = 0 }
    }

    func delete(_ deletion: DeleteInteraction) {
        offset = 0
        origin = nil
        deletion.delete()
    }
}

// MARK: - EditButton

/// A button that toggles the edit mode environment value.
@available(OpenSwiftUI_v1_0, *)
public struct EditButton: View {
    @Environment(\.editMode) private var editMode

    public init() {}

    public var body: some View {
        let editing = editMode?.wrappedValue.isEditing ?? false
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                editMode?.wrappedValue = editing ? .inactive : .active
            }
        } label: {
            if editing {
                Text("Done").fontWeight(.semibold)
            } else {
                Text("Edit")
            }
        }
    }
}
#endif
