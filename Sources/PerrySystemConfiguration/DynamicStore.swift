import PerryObjCInterop

// The dynamic store's proxy settings: none are configured, as CFNetwork's
// system proxy settings say, so connections go direct.

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
