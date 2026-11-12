// CFHost, CFNetwork's name resolution: no host can be made, so an app that
// checks a name with it (PlayHaven's reachability test) takes its
// resolution-failed path, where a missing import it calls would jump to
// address zero.

@c(_CFHostCreateWithName)
public func CFHostCreateWithName(_ allocator: UnsafeMutableRawPointer?, _ hostname: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    nil
}

@c(_CFHostStartInfoResolution)
public func CFHostStartInfoResolution(_ host: UnsafeMutableRawPointer?, _ info: Int32, _ error: UnsafeMutableRawPointer?) -> Bool {
    false
}

@c(_CFHostGetAddressing)
public func CFHostGetAddressing(_ host: UnsafeMutableRawPointer?, _ hasBeenResolved: UnsafeMutablePointer<UInt8>?) -> UnsafeMutableRawPointer? {
    hasBeenResolved?.pointee = 0
    return nil
}
