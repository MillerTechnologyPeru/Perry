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
