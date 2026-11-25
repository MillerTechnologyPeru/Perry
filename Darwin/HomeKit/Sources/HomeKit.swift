import Darwin
import Foundation

// HomeKit's Swift API that the library itself holds (the rest is in the
// framework): HMCharacteristicPropertySupportsEventNotification as a Swift
// string, as Swift 4 programs read it. The Swift declaration hides the
// framework's constant of the same name, so the constant is looked up by
// its symbol.

@available(iOS 8.0, watchOS 2.0, tvOS 10.0, macCatalyst 14.0, *)
@available(macOS, unavailable)
public var HMCharacteristicPropertySupportsEventNotification: String {
    // RTLD_DEFAULT: every image of the process.
    guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "HMCharacteristicPropertySupportsEventNotification"),
          let string = address.load(as: NSString?.self) else {
        return "HMCharacteristicPropertySupportsEventNotification"
    }
    return string as String
}
