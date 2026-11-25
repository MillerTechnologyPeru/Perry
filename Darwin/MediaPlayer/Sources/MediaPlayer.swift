import CoreFoundation
import Foundation

// MediaPlayer's Swift API that the library itself holds (the rest is in the
// framework): play parameters as Codable, through the dictionary the
// Objective-C class is made from and keeps.

/// A play parameter's name as a coding key.
private struct PlayParameterKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

@available(iOS 11.0, tvOS 16.4, *)
@available(macOS, unavailable)
@available(watchOS, unavailable)
extension MPMusicPlayerPlayParameters: Codable {
    /// Play parameters from the keys and values coded: strings, Booleans
    /// and numbers, which are all a play parameter's values are.
    public required convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: PlayParameterKey.self)
        var dictionary: [String: Any] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(Bool.self, forKey: key) {
                dictionary[key.stringValue] = value
            } else if let value = try? container.decode(Int64.self, forKey: key) {
                dictionary[key.stringValue] = value
            } else if let value = try? container.decode(Double.self, forKey: key) {
                dictionary[key.stringValue] = value
            } else if let value = try? container.decode(String.self, forKey: key) {
                dictionary[key.stringValue] = value
            }
        }
        self.init(dictionary: dictionary)!
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: PlayParameterKey.self)
        for (name, value) in dictionary {
            let key = PlayParameterKey(stringValue: name)
            switch value {
            case let string as String:
                try container.encode(string, forKey: key)
            case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
                try container.encode(number.boolValue, forKey: key)
            case let number as NSNumber where CFNumberIsFloatType(number):
                try container.encode(number.doubleValue, forKey: key)
            case let number as NSNumber:
                try container.encode(number.int64Value, forKey: key)
            default:
                break
            }
        }
    }
}
