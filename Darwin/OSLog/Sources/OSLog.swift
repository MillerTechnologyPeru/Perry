import Foundation

// OSLog's Swift API: a store's entries as a Swift sequence, and a message
// component's argument as an enum of its value.

@available(macOS 10.15, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension OSLogStore {
    /// The store's entries from the position given (or the first) that the
    /// predicate matches (or all), in the order the options ask for.
    public func getEntries(with options: OSLogEnumerator.Options = [], at position: OSLogPosition? = nil,
                           matching predicate: NSPredicate? = nil) throws -> AnySequence<OSLogEntry> {
        let enumerator = try __entriesEnumerator(options: options, position: position, predicate: predicate)
        return AnySequence(AnyIterator { enumerator.nextObject() as? OSLogEntry })
    }
}

@available(macOS 10.15, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension OSLogMessageComponent {
    /// A placeholder's argument, by the category the component reports.
    public enum Argument {
        case undefined
        case data(Data)
        case double(Double)
        case signed(Int64)
        case string(String)
        case unsigned(UInt64)
    }

    /// The argument, undefined when its value could not be decoded.
    public var argument: Argument {
        switch argumentCategory {
        case .data:
            guard let data = argumentDataValue else { return .undefined }
            return .data(data)
        case .double:
            return .double(argumentDoubleValue)
        case .int64:
            return .signed(argumentInt64Value)
        case .string:
            guard let string = argumentStringValue else { return .undefined }
            return .string(string)
        case .uInt64:
            return .unsigned(argumentUInt64Value)
        default:
            return .undefined
        }
    }
}
