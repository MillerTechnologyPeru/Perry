import Foundation

// UTType: the Swift value over the Objective-C class of the same name
// (UTTypeReference to Swift), which Perry's provider has.

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public struct UTType: Sendable {
    let reference: UTTypeReference

    init(reference: UTTypeReference) {
        self.reference = reference
    }

    /// A system type, by its identifier: declared, or imported under the
    /// name if the provider's table lacks it.
    init(system identifier: String) {
        reference = UTTypeReference(identifier) ?? UTTypeReference(importedAs: identifier)
    }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTType {
    public init?(_ identifier: String) {
        guard let reference = UTTypeReference(identifier) else { return nil }
        self.reference = reference
    }

    public init?(filenameExtension: String, conformingTo supertype: UTType = .data) {
        guard let reference = UTTypeReference(filenameExtension: filenameExtension, conformingTo: supertype) else { return nil }
        self.reference = reference
    }

    public init?(mimeType: String, conformingTo supertype: UTType = .data) {
        guard let reference = UTTypeReference(mimeType: mimeType, conformingTo: supertype) else { return nil }
        self.reference = reference
    }

    public var identifier: String { reference.identifier }
    public var preferredFilenameExtension: String? { reference.preferredFilenameExtension }
    public var preferredMIMEType: String? { reference.preferredMIMEType }
    public var localizedDescription: String? { reference.localizedDescription }
    public var version: Int? { reference.version?.intValue }
    public var referenceURL: URL? { reference.referenceURL }
    public var isDynamic: Bool { reference.isDynamic }
    public var isDeclared: Bool { reference.isDeclared }
    public var isPublic: Bool { reference.isPublic }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTType {
    public func conforms(to type: UTType) -> Bool { reference.conforms(to: type) }
    public func isSupertype(of type: UTType) -> Bool { reference.isSupertype(of: type) }
    public func isSubtype(of type: UTType) -> Bool { reference.isSubtype(of: type) }

    public var supertypes: Set<UTType> {
        reference.supertypes
    }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTType {
    public init?(tag: String, tagClass: UTTagClass, conformingTo supertype: UTType?) {
        guard let reference = UTTypeReference(tag: tag, tagClass: tagClass.rawValue, conformingTo: supertype) else {
            return nil
        }
        self.reference = reference
    }

    public static func types(tag: String, tagClass: UTTagClass, conformingTo supertype: UTType?) -> [UTType] {
        UTTypeReference.types(tag: tag, tagClass: tagClass.rawValue, conformingTo: supertype)
    }

    public var tags: [UTTagClass: [String]] {
        var result: [UTTagClass: [String]] = [:]
        for (key, value) in reference.tags { result[UTTagClass(rawValue: key)] = value }
        return result
    }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTType {
    public init(exportedAs identifier: String, conformingTo parentType: UTType? = nil) {
        if let parentType {
            reference = UTTypeReference(exportedAs: identifier, conformingTo: parentType)
        } else {
            reference = UTTypeReference(exportedAs: identifier)
        }
    }

    public init(importedAs identifier: String, conformingTo parentType: UTType? = nil) {
        if let parentType {
            reference = UTTypeReference(importedAs: identifier, conformingTo: parentType)
        } else {
            reference = UTTypeReference(importedAs: identifier)
        }
    }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTType: Equatable, Hashable {
    public static func == (lhs: UTType, rhs: UTType) -> Bool { lhs.reference.isEqual(rhs.reference) }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference.identifier.lowercased())
    }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTType: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { reference.description }
    public var debugDescription: String { reference.debugDescription }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTType: ReferenceConvertible {
    public typealias ReferenceType = UTTypeReference
    public typealias _ObjectiveCType = UTTypeReference

    public func _bridgeToObjectiveC() -> UTTypeReference { reference }

    public static func _forceBridgeFromObjectiveC(_ source: UTTypeReference, result: inout UTType?) {
        result = UTType(reference: source)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: UTTypeReference, result: inout UTType?) -> Bool {
        result = UTType(reference: source)
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: UTTypeReference?) -> UTType {
        UTType(reference: source!)
    }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension UTType: Codable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let identifier = try container.decode(String.self)
        guard let reference = UTTypeReference(identifier) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "No type has the identifier \(identifier).")
        }
        self.reference = reference
    }
}

@available(macOS 11.0, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension URL {
    /// The URL with a path component of `partialName`, and the type's
    /// preferred extension if the name does not have one of the type's.
    public func appendingPathComponent(_ partialName: String, conformingTo contentType: UTType) -> URL {
        var name = partialName
        let present = (partialName as NSString).pathExtension
        let fits = !present.isEmpty && (UTType(filenameExtension: present)?.conforms(to: contentType) ?? false)
        if !fits, let preferred = contentType.preferredFilenameExtension {
            name = (partialName as NSString).appendingPathExtension(preferred) ?? partialName
        }
        return appendingPathComponent(name, isDirectory: contentType.conforms(to: .directory))
    }

    public mutating func appendPathComponent(_ partialName: String, conformingTo contentType: UTType) {
        self = appendingPathComponent(partialName, conformingTo: contentType)
    }

    public func appendingPathExtension(for contentType: UTType) -> URL {
        let present = pathExtension
        if !present.isEmpty, UTType(filenameExtension: present)?.conforms(to: contentType) ?? false { return self }
        guard let preferred = contentType.preferredFilenameExtension else { return self }
        return appendingPathExtension(preferred)
    }

    public mutating func appendPathExtension(for contentType: UTType) {
        self = appendingPathExtension(for: contentType)
    }
}
