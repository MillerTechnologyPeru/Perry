// simd's functions of Float16 vectors, which the SDK exports only on arm64
// (Swift has no Float16 on x86_64 macOS). Element by element, over the
// standard library's Float16.

#if arch(arm64)

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func abs(_ x: SIMD2<Float16>) -> SIMD2<Float16> {
    return x.replacing(with: -x, where: x .< 0)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ x: SIMD2<Float16>, _ y: SIMD2<Float16>) -> SIMD2<Float16> {
    return pointwiseMin(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ x: SIMD2<Float16>, _ y: SIMD2<Float16>) -> SIMD2<Float16> {
    return pointwiseMax(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ vector: SIMD2<Float16>, _ scalar: Float16) -> SIMD2<Float16> {
    return pointwiseMin(vector, SIMD2<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ vector: SIMD2<Float16>, _ scalar: Float16) -> SIMD2<Float16> {
    return pointwiseMax(vector, SIMD2<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func ceil(_ x: SIMD2<Float16>) -> SIMD2<Float16> {
    return x.rounded(.up)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func floor(_ x: SIMD2<Float16>) -> SIMD2<Float16> {
    return x.rounded(.down)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func trunc(_ x: SIMD2<Float16>) -> SIMD2<Float16> {
    return x.rounded(.towardZero)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func rint(_ x: SIMD2<Float16>) -> SIMD2<Float16> {
    return x.rounded(.toNearestOrEven)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func sqrt(_ x: SIMD2<Float16>) -> SIMD2<Float16> {
    var r = x
    for i in r.indices { r[i] = x[i].squareRoot() }
    return r
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func abs(_ x: SIMD3<Float16>) -> SIMD3<Float16> {
    return x.replacing(with: -x, where: x .< 0)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ x: SIMD3<Float16>, _ y: SIMD3<Float16>) -> SIMD3<Float16> {
    return pointwiseMin(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ x: SIMD3<Float16>, _ y: SIMD3<Float16>) -> SIMD3<Float16> {
    return pointwiseMax(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ vector: SIMD3<Float16>, _ scalar: Float16) -> SIMD3<Float16> {
    return pointwiseMin(vector, SIMD3<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ vector: SIMD3<Float16>, _ scalar: Float16) -> SIMD3<Float16> {
    return pointwiseMax(vector, SIMD3<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func ceil(_ x: SIMD3<Float16>) -> SIMD3<Float16> {
    return x.rounded(.up)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func floor(_ x: SIMD3<Float16>) -> SIMD3<Float16> {
    return x.rounded(.down)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func trunc(_ x: SIMD3<Float16>) -> SIMD3<Float16> {
    return x.rounded(.towardZero)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func rint(_ x: SIMD3<Float16>) -> SIMD3<Float16> {
    return x.rounded(.toNearestOrEven)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func sqrt(_ x: SIMD3<Float16>) -> SIMD3<Float16> {
    var r = x
    for i in r.indices { r[i] = x[i].squareRoot() }
    return r
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func abs(_ x: SIMD4<Float16>) -> SIMD4<Float16> {
    return x.replacing(with: -x, where: x .< 0)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ x: SIMD4<Float16>, _ y: SIMD4<Float16>) -> SIMD4<Float16> {
    return pointwiseMin(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ x: SIMD4<Float16>, _ y: SIMD4<Float16>) -> SIMD4<Float16> {
    return pointwiseMax(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ vector: SIMD4<Float16>, _ scalar: Float16) -> SIMD4<Float16> {
    return pointwiseMin(vector, SIMD4<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ vector: SIMD4<Float16>, _ scalar: Float16) -> SIMD4<Float16> {
    return pointwiseMax(vector, SIMD4<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func ceil(_ x: SIMD4<Float16>) -> SIMD4<Float16> {
    return x.rounded(.up)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func floor(_ x: SIMD4<Float16>) -> SIMD4<Float16> {
    return x.rounded(.down)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func trunc(_ x: SIMD4<Float16>) -> SIMD4<Float16> {
    return x.rounded(.towardZero)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func rint(_ x: SIMD4<Float16>) -> SIMD4<Float16> {
    return x.rounded(.toNearestOrEven)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func sqrt(_ x: SIMD4<Float16>) -> SIMD4<Float16> {
    var r = x
    for i in r.indices { r[i] = x[i].squareRoot() }
    return r
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func abs(_ x: SIMD8<Float16>) -> SIMD8<Float16> {
    return x.replacing(with: -x, where: x .< 0)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ x: SIMD8<Float16>, _ y: SIMD8<Float16>) -> SIMD8<Float16> {
    return pointwiseMin(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ x: SIMD8<Float16>, _ y: SIMD8<Float16>) -> SIMD8<Float16> {
    return pointwiseMax(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ vector: SIMD8<Float16>, _ scalar: Float16) -> SIMD8<Float16> {
    return pointwiseMin(vector, SIMD8<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ vector: SIMD8<Float16>, _ scalar: Float16) -> SIMD8<Float16> {
    return pointwiseMax(vector, SIMD8<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func ceil(_ x: SIMD8<Float16>) -> SIMD8<Float16> {
    return x.rounded(.up)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func floor(_ x: SIMD8<Float16>) -> SIMD8<Float16> {
    return x.rounded(.down)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func trunc(_ x: SIMD8<Float16>) -> SIMD8<Float16> {
    return x.rounded(.towardZero)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func rint(_ x: SIMD8<Float16>) -> SIMD8<Float16> {
    return x.rounded(.toNearestOrEven)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func sqrt(_ x: SIMD8<Float16>) -> SIMD8<Float16> {
    var r = x
    for i in r.indices { r[i] = x[i].squareRoot() }
    return r
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func abs(_ x: SIMD16<Float16>) -> SIMD16<Float16> {
    return x.replacing(with: -x, where: x .< 0)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ x: SIMD16<Float16>, _ y: SIMD16<Float16>) -> SIMD16<Float16> {
    return pointwiseMin(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ x: SIMD16<Float16>, _ y: SIMD16<Float16>) -> SIMD16<Float16> {
    return pointwiseMax(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ vector: SIMD16<Float16>, _ scalar: Float16) -> SIMD16<Float16> {
    return pointwiseMin(vector, SIMD16<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ vector: SIMD16<Float16>, _ scalar: Float16) -> SIMD16<Float16> {
    return pointwiseMax(vector, SIMD16<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func ceil(_ x: SIMD16<Float16>) -> SIMD16<Float16> {
    return x.rounded(.up)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func floor(_ x: SIMD16<Float16>) -> SIMD16<Float16> {
    return x.rounded(.down)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func trunc(_ x: SIMD16<Float16>) -> SIMD16<Float16> {
    return x.rounded(.towardZero)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func rint(_ x: SIMD16<Float16>) -> SIMD16<Float16> {
    return x.rounded(.toNearestOrEven)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func sqrt(_ x: SIMD16<Float16>) -> SIMD16<Float16> {
    var r = x
    for i in r.indices { r[i] = x[i].squareRoot() }
    return r
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func abs(_ x: SIMD32<Float16>) -> SIMD32<Float16> {
    return x.replacing(with: -x, where: x .< 0)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ x: SIMD32<Float16>, _ y: SIMD32<Float16>) -> SIMD32<Float16> {
    return pointwiseMin(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ x: SIMD32<Float16>, _ y: SIMD32<Float16>) -> SIMD32<Float16> {
    return pointwiseMax(x, y)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func min(_ vector: SIMD32<Float16>, _ scalar: Float16) -> SIMD32<Float16> {
    return pointwiseMin(vector, SIMD32<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func max(_ vector: SIMD32<Float16>, _ scalar: Float16) -> SIMD32<Float16> {
    return pointwiseMax(vector, SIMD32<Float16>(repeating: scalar))
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func ceil(_ x: SIMD32<Float16>) -> SIMD32<Float16> {
    return x.rounded(.up)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func floor(_ x: SIMD32<Float16>) -> SIMD32<Float16> {
    return x.rounded(.down)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func trunc(_ x: SIMD32<Float16>) -> SIMD32<Float16> {
    return x.rounded(.towardZero)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func rint(_ x: SIMD32<Float16>) -> SIMD32<Float16> {
    return x.rounded(.toNearestOrEven)
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public func sqrt(_ x: SIMD32<Float16>) -> SIMD32<Float16> {
    var r = x
    for i in r.indices { r[i] = x[i].squareRoot() }
    return r
}

#endif
