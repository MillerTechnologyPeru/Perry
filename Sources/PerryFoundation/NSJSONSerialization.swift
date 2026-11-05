import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

/// NSJSONSerialization over swift-foundation's JSON coders.
enum JSON {
    // NSJSONReadingOptions
    static let mutableContainers: UInt = 1 << 0
    static let fragmentsAllowed: UInt = 1 << 2
    // NSJSONWritingOptions
    static let prettyPrinted: UInt = 1 << 0
    static let sortedKeys: UInt = 1 << 1
    static let writingFragmentsAllowed: UInt = 1 << 2
    static let withoutEscapingSlashes: UInt = 1 << 3

    /// Stores an NSError in `error` (NSError **), as Foundation reports failures.
    static func report(_ error: UnsafeMutablePointer<id?>?, code: Int, description: String) {
        error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: code, description: description)
    }

    /// JSON can hold strings, numbers, booleans, null, arrays and
    /// dictionaries with string keys; doubles must be finite.
    static func isValid(_ value: PropertyValue, topLevel: Bool, fragments: Bool) -> Bool {
        switch value {
        case .array(let values): return values.allSatisfy { isValid($0, topLevel: false, fragments: true) }
        case .dictionary(let values): return values.values.allSatisfy { isValid($0, topLevel: false, fragments: true) }
        case .date, .data: return false
        case .double(let value): return value.isFinite && (!topLevel || fragments)
        default: return !topLevel || fragments
        }
    }
}

/// NSJSONSerialization.
@ObjCClass("NSJSONSerialization")
public final class NSJSONSerialization: NSObject {
    @ObjCClassMethod("JSONObjectWithData:options:error:")
    static func object(data: NSData, options: UInt, error: UnsafeMutablePointer<id?>?) -> ObjCObject? {
        let decoder = JSONDecoder()
        guard let value = try? decoder.decode(PropertyValue.self, from: data.data) else {
            JSON.report(error, code: 3840, description: "The data couldn’t be read because it isn’t in the correct format.")
            return nil
        }
        switch value {
        case .array, .dictionary: break
        default:
            guard options & JSON.fragmentsAllowed != 0 else {
                JSON.report(error, code: 3840, description: "The data couldn’t be read because it isn’t in the correct format.")
                return nil
            }
        }
        return value.object(mutableContainers: options & JSON.mutableContainers != 0).map { ObjCObject($0) }
    }

    @ObjCClassMethod("dataWithJSONObject:options:error:")
    static func data(object: ObjCObject, options: UInt, error: UnsafeMutablePointer<id?>?) -> NSData? {
        PropertyValue.rejected = nil
        guard let value = PropertyValue(object: object.id),
              JSON.isValid(value, topLevel: true, fragments: options & JSON.writingFragmentsAllowed != 0) else {
            let type = PropertyValue.rejected.map { " (\($0))" } ?? ""
            foundationFatal("+[NSJSONSerialization dataWithJSONObject:options:error:]: Invalid type in JSON write\(type)")
        }
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = []
        if options & JSON.prettyPrinted != 0 { formatting.insert(.prettyPrinted) }
        if options & JSON.sortedKeys != 0 { formatting.insert(.sortedKeys) }
        if options & JSON.withoutEscapingSlashes != 0 { formatting.insert(.withoutEscapingSlashes) }
        encoder.outputFormatting = formatting
        guard let data = try? encoder.encode(value) else {
            JSON.report(error, code: 3851, description: "The data couldn’t be written because it isn’t in the correct format.")
            return nil
        }
        return DataObjects.owned(DataStorage(data))
    }

    @ObjCClassMethod("isValidJSONObject:")
    static func isValid(object: ObjCObject?) -> Bool {
        guard let value = PropertyValue(object: object?.id) else { return false }
        return JSON.isValid(value, topLevel: true, fragments: false)
    }
}
