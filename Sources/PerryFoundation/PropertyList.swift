import CPerryFoundation
import FoundationEssentials
import Glibc

/// A property list or JSON value, bridged between Objective-C objects and
/// swift-foundation's coders: JSONSerialization, Info.plist and user
/// defaults read and write through it.
enum PropertyValue: Codable, Equatable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case array([PropertyValue])
    case dictionary([String: PropertyValue])
    case null

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var values: [PropertyValue] = []
            while !array.isAtEnd {
                values.append(try array.decode(PropertyValue.self))
            }
            self = .array(values)
            return
        }
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            var values: [String: PropertyValue] = [:]
            for key in keyed.allKeys {
                values[key.stringValue] = try keyed.decode(PropertyValue.self, forKey: key)
            }
            self = .dictionary(values)
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null }
        else if let value = try? single.decode(Bool.self) { self = .bool(value) }
        else if let value = try? single.decode(Int64.self) { self = .integer(value) }
        else if let value = try? single.decode(Double.self) { self = .double(value) }
        else if let value = try? single.decode(String.self) { self = .string(value) }
        else if let value = try? single.decode(Date.self) { self = .date(value) }
        else if let value = try? single.decode(Data.self) { self = .data(value) }
        else {
            throw DecodingError.dataCorruptedError(in: single, debugDescription: "unsupported property list value")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values { try container.encode(value) }
        case .dictionary(let values):
            var container = encoder.container(keyedBy: AnyKey.self)
            for (key, value) in values { try container.encode(value, forKey: AnyKey(key)) }
        default:
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .integer(let value): try container.encode(value)
            case .double(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .date(let value): try container.encode(value)
            case .data(let value): try container.encode(value)
            case .null: try container.encodeNil()
            case .array, .dictionary: break
            }
        }
    }

    struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    // MARK: - Objective-C objects

    /// The value of an NSString, NSNumber, NSDate, NSData, NSArray,
    /// NSDictionary or NSNull; nil for anything else.
    init?(object: id?) {
        guard let object else { return nil }
        if let string = Strings.value(of: object) {
            self = .string(string)
        } else if ObjC.isKind(object, of: Numbers.numberClass) {
            let number = Numbers.storage(object)
            switch number.value {
            case .bool(let value): self = .bool(value)
            case .double(let value): self = .double(value)
            case .signed, .unsigned: self = .integer(number.int64)
            }
        } else if ObjC.isKind(object, of: Dates.dateClass) {
            self = .date(Dates.date(object))
        } else if ObjC.isKind(object, of: DataObjects.dataClass) {
            self = .data(DataObjects.data(object))
        } else if ObjC.isKind(object, of: Arrays.arrayClass) {
            var values: [PropertyValue] = []
            for element in Arrays.elements(object) {
                guard let value = PropertyValue(object: element) else { return nil }
                values.append(value)
            }
            self = .array(values)
        } else if ObjC.isKind(object, of: Dictionaries.dictionaryClass) {
            var values: [String: PropertyValue] = [:]
            for entry in Dictionaries.entries(object) {
                guard let key = Strings.value(of: entry.key), let value = PropertyValue(object: entry.value) else {
                    return nil
                }
                values[key] = value
            }
            self = .dictionary(values)
        } else if Nulls.isNull(object) {
            self = .null
        } else {
            PropertyValue.rejected = ObjC.className(object)
            return nil
        }
    }

    /// The class of the last object that is not a property list or JSON
    /// value, to name in the error.
    nonisolated(unsafe) static var rejected: String?

    /// A new autoreleased Objective-C object for this value. Collections
    /// are mutable when `mutableContainers` is set, as JSON reading allows.
    func object(mutableContainers: Bool = false) -> id? {
        switch self {
        case .string(let value): return Strings.autoreleased(value)
        case .integer(let value): return Numbers.make(nil, .signed(value))
        case .double(let value): return Numbers.make(nil, .double(value))
        case .bool(let value): return perry_foundation_boolean(value ? 1 : 0)
        case .date(let value): return Dates.autoreleased(value)
        case .data(let value): return DataObjects.autoreleased(value)
        case .null: return Nulls.null
        case .array(let values):
            let elements = values.compactMap { $0.object(mutableContainers: mutableContainers) }
            return Arrays.autoreleased(elements, cls: mutableContainers ? UnsafeMutableRawPointer(Arrays.mutableClass) : nil)
        case .dictionary(let values):
            let entries = values.compactMap { key, value in
                value.object(mutableContainers: mutableContainers).map { (key: Strings.autoreleased(key), value: $0) }
            }
            return Dictionaries.autoreleased(entries, cls: mutableContainers
                ? UnsafeMutableRawPointer(Dictionaries.mutableClass) : nil)
        }
    }
}
