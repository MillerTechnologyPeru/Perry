// Constants that Objective-C code reads as exported data symbols, such as
// `NSString *const NSCocoaErrorDomain`. Swift cannot define a data symbol by
// name, so the provider's perry_provider_symbol hook hands the loader a
// slot for each constant while images bind, and export() fills the slots
// at startup, before any Mach-O code runs.

/// What an exported constant holds.
public enum ObjCConstantValue {
    /// An NSString with this text, which lives forever.
    case string(String)
    /// The same object as another constant, as Darwin's toll-free names are
    /// (NSDefaultRunLoopMode and kCFRunLoopDefaultMode).
    case alias(String)
    /// An object made at startup.
    case object(() -> UnsafeMutableRawPointer?)
    /// Numbers, in the slot's bits: NSURLSessionTransferSizeUnknown is an
    /// int64_t, UIFontWeightBold a CGFloat, NSURLSessionTaskPriorityHigh a
    /// float in the slot's low four bytes. An integer's low bytes are also
    /// a 32-bit NSInteger's.
    case integer(Int64)
    case double(Double)
    case float(Float)
    /// A CGFloat: a double on 64-bit Darwin, a float on 32-bit.
    case cgFloat(Double)
}

/// A type whose constants @ObjCConstants collects.
public protocol ObjCConstantTable {
    static var objCConstants: [(name: String, value: ObjCConstantValue)] { get }
}

/// The constants a provider exports, by symbol name.
public final class ObjCConstantExports: @unchecked Sendable {
    public static let shared = ObjCConstantExports()

    private let lock = InteropLock()
    private var values: [String: ObjCConstantValue] = [:]
    private var order: [String] = []
    private var slots: [String: UnsafeMutablePointer<UnsafeMutableRawPointer?>] = [:]

    /// Adds tables' constants. Registering the same table again does nothing.
    public func register(_ tables: [any ObjCConstantTable.Type]) {
        lock.withLock {
            for table in tables {
                for (name, value) in table.objCConstants where values[name] == nil {
                    values[name] = value
                    order.append(name)
                }
            }
        }
    }

    /// The slot for a constant, by its C name ("NSCocoaErrorDomain"), or nil
    /// if no table defines it. Slots never move. They are 8 bytes, a
    /// pointer's or a number's, so on 32-bit Darwin too they hold an int64_t
    /// or a double.
    public func slot(_ name: String) -> UnsafeMutablePointer<UnsafeMutableRawPointer?>? {
        lock.withLock {
            guard values[name] != nil else { return nil }
            if let slot = slots[name] { return slot }
            let words = 8 / MemoryLayout<UInt>.size
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: words)
            slot.initialize(repeating: nil, count: words)
            slots[name] = slot
            return slot
        }
    }

    /// For perry_provider_symbol: a Mach-O name ("_NSCocoaErrorDomain").
    public func symbol(_ machOName: String) -> UnsafeMutableRawPointer? {
        guard machOName.hasPrefix("_") else { return nil }
        return slot(String(machOName.dropFirst())).map(UnsafeMutableRawPointer.init)
    }

    /// Makes every constant's object and stores it in its slot. Strings and
    /// objects are made first, then aliases point at them.
    public func export() {
        let entries = lock.withLock { order.map { ($0, values[$0]!) } }
        for (name, value) in entries {
            switch value {
            case .string(let text): slot(name)?.pointee = text.objCOwnedReturnValue()
            case .object(let make): slot(name)?.pointee = make()
            case .integer(let number): slot(name).map { UnsafeMutableRawPointer($0).storeBytes(of: number, as: Int64.self) }
            case .double(let number): slot(name).map { UnsafeMutableRawPointer($0).storeBytes(of: number, as: Double.self) }
            case .float(let number): slot(name).map { UnsafeMutableRawPointer($0).storeBytes(of: number, as: Float.self) }
            case .cgFloat(let number):
                guard let slot = slot(name).map(UnsafeMutableRawPointer.init) else { break }
                if MemoryLayout<UInt>.size == 8 { slot.storeBytes(of: number, as: Double.self) }
                else { slot.storeBytes(of: Float(number), as: Float.self) }
            case .alias: break
            }
        }
        for (name, value) in entries {
            if case .alias(let target) = value { slot(name)?.pointee = slot(target)?.pointee }
        }
    }

    /// A constant's object, once exported.
    public func object(_ name: String) -> UnsafeMutableRawPointer {
        guard let object = slot(name)?.pointee else { objcInteropFatal("constant \(name) is not exported") }
        return object
    }
}
