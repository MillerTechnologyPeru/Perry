import Swift
import simd

// The namespaces of Accelerate's Swift API, and the buffer protocols vDSP,
// vForce, vImage and BNNS take their arguments through.

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public enum vImage {
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public enum vDSP {
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public enum vForce {
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public enum BNNS {
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol AccelerateBuffer<Element> {
    associatedtype Element
    var count: Swift::Int { get }
    func withUnsafeBufferPointer<R>(_ body: (Swift::UnsafeBufferPointer<Self.Element>) throws -> R) rethrows -> R
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol AccelerateMutableBuffer<Element>: Accelerate::AccelerateBuffer {
    mutating func withUnsafeMutableBufferPointer<R>(_ body: (inout Swift::UnsafeMutableBufferPointer<Self.Element>) throws -> R) rethrows -> R
}

// The default implementations for contiguous collections; the symbol
// names are the ones the interface fixes.

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::AccelerateBuffer where Self: Swift::Collection {
    @_silgen_name("$s10Accelerate0A6BufferPAASlRzrlE010withUnsafeB7Pointeryqd__qd__SRy7ElementSTQzGKXEKlF")
    @inlinable public func withUnsafeBufferPointer<R>(_ body: (Swift::UnsafeBufferPointer<Self.Element>) throws -> R) rethrows -> R {
        guard let result = try withContiguousStorageIfAvailable(body) else {
            preconditionFailure("an AccelerateBuffer must have contiguous storage")
        }
        return result
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::AccelerateMutableBuffer where Self: Swift::MutableCollection {
    @_silgen_name("$s10Accelerate0A13MutableBufferPAASMRzrlE010withUnsafebC7Pointeryqd__qd__Sry7ElementSTQzGzKXEKlF")
    @inlinable public mutating func withUnsafeMutableBufferPointer<R>(_ body: (inout Swift::UnsafeMutableBufferPointer<Self.Element>) throws -> R) rethrows -> R {
        guard let result = try withContiguousMutableStorageIfAvailable(body) else {
            preconditionFailure("an AccelerateMutableBuffer must have contiguous storage")
        }
        return result
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Swift::Array: Accelerate::AccelerateMutableBuffer {
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Swift::ContiguousArray: Accelerate::AccelerateMutableBuffer {
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Swift::ArraySlice: Accelerate::AccelerateMutableBuffer {
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Swift::UnsafeBufferPointer: Accelerate::AccelerateBuffer {
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Swift::UnsafeMutableBufferPointer: Accelerate::AccelerateMutableBuffer {
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Swift::Slice: Accelerate::AccelerateBuffer where Base: Accelerate::AccelerateBuffer {
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Swift::Slice: Accelerate::AccelerateMutableBuffer where Base: Accelerate::AccelerateMutableBuffer, Base: Swift::MutableCollection {
}

/// The order of a matrix's elements in memory. Frozen: rowMajor is 0 and
/// columnMajor 1, as the interface lays the enumeration out.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
@frozen public enum AccelerateMatrixOrder: Swift::Int {
    case rowMajor
    case columnMajor

    public init?(rawValue: Swift::Int) {
        switch rawValue {
        case 0: self = .rowMajor
        case 1: self = .columnMajor
        default: return nil
        }
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    public typealias RawValue = Swift::Int

    public var rawValue: Swift::Int {
        switch self {
        case .rowMajor: return 0
        case .columnMajor: return 1
        }
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
public protocol AccelerateMatrixBuffer<Element> {
    associatedtype Element
    var rowCount: Swift::Int { get }
    var columnCount: Swift::Int { get }
    var accelerateMatrixOrder: Accelerate::AccelerateMatrixOrder { get }
    var leadingDimension: Swift::Int { get }
    func withUnsafeBufferPointer<R>(_ body: (Swift::UnsafeBufferPointer<Self.Element>) throws -> R) rethrows -> R
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
public protocol AccelerateMutableMatrixBuffer<Element>: Accelerate::AccelerateMatrixBuffer {
    mutating func withUnsafeMutableBufferPointer<R>(_ body: (inout Swift::UnsafeMutableBufferPointer<Self.Element>) throws -> R) rethrows -> R
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension Accelerate::AccelerateMatrixOrder: Swift::Equatable {}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension Accelerate::AccelerateMatrixOrder: Swift::Hashable {}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension Accelerate::AccelerateMatrixOrder: Swift::RawRepresentable {}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension Accelerate::AccelerateMatrixOrder: Swift::Sendable {}
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension Accelerate::AccelerateMatrixOrder: Swift::BitwiseCopyable {}
