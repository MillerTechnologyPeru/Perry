import Foundation

// Adaptive bitmap contexts, which pick their depth, color space and
// headroom from what is drawn.

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
@dynamicMemberLookup
public struct CGBitmapParameters {
    @usableFromInline
    internal var params: UnsafeMutablePointer<__CGBitmapParameters>

    init(_ params: UnsafeMutablePointer<__CGBitmapParameters>) {
        self.params = params
    }

    @inlinable public subscript<T>(dynamicMember keyPath: KeyPath<__CGBitmapParameters, T>) -> T {
        params.pointee[keyPath: keyPath]
    }

    @inlinable public subscript<T>(dynamicMember keyPath: WritableKeyPath<__CGBitmapParameters, T>) -> T {
        get { params.pointee[keyPath: keyPath] }
        _modify { yield &params.pointee[keyPath: keyPath] }
    }

    @inlinable public var colorSpace: CGColorSpace {
        get { params.pointee.colorSpace.takeUnretainedValue() }
        set {
            let retained = Unmanaged.passRetained(newValue)
            params.pointee.colorSpace.release()
            params.pointee.colorSpace = retained
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
public protocol _CGContextInit {
    init?(width: Int, height: Int, auxiliaryInfo: CGContext.AuxiliaryInfo,
          onResolve: ((CGContentInfo, inout CGBitmapParameters) -> Bool)?,
          onAllocate: ((CGContentInfo, CGBitmapParameters) -> CGRenderingBufferProvider?)?,
          onRelease: ((CGRenderingBufferProvider?, CGContentInfo, CGBitmapParameters) -> Void)?,
          onError: ((NSError, CGContentInfo, CGBitmapParameters) -> Void)?)
    init?(width: Int, height: Int, auxiliaryInfo: CGContext.AuxiliaryInfo,
          onResolve: ((CGContentInfo, inout CGBitmapParameters) -> Bool)?)
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension _CGContextInit where Self: CGContext {
    public init?(width: Int, height: Int, auxiliaryInfo: CGContext.AuxiliaryInfo = CGContext.AuxiliaryInfo(),
                 onResolve: ((CGContentInfo, inout CGBitmapParameters) -> Bool)? = nil,
                 onAllocate: ((CGContentInfo, CGBitmapParameters) -> CGRenderingBufferProvider?)? = nil,
                 onRelease: ((CGRenderingBufferProvider?, CGContentInfo, CGBitmapParameters) -> Void)? = nil,
                 onError: ((NSError, CGContentInfo, CGBitmapParameters) -> Void)? = nil) {
        let parameters = { (pointer: UnsafePointer<__CGBitmapParameters>) in
            CGBitmapParameters(UnsafeMutablePointer(mutating: pointer))
        }
        let resolve = onResolve.map { onResolve in
            { (info: UnsafePointer<CGContentInfo>, pointer: UnsafeMutablePointer<__CGBitmapParameters>) -> Bool in
                var bitmap = CGBitmapParameters(pointer)
                return onResolve(info.pointee, &bitmap)
            }
        }
        // The provider made here is the context's until it hands it back
        // to onFree.
        let allocate = onAllocate.map { onAllocate in
            { (info: UnsafePointer<CGContentInfo>, pointer: UnsafePointer<__CGBitmapParameters>) -> Unmanaged<CGRenderingBufferProvider>? in
                onAllocate(info.pointee, parameters(pointer)).map { Unmanaged.passRetained($0) }
            }
        }
        let free = onRelease.map { onRelease in
            { (provider: CGRenderingBufferProvider, info: UnsafePointer<CGContentInfo>, pointer: UnsafePointer<__CGBitmapParameters>) in
                onRelease(provider, info.pointee, parameters(pointer))
            }
        }
        let error = onError.map { onError in
            { (error: CFError, info: UnsafePointer<CGContentInfo>, pointer: UnsafePointer<__CGBitmapParameters>) in
                onError(unsafeBitCast(error, to: NSError.self), info.pointee, parameters(pointer))
            }
        }
        let options: NSDictionary = [__kCGAdaptiveMaximumBitDepth as String: NSNumber(value: auxiliaryInfo.maximumBitDepth.rawValue)]
        guard let context = __CGBitmapContextCreateAdaptive(width, height, options, resolve, allocate, free, error) else {
            return nil
        }
        self = unsafeDowncast(context, to: Self.self)
    }

    public init?(width: Int, height: Int, auxiliaryInfo: CGContext.AuxiliaryInfo,
                 onResolve: ((CGContentInfo, inout CGBitmapParameters) -> Bool)? = nil) {
        self.init(width: width, height: height, auxiliaryInfo: auxiliaryInfo, onResolve: onResolve,
                  onAllocate: nil, onRelease: nil, onError: nil)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CGContext: _CGContextInit {
    public struct AuxiliaryInfo: Equatable, Hashable, Sendable {
        public var maximumBitDepth: CGComponent

        public init() {
            maximumBitDepth = .float16Bit
        }

        @_alwaysEmitIntoClient public init(maximumBitDepth: CGComponent = .float16Bit) {
            self.init()
            self.maximumBitDepth = maximumBitDepth
        }
    }
}
