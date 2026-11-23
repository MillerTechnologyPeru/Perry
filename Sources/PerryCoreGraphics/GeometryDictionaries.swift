import CPerryCoreGraphics
import CPerryGeometry
import Glibc
import PerryObjCInterop

// Points, sizes and rects as dictionaries, as CoreGraphics stores them in
// property lists and window-server dictionaries: CFNumbers under "X" and
// "Y", "Width" and "Height". Reading accepts any number under those keys and
// fails when one is missing.

enum GeometryDictionaries {
    /// A new dictionary (+1) of the values as doubles.
    static func make(_ entries: [(String, CGFloat)]) -> Ref? {
        NSMutableDictionary.of(entries.map { ($0.0, NSObject.number(Double($0.1))) }).objCOwnedReturnValue()
    }

    /// The values under the keys, or nil if the argument isn't a dictionary
    /// or one is missing or isn't a number.
    static func read(_ dictionary: Ref?, _ keys: [String]) -> [CGFloat]? {
        guard let dictionary else { return nil }
        let object = NSObject(objCArgument: dictionary)
        guard let entries = object.dictionary else { return nil }
        var values: [CGFloat] = []
        for key in keys {
            guard let value = entries.object(key)?.doubleValue else { return nil }
            values.append(CGFloat(value))
        }
        return values
    }
}

@DarwinC("_CGPointCreateDictionaryRepresentation")
public func CGPointCreateDictionaryRepresentation(_ point: CGPoint) -> Ref? {
    GeometryDictionaries.make([("X", point.x), ("Y", point.y)])
}

@c(_CGPointMakeWithDictionaryRepresentation)
public func CGPointMakeWithDictionaryRepresentation(_ dictionary: Ref?, _ point: UnsafeMutablePointer<CGPoint>?) -> Bool {
    guard let values = GeometryDictionaries.read(dictionary, ["X", "Y"]) else { return false }
    point?.pointee = CGPoint(x: values[0], y: values[1])
    return true
}

@DarwinC("_CGSizeCreateDictionaryRepresentation")
public func CGSizeCreateDictionaryRepresentation(_ size: CGSize) -> Ref? {
    GeometryDictionaries.make([("Width", size.width), ("Height", size.height)])
}

@c(_CGSizeMakeWithDictionaryRepresentation)
public func CGSizeMakeWithDictionaryRepresentation(_ dictionary: Ref?, _ size: UnsafeMutablePointer<CGSize>?) -> Bool {
    guard let values = GeometryDictionaries.read(dictionary, ["Width", "Height"]) else { return false }
    size?.pointee = CGSize(width: values[0], height: values[1])
    return true
}

/// The rect as it is, not standardized, as CoreGraphics stores it.
@DarwinC("_CGRectCreateDictionaryRepresentation")
public func CGRectCreateDictionaryRepresentation(_ rect: CGRect) -> Ref? {
    GeometryDictionaries.make([("X", rect.origin.x), ("Y", rect.origin.y), ("Width", rect.size.width), ("Height", rect.size.height)])
}

@c(_CGRectMakeWithDictionaryRepresentation)
public func CGRectMakeWithDictionaryRepresentation(_ dictionary: Ref?, _ rect: UnsafeMutablePointer<CGRect>?) -> Bool {
    guard let values = GeometryDictionaries.read(dictionary, ["X", "Y", "Width", "Height"]) else { return false }
    rect?.pointee = CGRect(origin: CGPoint(x: values[0], y: values[1]), size: CGSize(width: values[2], height: values[3]))
    return true
}
