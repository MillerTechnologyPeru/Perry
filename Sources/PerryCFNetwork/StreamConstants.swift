import PerryObjCInterop

/// Socket streams' TLS and service-type keys, which CFNetwork exports on
/// Darwin: a program builds a stream's kCFStreamPropertySSLSettings from
/// them. Foundation's socket streams read the same strings.
@ObjCConstants
enum StreamSecurityKeys {
    static let kCFStreamPropertySSLSettings = "kCFStreamPropertySSLSettings"
    static let kCFStreamPropertySSLPeerTrust = "kCFStreamPropertySSLPeerTrust"
    static let kCFStreamPropertySSLContext = "kCFStreamPropertySSLContext"
    static let kCFStreamSSLLevel = "kCFStreamSSLLevel"
    static let kCFStreamSSLPeerName = "kCFStreamSSLPeerName"
    static let kCFStreamSSLCertificates = "kCFStreamSSLCertificates"
    static let kCFStreamSSLIsServer = "kCFStreamSSLIsServer"
    static let kCFStreamSSLValidatesCertificateChain = "kCFStreamSSLValidatesCertificateChain"
    static let kCFStreamSSLAllowsAnyRoot = "kCFStreamSSLAllowsAnyRoot"
    static let kCFStreamSSLAllowsExpiredCertificates = "kCFStreamSSLAllowsExpiredCertificates"
    static let kCFStreamSSLAllowsExpiredRoots = "kCFStreamSSLAllowsExpiredRoots"
    static let kCFStreamNetworkServiceType = "kCFStreamNetworkServiceType"
    static let kCFStreamNetworkServiceTypeVoIP = "kCFStreamNetworkServiceTypeVoIP"
    static let kCFStreamNetworkServiceTypeVideo = "kCFStreamNetworkServiceTypeVideo"
    static let kCFStreamNetworkServiceTypeBackground = "kCFStreamNetworkServiceTypeBackground"
    static let kCFStreamNetworkServiceTypeVoice = "kCFStreamNetworkServiceTypeVoice"
}
