import PerryObjCInterop

// Secure Transport (SSLContext), Darwin's deprecated TLS API, isn't
// implemented: no context can be made, so a connection that asks for one
// fails at once rather than in the middle, as on a system without TLS.
// Every other call on a context says it is invalid.

/// errSSLInternal, and paramErr for a context that doesn't exist.
private let errSSLInternal: Int32 = -9810
private let paramErr: Int32 = -50

nonisolated(unsafe) private var warned = false

@c(_SSLCreateContext)
public func SSLCreateContext(_ allocator: UnsafeRawPointer?, _ side: Int32, _ type: Int32) -> UnsafeMutableRawPointer? {
    if !warned {
        warned = true
        securityWarning("SSLCreateContext: Secure Transport isn't implemented; TLS connections through it fail")
    }
    return nil
}

@c(_SSLNewContext)
public func SSLNewContext(_ isServer: Bool, _ context: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    context?.pointee = SSLCreateContext(nil, isServer ? 0 : 1, 0)
    return errSSLInternal
}

@c(_SSLClose) public func SSLClose(_ context: UnsafeMutableRawPointer?) -> Int32 { paramErr }
@c(_SSLHandshake) public func SSLHandshake(_ context: UnsafeMutableRawPointer?) -> Int32 { context == nil ? paramErr : errSSLInternal }

@c(_SSLRead)
public func SSLRead(_ context: UnsafeMutableRawPointer?, _ data: UnsafeMutableRawPointer?, _ length: Int,
                    _ processed: UnsafeMutablePointer<Int>?) -> Int32 {
    processed?.pointee = 0
    return context == nil ? paramErr : errSSLInternal
}

@c(_SSLWrite)
public func SSLWrite(_ context: UnsafeMutableRawPointer?, _ data: UnsafeRawPointer?, _ length: Int,
                     _ processed: UnsafeMutablePointer<Int>?) -> Int32 {
    processed?.pointee = 0
    return context == nil ? paramErr : errSSLInternal
}

@c(_SSLGetBufferedReadSize)
public func SSLGetBufferedReadSize(_ context: UnsafeMutableRawPointer?, _ size: UnsafeMutablePointer<Int>?) -> Int32 {
    size?.pointee = 0
    return paramErr
}

@c(_SSLSetIOFuncs)
public func SSLSetIOFuncs(_ context: UnsafeMutableRawPointer?, _ read: UnsafeRawPointer?, _ write: UnsafeRawPointer?) -> Int32 { paramErr }
@c(_SSLSetConnection)
public func SSLSetConnection(_ context: UnsafeMutableRawPointer?, _ connection: UnsafeRawPointer?) -> Int32 { paramErr }
@c(_SSLSetPeerDomainName)
public func SSLSetPeerDomainName(_ context: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?, _ length: Int) -> Int32 { paramErr }
@c(_SSLSetPeerID)
public func SSLSetPeerID(_ context: UnsafeMutableRawPointer?, _ peerID: UnsafeRawPointer?, _ length: Int) -> Int32 { paramErr }
@c(_SSLSetProtocolVersionMin) public func SSLSetProtocolVersionMin(_ context: UnsafeMutableRawPointer?, _ version: Int32) -> Int32 { paramErr }
@c(_SSLSetProtocolVersionMax) public func SSLSetProtocolVersionMax(_ context: UnsafeMutableRawPointer?, _ version: Int32) -> Int32 { paramErr }
@c(_SSLSetSessionOption)
public func SSLSetSessionOption(_ context: UnsafeMutableRawPointer?, _ option: Int32, _ value: Bool) -> Int32 { paramErr }
@c(_SSLSetCertificate) public func SSLSetCertificate(_ context: UnsafeMutableRawPointer?, _ certificates: UnsafeRawPointer?) -> Int32 { paramErr }
@c(_SSLSetALPNProtocols) public func SSLSetALPNProtocols(_ context: UnsafeMutableRawPointer?, _ protocols: UnsafeRawPointer?) -> Int32 { paramErr }

@c(_SSLCopyALPNProtocols)
public func SSLCopyALPNProtocols(_ context: UnsafeMutableRawPointer?, _ protocols: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    protocols?.pointee = nil
    return paramErr
}

@c(_SSLCopyPeerTrust)
public func SSLCopyPeerTrust(_ context: UnsafeMutableRawPointer?, _ trust: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    trust?.pointee = nil
    return paramErr
}

@c(_SSLGetNegotiatedCipher)
public func SSLGetNegotiatedCipher(_ context: UnsafeMutableRawPointer?, _ cipher: UnsafeMutablePointer<UInt16>?) -> Int32 { paramErr }

@c(_SSLGetNegotiatedProtocolVersion)
public func SSLGetNegotiatedProtocolVersion(_ context: UnsafeMutableRawPointer?, _ version: UnsafeMutablePointer<Int32>?) -> Int32 { paramErr }

@c(_SSLGetNumberSupportedCiphers)
public func SSLGetNumberSupportedCiphers(_ context: UnsafeMutableRawPointer?, _ count: UnsafeMutablePointer<Int>?) -> Int32 {
    count?.pointee = 0
    return paramErr
}

@c(_SSLGetSupportedCiphers)
public func SSLGetSupportedCiphers(_ context: UnsafeMutableRawPointer?, _ ciphers: UnsafeMutablePointer<UInt16>?,
                                   _ count: UnsafeMutablePointer<Int>?) -> Int32 {
    count?.pointee = 0
    return paramErr
}

@c(_SSLSetEnabledCiphers)
public func SSLSetEnabledCiphers(_ context: UnsafeMutableRawPointer?, _ ciphers: UnsafePointer<UInt16>?, _ count: Int) -> Int32 { paramErr }
