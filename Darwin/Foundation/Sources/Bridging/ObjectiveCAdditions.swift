// Parts of Darwin's Foundation overlay that programs built against it call
// and swift-foundation leaves to Apple's build: literals for NSArray,
// NSString and NSDecimal, key-value observation by key path, a scanner's
// and a string's conveniences, and searching a Data.

// MARK: - Literals

extension NSArray: ExpressibleByArrayLiteral {
    /// An array of the elements, each bridged.
    public required convenience init(arrayLiteral elements: Any...) {
        self.init(array: elements)
    }
}

extension NSString: ExpressibleByStringLiteral {
    public required convenience init(stringLiteral value: StaticString) {
        self.init(string: value.description)
    }
}

@available(*, unavailable)
extension NSDecimal: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = Decimal(value)._c
    }
}

@available(*, unavailable)
extension NSDecimal: Comparable {
    public static func < (lhs: NSDecimal, rhs: NSDecimal) -> Bool {
        Decimal(lhs) < Decimal(rhs)
    }
}

extension NSObject: CustomDebugStringConvertible {}

// MARK: - Key-value observation by key path

/// What changed, for an observation's handler.
public struct NSKeyValueObservedChange<Value> {
    public typealias Kind = NSKeyValueChange

    public let kind: Kind
    /// The value after the change, when the options asked for it.
    public let newValue: Value?
    /// The value before the change, when the options asked for it.
    public let oldValue: Value?
    /// The indexes changed, of an ordered to-many relationship.
    public let indexes: IndexSet?
    /// Whether this is the notification before the change.
    public let isPrior: Bool
}

/// An observation, kept for as long as it should last: it ends when this
/// is invalidated or let go.
public class NSKeyValueObservation: NSObject {
    private weak var object: NSObject?
    private let keyPath: String
    private let handler: (NSObject, [NSKeyValueChangeKey: Any]?) -> Void
    private var observing = false

    fileprivate init(object: NSObject, keyPath: String, options: NSKeyValueObservingOptions,
                     handler: @escaping (NSObject, [NSKeyValueChangeKey: Any]?) -> Void) {
        self.object = object
        self.keyPath = keyPath
        self.handler = handler
        super.init()
        object.addObserver(self, forKeyPath: keyPath, options: options, context: nil)
        observing = true
    }

    /// Ends the observation.
    @objc public func invalidate() {
        guard observing else { return }
        observing = false
        object?.removeObserver(self, forKeyPath: keyPath, context: nil)
        object = nil
    }

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                                      context: UnsafeMutableRawPointer?) {
        guard observing, let object = object as? NSObject else { return }
        handler(object, change)
    }

    deinit {
        invalidate()
    }
}

/// What gives NSObject and its subclasses observation by key path.
public protocol _KeyValueCodingAndObserving {}

extension NSObject: _KeyValueCodingAndObserving {}

extension _KeyValueCodingAndObserving {
    /// Observes a property that is visible to Objective-C by its key path;
    /// the handler is called as key-value observing reports each change.
    public func observe<Value>(_ keyPath: KeyPath<Self, Value>, options: NSKeyValueObservingOptions = [],
                               changeHandler: @escaping (Self, NSKeyValueObservedChange<Value>) -> Void)
        -> NSKeyValueObservation {
        guard let name = keyPath._kvcKeyPathString else {
            fatalError("Could not extract a String from KeyPath \(keyPath)")
        }
        return NSKeyValueObservation(object: self as! NSObject, keyPath: name, options: options) { object, change in
            let kind = (change?[.kindKey] as? UInt).flatMap(NSKeyValueChange.init(rawValue:)) ?? .setting
            let notification = NSKeyValueObservedChange<Value>(
                kind: kind,
                newValue: change?[.newKey] as? Value,
                oldValue: change?[.oldKey] as? Value,
                indexes: change?[.indexesKey] as? IndexSet,
                isPrior: change?[.notificationIsPriorKey] as? Bool ?? false)
            changeHandler(object as! Self, notification)
        }
    }
}

// MARK: - Scanner and strings

extension Scanner {
    /// The characters up to the string given, or to the end when it does
    /// not occur; nil when there are none.
    public func scanUpToString(_ substring: String) -> String? {
        var found: NSString?
        return scanUpTo(substring, into: &found) ? found.map { String($0) } : nil
    }
}

extension StringProtocol {
    /// The string with each percent escape replaced by the byte it names,
    /// read as UTF-8; nil when an escape is malformed or the bytes are not
    /// UTF-8.
    public var removingPercentEncoding: String? {
        var bytes: [UInt8] = []
        var iterator = utf8.makeIterator()
        func digit(_ byte: UInt8?) -> UInt8? {
            guard let byte else { return nil }
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
            default: return nil
            }
        }
        while let byte = iterator.next() {
            guard byte == UInt8(ascii: "%") else {
                bytes.append(byte)
                continue
            }
            guard let high = digit(iterator.next()), let low = digit(iterator.next()) else { return nil }
            bytes.append(high << 4 | low)
        }
        return String(validating: bytes, as: UTF8.self)
    }
}

// MARK: - Data

extension Data {
    /// Where the bytes given first occur (last, searching backwards) in
    /// the range, or in all of the data; nil when they do not. Anchored,
    /// they must be at the search's start.
    public func range(of dataToFind: Data, options: NSData.SearchOptions = [], in range: Range<Index>? = nil) -> Range<Index>? {
        let bounds = range ?? startIndex..<endIndex
        let count = dataToFind.count
        guard count > 0, bounds.count >= count else { return nil }
        let first = bounds.lowerBound, last = bounds.upperBound - count
        func matches(at start: Index) -> Bool {
            self[start..<start + count].elementsEqual(dataToFind)
        }
        let backwards = options.contains(.backwards)
        if options.contains(.anchored) {
            let start = backwards ? last : first
            return matches(at: start) ? start..<start + count : nil
        }
        let starts = backwards ? AnySequence(stride(from: last, through: first, by: -1)) : AnySequence(first...last)
        for start in starts where matches(at: start) {
            return start..<start + count
        }
        return nil
    }
}

// MARK: - URL cache

extension URLCache {
    /// A cache of the capacities given, kept in the directory, or the
    /// default one.
    public convenience init(memoryCapacity: Int, diskCapacity: Int, directory: URL? = nil) {
        self.init(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: directory?.path)
    }
}

// MARK: - Errors

extension CocoaError {
    public static var coderReadCorrupt: CocoaError.Code { CocoaError.Code(rawValue: 4864) }
    public static var coderValueNotFound: CocoaError.Code { CocoaError.Code(rawValue: 4865) }
}
