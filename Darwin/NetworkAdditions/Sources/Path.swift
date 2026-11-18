// Network's Swift API newer than the overlay Perry runs with: iOS 13's
// NWPath.isConstrained, which Unity reads, unchecked, from a weak import,
// and iOS 14's NWPath.gateways.
// NWPath is a type of Network's Swift overlay, which a module compiled as
// Network cannot import, so the getter is defined by its symbol: it takes
// the path indirectly and answers in the result register, and as it
// answers the same for every path, it reads no argument.

/// NWPath.isConstrained: whether the path uses an interface in Low Data
/// Mode; never, here.
@_silgen_name("$s7Network6NWPathV13isConstrainedSbvg")
public func _NWPathIsConstrained() -> Bool { false }

/// NWPath.gateways: the gateways of the path, none here. The array is
/// empty, so its element type (an NWEndpoint of the overlay) is not used.
@_silgen_name("$s7Network6NWPathV8gatewaysSayAA10NWEndpointOGvg")
public func _NWPathGateways() -> [Int] { [] }

/// NWPath's members of iOS 26. The overlay's NWPath cannot be extended
/// from here, so this is a type of the same name: its own symbols are
/// found in the overlay first and never used, and those of the members
/// the overlay lacks are found here. The getters answer the same for
/// every path and read nothing of it.
public struct NWPath {
    /// How good the path's link is; never known here.
    public enum LinkQuality: Sendable {
        case unknown
        case minimal
        case moderate
        case good
    }

    /// Why a path cannot be used. A path here is always usable, so no
    /// reason is ever given other than that none is known.
    public enum UnsatisfiedReason: Sendable, Hashable {
        case notAvailable
        case cellularDenied
        case wifiDenied
        case localNetworkDenied
        case vpnInactive
    }

    /// Why the path cannot be used: not known (the path is usable).
    public var unsatisfiedReason: UnsatisfiedReason { .notAvailable }

    /// The quality of the path's link: unknown.
    public var linkQuality: LinkQuality { .unknown }

    /// Whether the path uses an interface in an ultra-constrained mode; never, here.
    public var isUltraConstrained: Bool { false }
}
