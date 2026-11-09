import CJavaScriptCore
import PerryObjCInterop

// The one function of JavaScriptCore's C API that WebKitGTK's lacks, as it
// takes a CFString.

@c(_JSStringCreateWithCFString)
public func JSStringCreateWithCFStringFromDarwin(_ string: UnsafeMutableRawPointer?) -> JSStringRef? {
    typealias Send = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> UnsafePointer<CChar>?
    guard let string, let characters = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(string, ObjCRuntime.selector("UTF8String")) else {
        return JSStringCreateWithUTF8CString("")
    }
    return JSStringCreateWithUTF8CString(characters)
}
