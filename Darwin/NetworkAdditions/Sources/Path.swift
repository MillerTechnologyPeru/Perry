// Network's Swift API newer than the overlay Perry runs with: iOS 13's
// NWPath.isConstrained, which Unity reads, unchecked, from a weak import.
// NWPath is a type of Network's Swift overlay, which a module compiled as
// Network cannot import, so the getter is defined by its symbol: it takes
// the path indirectly and answers in the result register, and as it
// answers the same for every path, it reads no argument.

/// NWPath.isConstrained: whether the path uses an interface in Low Data
/// Mode; never, here.
@_silgen_name("$s7Network6NWPathV13isConstrainedSbvg")
public func _NWPathIsConstrained() -> Bool { false }
