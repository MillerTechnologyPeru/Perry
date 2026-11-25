import Glibc
import PerryObjCInterop

// The dynamic store's proxy settings: none are configured, as CFNetwork's
// system proxy settings say, so connections go direct. The computer's name
// and local host name are the Linux host name's.

/// CFDictionaryRef SCDynamicStoreCopyProxies(SCDynamicStoreRef store): HTTP,
/// HTTPS and automatic proxy configuration off, +1.
@c(_SCDynamicStoreCopyProxies)
public func SCDynamicStoreCopyProxies(_ store: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    typealias Make = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias Number = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int64) -> UnsafeMutableRawPointer?
    typealias Set = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    let send = ObjCRuntime.msgSend
    let settings = unsafeBitCast(send, to: Make.self)(ObjCRuntime.classObject("NSMutableDictionary"), ObjCRuntime.selector("dictionary"))
    let off = unsafeBitCast(send, to: Number.self)(ObjCRuntime.classObject("NSNumber"), ObjCRuntime.selector("numberWithLongLong:"), 0)
    for key in ["HTTPEnable", "HTTPSEnable", "ProxyAutoConfigEnable", "SOCKSEnable"] {
        unsafeBitCast(send, to: Set.self)(settings, ObjCRuntime.selector("setObject:forKey:"), off, key.objCArgument())
    }
    return ObjCRuntime.retain(settings)
}

/// The host name before its first dot.
private func hostName() -> String {
    var buffer = [CChar](repeating: 0, count: 256)
    guard gethostname(&buffer, buffer.count - 1) == 0 else { return "localhost" }
    let name = String(cString: buffer)
    return String(name.prefix { $0 != "." })
}

/// CFStringRef SCDynamicStoreCopyComputerName(SCDynamicStoreRef store,
/// CFStringEncoding *nameEncoding), +1, in UTF-8.
@c(_SCDynamicStoreCopyComputerName)
public func SCDynamicStoreCopyComputerName(_ store: UnsafeMutableRawPointer?, _ encoding: UnsafeMutablePointer<UInt32>?) -> UnsafeMutableRawPointer? {
    encoding?.pointee = 0x0800_0100    // kCFStringEncodingUTF8
    return ObjCRuntime.retain(hostName().objCArgument())
}

/// CFStringRef SCDynamicStoreCopyLocalHostName(SCDynamicStoreRef store), +1:
/// the name the machine answers to on the local network, without ".local".
@c(_SCDynamicStoreCopyLocalHostName)
public func SCDynamicStoreCopyLocalHostName(_ store: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(hostName().objCArgument())
}
