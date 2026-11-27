import Foundation
import UniformTypeIdentifiers

// Protocol requirements follow the SDK ABI. In particular, neither associated
// representation has an extra same-type constraint on its Item.
public protocol TransferRepresentation<Item>: Sendable {
    associatedtype Item: Transferable
    associatedtype Body: TransferRepresentation
    @TransferRepresentationBuilder<Item> var body: Body { get }
}

public protocol Transferable: Sendable {
    associatedtype Representation: TransferRepresentation
    @TransferRepresentationBuilder<Self> static var transferRepresentation: Representation { get }
}

@resultBuilder
public struct TransferRepresentationBuilder<Item: Transferable> {
    public static func buildExpression<R: TransferRepresentation>(_ content: R) -> R where R.Item == Item {
        content
    }

    public static func buildBlock<R: TransferRepresentation>(_ content: R) -> R where R.Item == Item {
        content
    }
}

extension Never: Transferable, TransferRepresentation {
    public typealias Item = Never
    public typealias Body = Never
    public typealias Representation = Never

    public var body: Never { fatalError("Never has no representation body") }
    public static var transferRepresentation: Never {
        fatalError("Never has no transferable values")
    }
}

public struct DataRepresentation<Item: Transferable>: TransferRepresentation {
    public typealias Body = Never
    let contentType: UTType
    let exporting: (@Sendable (Item) async throws -> Data)?
    let importing: (@Sendable (Data) async throws -> Item)?

    public init(contentType: UTType,
                exporting: @escaping @Sendable (Item) async throws -> Data,
                importing: @escaping @Sendable (Data) async throws -> Item) {
        self.contentType = contentType
        self.exporting = exporting
        self.importing = importing
    }

    public init(exportedContentType: UTType,
                exporting: @escaping @Sendable (Item) async throws -> Data) {
        contentType = exportedContentType
        self.exporting = exporting
        importing = nil
    }

    public init(importedContentType: UTType,
                importing: @escaping @Sendable (Data) async throws -> Item) {
        contentType = importedContentType
        exporting = nil
        self.importing = importing
    }

    // Primitive representations are interpreted by a transport, not expanded.
    public var body: Never { return fatalError("DataRepresentation is a primitive representation") }
}

extension URL: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation<URL>(contentType: .url) { url in
            Data(url.absoluteString.utf8)
        } importing: { data in
            guard let string = String(data: data, encoding: .utf8), let url = URL(string: string) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return url
        }
    }
}
