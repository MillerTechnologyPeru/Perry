import PerryObjCInterop

// SCNetworkReachability. Perry runs apps offline as far as reachability
// goes: every target reports no flags (not reachable), so apps take their
// offline paths rather than waiting on services. Callbacks are kept but
// never called, the status never changing.

/// A reachability target: an object, as CFRelease expects.
@ObjCClass("__SCNetworkReachability")
open class SCNetworkReachability: NSObject {}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

private func makeTarget() -> UnsafeMutableRawPointer? {
    NSObject(SCNetworkReachability.objCClass.pointer).newInstance().objCOwnedReturnValue()
}

@c(_SCNetworkReachabilityCreateWithName)
public func SCNetworkReachabilityCreateWithName(_ allocator: UnsafeRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    makeTarget()
}

@c(_SCNetworkReachabilityCreateWithAddress)
public func SCNetworkReachabilityCreateWithAddress(_ allocator: UnsafeRawPointer?, _ address: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    makeTarget()
}

@c(_SCNetworkReachabilityCreateWithAddressPair)
public func SCNetworkReachabilityCreateWithAddressPair(_ allocator: UnsafeRawPointer?, _ local: UnsafeRawPointer?,
                                                       _ remote: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    makeTarget()
}

/// True, with no flags: the status is known, and nothing is reachable.
@c(_SCNetworkReachabilityGetFlags)
public func SCNetworkReachabilityGetFlags(_ target: UnsafeMutableRawPointer?, _ flags: UnsafeMutablePointer<UInt32>?) -> Bool {
    flags?.pointee = 0
    return target != nil
}

@c(_SCNetworkReachabilitySetCallback)
public func SCNetworkReachabilitySetCallback(_ target: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                             _ context: UnsafeRawPointer?) -> Bool {
    target != nil
}

@c(_SCNetworkReachabilityScheduleWithRunLoop)
public func SCNetworkReachabilityScheduleWithRunLoop(_ target: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                                     _ mode: UnsafeMutableRawPointer?) -> Bool {
    target != nil
}

@c(_SCNetworkReachabilityUnscheduleFromRunLoop)
public func SCNetworkReachabilityUnscheduleFromRunLoop(_ target: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                                       _ mode: UnsafeMutableRawPointer?) -> Bool {
    target != nil
}

@c(_SCNetworkReachabilitySetDispatchQueue)
public func SCNetworkReachabilitySetDispatchQueue(_ target: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) -> Bool {
    target != nil
}
