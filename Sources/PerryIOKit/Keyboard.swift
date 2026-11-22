import Glibc
import PerryObjCInterop

// The keyboard, as a HID device: an Apple USB keyboard (Generic Desktop,
// Keyboard) whose elements are its keys, buttons on the Keyboard/Keypad
// page, the modifiers first as a Mac keyboard's report lists them, then the
// keys from A (4) to Power (0x66). Games of the Mac OS X 10.2 to 10.5 years
// read it through the I/O Registry and the HID device interface (Pangea's
// look for its key elements by usage and poll them by cookie); a key's
// value is SDL3's keyboard state, whose scancodes are the page's usages.

enum Keyboard {
    /// The keys' usages, in the order of their elements.
    static let usages: [UInt32] = Array(0xE0...0xE7) + Array(0x04...0x66)

    /// The device, its collection cookie 1 and its keys from 2 on.
    nonisolated(unsafe) static let device: HIDDevice = {
        let device = HIDDevice()
        device.usages = [(1, 6)]
        func number(_ value: Int) -> NSObject { NSNumber.make(int64: Int64(value)) }
        device.properties = NSMutableDictionary.of([
            ("VendorID", number(0x05AC)),
            ("ProductID", number(0x0221)),
            ("VersionNumber", number(0x0069)),
            ("Product", NSObject.string("Apple Keyboard")),
            ("Manufacturer", NSObject.string("Apple Inc.")),
            ("Transport", NSObject.string("USB")),
            ("LocationID", number(0x1420_0000)),
            ("PrimaryUsagePage", number(1)),
            ("PrimaryUsage", number(6)),
            ("DeviceUsagePairs", NSMutableArray.of([NSMutableDictionary.of([("DeviceUsagePage", number(1)), ("DeviceUsage", number(6))])])),
        ])
        for usage in usages {
            let element = HIDElement()
            element.cookie = UInt32(device.elements.count + 2)
            (element.type, element.usagePage, element.usage) = (HIDElementType.button, 7, usage)
            (element.logicalMinimum, element.logicalMaximum) = (0, 1)
            element.device = device.objcObject
            device.elements.append(element)
        }
        return device
    }()

    /// The registry's properties for the device: its own, and its elements
    /// as kIOHIDElementKey's tree, one application collection of the keys.
    static var registryProperties: [(String, NSObject)] {
        func number(_ value: Int) -> NSObject { NSNumber.make(int64: Int64(value)) }
        func element(cookie: UInt32, type: UInt32, page: UInt32, usage: UInt32, children: [NSObject] = []) -> NSObject {
            var entries: [(String, NSObject)] = [
                ("ElementCookie", number(Int(cookie))), ("Type", number(Int(type))),
                ("UsagePage", number(Int(page))), ("Usage", number(Int(usage))),
                ("Min", number(0)), ("Max", number(1)), ("ScaledMin", number(0)), ("ScaledMax", number(1)),
                ("Size", number(1)), ("ReportSize", number(1)), ("ReportCount", number(1)), ("ReportID", number(0)),
                ("IsArray", NSNumber.make(bool: false)), ("IsRelative", NSNumber.make(bool: false)),
                ("IsWrapping", NSNumber.make(bool: false)), ("IsNonLinear", NSNumber.make(bool: false)),
                ("HasPreferredState", NSNumber.make(bool: true)), ("HasNullState", NSNumber.make(bool: false)),
            ]
            if !children.isEmpty {
                entries.append(("CollectionType", number(1)))
                entries.append(("Elements", NSMutableArray.of(children)))
            }
            return NSMutableDictionary.of(entries)
        }
        let keys = device.elements.map { element(cookie: $0.cookie, type: $0.type, page: $0.usagePage, usage: $0.usage) }
        let collection = element(cookie: 1, type: 513, page: 1, usage: 6, children: keys)
        let own = [
            "VendorID", "ProductID", "VersionNumber", "Product", "Manufacturer", "Transport", "LocationID",
            "PrimaryUsagePage", "PrimaryUsage", "DeviceUsagePairs",
        ].compactMap { key in device.property(key).map { (key, $0) } }
        return own + [("IOClass", NSObject.string("IOHIDDevice")), ("Elements", NSMutableArray.of([collection]))]
    }

    /// The element of a cookie.
    static func element(cookie: UInt32) -> HIDElement? {
        let index = Int(cookie) - 2
        return device.elements.indices.contains(index) ? device.elements[index] : nil
    }

    /// Whether the key of a usage is down now.
    static func isDown(_ usage: UInt32) -> Bool {
        guard let state = keyboardState else { return false }
        var count: Int32 = 0
        guard let keys = state(&count), Int(usage) < Int(count) else { return false }
        return keys[Int(usage)]
    }

    /// SDL_GetKeyboardState, from the SDL3 AppKit has started.
    nonisolated(unsafe) private static let keyboardState: (@convention(c) (UnsafeMutablePointer<Int32>?) -> UnsafePointer<Bool>?)? = {
        guard let library = dlopen("libSDL3.so.0", RTLD_NOW), let symbol = dlsym(library, "SDL_GetKeyboardState") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (UnsafeMutablePointer<Int32>?) -> UnsafePointer<Bool>?).self)
    }()
}
