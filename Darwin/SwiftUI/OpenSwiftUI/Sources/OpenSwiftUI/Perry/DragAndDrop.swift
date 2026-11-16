//
//  DragAndDrop.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Drag and drop, and the file importer. Perry has no drag sessions and no
//  document picker yet: views take these modifiers and draw as they are, a
//  drag never starts, nothing is dropped, and no importer is shown.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore
public import UniformTypeIdentifiers

// MARK: - Drop

/// Operation types that determine how a drag and drop session resolves
/// when the user drops a drag item.
@available(OpenSwiftUI_v1_0, *)
public enum DropOperation: Sendable {
    /// Cancel the drag operation and transfer no data.
    case cancel
    /// The drop activity is not allowed at this time or location.
    case forbidden
    /// Copy the data to the modified view.
    case copy
    /// Move the data represented by the drag items instead of copying it.
    case move
}

/// The behavior of a drop.
@available(OpenSwiftUI_v1_0, *)
public struct DropProposal: Sendable {
    /// The drop operation that the drop proposes to perform.
    public let operation: DropOperation

    public init(operation: DropOperation) {
        self.operation = operation
    }
}

/// The current state of a drop.
@available(OpenSwiftUI_v1_0, *)
public struct DropInfo {
    /// The location of the drag in the coordinate space of the drop view.
    public var location: CGPoint { .zero }

    /// Indicates whether at least one item conforms to at least one of the
    /// specified uniform type identifiers.
    public func hasItemsConforming(to contentTypes: [UTType]) -> Bool { false }

    /// Finds item providers that conform to at least one of the specified
    /// uniform type identifiers.
    public func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider] { [] }
}

@available(*, unavailable)
extension DropInfo: Sendable {}

/// An interface that you implement to interact with a drop operation in a
/// view modified to accept drops.
@available(OpenSwiftUI_v1_0, *)
@preconcurrency
@MainActor
public protocol DropDelegate {
    /// Tells the delegate that a drop containing items conforming to one
    /// of the expected types entered a view that accepts drops.
    func validateDrop(info: DropInfo) -> Bool

    /// Tells the delegate it can request the item provider data from the
    /// given information.
    func performDrop(info: DropInfo) -> Bool

    /// Tells the delegate a validated drop has entered the modified view.
    func dropEntered(info: DropInfo)

    /// Tells the delegate that a validated drop moved inside the modified
    /// view.
    func dropUpdated(info: DropInfo) -> DropProposal?

    /// Tells the delegate a validated drop operation has exited the
    /// modified view.
    func dropExited(info: DropInfo)
}

@available(OpenSwiftUI_v1_0, *)
extension DropDelegate {
    public func validateDrop(info: DropInfo) -> Bool { true }

    public func dropEntered(info: DropInfo) {}

    public func dropUpdated(info: DropInfo) -> DropProposal? { nil }

    public func dropExited(info: DropInfo) {}
}

@available(OpenSwiftUI_v2_0, *)
extension View {
    /// Defines the destination of a drag-and-drop operation that handles
    /// the dropped content with a closure that you specify.
    nonisolated public func onDrop(
        of supportedContentTypes: [UTType],
        isTargeted: Binding<Bool>?,
        perform action: @escaping (_ providers: [NSItemProvider]) -> Bool
    ) -> some View {
        self
    }

    /// Defines the destination of a drag and drop operation that handles
    /// the dropped content with a closure that you specify.
    nonisolated public func onDrop(
        of supportedContentTypes: [UTType],
        isTargeted: Binding<Bool>?,
        perform action: @escaping (_ providers: [NSItemProvider], _ location: CGPoint) -> Bool
    ) -> some View {
        self
    }

    /// Defines the destination of a drag and drop operation using behavior
    /// controlled by the delegate that you provide.
    nonisolated public func onDrop(of supportedContentTypes: [UTType], delegate: any DropDelegate) -> some View {
        self
    }
}

// MARK: - Drag

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Activates this view as the source of a drag and drop operation,
    /// with a preview of the dragged data.
    nonisolated public func onDrag<V>(
        _ data: @escaping () -> NSItemProvider,
        @ViewBuilder preview: () -> V
    ) -> some View where V: View {
        self
    }
}

// MARK: - File importer

@available(OpenSwiftUI_v2_0, *)
extension View {
    /// Presents a system interface for allowing the user to import an
    /// existing file.
    nonisolated public func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        onCompletion: @escaping (_ result: Result<URL, any Error>) -> Void
    ) -> some View {
        self
    }
}
#endif
