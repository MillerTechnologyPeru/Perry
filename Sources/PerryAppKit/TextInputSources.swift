import PerryObjCInterop

// Carbon's Text Input Sources (HIToolbox), which AppKit keeps here: the
// keyboard layout is always the U.S. one AppKit's key events are typed
// with. Its Unicode layout data is a marker that CoreServices'
// UCKeyTranslate reads as that layout.

/// An input source: the U.S. keyboard layout.
@ObjCClass("__TISInputSource")
open class TISInputSource: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }

    nonisolated(unsafe) static let us = TISInputSource()

    /// The layout data's bytes: "PerryUS", which UCKeyTranslate knows.
    nonisolated(unsafe) static let layoutData: NSObject = {
        typealias Make = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UInt) -> UnsafeMutableRawPointer?
        let bytes = Array("PerryUS\0".utf8)
        let data = bytes.withUnsafeBytes {
            unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(ObjCRuntime.classObject("NSData"), ObjCRuntime.selector("dataWithBytes:length:"),
                                                              $0.baseAddress, UInt($0.count))
        }
        return NSObject(data!)
    }()

    nonisolated(unsafe) static let properties: [String: NSObject] = [
        InputSourceKeys.kTISPropertyInputSourceID: NSObject.string("com.apple.keylayout.US"),
        InputSourceKeys.kTISPropertyInputSourceType: NSObject(InputSourceKeys.kTISTypeKeyboardLayoutObject),
        InputSourceKeys.kTISPropertyInputSourceIsASCIICapable: NSNumber.make(bool: true),
        InputSourceKeys.kTISPropertyInputSourceIsEnabled: NSNumber.make(bool: true),
        InputSourceKeys.kTISPropertyInputSourceIsSelected: NSNumber.make(bool: true),
        InputSourceKeys.kTISPropertyInputSourceLanguages: NSMutableArray.of([NSObject.string("en")]),
        InputSourceKeys.kTISPropertyLocalizedName: NSObject.string("U.S."),
        InputSourceKeys.kTISPropertyUnicodeKeyLayoutData: layoutData,
    ]
}

extension NSObject {
    static func string(_ text: String) -> NSObject { NSObject(objCReturnValue: text.objCArgument()) }
}

@ObjCConstants
enum InputSourceKeys {
    static let kTISPropertyInputSourceID = "TISPropertyInputSourceID"
    static let kTISPropertyInputSourceType = "TISPropertyInputSourceType"
    static let kTISPropertyInputSourceCategory = "TISPropertyInputSourceCategory"
    static let kTISPropertyInputSourceIsASCIICapable = "TISPropertyInputSourceIsASCIICapable"
    static let kTISPropertyInputSourceIsEnabled = "TISPropertyInputSourceIsEnabled"
    static let kTISPropertyInputSourceIsSelected = "TISPropertyInputSourceIsSelected"
    static let kTISPropertyInputSourceLanguages = "TISPropertyInputSourceLanguages"
    static let kTISPropertyLocalizedName = "TISPropertyLocalizedName"
    static let kTISPropertyUnicodeKeyLayoutData = "TISPropertyUnicodeKeyLayoutData"
    static let kTISTypeKeyboardLayout = "TISTypeKeyboardLayout"
    static let kTISTypeKeyboardInputMode = "TISTypeKeyboardInputMode"
    static let kTISCategoryKeyboardInputSource = "TISCategoryKeyboardInputSource"
    static let kTISNotifySelectedKeyboardInputSourceChanged = "TISNotifySelectedKeyboardInputSourceChanged"
    static let kTISNotifyEnabledKeyboardInputSourcesChanged = "TISNotifyEnabledKeyboardInputSourcesChanged"
}

/// The current keyboard source, +1.
private func current() -> UnsafeMutableRawPointer? { ObjCRuntime.retain(TISInputSource.us.objcObject) }

@c(_TISCopyCurrentKeyboardInputSource) public func TISCopyCurrentKeyboardInputSource() -> UnsafeMutableRawPointer? { current() }
@c(_TISCopyCurrentKeyboardLayoutInputSource) public func TISCopyCurrentKeyboardLayoutInputSource() -> UnsafeMutableRawPointer? { current() }
@c(_TISCopyCurrentASCIICapableKeyboardInputSource) public func TISCopyCurrentASCIICapableKeyboardInputSource() -> UnsafeMutableRawPointer? { current() }
@c(_TISCopyCurrentASCIICapableKeyboardLayoutInputSource)
public func TISCopyCurrentASCIICapableKeyboardLayoutInputSource() -> UnsafeMutableRawPointer? { current() }
@c(_TISCopyInputSourceForLanguage) public func TISCopyInputSourceForLanguage(_ language: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { current() }

@c(_TISCreateInputSourceList)
public func TISCreateInputSourceList(_ properties: UnsafeMutableRawPointer?, _ includeAll: Bool) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(NSMutableArray.of([TISInputSource.us]).objcObject)
}

/// A property of the source, not retained (the Get rule).
@c(_TISGetInputSourceProperty)
public func TISGetInputSourceProperty(_ source: UnsafeMutableRawPointer?, _ key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard source != nil, let key else { return nil }
    return TISInputSource.properties[String(objCArgument: key)]?.objcObject
}

@c(_TISSelectInputSource) public func TISSelectInputSource(_ source: UnsafeMutableRawPointer?) -> Int32 { 0 }
@c(_TISEnableInputSource) public func TISEnableInputSource(_ source: UnsafeMutableRawPointer?) -> Int32 { 0 }
@c(_TISGetInputSourceTypeID) public func TISGetInputSourceTypeID() -> UInt { 0x120 }

/// The keyboard type: an ANSI keyboard (gestaltUSBAndyANSIKbd).
@c(_LMGetKbdType) public func LMGetKbdType() -> UInt8 { 40 }
@c(_LMGetKbdLast) public func LMGetKbdLast() -> UInt8 { 40 }
@c(_KBGetLayoutType) public func KBGetLayoutType(_ type: Int16) -> UInt32 { 0 }
