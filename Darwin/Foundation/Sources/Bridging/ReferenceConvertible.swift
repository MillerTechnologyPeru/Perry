/// A value type that bridges to an Objective-C reference type, as
/// `CharacterSet` does to `NSCharacterSet`.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol ReferenceConvertible: CustomDebugStringConvertible, CustomStringConvertible, Hashable, _ObjectiveCBridgeable {
    associatedtype ReferenceType: NSObject, NSCopying
}
