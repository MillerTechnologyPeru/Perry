// CaptiveNetwork: the Wi-Fi interfaces and the network each is joined to.
// Apple stopped answering apps without an entitlement long ago; here there
// is no Wi-Fi to describe.

/// CFArrayRef CNCopySupportedInterfaces(void): none.
@c(_CNCopySupportedInterfaces)
public func CNCopySupportedInterfaces() -> UnsafeMutableRawPointer? { nil }

/// CFDictionaryRef CNCopyCurrentNetworkInfo(CFStringRef): none.
@c(_CNCopyCurrentNetworkInfo)
public func CNCopyCurrentNetworkInfo(_ interface: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }
