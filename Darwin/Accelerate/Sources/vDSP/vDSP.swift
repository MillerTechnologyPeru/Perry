// vDSP, vForce, Quadrature and BLAS: Accelerate's Swift API over the C
// functions of vDSP.h, vForce.h, Quadrature and thread_api.h. The
// declarations are the SDK interface's; the bodies are Perry's.

import Swift
import _Concurrency
import _StringProcessing
import _SwiftConcurrencyShims
import simd
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
  public struct VectorizableFloat {
    public typealias Scalar = Swift::Float
  }
  @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
  public struct VectorizableDouble {
    public typealias Scalar = Swift::Double
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func convolve<T, U>(_ vector: T, withKernel kernel: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vector.count - kernel.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.convolve(vector, withKernel: kernel, result: &result) }
  }
  public static func convolve<T, U, V>(_ vector: T, withKernel kernel: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n + kernel.count - 1)
      let p = kernel.count
      _wr(&result) { r in _rd(vector) { v in _rd(kernel) { k in vDSP_conv(v, 1, k.advanced(by: p - 1), -1, r, 1, vDSP_Length(n), vDSP_Length(p)) } } }
  }
  public static func convolve<T, U>(_ vector: T, withKernel kernel: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vector.count - kernel.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.convolve(vector, withKernel: kernel, result: &result) }
  }
  public static func convolve<T, U, V>(_ vector: T, withKernel kernel: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n + kernel.count - 1)
      let p = kernel.count
      _wr(&result) { r in _rd(vector) { v in _rd(kernel) { k in vDSP_convD(v, 1, k.advanced(by: p - 1), -1, r, 1, vDSP_Length(n), vDSP_Length(p)) } } }
  }
  public static func correlate<T, U>(_ vector: T, withKernel kernel: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vector.count - kernel.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.correlate(vector, withKernel: kernel, result: &result) }
  }
  public static func correlate<T, U, V>(_ vector: T, withKernel kernel: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n + kernel.count - 1)
      let p = kernel.count
      _wr(&result) { r in _rd(vector) { v in _rd(kernel) { k in vDSP_conv(v, 1, k, 1, r, 1, vDSP_Length(n), vDSP_Length(p)) } } }
  }
  public static func correlate<T, U>(_ vector: T, withKernel kernel: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vector.count - kernel.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.correlate(vector, withKernel: kernel, result: &result) }
  }
  public static func correlate<T, U, V>(_ vector: T, withKernel kernel: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n + kernel.count - 1)
      let p = kernel.count
      _wr(&result) { r in _rd(vector) { v in _rd(kernel) { k in vDSP_convD(v, 1, k, 1, r, 1, vDSP_Length(n), vDSP_Length(p)) } } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func convolve<T, U>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, with3x3Kernel kernel: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(rowCount * columnCount) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.convolve(vector, rowCount: rowCount, columnCount: columnCount, with3x3Kernel: kernel, result: &result) }
  }
  public static func convolve<T, U, V>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, with3x3Kernel kernel: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = rowCount * columnCount
      precondition(vector.count >= n && result.count >= n && kernel.count >= 9)
      _wr(&result) { r in _rd(vector) { v in _rd(kernel) { k in vDSP_f3x3(v, vDSP_Length(rowCount), vDSP_Length(columnCount), k, r) } } }
  }
  public static func convolve<T, U>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, with3x3Kernel kernel: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(rowCount * columnCount) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.convolve(vector, rowCount: rowCount, columnCount: columnCount, with3x3Kernel: kernel, result: &result) }
  }
  public static func convolve<T, U, V>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, with3x3Kernel kernel: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = rowCount * columnCount
      precondition(vector.count >= n && result.count >= n && kernel.count >= 9)
      _wr(&result) { r in _rd(vector) { v in _rd(kernel) { k in vDSP_f3x3D(v, vDSP_Length(rowCount), vDSP_Length(columnCount), k, r) } } }
  }
  public static func convolve<T, U>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, with5x5Kernel kernel: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(rowCount * columnCount) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.convolve(vector, rowCount: rowCount, columnCount: columnCount, with5x5Kernel: kernel, result: &result) }
  }
  public static func convolve<T, U, V>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, with5x5Kernel kernel: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = rowCount * columnCount
      precondition(vector.count >= n && result.count >= n && kernel.count >= 25)
      _wr(&result) { r in _rd(vector) { v in _rd(kernel) { k in vDSP_f5x5(v, vDSP_Length(rowCount), vDSP_Length(columnCount), k, r) } } }
  }
  public static func convolve<T, U>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, with5x5Kernel kernel: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(rowCount * columnCount) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.convolve(vector, rowCount: rowCount, columnCount: columnCount, with5x5Kernel: kernel, result: &result) }
  }
  public static func convolve<T, U, V>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, with5x5Kernel kernel: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = rowCount * columnCount
      precondition(vector.count >= n && result.count >= n && kernel.count >= 25)
      _wr(&result) { r in _rd(vector) { v in _rd(kernel) { k in vDSP_f5x5D(v, vDSP_Length(rowCount), vDSP_Length(columnCount), k, r) } } }
  }
  public static func convolve<T, U>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, withKernel kernel: U, kernelRowCount: Swift::Int, kernelColumnCount: Swift::Int) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(rowCount * columnCount) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.convolve(vector, rowCount: rowCount, columnCount: columnCount, withKernel: kernel, kernelRowCount: kernelRowCount, kernelColumnCount: kernelColumnCount, result: &result) }
  }
  public static func convolve<T, U, V>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, withKernel kernel: U, kernelRowCount: Swift::Int, kernelColumnCount: Swift::Int, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = rowCount * columnCount
      precondition(vector.count >= n && result.count >= n && kernel.count >= kernelRowCount * kernelColumnCount)
      _wr(&result) { r in _rd(vector) { v in _rd(kernel) { k in vDSP_imgfir(v, vDSP_Length(rowCount), vDSP_Length(columnCount), k, r, vDSP_Length(kernelRowCount), vDSP_Length(kernelColumnCount)) } } }
  }
  public static func convolve<T, U>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, withKernel kernel: U, kernelRowCount: Swift::Int, kernelColumnCount: Swift::Int) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(rowCount * columnCount) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.convolve(vector, rowCount: rowCount, columnCount: columnCount, withKernel: kernel, kernelRowCount: kernelRowCount, kernelColumnCount: kernelColumnCount, result: &result) }
  }
  public static func convolve<T, U, V>(_ vector: T, rowCount: Swift::Int, columnCount: Swift::Int, withKernel kernel: U, kernelRowCount: Swift::Int, kernelColumnCount: Swift::Int, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = rowCount * columnCount
      precondition(vector.count >= n && result.count >= n && kernel.count >= kernelRowCount * kernelColumnCount)
      _wr(&result) { r in _rd(vector) { v in _rd(kernel) { k in vDSP_imgfirD(v, vDSP_Length(rowCount), vDSP_Length(columnCount), k, r, vDSP_Length(kernelRowCount), vDSP_Length(kernelColumnCount)) } } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func downsample<T, U>(_ source: U, decimationFactor: Swift::Int, filter: T) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make((source.count - filter.count) / decimationFactor + 1) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.downsample(source, decimationFactor: decimationFactor, filter: filter, result: &result) }
  }
  public static func downsample<T, U, V>(_ source: U, decimationFactor: Swift::Int, filter: T, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      let p = filter.count
      precondition(n == 0 || source.count >= (n - 1) * decimationFactor + p)
      _wr(&result) { r in _rd(source) { s in _rd(filter) { f in vDSP_desamp(s, decimationFactor, f, r, vDSP_Length(n), vDSP_Length(p)) } } }
  }
  public static func downsample<T, U>(_ source: U, decimationFactor: Swift::Int, filter: T) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make((source.count - filter.count) / decimationFactor + 1) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.downsample(source, decimationFactor: decimationFactor, filter: filter, result: &result) }
  }
  public static func downsample<T, U, V>(_ source: U, decimationFactor: Swift::Int, filter: T, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      let p = filter.count
      precondition(n == 0 || source.count >= (n - 1) * decimationFactor + p)
      _wr(&result) { r in _rd(source) { s in _rd(filter) { f in vDSP_desampD(s, decimationFactor, f, r, vDSP_Length(n), vDSP_Length(p)) } } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func convert(splitComplexVector: Accelerate::DSPSplitComplex, toInterleavedComplexVector interleavedComplexVector: inout [Accelerate::DSPComplex]) {
      var split = splitComplexVector
      let n = interleavedComplexVector.count
      interleavedComplexVector.withUnsafeMutableBufferPointer { c in
          c.baseAddress.map { vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(n)) }
      }
  }
  public static func convert(interleavedComplexVector: [Accelerate::DSPComplex], toSplitComplexVector splitComplexVector: inout Accelerate::DSPSplitComplex) {
      let n = interleavedComplexVector.count
      interleavedComplexVector.withUnsafeBufferPointer { c in
          c.baseAddress.map { vDSP_ctoz($0, 2, &splitComplexVector, 1, vDSP_Length(n)) }
      }
  }
  public static func convert(splitComplexVector: Accelerate::DSPDoubleSplitComplex, toInterleavedComplexVector interleavedComplexVector: inout [Accelerate::DSPDoubleComplex]) {
      var split = splitComplexVector
      let n = interleavedComplexVector.count
      interleavedComplexVector.withUnsafeMutableBufferPointer { c in
          c.baseAddress.map { vDSP_ztocD(&split, 1, $0, 2, vDSP_Length(n)) }
      }
  }
  public static func convert(interleavedComplexVector: [Accelerate::DSPDoubleComplex], toSplitComplexVector splitComplexVector: inout Accelerate::DSPDoubleSplitComplex) {
      let n = interleavedComplexVector.count
      interleavedComplexVector.withUnsafeBufferPointer { c in
          c.baseAddress.map { vDSP_ctozD($0, 2, &splitComplexVector, 1, vDSP_Length(n)) }
      }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func maximum<U>(_ vector: U) -> Swift::Float where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var r: Float = 0
      let n = vector.count
      _rd(vector) { v in vDSP_maxv(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func maximum<U>(_ vector: U) -> Swift::Double where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var r: Double = 0
      let n = vector.count
      _rd(vector) { v in vDSP_maxvD(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func maximumMagnitude<U>(_ vector: U) -> Swift::Float where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var r: Float = 0
      let n = vector.count
      _rd(vector) { v in vDSP_maxmgv(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func maximumMagnitude<U>(_ vector: U) -> Swift::Double where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var r: Double = 0
      let n = vector.count
      _rd(vector) { v in vDSP_maxmgvD(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func minimum<U>(_ vector: U) -> Swift::Float where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var r: Float = 0
      let n = vector.count
      _rd(vector) { v in vDSP_minv(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func minimum<U>(_ vector: U) -> Swift::Double where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var r: Double = 0
      let n = vector.count
      _rd(vector) { v in vDSP_minvD(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func sum<U>(_ vector: U) -> Swift::Float where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var r: Float = 0
      let n = vector.count
      _rd(vector) { v in vDSP_sve(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func sum<U>(_ vector: U) -> Swift::Double where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var r: Double = 0
      let n = vector.count
      _rd(vector) { v in vDSP_sveD(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func sumOfSquares<U>(_ vector: U) -> Swift::Float where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var r: Float = 0
      let n = vector.count
      _rd(vector) { v in vDSP_svesq(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func sumOfSquares<U>(_ vector: U) -> Swift::Double where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var r: Double = 0
      let n = vector.count
      _rd(vector) { v in vDSP_svesqD(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func sumAndSumOfSquares<U>(_ vector: U) -> (elementsSum: Swift::Float, squaresSum: Swift::Float) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var sum: Float = 0
      var squares: Float = 0
      let n = vector.count
      _rd(vector) { v in vDSP_sve_svesq(v, 1, &sum, &squares, vDSP_Length(n)) }
      return (sum, squares)
  }
  public static func sumAndSumOfSquares<U>(_ vector: U) -> (elementsSum: Swift::Double, squaresSum: Swift::Double) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var sum: Double = 0
      var squares: Double = 0
      let n = vector.count
      _rd(vector) { v in vDSP_sve_svesqD(v, 1, &sum, &squares, vDSP_Length(n)) }
      return (sum, squares)
  }
  public static func sumOfMagnitudes<U>(_ vector: U) -> Swift::Float where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var r: Float = 0
      let n = vector.count
      _rd(vector) { v in vDSP_svemg(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func sumOfMagnitudes<U>(_ vector: U) -> Swift::Double where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var r: Double = 0
      let n = vector.count
      _rd(vector) { v in vDSP_svemgD(v, 1, &r, vDSP_Length(n)) }
      return r
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func indexOfMaximum<U>(_ vector: U) -> (Swift::UInt, Swift::Float) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var value: Float = 0
      var index: vDSP_Length = 0
      let n = vector.count
      _rd(vector) { v in vDSP_maxvi(v, 1, &value, &index, vDSP_Length(n)) }
      return (UInt(index), value)
  }
  public static func indexOfMaximum<U>(_ vector: U) -> (Swift::UInt, Swift::Double) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var value: Double = 0
      var index: vDSP_Length = 0
      let n = vector.count
      _rd(vector) { v in vDSP_maxviD(v, 1, &value, &index, vDSP_Length(n)) }
      return (UInt(index), value)
  }
  public static func indexOfMaximumMagnitude<U>(_ vector: U) -> (Swift::UInt, Swift::Float) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var value: Float = 0
      var index: vDSP_Length = 0
      let n = vector.count
      _rd(vector) { v in vDSP_maxmgvi(v, 1, &value, &index, vDSP_Length(n)) }
      return (UInt(index), value)
  }
  public static func indexOfMaximumMagnitude<U>(_ vector: U) -> (Swift::UInt, Swift::Double) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var value: Double = 0
      var index: vDSP_Length = 0
      let n = vector.count
      _rd(vector) { v in vDSP_maxmgviD(v, 1, &value, &index, vDSP_Length(n)) }
      return (UInt(index), value)
  }
  public static func indexOfMinimum<U>(_ vector: U) -> (Swift::UInt, Swift::Float) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var value: Float = 0
      var index: vDSP_Length = 0
      let n = vector.count
      _rd(vector) { v in vDSP_minvi(v, 1, &value, &index, vDSP_Length(n)) }
      return (UInt(index), value)
  }
  public static func indexOfMinimum<U>(_ vector: U) -> (Swift::UInt, Swift::Double) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var value: Double = 0
      var index: vDSP_Length = 0
      let n = vector.count
      _rd(vector) { v in vDSP_minviD(v, 1, &value, &index, vDSP_Length(n)) }
      return (UInt(index), value)
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func meanSquare<U>(_ vector: U) -> Swift::Float where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var r: Float = 0
      let n = vector.count
      _rd(vector) { v in vDSP_measqv(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func meanSquare<U>(_ vector: U) -> Swift::Double where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var r: Double = 0
      let n = vector.count
      _rd(vector) { v in vDSP_measqvD(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func meanMagnitude<U>(_ vector: U) -> Swift::Float where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var r: Float = 0
      let n = vector.count
      _rd(vector) { v in vDSP_meamgv(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func meanMagnitude<U>(_ vector: U) -> Swift::Double where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var r: Double = 0
      let n = vector.count
      _rd(vector) { v in vDSP_meamgvD(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func mean<U>(_ vector: U) -> Swift::Float where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var r: Float = 0
      let n = vector.count
      _rd(vector) { v in vDSP_meanv(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func mean<U>(_ vector: U) -> Swift::Double where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var r: Double = 0
      let n = vector.count
      _rd(vector) { v in vDSP_meanvD(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func rootMeanSquare<U>(_ vector: U) -> Swift::Float where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      var r: Float = 0
      let n = vector.count
      _rd(vector) { v in vDSP_rmsqv(v, 1, &r, vDSP_Length(n)) }
      return r
  }
  public static func rootMeanSquare<U>(_ vector: U) -> Swift::Double where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      var r: Double = 0
      let n = vector.count
      _rd(vector) { v in vDSP_rmsqvD(v, 1, &r, vDSP_Length(n)) }
      return r
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::UInt8, V.Element == Swift::Float {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vfltu8(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::UInt8, V.Element == Swift::Double {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vfltu8D(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::UInt16, V.Element == Swift::Float {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vfltu16(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::UInt16, V.Element == Swift::Double {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vfltu16D(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::UInt32, V.Element == Swift::Float {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vfltu32(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::UInt32, V.Element == Swift::Double {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vfltu32D(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Int8, V.Element == Swift::Float {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vflt8(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Int8, V.Element == Swift::Double {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vflt8D(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Int16, V.Element == Swift::Float {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vflt16(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Int16, V.Element == Swift::Double {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vflt16D(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Int32, V.Element == Swift::Float {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vflt32(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Int32, V.Element == Swift::Double {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vflt32D(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public enum RoundingMode {
    case towardZero
    case towardNearestInteger
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Int32 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfix32(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixr32(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Int32 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfix32D(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixr32D(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::UInt16 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfixu16(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixru16(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::UInt16 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfixu16D(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixru16D(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::UInt32 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfixu32(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixru32(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::UInt32 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfixu32D(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixru32D(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Int16 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfix16(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixr16(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Int16 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfix16D(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixr16D(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Int8 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfix8(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixr8(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Int8 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfix8D(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixr8D(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::UInt8 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfixu8(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixru8(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V, rounding: Accelerate::vDSP.Accelerate::RoundingMode) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::UInt8 {
      let n = destination.count
      precondition(source.count >= n)
      switch rounding {
      case .towardZero: _wr(&destination) { d in _rd(source) { s in vDSP_vfixu8D(s, 1, d, 1, vDSP_Length(n)) } }
      case .towardNearestInteger: _wr(&destination) { d in _rd(source) { s in vDSP_vfixru8D(s, 1, d, 1, vDSP_Length(n)) } }
      }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Double {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vspdp(s, 1, d, 1, vDSP_Length(n)) } }
  }
  public static func convertElements<U, V>(of source: U, to destination: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Float {
      let n = destination.count
      precondition(source.count >= n)
      _wr(&destination) { d in _rd(source) { s in vDSP_vdpsp(s, 1, d, 1, vDSP_Length(n)) } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol vDSP_IntegerConvertable {
}
extension Swift::UInt8 : Accelerate::vDSP_IntegerConvertable {
}
extension Swift::UInt16 : Accelerate::vDSP_IntegerConvertable {
}
extension Swift::UInt32 : Accelerate::vDSP_IntegerConvertable {
}
extension Swift::Int8 : Accelerate::vDSP_IntegerConvertable {
}
extension Swift::Int16 : Accelerate::vDSP_IntegerConvertable {
}
extension Swift::Int32 : Accelerate::vDSP_IntegerConvertable {
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol vDSP_FloatingPointConvertable {
}
extension Swift::Float : Accelerate::vDSP_FloatingPointConvertable {
}
extension Swift::Double : Accelerate::vDSP_FloatingPointConvertable {
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func integerToFloatingPoint<T, U>(_ vector: T, floatingPointType: U.Type) -> [U] where T : Accelerate::AccelerateBuffer, U : Accelerate::vDSP_FloatingPointConvertable, T.Element == Swift::UInt8 {
      if U.self == Float.self {
          let r: [Float] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Float>) in vDSP.convertElements(of: vector, to: &d) }
          return unsafeBitCast(r, to: [U].self)
      }
      let r: [Double] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Double>) in vDSP.convertElements(of: vector, to: &d) }
      return unsafeBitCast(r, to: [U].self)
  }
  public static func integerToFloatingPoint<T, U>(_ vector: T, floatingPointType: U.Type) -> [U] where T : Accelerate::AccelerateBuffer, U : Accelerate::vDSP_FloatingPointConvertable, T.Element == Swift::UInt16 {
      if U.self == Float.self {
          let r: [Float] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Float>) in vDSP.convertElements(of: vector, to: &d) }
          return unsafeBitCast(r, to: [U].self)
      }
      let r: [Double] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Double>) in vDSP.convertElements(of: vector, to: &d) }
      return unsafeBitCast(r, to: [U].self)
  }
  public static func integerToFloatingPoint<T, U>(_ vector: T, floatingPointType: U.Type) -> [U] where T : Accelerate::AccelerateBuffer, U : Accelerate::vDSP_FloatingPointConvertable, T.Element == Swift::UInt32 {
      if U.self == Float.self {
          let r: [Float] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Float>) in vDSP.convertElements(of: vector, to: &d) }
          return unsafeBitCast(r, to: [U].self)
      }
      let r: [Double] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Double>) in vDSP.convertElements(of: vector, to: &d) }
      return unsafeBitCast(r, to: [U].self)
  }
  public static func integerToFloatingPoint<T, U>(_ vector: T, floatingPointType: U.Type) -> [U] where T : Accelerate::AccelerateBuffer, U : Accelerate::vDSP_FloatingPointConvertable, T.Element == Swift::Int8 {
      if U.self == Float.self {
          let r: [Float] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Float>) in vDSP.convertElements(of: vector, to: &d) }
          return unsafeBitCast(r, to: [U].self)
      }
      let r: [Double] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Double>) in vDSP.convertElements(of: vector, to: &d) }
      return unsafeBitCast(r, to: [U].self)
  }
  public static func integerToFloatingPoint<T, U>(_ vector: T, floatingPointType: U.Type) -> [U] where T : Accelerate::AccelerateBuffer, U : Accelerate::vDSP_FloatingPointConvertable, T.Element == Swift::Int16 {
      if U.self == Float.self {
          let r: [Float] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Float>) in vDSP.convertElements(of: vector, to: &d) }
          return unsafeBitCast(r, to: [U].self)
      }
      let r: [Double] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Double>) in vDSP.convertElements(of: vector, to: &d) }
      return unsafeBitCast(r, to: [U].self)
  }
  public static func integerToFloatingPoint<T, U>(_ vector: T, floatingPointType: U.Type) -> [U] where T : Accelerate::AccelerateBuffer, U : Accelerate::vDSP_FloatingPointConvertable, T.Element == Swift::Int32 {
      if U.self == Float.self {
          let r: [Float] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Float>) in vDSP.convertElements(of: vector, to: &d) }
          return unsafeBitCast(r, to: [U].self)
      }
      let r: [Double] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Double>) in vDSP.convertElements(of: vector, to: &d) }
      return unsafeBitCast(r, to: [U].self)
  }
  public static func floatingPointToInteger<T, U>(_ vector: T, integerType: U.Type, rounding: Accelerate::vDSP.Accelerate::RoundingMode) -> [U] where T : Accelerate::AccelerateBuffer, U : Accelerate::vDSP_IntegerConvertable, T.Element == Swift::Float {
      if U.self == UInt8.self {
          let r: [UInt8] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<UInt8>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
          return unsafeBitCast(r, to: [U].self)
      }
      if U.self == UInt16.self {
          let r: [UInt16] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<UInt16>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
          return unsafeBitCast(r, to: [U].self)
      }
      if U.self == UInt32.self {
          let r: [UInt32] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<UInt32>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
          return unsafeBitCast(r, to: [U].self)
      }
      if U.self == Int8.self {
          let r: [Int8] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Int8>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
          return unsafeBitCast(r, to: [U].self)
      }
      if U.self == Int16.self {
          let r: [Int16] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Int16>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
          return unsafeBitCast(r, to: [U].self)
      }
      let r: [Int32] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Int32>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
      return unsafeBitCast(r, to: [U].self)
  }
  public static func floatingPointToInteger<T, U>(_ vector: T, integerType: U.Type, rounding: Accelerate::vDSP.Accelerate::RoundingMode) -> [U] where T : Accelerate::AccelerateBuffer, U : Accelerate::vDSP_IntegerConvertable, T.Element == Swift::Double {
      if U.self == UInt8.self {
          let r: [UInt8] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<UInt8>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
          return unsafeBitCast(r, to: [U].self)
      }
      if U.self == UInt16.self {
          let r: [UInt16] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<UInt16>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
          return unsafeBitCast(r, to: [U].self)
      }
      if U.self == UInt32.self {
          let r: [UInt32] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<UInt32>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
          return unsafeBitCast(r, to: [U].self)
      }
      if U.self == Int8.self {
          let r: [Int8] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Int8>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
          return unsafeBitCast(r, to: [U].self)
      }
      if U.self == Int16.self {
          let r: [Int16] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Int16>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
          return unsafeBitCast(r, to: [U].self)
      }
      let r: [Int32] = _make(vector.count) { (d: inout UnsafeMutableBufferPointer<Int32>) in vDSP.convertElements(of: vector, to: &d, rounding: rounding) }
      return unsafeBitCast(r, to: [U].self)
  }
  public static func floatToDouble<U>(_ source: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(source.count) { (d: inout UnsafeMutableBufferPointer<Double>) in vDSP.convertElements(of: source, to: &d) }
  }
  public static func doubleToFloat<U>(_ source: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(source.count) { (d: inout UnsafeMutableBufferPointer<Float>) in vDSP.convertElements(of: source, to: &d) }
  }
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Accelerate::vDSP {
  public static func taperedMerge<T, U, V>(_ vectorA: T, _ vectorB: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vtmerg(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func taperedMerge<T, U, V>(_ vectorA: T, _ vectorB: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vtmergD(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func taperedMerge<T, U>(_ vectorA: T, _ vectorB: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.taperedMerge(vectorA, vectorB, result: &result) }
  }
  public static func taperedMerge<T, U>(_ vectorA: T, _ vectorB: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.taperedMerge(vectorA, vectorB, result: &result) }
  }
  public static func swapElements<T, U>(_ vectorA: inout T, _ vectorB: inout U) where T : Accelerate::AccelerateMutableBuffer, U : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      let n = Swift.min(vectorA.count, vectorB.count)
      precondition(vectorA.count == vectorB.count)
      _wr(&vectorA) { a in _wr(&vectorB) { b in vDSP_vswap(a, 1, b, 1, vDSP_Length(n)) } }
  }
  public static func swapElements<T, U>(_ vectorA: inout T, _ vectorB: inout U) where T : Accelerate::AccelerateMutableBuffer, U : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      let n = Swift.min(vectorA.count, vectorB.count)
      precondition(vectorA.count == vectorB.count)
      _wr(&vectorA) { a in _wr(&vectorB) { b in vDSP_vswapD(a, 1, b, 1, vDSP_Length(n)) } }
  }
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Accelerate::vDSP {
  public static func gather<T, U, V>(_ vector: T, indices: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::UInt, V.Element == Swift::Float {
      let n = result.count
      precondition(indices.count >= n)
      _wr(&result) { r in _rd(vector) { v in _rd(indices) { i in vDSP_vgathr(v, i, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func gather<T, U, V>(_ vector: T, indices: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::UInt, V.Element == Swift::Double {
      let n = result.count
      precondition(indices.count >= n)
      _wr(&result) { r in _rd(vector) { v in _rd(indices) { i in vDSP_vgathrD(v, i, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func gather<T, U>(_ vector: T, indices: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::UInt {
      return _make(indices.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.gather(vector, indices: indices, result: &result) }
  }
  public static func gather<T, U>(_ vector: T, indices: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::UInt {
      return _make(indices.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.gather(vector, indices: indices, result: &result) }
  }
  public static func compress<T, U, V>(_ vector: T, gatingVector: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = vector.count
      precondition(gatingVector.count >= n)
      _wr(&result) { r in _rd(vector) { v in _rd(gatingVector) { g in vDSP_vcmprs(v, 1, g, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func compress<T, U, V>(_ vector: T, gatingVector: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = vector.count
      precondition(gatingVector.count >= n)
      _wr(&result) { r in _rd(vector) { v in _rd(gatingVector) { g in vDSP_vcmprsD(v, 1, g, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func compress<T, U>(_ vector: T, gatingVector: U, nonZeroGatingCount: Swift::Int?) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      let count = nonZeroGatingCount ?? gatingVector.withUnsafeBufferPointer { $0.reduce(0) { $1 != 0 ? $0 + 1 : $0 } }
      return _make(count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.compress(vector, gatingVector: gatingVector, result: &result) }
  }
  public static func compress<T, U>(_ vector: T, gatingVector: U, nonZeroGatingCount: Swift::Int?) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      let count = nonZeroGatingCount ?? gatingVector.withUnsafeBufferPointer { $0.reduce(0) { $1 != 0 ? $0 + 1 : $0 } }
      return _make(count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.compress(vector, gatingVector: gatingVector, result: &result) }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func powerToDecibels<U>(_ power: U, zeroReference: Swift::Float) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(power.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.convert(power: power, toDecibels: &result, zeroReference: zeroReference) }
  }
  public static func convert<U, V>(power: U, toDecibels decibels: inout V, zeroReference: Swift::Float) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = decibels.count
      precondition(power.count >= n)
      var reference = zeroReference
      _wr(&decibels) { r in _rd(power) { v in vDSP_vdbcon(v, 1, &reference, r, 1, vDSP_Length(n), 0) } }
  }
  public static func powerToDecibels<U>(_ power: U, zeroReference: Swift::Double) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(power.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.convert(power: power, toDecibels: &result, zeroReference: zeroReference) }
  }
  public static func convert<U, V>(power: U, toDecibels decibels: inout V, zeroReference: Swift::Double) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = decibels.count
      precondition(power.count >= n)
      var reference = zeroReference
      _wr(&decibels) { r in _rd(power) { v in vDSP_vdbconD(v, 1, &reference, r, 1, vDSP_Length(n), 0) } }
  }
  public static func amplitudeToDecibels<U>(_ amplitude: U, zeroReference: Swift::Float) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(amplitude.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.convert(amplitude: amplitude, toDecibels: &result, zeroReference: zeroReference) }
  }
  public static func convert<U, V>(amplitude: U, toDecibels decibels: inout V, zeroReference: Swift::Float) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = decibels.count
      precondition(amplitude.count >= n)
      var reference = zeroReference
      _wr(&decibels) { r in _rd(amplitude) { v in vDSP_vdbcon(v, 1, &reference, r, 1, vDSP_Length(n), 1) } }
  }
  public static func amplitudeToDecibels<U>(_ amplitude: U, zeroReference: Swift::Double) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(amplitude.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.convert(amplitude: amplitude, toDecibels: &result, zeroReference: zeroReference) }
  }
  public static func convert<U, V>(amplitude: U, toDecibels decibels: inout V, zeroReference: Swift::Double) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = decibels.count
      precondition(amplitude.count >= n)
      var reference = zeroReference
      _wr(&decibels) { r in _rd(amplitude) { v in vDSP_vdbconD(v, 1, &reference, r, 1, vDSP_Length(n), 1) } }
  }
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public protocol vDSP_DiscreteFourierTransformable {
  associatedtype DiscreteFourierTransformFunctions : Accelerate::vDSP_DiscreteTransformLifecycleFunctions
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public protocol vDSP_DiscreteTransformLifecycleFunctions {
  static func makeDiscreteFourierTransform(previous: Swift::OpaquePointer?, count: Swift::Int, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection, transformType: Accelerate::vDSP.Accelerate::DFTTransformType) throws -> Swift::OpaquePointer
  static func destroySetup(_ setup: Swift::OpaquePointer)
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Swift::Float : Accelerate::vDSP_DiscreteFourierTransformable {
  public typealias DiscreteFourierTransformFunctions = Accelerate::vDSP.Accelerate::DFTSinglePrecisionSplitComplexFunctions
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Swift::Double : Accelerate::vDSP_DiscreteFourierTransformable {
  public typealias DiscreteFourierTransformFunctions = Accelerate::vDSP.Accelerate::DFTDoublePrecisionSplitComplexFunctions
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::DSPComplex : Accelerate::vDSP_DiscreteFourierTransformable {
  public typealias DiscreteFourierTransformFunctions = Accelerate::vDSP.Accelerate::DFTSinglePrecisionInterleavedFunctions
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::DSPDoubleComplex : Accelerate::vDSP_DiscreteFourierTransformable {
  public typealias DiscreteFourierTransformFunctions = Accelerate::vDSP.Accelerate::DFTDoublePrecisionInterleavedFunctions
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::vDSP {
  public struct DFTSinglePrecisionSplitComplexFunctions : Accelerate::vDSP_DiscreteTransformLifecycleFunctions {
    public static func makeDiscreteFourierTransform(previous: Swift::OpaquePointer? = nil, count: Swift::Int, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection, transformType: Accelerate::vDSP.Accelerate::DFTTransformType) throws -> Swift::OpaquePointer {
        let length = vDSP_Length(count)
        let setup: OpaquePointer?
        switch transformType {
        case .complexComplex: setup = vDSP_DFT_zop_CreateSetup(previous, length, direction.dftDirection)
        case .complexReal: setup = vDSP_DFT_zrop_CreateSetup(previous, length, direction.dftDirection)
        }
        guard let setup else { throw vDSP.DFTError.invalidSplitComplexCount(count: count, transformType: transformType) }
        return setup
    }
    public static func destroySetup(_ setup: Swift::OpaquePointer) {
        vDSP_DFT_DestroySetup(setup)
    }
  }
  public struct DFTDoublePrecisionSplitComplexFunctions : Accelerate::vDSP_DiscreteTransformLifecycleFunctions {
    public static func makeDiscreteFourierTransform(previous: Swift::OpaquePointer? = nil, count: Swift::Int, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection, transformType: Accelerate::vDSP.Accelerate::DFTTransformType) throws -> Swift::OpaquePointer {
        let length = vDSP_Length(count)
        let setup: OpaquePointer?
        switch transformType {
        case .complexComplex: setup = vDSP_DFT_zop_CreateSetupD(previous, length, direction.dftDirection)
        case .complexReal: setup = vDSP_DFT_zrop_CreateSetupD(previous, length, direction.dftDirection)
        }
        guard let setup else { throw vDSP.DFTError.invalidSplitComplexCount(count: count, transformType: transformType) }
        return setup
    }
    public static func destroySetup(_ setup: Swift::OpaquePointer) {
        vDSP_DFT_DestroySetupD(setup)
    }
  }
  public struct DFTSinglePrecisionInterleavedFunctions : Accelerate::vDSP_DiscreteTransformLifecycleFunctions {
    public static func makeDiscreteFourierTransform(previous: Swift::OpaquePointer? = nil, count: Swift::Int, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection, transformType: Accelerate::vDSP.Accelerate::DFTTransformType) throws -> Swift::OpaquePointer {
        let kind: vDSP_DFT_RealtoComplex = transformType == .complexReal ? .interleaved_RealtoComplex : .interleaved_ComplextoComplex
        guard let setup = vDSP_DFT_Interleaved_CreateSetup(previous, vDSP_Length(count), direction.dftDirection, kind) else {
            throw vDSP.DFTError.invalidInterleavedCount(count: count)
        }
        return setup
    }
    public static func destroySetup(_ setup: Swift::OpaquePointer) {
        vDSP_DFT_Interleaved_DestroySetup(setup)
    }
  }
  public struct DFTDoublePrecisionInterleavedFunctions : Accelerate::vDSP_DiscreteTransformLifecycleFunctions {
    public static func makeDiscreteFourierTransform(previous: Swift::OpaquePointer? = nil, count: Swift::Int, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection, transformType: Accelerate::vDSP.Accelerate::DFTTransformType) throws -> Swift::OpaquePointer {
        let kind: vDSP_DFT_RealtoComplex = transformType == .complexReal ? .interleaved_RealtoComplex : .interleaved_ComplextoComplex
        guard let setup = vDSP_DFT_Interleaved_CreateSetupD(previous, vDSP_Length(count), direction.dftDirection, kind) else {
            throw vDSP.DFTError.invalidInterleavedCount(count: count)
        }
        return setup
    }
    public static func destroySetup(_ setup: Swift::OpaquePointer) {
        vDSP_DFT_Interleaved_DestroySetupD(setup)
    }
  }
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::vDSP {
  public enum DFTError : Swift::Error {
    case invalidSplitComplexCount(count: Swift::Int, transformType: Accelerate::vDSP.Accelerate::DFTTransformType)
    case invalidInterleavedCount(count: Swift::Int)
    public var errorDescription: Swift::String? {
      switch self {
      case .invalidSplitComplexCount(let count, let transformType):
        return "Invalid count (\(count)) for a \(transformType == .complexReal ? "complex-real" : "complex-complex") split-complex discrete Fourier transform."
      case .invalidInterleavedCount(let count):
        return "Invalid count (\(count)) for an interleaved discrete Fourier transform."
      }
    }
  }
  public class DiscreteFourierTransform<T> where T : Accelerate::vDSP_DiscreteFourierTransformable {
    internal let setup: Swift::OpaquePointer
    internal let count: Swift::Int
    internal let transformType: Accelerate::vDSP.Accelerate::DFTTransformType
    public init(previous: Accelerate::vDSP.Accelerate::DiscreteFourierTransform<Swift::Float>? = nil, count: Swift::Int, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection, transformType: Accelerate::vDSP.Accelerate::DFTTransformType, ofType: T.Type) throws {
        setup = try T.DiscreteFourierTransformFunctions.makeDiscreteFourierTransform(previous: previous?.setup, count: count, direction: direction, transformType: transformType)
        self.count = count
        self.transformType = transformType
    }
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26.0, *)
    public init(previousDFT: Accelerate::vDSP.Accelerate::DiscreteFourierTransform<T>?, count: Swift::Int, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection, transformType: Accelerate::vDSP.Accelerate::DFTTransformType, ofType: T.Type) throws {
        setup = try T.DiscreteFourierTransformFunctions.makeDiscreteFourierTransform(previous: previousDFT?.setup, count: count, direction: direction, transformType: transformType)
        self.count = count
        self.transformType = transformType
    }
    deinit { T.DiscreteFourierTransformFunctions.destroySetup(setup) }
  }
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::vDSP.Accelerate::DiscreteFourierTransform where T == Swift::Float {
  public func transform<U>(real: U, imaginary: U) -> (real: [Swift::Float], imaginary: [Swift::Float]) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      let n = transformType == .complexReal ? count / 2 : count
      var outputReal = [Float](repeating: 0, count: n)
      var outputImaginary = [Float](repeating: 0, count: n)
      transform(inputReal: real, inputImaginary: imaginary, outputReal: &outputReal, outputImaginary: &outputImaginary)
      return (outputReal, outputImaginary)
  }
  public func transform<U, V>(inputReal: U, inputImaginary: U, outputReal: inout V, outputImaginary: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = transformType == .complexReal ? count / 2 : count
      precondition(inputReal.count >= n && inputImaginary.count >= n && outputReal.count >= n && outputImaginary.count >= n)
      let setup = self.setup
      _wr(&outputReal) { or in _wr(&outputImaginary) { oi in _rd(inputReal) { ir in _rd(inputImaginary) { ii in
          vDSP_DFT_Execute(setup, ir, ii, or, oi)
      } } } }
  }
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::vDSP.Accelerate::DiscreteFourierTransform where T == Swift::Double {
  public func transform<U>(real: U, imaginary: U) -> (real: [Swift::Double], imaginary: [Swift::Double]) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      let n = transformType == .complexReal ? count / 2 : count
      var outputReal = [Double](repeating: 0, count: n)
      var outputImaginary = [Double](repeating: 0, count: n)
      transform(inputReal: real, inputImaginary: imaginary, outputReal: &outputReal, outputImaginary: &outputImaginary)
      return (outputReal, outputImaginary)
  }
  public func transform<U, V>(inputReal: U, inputImaginary: U, outputReal: inout V, outputImaginary: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = transformType == .complexReal ? count / 2 : count
      precondition(inputReal.count >= n && inputImaginary.count >= n && outputReal.count >= n && outputImaginary.count >= n)
      let setup = self.setup
      _wr(&outputReal) { or in _wr(&outputImaginary) { oi in _rd(inputReal) { ir in _rd(inputImaginary) { ii in
          vDSP_DFT_ExecuteD(setup, ir, ii, or, oi)
      } } } }
  }
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::vDSP.Accelerate::DiscreteFourierTransform where T == Accelerate::DSPComplex {
  public func transform<U>(input: U) -> [Accelerate::DSPComplex] where U : Accelerate::AccelerateBuffer, U.Element == Accelerate::DSPComplex {
      var output = [DSPComplex](repeating: DSPComplex(), count: count)
      transform(input: input, output: &output)
      return output
  }
  public func transform<U, V>(input: U, output: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Accelerate::DSPComplex, V.Element == Accelerate::DSPComplex {
      precondition(input.count >= count && output.count >= count)
      let setup = self.setup
      _wr(&output) { o in _rd(input) { i in vDSP_DFT_Interleaved_Execute(setup, i, o) } }
  }
}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::vDSP.Accelerate::DiscreteFourierTransform where T == Accelerate::DSPDoubleComplex {
  public func transform<U>(input: U) -> [Accelerate::DSPDoubleComplex] where U : Accelerate::AccelerateBuffer, U.Element == Accelerate::DSPDoubleComplex {
      var output = [DSPDoubleComplex](repeating: DSPDoubleComplex(), count: count)
      transform(input: input, output: &output)
      return output
  }
  public func transform<U, V>(input: U, output: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Accelerate::DSPDoubleComplex, V.Element == Accelerate::DSPDoubleComplex {
      precondition(input.count >= count && output.count >= count)
      let setup = self.setup
      _wr(&output) { o in _rd(input) { i in vDSP_DFT_Interleaved_ExecuteD(setup, i, o) } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func rectangularToPolar<U>(_ rectangularCoordinates: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(rectangularCoordinates.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.convert(rectangularCoordinates: rectangularCoordinates, toPolarCoordinates: &result) }
  }
  public static func convert<U, V>(rectangularCoordinates: U, toPolarCoordinates polarCoordinates: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = polarCoordinates.count
      precondition(rectangularCoordinates.count >= n)
      _wr(&polarCoordinates) { r in _rd(rectangularCoordinates) { v in vDSP_polar(v, 2, r, 2, vDSP_Length(n / 2)) } }
  }
  public static func rectangularToPolar<U>(_ rectangularCoordinates: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(rectangularCoordinates.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.convert(rectangularCoordinates: rectangularCoordinates, toPolarCoordinates: &result) }
  }
  public static func convert<U, V>(rectangularCoordinates: U, toPolarCoordinates polarCoordinates: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = polarCoordinates.count
      precondition(rectangularCoordinates.count >= n)
      _wr(&polarCoordinates) { r in _rd(rectangularCoordinates) { v in vDSP_polarD(v, 2, r, 2, vDSP_Length(n / 2)) } }
  }
  public static func polarToRectangular<U>(_ polarCoordinates: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(polarCoordinates.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.convert(polarCoordinates: polarCoordinates, toRectangularCoordinates: &result) }
  }
  public static func convert<U, V>(polarCoordinates: U, toRectangularCoordinates rectangularCoordinates: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = rectangularCoordinates.count
      precondition(polarCoordinates.count >= n)
      _wr(&rectangularCoordinates) { r in _rd(polarCoordinates) { v in vDSP_rect(v, 2, r, 2, vDSP_Length(n / 2)) } }
  }
  public static func polarToRectangular<U>(_ polarCoordinates: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(polarCoordinates.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.convert(polarCoordinates: polarCoordinates, toRectangularCoordinates: &result) }
  }
  public static func convert<U, V>(polarCoordinates: U, toRectangularCoordinates rectangularCoordinates: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = rectangularCoordinates.count
      precondition(polarCoordinates.count >= n)
      _wr(&rectangularCoordinates) { r in _rd(polarCoordinates) { v in vDSP_rectD(v, 2, r, 2, vDSP_Length(n / 2)) } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public enum DFTTransformType {
    case complexComplex
    case complexReal
  }
  @available(macOS, deprecated, introduced: 10.15, message: "Use `vDSP.DiscreteFourierTransform`.")
  @available(iOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
  @available(watchOS, deprecated, introduced: 6.0, message: "Use `vDSP.DiscreteFourierTransform`.")
  @available(tvOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
  @available(*, deprecated, message: "Use `vDSP.DiscreteFourierTransform`.")
  public class DFT<T> where T : Accelerate::vDSP_FloatingPointDiscreteFourierTransformable {
    internal let setup: Swift::OpaquePointer
    internal let count: Swift::Int
    internal let transformType: Accelerate::vDSP.Accelerate::DFTTransformType
    public init?(previous: Accelerate::vDSP.Accelerate::DFT<T>? = nil, count: Swift::Int, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection, transformType: Accelerate::vDSP.Accelerate::DFTTransformType, ofType: T.Type) {
        guard let setup = T.DFTFunctions.makeDFTSetup(previous: previous, count: count, direction: direction, transformType: transformType) else { return nil }
        self.setup = setup
        self.count = count
        self.transformType = transformType
    }
    public func transform<U>(inputReal: U, inputImaginary: U) -> (real: [T], imaginary: [T]) where T == U.Element, U : Accelerate::AccelerateBuffer {
        let n = transformType == .complexReal ? count / 2 : count
        var outputReal = [T](repeating: 0, count: n)
        var outputImaginary = [T](repeating: 0, count: n)
        transform(inputReal: inputReal, inputImaginary: inputImaginary, outputReal: &outputReal, outputImaginary: &outputImaginary)
        return (outputReal, outputImaginary)
    }
    public func transform<U, V>(inputReal: U, inputImaginary: U, outputReal: inout V, outputImaginary: inout V) where T == U.Element, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == V.Element {
        T.DFTFunctions.transform(dftSetup: setup, inputReal: inputReal, inputImaginary: inputImaginary, outputReal: &outputReal, outputImaginary: &outputImaginary)
    }
    deinit { T.DFTFunctions.destroySetup(setup) }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
@available(macOS, deprecated, introduced: 10.15, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(iOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(watchOS, deprecated, introduced: 6.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(tvOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(*, deprecated, message: "Use `vDSP.DiscreteFourierTransform`.")
public protocol vDSP_FloatingPointDiscreteFourierTransformable : Swift::BinaryFloatingPoint {
  associatedtype DFTFunctions : Accelerate::vDSP_DFTFunctions where Self == Self.DFTFunctions.Scalar
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
@available(macOS, deprecated, introduced: 10.15, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(iOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(watchOS, deprecated, introduced: 6.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(tvOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(*, deprecated, message: "Use `vDSP.DiscreteFourierTransform`.")
extension Swift::Float : Accelerate::vDSP_FloatingPointDiscreteFourierTransformable {
  public typealias DFTFunctions = Accelerate::vDSP.Accelerate::VectorizableFloat
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
@available(macOS, deprecated, introduced: 10.15, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(iOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(watchOS, deprecated, introduced: 6.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(tvOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(*, deprecated, message: "Use `vDSP.DiscreteFourierTransform`.")
extension Swift::Double : Accelerate::vDSP_FloatingPointDiscreteFourierTransformable {
  public typealias DFTFunctions = Accelerate::vDSP.Accelerate::VectorizableDouble
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
@available(macOS, deprecated, introduced: 10.15, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(iOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(watchOS, deprecated, introduced: 6.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(tvOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(*, deprecated, message: "Use `vDSP.DiscreteFourierTransform`.")
public protocol vDSP_DFTFunctions {
  associatedtype Scalar
  static func makeDFTSetup<T>(previous: Accelerate::vDSP.Accelerate::DFT<T>?, count: Swift::Int, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection, transformType: Accelerate::vDSP.Accelerate::DFTTransformType) -> Swift::OpaquePointer? where T : Accelerate::vDSP_FloatingPointDiscreteFourierTransformable
  static func transform<U, V>(dftSetup: Swift::OpaquePointer, inputReal: U, inputImaginary: U, outputReal: inout V, outputImaginary: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, Self.Scalar == U.Element, U.Element == V.Element
  static func destroySetup(_ setup: Swift::OpaquePointer)
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
@available(macOS, deprecated, introduced: 10.15, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(iOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(watchOS, deprecated, introduced: 6.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(tvOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(*, deprecated, message: "Use `vDSP.DiscreteFourierTransform`.")
extension Accelerate::vDSP.Accelerate::VectorizableFloat : Accelerate::vDSP_DFTFunctions {
  public static func makeDFTSetup<T>(previous: Accelerate::vDSP.Accelerate::DFT<T>? = nil, count: Swift::Int, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection, transformType: Accelerate::vDSP.Accelerate::DFTTransformType) -> Swift::OpaquePointer? where T : Accelerate::vDSP_FloatingPointDiscreteFourierTransformable {
      let length = vDSP_Length(count)
      switch transformType {
      case .complexComplex: return vDSP_DFT_zop_CreateSetup(previous?.setup, length, direction.dftDirection)
      case .complexReal: return vDSP_DFT_zrop_CreateSetup(previous?.setup, length, direction.dftDirection)
      }
  }
  public static func transform<U, V>(dftSetup: Swift::OpaquePointer, inputReal: U, inputImaginary: U, outputReal: inout V, outputImaginary: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = outputReal.count
      precondition(outputImaginary.count == n && inputReal.count >= n && inputImaginary.count >= n)
      _wr(&outputReal) { or in _wr(&outputImaginary) { oi in _rd(inputReal) { ir in _rd(inputImaginary) { ii in
          vDSP_DFT_Execute(dftSetup, ir, ii, or, oi)
      } } } }
  }
  public static func destroySetup(_ setup: Swift::OpaquePointer) {
      vDSP_DFT_DestroySetup(setup)
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
@available(macOS, deprecated, introduced: 10.15, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(iOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(watchOS, deprecated, introduced: 6.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(tvOS, deprecated, introduced: 13.0, message: "Use `vDSP.DiscreteFourierTransform`.")
@available(*, deprecated, message: "Use `vDSP.DiscreteFourierTransform`.")
extension Accelerate::vDSP.Accelerate::VectorizableDouble : Accelerate::vDSP_DFTFunctions {
  public static func makeDFTSetup<T>(previous: Accelerate::vDSP.Accelerate::DFT<T>? = nil, count: Swift::Int, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection, transformType: Accelerate::vDSP.Accelerate::DFTTransformType) -> Swift::OpaquePointer? where T : Accelerate::vDSP_FloatingPointDiscreteFourierTransformable {
      let length = vDSP_Length(count)
      switch transformType {
      case .complexComplex: return vDSP_DFT_zop_CreateSetupD(previous?.setup, length, direction.dftDirection)
      case .complexReal: return vDSP_DFT_zrop_CreateSetupD(previous?.setup, length, direction.dftDirection)
      }
  }
  public static func transform<U, V>(dftSetup: Swift::OpaquePointer, inputReal: U, inputImaginary: U, outputReal: inout V, outputImaginary: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = outputReal.count
      precondition(outputImaginary.count == n && inputReal.count >= n && inputImaginary.count >= n)
      _wr(&outputReal) { or in _wr(&outputImaginary) { oi in _rd(inputReal) { ir in _rd(inputImaginary) { ii in
          vDSP_DFT_ExecuteD(dftSetup, ir, ii, or, oi)
      } } } }
  }
  public static func destroySetup(_ setup: Swift::OpaquePointer) {
      vDSP_DFT_DestroySetupD(setup)
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public enum IntegrationRule {
    case runningSum
    case simpson
    case trapezoidal
  }
  public static func integrate<U>(_ vector: U, using rule: Accelerate::vDSP.Accelerate::IntegrationRule, stepSize: Swift::Float = 1) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.integrate(vector, using: rule, stepSize: stepSize, result: &result) }
  }
  public static func integrate<U, V>(_ vector: U, using rule: Accelerate::vDSP.Accelerate::IntegrationRule, stepSize: Swift::Float = 1, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var step = stepSize
      _wr(&result) { r in _rd(vector) { v in
          switch rule {
          case .runningSum: vDSP_vrsum(v, 1, &step, r, 1, vDSP_Length(n))
          case .simpson: vDSP_vsimps(v, 1, &step, r, 1, vDSP_Length(n))
          case .trapezoidal: vDSP_vtrapz(v, 1, &step, r, 1, vDSP_Length(n))
          }
      } }
  }
  public static func integrate<U>(_ vector: U, using rule: Accelerate::vDSP.Accelerate::IntegrationRule, stepSize: Swift::Double = 1) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.integrate(vector, using: rule, stepSize: stepSize, result: &result) }
  }
  public static func integrate<U, V>(_ vector: U, using rule: Accelerate::vDSP.Accelerate::IntegrationRule, stepSize: Swift::Double = 1, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var step = stepSize
      _wr(&result) { r in _rd(vector) { v in
          switch rule {
          case .runningSum: vDSP_vrsumD(v, 1, &step, r, 1, vDSP_Length(n))
          case .simpson: vDSP_vsimpsD(v, 1, &step, r, 1, vDSP_Length(n))
          case .trapezoidal: vDSP_vtrapzD(v, 1, &step, r, 1, vDSP_Length(n))
          }
      } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func clip<U>(_ vector: U, to bounds: Swift::ClosedRange<Swift::Float>) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.clip(vector, to: bounds, result: &result) }
  }
  public static func clip<U, V>(_ vector: U, to bounds: Swift::ClosedRange<Swift::Float>, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var low = bounds.lowerBound
      var high = bounds.upperBound
      _wr(&result) { r in _rd(vector) { v in vDSP_vclip(v, 1, &low, &high, r, 1, vDSP_Length(n)) } }
  }
  public static func clip<U>(_ vector: U, to bounds: Swift::ClosedRange<Swift::Double>) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.clip(vector, to: bounds, result: &result) }
  }
  public static func clip<U, V>(_ vector: U, to bounds: Swift::ClosedRange<Swift::Double>, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var low = bounds.lowerBound
      var high = bounds.upperBound
      _wr(&result) { r in _rd(vector) { v in vDSP_vclipD(v, 1, &low, &high, r, 1, vDSP_Length(n)) } }
  }
  public static func invertedClip<U>(_ vector: U, to bounds: Swift::ClosedRange<Swift::Float>) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.invertedClip(vector, to: bounds, result: &result) }
  }
  public static func invertedClip<U, V>(_ vector: U, to bounds: Swift::ClosedRange<Swift::Float>, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var low = bounds.lowerBound
      var high = bounds.upperBound
      _wr(&result) { r in _rd(vector) { v in vDSP_viclip(v, 1, &low, &high, r, 1, vDSP_Length(n)) } }
  }
  public static func invertedClip<U>(_ vector: U, to bounds: Swift::ClosedRange<Swift::Double>) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.invertedClip(vector, to: bounds, result: &result) }
  }
  public static func invertedClip<U, V>(_ vector: U, to bounds: Swift::ClosedRange<Swift::Double>, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var low = bounds.lowerBound
      var high = bounds.upperBound
      _wr(&result) { r in _rd(vector) { v in vDSP_viclipD(v, 1, &low, &high, r, 1, vDSP_Length(n)) } }
  }
  public enum ThresholdRule<T> where T : Swift::BinaryFloatingPoint {
    case clampToThreshold
    case zeroFill
    case signedConstant(_: T)
  }
  public static func threshold<U>(_ vector: U, to lowerBound: Swift::Float, with rule: Accelerate::vDSP.Accelerate::ThresholdRule<Swift::Float>) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.threshold(vector, to: lowerBound, with: rule, result: &result) }
  }
  public static func threshold<U, V>(_ vector: U, to lowerBound: Swift::Float, with rule: Accelerate::vDSP.Accelerate::ThresholdRule<Swift::Float>, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var low = lowerBound
      _wr(&result) { r in _rd(vector) { v in
          switch rule {
          case .clampToThreshold: vDSP_vthr(v, 1, &low, r, 1, vDSP_Length(n))
          case .zeroFill: vDSP_vthres(v, 1, &low, r, 1, vDSP_Length(n))
          case .signedConstant(let constant):
              var c = constant
              vDSP_vthrsc(v, 1, &low, &c, r, 1, vDSP_Length(n))
          }
      } }
  }
  public static func threshold<U>(_ vector: U, to lowerBound: Swift::Double, with rule: Accelerate::vDSP.Accelerate::ThresholdRule<Swift::Double>) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.threshold(vector, to: lowerBound, with: rule, result: &result) }
  }
  public static func threshold<U, V>(_ vector: U, to lowerBound: Swift::Double, with rule: Accelerate::vDSP.Accelerate::ThresholdRule<Swift::Double>, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var low = lowerBound
      _wr(&result) { r in _rd(vector) { v in
          switch rule {
          case .clampToThreshold: vDSP_vthrD(v, 1, &low, r, 1, vDSP_Length(n))
          case .zeroFill: vDSP_vthresD(v, 1, &low, r, 1, vDSP_Length(n))
          case .signedConstant(let constant):
              var c = constant
              vDSP_vthrscD(v, 1, &low, &c, r, 1, vDSP_Length(n))
          }
      } }
  }
  public static func limit<U>(_ vector: U, limit: Swift::Float, withOutputConstant outputConstant: Swift::Float) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.limit(vector, limit: limit, withOutputConstant: outputConstant, result: &result) }
  }
  public static func limit<U, V>(_ vector: U, limit: Swift::Float, withOutputConstant outputConstant: Swift::Float, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var l = limit
      var c = outputConstant
      _wr(&result) { r in _rd(vector) { v in vDSP_vlim(v, 1, &l, &c, r, 1, vDSP_Length(n)) } }
  }
  public static func limit<U>(_ vector: U, limit: Swift::Double, withOutputConstant outputConstant: Swift::Double) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.limit(vector, limit: limit, withOutputConstant: outputConstant, result: &result) }
  }
  public static func limit<U, V>(_ vector: U, limit: Swift::Double, withOutputConstant outputConstant: Swift::Double, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var l = limit
      var c = outputConstant
      _wr(&result) { r in _rd(vector) { v in vDSP_vlimD(v, 1, &l, &c, r, 1, vDSP_Length(n)) } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  @_silgen_name("_swift_vDSP_dotpr")
  @_alwaysEmitIntoClient public static func dot<T, U>(_ vectorA: T, _ vectorB: U) -> Swift::Float where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      let n = vectorA.count
      precondition(vectorB.count == n)
      var r: Float = 0
      _ = vectorA.withUnsafeBufferPointer { a in vectorB.withUnsafeBufferPointer { b in
          if let a = a.baseAddress, let b = b.baseAddress { vDSP_dotpr(a, 1, b, 1, &r, vDSP_Length(n)) }
      } }
      return r
  }
  @_silgen_name("_swift_vDSP_dotprD")
  @_alwaysEmitIntoClient public static func dot<T, U>(_ vectorA: T, _ vectorB: U) -> Swift::Double where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      let n = vectorA.count
      precondition(vectorB.count == n)
      var r: Double = 0
      _ = vectorA.withUnsafeBufferPointer { a in vectorB.withUnsafeBufferPointer { b in
          if let a = a.baseAddress, let b = b.baseAddress { vDSP_dotprD(a, 1, b, 1, &r, vDSP_Length(n)) }
      } }
      return r
  }
  @available(*, unavailable)
  public static func dot<T>(_ vectorA: T, _ vectorB: T) -> Swift::Float where T : Accelerate::AccelerateBuffer, T.Element == Swift::Float {
      let n = vectorA.count
      precondition(vectorB.count == n)
      var r: Float = 0
      _ = vectorA.withUnsafeBufferPointer { a in vectorB.withUnsafeBufferPointer { b in
          if let a = a.baseAddress, let b = b.baseAddress { vDSP_dotpr(a, 1, b, 1, &r, vDSP_Length(n)) }
      } }
      return r
  }
  @available(*, unavailable)
  public static func dot<T>(_ vectorA: T, _ vectorB: T) -> Swift::Double where T : Accelerate::AccelerateBuffer, T.Element == Swift::Double {
      let n = vectorA.count
      precondition(vectorB.count == n)
      var r: Double = 0
      _ = vectorA.withUnsafeBufferPointer { a in vectorB.withUnsafeBufferPointer { b in
          if let a = a.baseAddress, let b = b.baseAddress { vDSP_dotprD(a, 1, b, 1, &r, vDSP_Length(n)) }
      } }
      return r
  }
  @available(*, unavailable)
  @_silgen_name("$s10Accelerate4vDSPO3dotySfx_q_tAA0A6BufferRzAaER_Sf7ElementRtzSfAFRt_r0_lFZ")
  public static func dot_legacySupport<T, U>(_ vectorA: T, _ vectorB: U) -> Swift::Float where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      let n = vectorA.count
      precondition(vectorB.count == n)
      var r: Float = 0
      _ = vectorA.withUnsafeBufferPointer { a in vectorB.withUnsafeBufferPointer { b in
          if let a = a.baseAddress, let b = b.baseAddress { vDSP_dotpr(a, 1, b, 1, &r, vDSP_Length(n)) }
      } }
      return r
  }
  @available(*, unavailable)
  @_silgen_name("$s10Accelerate4vDSPO3dotySdx_q_tAA0A6BufferRzAaER_Sd7ElementRtzSdAFRt_r0_lFZ")
  public static func dot_legacySupport<T, U>(_ vectorA: T, _ vectorB: U) -> Swift::Double where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      let n = vectorA.count
      precondition(vectorB.count == n)
      var r: Double = 0
      _ = vectorA.withUnsafeBufferPointer { a in vectorB.withUnsafeBufferPointer { b in
          if let a = a.baseAddress, let b = b.baseAddress { vDSP_dotprD(a, 1, b, 1, &r, vDSP_Length(n)) }
      } }
      return r
  }
  public static func hypot<U, V>(_ x: U, _ y: V) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      return _make(x.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.hypot(x, y, result: &result) }
  }
  public static func hypot<T, U, V>(_ x: T, _ y: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(x.count >= n && y.count >= n)
      _wr(&result) { r in _rd(x) { a in _rd(y) { b in vDSP_vdist(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func hypot<U, V>(_ x: U, _ y: V) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      return _make(x.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.hypot(x, y, result: &result) }
  }
  public static func hypot<T, U, V>(_ x: T, _ y: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(x.count >= n && y.count >= n)
      _wr(&result) { r in _rd(x) { a in _rd(y) { b in vDSP_vdistD(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func hypot<R, S, T, U>(x0: R, x1: S, y0: T, y1: U) -> [Swift::Float] where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, R.Element == Swift::Float, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(x0.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.hypot(x0: x0, x1: x1, y0: y0, y1: y1, result: &result) }
  }
  public static func hypot<R, S, T, U, V>(x0: R, x1: S, y0: T, y1: U, result: inout V) where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, R.Element == Swift::Float, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(x0.count >= n && x1.count >= n && y0.count >= n && y1.count >= n)
      _wr(&result) { r in _rd(x0) { a in _rd(y0) { b in _rd(x1) { c in _rd(y1) { d in vDSP_vpythg(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func hypot<R, S, T, U>(x0: R, x1: S, y0: T, y1: U) -> [Swift::Double] where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, R.Element == Swift::Double, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(x0.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.hypot(x0: x0, x1: x1, y0: y0, y1: y1, result: &result) }
  }
  public static func hypot<R, S, T, U, V>(x0: R, x1: S, y0: T, y1: U, result: inout V) where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, R.Element == Swift::Double, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(x0.count >= n && x1.count >= n && y0.count >= n && y1.count >= n)
      _wr(&result) { r in _rd(x0) { a in _rd(y0) { b in _rd(x1) { c in _rd(y1) { d in vDSP_vpythgD(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func distanceSquared<U, V>(_ pointA: U, _ pointB: V) -> Swift::Float where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = pointA.count
      precondition(pointB.count == n)
      var r: Float = 0
      _rd(pointA) { a in _rd(pointB) { b in vDSP_distancesq(a, 1, b, 1, &r, vDSP_Length(n)) } }
      return r
  }
  public static func distanceSquared<U, V>(_ pointA: U, _ pointB: V) -> Swift::Double where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = pointA.count
      precondition(pointB.count == n)
      var r: Double = 0
      _rd(pointA) { a in _rd(pointB) { b in vDSP_distancesqD(a, 1, b, 1, &r, vDSP_Length(n)) } }
      return r
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func add<U>(_ scalar: Swift::Float, _ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.add(scalar, vector, result: &result) }
  }
  public static func add<U, V>(_ scalar: Swift::Float, _ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(vector) { v in vDSP_vsadd(v, 1, &s, r, 1, vDSP_Length(n)) } }
  }
  public static func add<U>(_ scalar: Swift::Double, _ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.add(scalar, vector, result: &result) }
  }
  public static func add<U, V>(_ scalar: Swift::Double, _ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(vector) { v in vDSP_vsaddD(v, 1, &s, r, 1, vDSP_Length(n)) } }
  }
  public static func add<T, U>(_ vectorA: T, _ vectorB: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.add(vectorA, vectorB, result: &result) }
  }
  public static func add<T, U, V>(_ vectorA: T, _ vectorB: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vadd(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func add<T, U>(_ vectorA: T, _ vectorB: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.add(vectorA, vectorB, result: &result) }
  }
  public static func add<T, U, V>(_ vectorA: T, _ vectorB: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vaddD(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func subtract<T, U>(_ vectorA: U, _ vectorB: T) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.subtract(vectorA, vectorB, result: &result) }
  }
  public static func subtract<T, U, V>(_ vectorA: U, _ vectorB: T, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vsub(b, 1, a, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func subtract<T, U>(_ vectorA: U, _ vectorB: T) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.subtract(vectorA, vectorB, result: &result) }
  }
  public static func subtract<T, U, V>(_ vectorA: U, _ vectorB: T, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vsubD(b, 1, a, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func multiply<U>(_ scalar: Swift::Float, _ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.multiply(scalar, vector, result: &result) }
  }
  public static func multiply<U, V>(_ scalar: Swift::Float, _ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(vector) { v in vDSP_vsmul(v, 1, &s, r, 1, vDSP_Length(n)) } }
  }
  public static func multiply<U>(_ scalar: Swift::Double, _ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.multiply(scalar, vector, result: &result) }
  }
  public static func multiply<U, V>(_ scalar: Swift::Double, _ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(vector) { v in vDSP_vsmulD(v, 1, &s, r, 1, vDSP_Length(n)) } }
  }
  public static func multiply<T, U>(_ vectorA: T, _ vectorB: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.multiply(vectorA, vectorB, result: &result) }
  }
  public static func multiply<T, U, V>(_ vectorA: T, _ vectorB: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vmul(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func multiply<T, U>(_ vectorA: T, _ vectorB: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.multiply(vectorA, vectorB, result: &result) }
  }
  public static func multiply<T, U, V>(_ vectorA: T, _ vectorB: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vmulD(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func divide<U>(_ vector: U, _ scalar: Swift::Float) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.divide(vector, scalar, result: &result) }
  }
  public static func divide<U, V>(_ vector: U, _ scalar: Swift::Float, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(vector) { v in vDSP_vsdiv(v, 1, &s, r, 1, vDSP_Length(n)) } }
  }
  public static func divide<U>(_ vector: U, _ scalar: Swift::Double) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.divide(vector, scalar, result: &result) }
  }
  public static func divide<U, V>(_ vector: U, _ scalar: Swift::Double, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(vector) { v in vDSP_vsdivD(v, 1, &s, r, 1, vDSP_Length(n)) } }
  }
  public static func divide<U>(_ scalar: Swift::Float, _ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.divide(scalar, vector, result: &result) }
  }
  public static func divide<U, V>(_ scalar: Swift::Float, _ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(vector) { v in vDSP_svdiv(&s, v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func divide<U>(_ scalar: Swift::Double, _ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.divide(scalar, vector, result: &result) }
  }
  public static func divide<U, V>(_ scalar: Swift::Double, _ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(vector) { v in vDSP_svdivD(&s, v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func divide<T, U>(_ vectorA: T, _ vectorB: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.divide(vectorA, vectorB, result: &result) }
  }
  public static func divide<T, U, V>(_ vectorA: T, _ vectorB: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vdiv(b, 1, a, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func divide<T, U>(_ vectorA: T, _ vectorB: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.divide(vectorA, vectorB, result: &result) }
  }
  public static func divide<T, U, V>(_ vectorA: T, _ vectorB: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vdivD(b, 1, a, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func addSubtract<S, T, U, V>(_ vectorA: S, _ vectorB: T, addResult: inout U, subtractResult: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateMutableBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = addResult.count
      precondition(subtractResult.count == n && vectorA.count >= n && vectorB.count >= n)
      _wr(&addResult) { o0 in _wr(&subtractResult) { o1 in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vaddsub(b, 1, a, 1, o0, 1, o1, 1, vDSP_Length(n)) } } } }
  }
  public static func addSubtract<S, T, U, V>(_ vectorA: S, _ vectorB: T, addResult: inout U, subtractResult: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateMutableBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = addResult.count
      precondition(subtractResult.count == n && vectorA.count >= n && vectorB.count >= n)
      _wr(&addResult) { o0 in _wr(&subtractResult) { o1 in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vaddsubD(b, 1, a, 1, o0, 1, o1, 1, vDSP_Length(n)) } } } }
  }
  public static func multiply<T, U>(addition: (a: T, b: U), _ scalar: Swift::Float) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(addition.a.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.multiply(addition: addition, scalar, result: &result) }
  }
  public static func multiply<T, U, V>(addition: (a: T, b: U), _ scalar: Swift::Float, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(addition.a) { a in _rd(addition.b) { b in vDSP_vasm(a, 1, b, 1, &s, r, 1, vDSP_Length(n)) } } }
  }
  public static func multiply<T, U>(addition: (a: T, b: U), _ scalar: Swift::Double) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(addition.a.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.multiply(addition: addition, scalar, result: &result) }
  }
  public static func multiply<T, U, V>(addition: (a: T, b: U), _ scalar: Swift::Double, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(addition.a) { a in _rd(addition.b) { b in vDSP_vasmD(a, 1, b, 1, &s, r, 1, vDSP_Length(n)) } } }
  }
  public static func multiply<S, T, U>(addition: (a: S, b: T), _ vector: U) -> [Swift::Float] where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.multiply(addition: addition, vector, result: &result) }
  }
  public static func multiply<S, T, U, V>(addition: (a: S, b: T), _ vector: U, result: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      _wr(&result) { r in _rd(addition.a) { a in _rd(addition.b) { b in _rd(vector) { c in vDSP_vam(a, 1, b, 1, c, 1, r, 1, vDSP_Length(n)) } } } }
  }
  public static func multiply<S, T, U>(addition: (a: S, b: T), _ vector: U) -> [Swift::Double] where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.multiply(addition: addition, vector, result: &result) }
  }
  public static func multiply<S, T, U, V>(addition: (a: S, b: T), _ vector: U, result: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      _wr(&result) { r in _rd(addition.a) { a in _rd(addition.b) { b in _rd(vector) { c in vDSP_vamD(a, 1, b, 1, c, 1, r, 1, vDSP_Length(n)) } } } }
  }
  public static func multiply<T, U>(subtraction: (a: T, b: U), _ scalar: Swift::Float) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(subtraction.a.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.multiply(subtraction: subtraction, scalar, result: &result) }
  }
  public static func multiply<T, U, V>(subtraction: (a: T, b: U), _ scalar: Swift::Float, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(subtraction.a) { a in _rd(subtraction.b) { b in vDSP_vsbsm(a, 1, b, 1, &s, r, 1, vDSP_Length(n)) } } }
  }
  public static func multiply<T, U>(subtraction: (a: T, b: U), _ scalar: Swift::Double) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(subtraction.a.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.multiply(subtraction: subtraction, scalar, result: &result) }
  }
  public static func multiply<T, U, V>(subtraction: (a: T, b: U), _ scalar: Swift::Double, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(subtraction.a) { a in _rd(subtraction.b) { b in vDSP_vsbsmD(a, 1, b, 1, &s, r, 1, vDSP_Length(n)) } } }
  }
  public static func multiply<S, T, U>(subtraction: (a: S, b: T), _ vector: U) -> [Swift::Float] where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.multiply(subtraction: subtraction, vector, result: &result) }
  }
  public static func multiply<S, T, U, V>(subtraction: (a: S, b: T), _ vector: U, result: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      _wr(&result) { r in _rd(subtraction.a) { a in _rd(subtraction.b) { b in _rd(vector) { c in vDSP_vsbm(a, 1, b, 1, c, 1, r, 1, vDSP_Length(n)) } } } }
  }
  public static func multiply<S, T, U>(subtraction: (a: S, b: T), _ vector: U) -> [Swift::Double] where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.multiply(subtraction: subtraction, vector, result: &result) }
  }
  public static func multiply<S, T, U, V>(subtraction: (a: S, b: T), _ vector: U, result: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      _wr(&result) { r in _rd(subtraction.a) { a in _rd(subtraction.b) { b in _rd(vector) { c in vDSP_vsbmD(a, 1, b, 1, c, 1, r, 1, vDSP_Length(n)) } } } }
  }
  public static func add<T, U>(multiplication: (a: T, b: U), _ scalar: Swift::Float) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(multiplication.a.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.add(multiplication: multiplication, scalar, result: &result) }
  }
  public static func add<T, U, V>(multiplication: (a: T, b: U), _ scalar: Swift::Float, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(multiplication.a) { a in _rd(multiplication.b) { b in vDSP_vmsa(a, 1, b, 1, &s, r, 1, vDSP_Length(n)) } } }
  }
  public static func add<T, U>(multiplication: (a: T, b: U), _ scalar: Swift::Double) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(multiplication.a.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.add(multiplication: multiplication, scalar, result: &result) }
  }
  public static func add<T, U, V>(multiplication: (a: T, b: U), _ scalar: Swift::Double, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      var s = scalar
      _wr(&result) { r in _rd(multiplication.a) { a in _rd(multiplication.b) { b in vDSP_vmsaD(a, 1, b, 1, &s, r, 1, vDSP_Length(n)) } } }
  }
  public static func add<T, U>(multiplication: (a: T, b: Swift::Float), _ vector: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.add(multiplication: multiplication, vector, result: &result) }
  }
  public static func add<T, U, V>(multiplication: (a: T, b: Swift::Float), _ vector: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      var b = multiplication.b
      _wr(&result) { r in _rd(multiplication.a) { a in _rd(vector) { c in vDSP_vsma(a, 1, &b, c, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func add<T, U>(multiplication: (a: T, b: Swift::Double), _ vector: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.add(multiplication: multiplication, vector, result: &result) }
  }
  public static func add<T, U, V>(multiplication: (a: T, b: Swift::Double), _ vector: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      var b = multiplication.b
      _wr(&result) { r in _rd(multiplication.a) { a in _rd(vector) { c in vDSP_vsmaD(a, 1, &b, c, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func add<S, T, U>(multiplication: (a: S, b: T), _ vector: U) -> [Swift::Float] where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.add(multiplication: multiplication, vector, result: &result) }
  }
  public static func add<S, T, U, V>(multiplication: (a: S, b: T), _ vector: U, result: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      _wr(&result) { r in _rd(multiplication.a) { a in _rd(multiplication.b) { b in _rd(vector) { c in vDSP_vma(a, 1, b, 1, c, 1, r, 1, vDSP_Length(n)) } } } }
  }
  public static func add<S, T, U>(multiplication: (a: S, b: T), _ vector: U) -> [Swift::Double] where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.add(multiplication: multiplication, vector, result: &result) }
  }
  public static func add<S, T, U, V>(multiplication: (a: S, b: T), _ vector: U, result: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      _wr(&result) { r in _rd(multiplication.a) { a in _rd(multiplication.b) { b in _rd(vector) { c in vDSP_vmaD(a, 1, b, 1, c, 1, r, 1, vDSP_Length(n)) } } } }
  }
  public static func subtract<S, T, U>(multiplication: (a: T, b: U), _ vector: S) -> [Swift::Float] where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.subtract(multiplication: multiplication, vector, result: &result) }
  }
  public static func subtract<S, T, U, V>(multiplication: (a: T, b: U), _ vector: S, result: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      _wr(&result) { r in _rd(multiplication.a) { a in _rd(multiplication.b) { b in _rd(vector) { c in vDSP_vmsb(a, 1, b, 1, c, 1, r, 1, vDSP_Length(n)) } } } }
  }
  public static func subtract<S, T, U>(multiplication: (a: T, b: U), _ vector: S) -> [Swift::Double] where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.subtract(multiplication: multiplication, vector, result: &result) }
  }
  public static func subtract<S, T, U, V>(multiplication: (a: T, b: U), _ vector: S, result: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      _wr(&result) { r in _rd(multiplication.a) { a in _rd(multiplication.b) { b in _rd(vector) { c in vDSP_vmsbD(a, 1, b, 1, c, 1, r, 1, vDSP_Length(n)) } } } }
  }
  public static func add<T, U>(multiplication multiplicationAB: (a: T, b: Swift::Float), multiplication multiplicationCD: (c: U, d: Swift::Float)) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(multiplicationAB.a.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.add(multiplication: multiplicationAB, multiplication: multiplicationCD, result: &result) }
  }
  public static func add<T, U, V>(multiplication multiplicationAB: (a: T, b: Swift::Float), multiplication multiplicationCD: (c: U, d: Swift::Float), result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      var b = multiplicationAB.b
      var d = multiplicationCD.d
      _wr(&result) { r in _rd(multiplicationAB.a) { a in _rd(multiplicationCD.c) { c in vDSP_vsmsma(a, 1, &b, c, 1, &d, r, 1, vDSP_Length(n)) } } }
  }
  public static func add<T, U>(multiplication multiplicationAB: (a: T, b: Swift::Double), multiplication multiplicationCD: (c: U, d: Swift::Double)) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(multiplicationAB.a.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.add(multiplication: multiplicationAB, multiplication: multiplicationCD, result: &result) }
  }
  public static func add<T, U, V>(multiplication multiplicationAB: (a: T, b: Swift::Double), multiplication multiplicationCD: (c: U, d: Swift::Double), result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      var b = multiplicationAB.b
      var d = multiplicationCD.d
      _wr(&result) { r in _rd(multiplicationAB.a) { a in _rd(multiplicationCD.c) { c in vDSP_vsmsmaD(a, 1, &b, c, 1, &d, r, 1, vDSP_Length(n)) } } }
  }
  public static func add<R, S, T, U>(multiplication multiplicationAB: (a: R, b: S), multiplication multiplicationCD: (c: T, d: U)) -> [Swift::Float] where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, R.Element == Swift::Float, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(multiplicationAB.a.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.add(multiplication: multiplicationAB, multiplication: multiplicationCD, result: &result) }
  }
  public static func add<R, S, T, U, V>(multiplication multiplicationAB: (a: R, b: S), multiplication multiplicationCD: (c: T, d: U), result: inout V) where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, R.Element == Swift::Float, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      _wr(&result) { r in _rd(multiplicationAB.a) { a in _rd(multiplicationAB.b) { b in _rd(multiplicationCD.c) { c in _rd(multiplicationCD.d) { d in vDSP_vmma(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func add<R, S, T, U>(multiplication multiplicationAB: (a: R, b: S), multiplication multiplicationCD: (c: T, d: U)) -> [Swift::Double] where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, R.Element == Swift::Double, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(multiplicationAB.a.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.add(multiplication: multiplicationAB, multiplication: multiplicationCD, result: &result) }
  }
  public static func add<R, S, T, U, V>(multiplication multiplicationAB: (a: R, b: S), multiplication multiplicationCD: (c: T, d: U), result: inout V) where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, R.Element == Swift::Double, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      _wr(&result) { r in _rd(multiplicationAB.a) { a in _rd(multiplicationAB.b) { b in _rd(multiplicationCD.c) { c in _rd(multiplicationCD.d) { d in vDSP_vmmaD(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func multiply<S, T, U>(addition additionAB: (a: S, b: T), addition additionCD: (c: U, d: U)) -> [Swift::Float] where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(additionAB.a.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.multiply(addition: additionAB, addition: additionCD, result: &result) }
  }
  public static func multiply<S, T, U, V>(addition additionAB: (a: S, b: T), addition additionCD: (c: U, d: U), result: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      _wr(&result) { r in _rd(additionAB.a) { a in _rd(additionAB.b) { b in _rd(additionCD.c) { c in _rd(additionCD.d) { d in vDSP_vaam(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func multiply<S, T, U>(addition additionAB: (a: S, b: T), addition additionCD: (c: U, d: U)) -> [Swift::Double] where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(additionAB.a.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.multiply(addition: additionAB, addition: additionCD, result: &result) }
  }
  public static func multiply<S, T, U, V>(addition additionAB: (a: S, b: T), addition additionCD: (c: U, d: U), result: inout V) where S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      _wr(&result) { r in _rd(additionAB.a) { a in _rd(additionAB.b) { b in _rd(additionCD.c) { c in _rd(additionCD.d) { d in vDSP_vaamD(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func subtract<R, S, T, U>(multiplication multiplicationAB: (a: T, b: U), multiplication multiplicationCD: (c: R, d: S)) -> [Swift::Float] where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, R.Element == Swift::Float, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(multiplicationAB.a.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.subtract(multiplication: multiplicationAB, multiplication: multiplicationCD, result: &result) }
  }
  public static func subtract<R, S, T, U, V>(multiplication multiplicationAB: (a: T, b: U), multiplication multiplicationCD: (c: R, d: S), result: inout V) where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, R.Element == Swift::Float, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      _wr(&result) { r in _rd(multiplicationAB.a) { a in _rd(multiplicationAB.b) { b in _rd(multiplicationCD.c) { c in _rd(multiplicationCD.d) { d in vDSP_vmmsb(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func subtract<R, S, T, U>(multiplication multiplicationAB: (a: T, b: U), multiplication multiplicationCD: (c: R, d: S)) -> [Swift::Double] where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, R.Element == Swift::Double, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(multiplicationAB.a.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.subtract(multiplication: multiplicationAB, multiplication: multiplicationCD, result: &result) }
  }
  public static func subtract<R, S, T, U, V>(multiplication multiplicationAB: (a: T, b: U), multiplication multiplicationCD: (c: R, d: S), result: inout V) where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, R.Element == Swift::Double, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      _wr(&result) { r in _rd(multiplicationAB.a) { a in _rd(multiplicationAB.b) { b in _rd(multiplicationCD.c) { c in _rd(multiplicationCD.d) { d in vDSP_vmmsbD(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func multiply<R, S, T, U>(subtraction subtractionAB: (a: R, b: S), subtraction subtractionCD: (c: T, d: U)) -> [Swift::Float] where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, R.Element == Swift::Float, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(subtractionAB.a.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.multiply(subtraction: subtractionAB, subtraction: subtractionCD, result: &result) }
  }
  public static func multiply<R, S, T, U, V>(subtraction subtractionAB: (a: R, b: S), subtraction subtractionCD: (c: T, d: U), result: inout V) where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, R.Element == Swift::Float, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      _wr(&result) { r in _rd(subtractionAB.a) { a in _rd(subtractionAB.b) { b in _rd(subtractionCD.c) { c in _rd(subtractionCD.d) { d in vDSP_vsbsbm(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func multiply<R, S, T, U>(subtraction subtractionAB: (a: R, b: S), subtraction subtractionCD: (c: T, d: U)) -> [Swift::Double] where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, R.Element == Swift::Double, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(subtractionAB.a.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.multiply(subtraction: subtractionAB, subtraction: subtractionCD, result: &result) }
  }
  public static func multiply<R, S, T, U, V>(subtraction subtractionAB: (a: R, b: S), subtraction subtractionCD: (c: T, d: U), result: inout V) where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, R.Element == Swift::Double, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      _wr(&result) { r in _rd(subtractionAB.a) { a in _rd(subtractionAB.b) { b in _rd(subtractionCD.c) { c in _rd(subtractionCD.d) { d in vDSP_vsbsbmD(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func multiply<R, S, T, U>(addition: (a: R, b: S), subtraction: (c: T, d: U)) -> [Swift::Float] where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, R.Element == Swift::Float, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(addition.a.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.multiply(addition: addition, subtraction: subtraction, result: &result) }
  }
  public static func multiply<R, S, T, U, V>(addition: (a: R, b: S), subtraction: (c: T, d: U), result: inout V) where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, R.Element == Swift::Float, S.Element == Swift::Float, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      _wr(&result) { r in _rd(addition.a) { a in _rd(addition.b) { b in _rd(subtraction.c) { c in _rd(subtraction.d) { d in vDSP_vasbm(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func multiply<R, S, T, U>(addition: (a: R, b: S), subtraction: (c: T, d: U)) -> [Swift::Double] where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, R.Element == Swift::Double, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(addition.a.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.multiply(addition: addition, subtraction: subtraction, result: &result) }
  }
  public static func multiply<R, S, T, U, V>(addition: (a: R, b: S), subtraction: (c: T, d: U), result: inout V) where R : Accelerate::AccelerateBuffer, S : Accelerate::AccelerateBuffer, T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, R.Element == Swift::Double, S.Element == Swift::Double, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      _wr(&result) { r in _rd(addition.a) { a in _rd(addition.b) { b in _rd(subtraction.c) { c in _rd(subtraction.d) { d in vDSP_vasbmD(a, 1, b, 1, c, 1, d, 1, r, 1, vDSP_Length(n)) } } } } }
  }
  public static func add<U>(multiplication: (a: U, b: Swift::Float), _ scalar: Swift::Float) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(multiplication.a.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.add(multiplication: multiplication, scalar, result: &result) }
  }
  public static func add<U, V>(multiplication: (a: U, b: Swift::Float), _ scalar: Swift::Float, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      var b = multiplication.b
      var c = scalar
      _wr(&result) { r in _rd(multiplication.a) { a in vDSP_vsmsa(a, 1, &b, &c, r, 1, vDSP_Length(n)) } }
  }
  public static func add<U>(multiplication: (a: U, b: Swift::Double), _ scalar: Swift::Double) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(multiplication.a.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.add(multiplication: multiplication, scalar, result: &result) }
  }
  public static func add<U, V>(multiplication: (a: U, b: Swift::Double), _ scalar: Swift::Double, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      var b = multiplication.b
      var c = scalar
      _wr(&result) { r in _rd(multiplication.a) { a in vDSP_vsmsaD(a, 1, &b, &c, r, 1, vDSP_Length(n)) } }
  }
  public static func subtract<T, U>(multiplication: (a: U, b: Swift::Float), _ vector: T) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.subtract(multiplication: multiplication, vector, result: &result) }
  }
  public static func subtract<T, U, V>(multiplication: (a: U, b: Swift::Float), _ vector: T, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      var b = multiplication.b
      _wr(&result) { r in _rd(multiplication.a) { a in _rd(vector) { c in vDSP_vsmsb(a, 1, &b, c, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func subtract<T, U>(multiplication: (a: U, b: Swift::Double), _ vector: T) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.subtract(multiplication: multiplication, vector, result: &result) }
  }
  public static func subtract<T, U, V>(multiplication: (a: U, b: Swift::Double), _ vector: T, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      var b = multiplication.b
      _wr(&result) { r in _rd(multiplication.a) { a in _rd(vector) { c in vDSP_vsmsbD(a, 1, &b, c, 1, r, 1, vDSP_Length(n)) } } }
  }
  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
  public static func normalize(_ vector: some AccelerateBuffer<Double>) -> [Swift::Double] {
      var r = [Double](repeating: 0, count: vector.count)
      vDSP.normalize(vector, result: &r)
      return r
  }
  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
  @discardableResult
  public static func normalize(_ vector: some AccelerateBuffer<Double>, result: inout some AccelerateMutableBuffer<Double>) -> (mean: Swift::Double, stdDev: Swift::Double) {
      let n = vector.count
      precondition(result.count >= n)
      var mean: Double = 0
      var deviation: Double = 0
      vector.withUnsafeBufferPointer { v in _wr(&result) { r in vDSP_normalizeD(v.baseAddress ?? _vdspEmpty(), 1, r, 1, &mean, &deviation, vDSP_Length(n)) } }
      return (mean, deviation)
  }
  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
  public static func standardDeviation(_ vector: some AccelerateMutableBuffer<Double>) -> Swift::Double {
      let n = vector.count
      var mean: Double = 0
      var deviation: Double = 0
      vector.withUnsafeBufferPointer { v in vDSP_normalizeD(v.baseAddress ?? _vdspEmpty(), 1, nil, 1, &mean, &deviation, vDSP_Length(n)) }
      return deviation
  }
  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
  public static func normalize(_ vector: some AccelerateBuffer<Float>) -> [Swift::Float] {
      var r = [Float](repeating: 0, count: vector.count)
      vDSP.normalize(vector, result: &r)
      return r
  }
  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
  @discardableResult
  public static func normalize(_ vector: some AccelerateBuffer<Float>, result: inout some AccelerateMutableBuffer<Float>) -> (mean: Swift::Float, stdDev: Swift::Float) {
      let n = vector.count
      precondition(result.count >= n)
      var mean: Float = 0
      var deviation: Float = 0
      vector.withUnsafeBufferPointer { v in _wr(&result) { r in vDSP_normalize(v.baseAddress ?? _vdspEmpty(), 1, r, 1, &mean, &deviation, vDSP_Length(n)) } }
      return (mean, deviation)
  }
  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
  public static func standardDeviation(_ vector: some AccelerateMutableBuffer<Float>) -> Swift::Float {
      let n = vector.count
      var mean: Float = 0
      var deviation: Float = 0
      vector.withUnsafeBufferPointer { v in vDSP_normalize(v.baseAddress ?? _vdspEmpty(), 1, nil, 1, &mean, &deviation, vDSP_Length(n)) }
      return deviation
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public struct Quadrature {
  internal let integrator: Accelerate::Quadrature.Accelerate::Integrator
  public init(integrator: Accelerate::Quadrature.Accelerate::Integrator, absoluteTolerance: Swift::Double = 1.0e-8, relativeTolerance: Swift::Double = 1.0e-2) {
      self.integrator = integrator
      self.absoluteTolerance = absoluteTolerance
      self.relativeTolerance = relativeTolerance
  }
  public var absoluteTolerance: Swift::Double
  public var relativeTolerance: Swift::Double
  public func integrate(over interval: Swift::ClosedRange<Swift::Double>, integrand: (_ input: Swift::UnsafeBufferPointer<Swift::Double>, _ result: Swift::UnsafeMutableBufferPointer<Swift::Double>) -> ()) -> Swift::Result<(integralResult: Swift::Double, estimatedAbsoluteError: Swift::Double), Accelerate::Quadrature.Accelerate::Error> {
      var options = quadrature_integrate_options()
      options.abs_tolerance = absoluteTolerance
      options.rel_tolerance = relativeTolerance
      switch integrator {
      case .qng:
          options.integrator = QUADRATURE_INTEGRATE_QNG
      case .qag(let pointsPerInterval, let maxIntervals):
          options.integrator = QUADRATURE_INTEGRATE_QAG
          options.qag_points_per_interval = pointsPerInterval.points
          options.max_intervals = maxIntervals
      case .qags(let maxIntervals):
          options.integrator = QUADRATURE_INTEGRATE_QAGS
          options.max_intervals = maxIntervals
      }
      typealias Integrand = (Swift::UnsafeBufferPointer<Swift::Double>, Swift::UnsafeMutableBufferPointer<Swift::Double>) -> ()
      return withoutActuallyEscaping(integrand) { (integrand: @escaping Integrand) in
          var context = integrand
          return withUnsafeMutablePointer(to: &context) { contextPointer in
              var function = quadrature_integrate_function(fun: { argument, count, x, y in
                  let integrand = argument!.assumingMemoryBound(to: Integrand.self).pointee
                  integrand(Swift::UnsafeBufferPointer(start: x, count: count), Swift::UnsafeMutableBufferPointer(start: y, count: count))
              }, fun_arg: Swift::UnsafeMutableRawPointer(contextPointer))
              var status = QUADRATURE_SUCCESS
              var estimatedError = 0.0
              let result = quadrature_integrate(&function, interval.lowerBound, interval.upperBound, &options, &status, &estimatedError, 0, nil)
              if status == QUADRATURE_SUCCESS {
                  return .success((integralResult: result, estimatedAbsoluteError: estimatedError))
              }
              return .failure(Quadrature.Error(quadratureStatus: status))
          }
      }
  }
  public func integrate(over interval: Swift::ClosedRange<Swift::Double>, integrand: (Swift::Double) -> Swift::Double) -> Swift::Result<(integralResult: Swift::Double, estimatedAbsoluteError: Swift::Double), Accelerate::Quadrature.Accelerate::Error> {
      return integrate(over: interval) { (input: Swift::UnsafeBufferPointer<Swift::Double>, result: Swift::UnsafeMutableBufferPointer<Swift::Double>) in
          for i in input.indices { result[i] = integrand(input[i]) }
      }
  }
  public enum Integrator {
    case qng
    public static let nonAdaptive: Accelerate::Quadrature.Accelerate::Integrator = .qng
    case qag(pointsPerInterval: Accelerate::Quadrature.Accelerate::QAGPointsPerInterval, maxIntervals: Swift::Int)
    public static func adaptive(pointsPerInterval: Accelerate::Quadrature.Accelerate::QAGPointsPerInterval, maxIntervals: Swift::Int) -> Accelerate::Quadrature.Accelerate::Integrator {
        return .qag(pointsPerInterval: pointsPerInterval, maxIntervals: maxIntervals)
    }
    case qags(maxIntervals: Swift::Int)
    public static func adaptiveWithSingularities(maxIntervals: Swift::Int) -> Accelerate::Quadrature.Accelerate::Integrator {
        return .qags(maxIntervals: maxIntervals)
    }
  }
  public struct QAGPointsPerInterval {
    public let points: Swift::Int
    internal init(points: Swift::Int) { self.points = points }
    public static let fifteen: Accelerate::Quadrature.Accelerate::QAGPointsPerInterval = Accelerate::Quadrature.Accelerate::QAGPointsPerInterval(points: 15)
    public static let twentyOne: Accelerate::Quadrature.Accelerate::QAGPointsPerInterval = Accelerate::Quadrature.Accelerate::QAGPointsPerInterval(points: 21)
    public static let thirtyOne: Accelerate::Quadrature.Accelerate::QAGPointsPerInterval = Accelerate::Quadrature.Accelerate::QAGPointsPerInterval(points: 31)
    public static let fortyOne: Accelerate::Quadrature.Accelerate::QAGPointsPerInterval = Accelerate::Quadrature.Accelerate::QAGPointsPerInterval(points: 41)
    public static let fiftyOne: Accelerate::Quadrature.Accelerate::QAGPointsPerInterval = Accelerate::Quadrature.Accelerate::QAGPointsPerInterval(points: 51)
    public static let sixtyOne: Accelerate::Quadrature.Accelerate::QAGPointsPerInterval = Accelerate::Quadrature.Accelerate::QAGPointsPerInterval(points: 61)
  }
  public enum Error : Swift::Error {
    case generic
    case invalidArgument
    case `internal`
    case integrateMaxEval
    case badIntegrandBehaviour
    public init(quadratureStatus: Accelerate::quadrature_status) {
        switch quadratureStatus {
        case QUADRATURE_INVALID_ARG_ERROR: self = .invalidArgument
        case QUADRATURE_INTERNAL_ERROR: self = .internal
        case QUADRATURE_INTEGRATE_MAX_EVAL_ERROR: self = .integrateMaxEval
        case QUADRATURE_INTEGRATE_BAD_BEHAVIOUR_ERROR: self = .badIntegrandBehaviour
        default: self = .generic
        }
    }
    public var errorDescription: Swift::String {
      switch self {
      case .generic: return "The integration failed."
      case .invalidArgument: return "An argument of the integration is invalid."
      case .internal: return "The integrator failed internally."
      case .integrateMaxEval: return "The integration reached its maximum number of intervals or evaluations."
      case .badIntegrandBehaviour: return "The integrand behaves too badly for the integrator."
      }
    }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func evaluatePolynomial<U>(usingCoefficients coefficients: [Swift::Float], withVariables variables: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(variables.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.evaluatePolynomial(usingCoefficients: coefficients, withVariables: variables, result: &result) }
  }
  public static func evaluatePolynomial<U, V>(usingCoefficients coefficients: [Swift::Float], withVariables variables: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(variables.count >= n && !coefficients.isEmpty)
      let degree = coefficients.count - 1
      _wr(&result) { r in _rd(variables) { v in _rd(coefficients) { c in vDSP_vpoly(c, 1, v, 1, r, 1, vDSP_Length(n), vDSP_Length(degree)) } } }
  }
  public static func evaluatePolynomial<U>(usingCoefficients coefficients: [Swift::Double], withVariables variables: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(variables.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.evaluatePolynomial(usingCoefficients: coefficients, withVariables: variables, result: &result) }
  }
  public static func evaluatePolynomial<U, V>(usingCoefficients coefficients: [Swift::Double], withVariables variables: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(variables.count >= n && !coefficients.isEmpty)
      let degree = coefficients.count - 1
      _wr(&result) { r in _rd(variables) { v in _rd(coefficients) { c in vDSP_vpolyD(c, 1, v, 1, r, 1, vDSP_Length(n), vDSP_Length(degree)) } } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public enum Radix {
    case radix2
    case radix3
    case radix5
    public var fftRadix: Accelerate::FFTRadix {
      switch self {
      case .radix2: return Accelerate::FFTRadix(kFFTRadix2)
      case .radix3: return Accelerate::FFTRadix(kFFTRadix3)
      case .radix5: return Accelerate::FFTRadix(kFFTRadix5)
      }
    }
  }
  public class FFT<T> where T : Accelerate::vDSP_FourierTransformable {
    /// The class's own element type, which the generic methods below shadow.
    internal typealias _SplitComplex = T
    internal let fftSetup: Swift::OpaquePointer
    internal let log2n: Accelerate::vDSP_Length
    public init?(log2n: Accelerate::vDSP_Length, radix: Accelerate::vDSP.Accelerate::Radix, ofType: T.Type) {
        guard let setup = T.FFTFunctions.makeFFTSetup(log2n: log2n, radix: radix) else { return nil }
        fftSetup = setup
        self.log2n = log2n
    }
    public func transform<T>(input: T, output: inout T, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection) where T : Accelerate::vDSP_FourierTransformable {
        precondition(MemoryLayout<T>.size == MemoryLayout<_SplitComplex>.size, "the FFT's split complex type")
        withUnsafePointer(to: input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                inputPointer.withMemoryRebound(to: _SplitComplex.FFTFunctions.SplitComplex.self, capacity: 1) { source in
                    outputPointer.withMemoryRebound(to: _SplitComplex.FFTFunctions.SplitComplex.self, capacity: 1) { destination in
                        _SplitComplex.FFTFunctions.transform(fftSetup: fftSetup, log2n: log2n, source: source, destination: destination, direction: direction)
                    }
                }
            }
        }
    }
    public func forward(input: Accelerate::DSPSplitComplex, output: inout Accelerate::DSPSplitComplex) {
        transform(input: input, output: &output, direction: .forward)
    }
    public func inverse(input: Accelerate::DSPSplitComplex, output: inout Accelerate::DSPSplitComplex) {
        transform(input: input, output: &output, direction: .inverse)
    }
    deinit { T.FFTFunctions.destroySetup(fftSetup) }
  }
  public class FFT2D<T> : Accelerate::vDSP.Accelerate::FFT<T> where T : Accelerate::vDSP_FourierTransformable {
    internal let width: Swift::Int
    internal let height: Swift::Int
    required public init?(width: Swift::Int, height: Swift::Int, ofType: T.Type) {
        self.width = width
        self.height = height
        let largest = Swift::max(width, height, 1)
        let log2n = Accelerate::vDSP_Length(Swift::Int.bitWidth - 1 - largest.leadingZeroBitCount + (largest.nonzeroBitCount > 1 ? 1 : 0))
        super.init(log2n: log2n, radix: .radix2, ofType: ofType)
    }
    override public func transform<T>(input: T, output: inout T, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection) where T : Accelerate::vDSP_FourierTransformable {
        precondition(MemoryLayout<T>.size == MemoryLayout<_SplitComplex>.size, "the FFT's split complex type")
        withUnsafePointer(to: input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                inputPointer.withMemoryRebound(to: _SplitComplex.FFTFunctions.SplitComplex.self, capacity: 1) { source in
                    outputPointer.withMemoryRebound(to: _SplitComplex.FFTFunctions.SplitComplex.self, capacity: 1) { destination in
                        _SplitComplex.FFTFunctions.transform2D(fftSetup: fftSetup, width: width, height: height, source: source, destination: destination, direction: direction)
                    }
                }
            }
        }
    }
    deinit {}
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol vDSP_FourierTransformFunctions {
  associatedtype SplitComplex
  static func makeFFTSetup(log2n: Accelerate::vDSP_Length, radix: Accelerate::vDSP.Accelerate::Radix) -> Swift::OpaquePointer?
  static func transform(fftSetup: Swift::OpaquePointer, log2n: Accelerate::vDSP_Length, source: Swift::UnsafePointer<Self.SplitComplex>, destination: Swift::UnsafeMutablePointer<Self.SplitComplex>, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection)
  static func transform2D(fftSetup: Swift::OpaquePointer, width: Swift::Int, height: Swift::Int, source: Swift::UnsafePointer<Self.SplitComplex>, destination: Swift::UnsafeMutablePointer<Self.SplitComplex>, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection)
  static func destroySetup(_ setup: Swift::OpaquePointer)
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public struct vDSP_SplitComplexFloat : Accelerate::vDSP_FourierTransformFunctions {
  public typealias SplitComplex = Accelerate::DSPSplitComplex
  public static func makeFFTSetup(log2n: Accelerate::vDSP_Length, radix: Accelerate::vDSP.Accelerate::Radix) -> Swift::OpaquePointer? {
      return vDSP_create_fftsetup(log2n, radix.fftRadix)
  }
  public static func transform(fftSetup: Swift::OpaquePointer, log2n: Accelerate::vDSP_Length, source: Swift::UnsafePointer<Accelerate::vDSP_SplitComplexFloat.Accelerate::SplitComplex>, destination: Swift::UnsafeMutablePointer<Accelerate::vDSP_SplitComplexFloat.Accelerate::SplitComplex>, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection) {
      vDSP_fft_zop(fftSetup, source, 1, destination, 1, log2n, direction.fftDirection)
  }
  public static func transform2D(fftSetup: Swift::OpaquePointer, width: Swift::Int, height: Swift::Int, source: Swift::UnsafePointer<Accelerate::vDSP_SplitComplexFloat.Accelerate::SplitComplex>, destination: Swift::UnsafeMutablePointer<Accelerate::vDSP_SplitComplexFloat.Accelerate::SplitComplex>, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection) {
      func log2(_ value: Swift::Int) -> Accelerate::vDSP_Length { Accelerate::vDSP_Length(Swift::max(value, 1).trailingZeroBitCount) }
      vDSP_fft2d_zop(fftSetup, source, 1, 0, destination, 1, 0, log2(width), log2(height), direction.fftDirection)
  }
  public static func destroySetup(_ setup: Swift::OpaquePointer) {
      vDSP_destroy_fftsetup(setup)
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public struct vDSP_SplitComplexDouble : Accelerate::vDSP_FourierTransformFunctions {
  public typealias SplitComplex = Accelerate::DSPDoubleSplitComplex
  public static func makeFFTSetup(log2n: Accelerate::vDSP_Length, radix: Accelerate::vDSP.Accelerate::Radix) -> Swift::OpaquePointer? {
      return vDSP_create_fftsetupD(log2n, radix.fftRadix)
  }
  public static func transform(fftSetup: Swift::OpaquePointer, log2n: Accelerate::vDSP_Length, source: Swift::UnsafePointer<Accelerate::vDSP_SplitComplexDouble.Accelerate::SplitComplex>, destination: Swift::UnsafeMutablePointer<Accelerate::vDSP_SplitComplexDouble.Accelerate::SplitComplex>, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection) {
      vDSP_fft_zopD(fftSetup, source, 1, destination, 1, log2n, direction.fftDirection)
  }
  public static func transform2D(fftSetup: Swift::OpaquePointer, width: Swift::Int, height: Swift::Int, source: Swift::UnsafePointer<Accelerate::vDSP_SplitComplexDouble.Accelerate::SplitComplex>, destination: Swift::UnsafeMutablePointer<Accelerate::vDSP_SplitComplexDouble.Accelerate::SplitComplex>, direction: Accelerate::vDSP.Accelerate::FourierTransformDirection) {
      func log2(_ value: Swift::Int) -> Accelerate::vDSP_Length { Accelerate::vDSP_Length(Swift::max(value, 1).trailingZeroBitCount) }
      vDSP_fft2d_zopD(fftSetup, source, 1, 0, destination, 1, 0, log2(width), log2(height), direction.fftDirection)
  }
  public static func destroySetup(_ setup: Swift::OpaquePointer) {
      vDSP_destroy_fftsetupD(setup)
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol vDSP_FourierTransformable {
  associatedtype FFTFunctions : Accelerate::vDSP_FourierTransformFunctions where Self == Self.FFTFunctions.SplitComplex
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::DSPSplitComplex : Accelerate::vDSP_FourierTransformable {
  public typealias FFTFunctions = Accelerate::vDSP_SplitComplexFloat
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::DSPDoubleSplitComplex : Accelerate::vDSP_FourierTransformable {
  public typealias FFTFunctions = Accelerate::vDSP_SplitComplexDouble
}
@available(macOS, deprecated, introduced: 10.15, message: "Use the `withUnsafeMutableBufferPointer` method on the real and imaginary arrays to create `DSPSplitComplex` for a defined scope.")
@available(iOS, deprecated, introduced: 13.0, message: "Use the `withUnsafeMutableBufferPointer` method on the real and imaginary arrays to create `DSPSplitComplex` for a defined scope.")
@available(watchOS, deprecated, introduced: 6.0, message: "Use the `withUnsafeMutableBufferPointer` method on the real and imaginary arrays to create `DSPSplitComplex` for a defined scope.")
@available(tvOS, deprecated, introduced: 13.0, message: "Use the `withUnsafeMutableBufferPointer` method on the real and imaginary arrays to create `DSPSplitComplex` for a defined scope.")
@available(*, deprecated, message: "Use the `withUnsafeMutableBufferPointer` method on the real and imaginary arrays to create `DSPSplitComplex` for a defined scope.")
extension Accelerate::DSPSplitComplex {
  public init(fromInputArray inputArray: [Swift::Float], realParts: inout [Swift::Float], imaginaryParts: inout [Swift::Float]) {
      let n = inputArray.count / 2
      precondition(realParts.count >= n && imaginaryParts.count >= n)
      // The split complex points into the arrays' storage, as the API intends:
      // it is valid only while they are neither resized nor freed.
      let real = realParts.withUnsafeMutableBufferPointer { $0.baseAddress! }
      let imaginary = imaginaryParts.withUnsafeMutableBufferPointer { $0.baseAddress! }
      self.init(realp: real, imagp: imaginary)
      var split = self
      inputArray.withUnsafeBufferPointer { buffer in
          guard let base = buffer.baseAddress, n > 0 else { return }
          base.withMemoryRebound(to: DSPComplex.self, capacity: n) { vDSP_ctoz($0, 2, &split, 1, Accelerate::vDSP_Length(n)) }
      }
  }
}
@available(macOS, deprecated, introduced: 10.15, message: "Use the `withUnsafeMutableBufferPointer` method on the real and imaginary arrays to create `DSPSplitComplex` for a defined scope.")
@available(iOS, deprecated, introduced: 13.0, message: "Use the `withUnsafeMutableBufferPointer` method on the real and imaginary arrays to create `DSPSplitComplex` for a defined scope.")
@available(watchOS, deprecated, introduced: 6.0, message: "Use the `withUnsafeMutableBufferPointer` method on the real and imaginary arrays to create `DSPSplitComplex` for a defined scope.")
@available(tvOS, deprecated, introduced: 13.0, message: "Use the `withUnsafeMutableBufferPointer` method on the real and imaginary arrays to create `DSPSplitComplex` for a defined scope.")
@available(*, deprecated, message: "Use the `withUnsafeMutableBufferPointer` method on the real and imaginary arrays to create `DSPSplitComplex` for a defined scope.")
extension Accelerate::DSPDoubleSplitComplex {
  public init(fromInputArray inputArray: [Swift::Double], realParts: inout [Swift::Double], imaginaryParts: inout [Swift::Double]) {
      let n = inputArray.count / 2
      precondition(realParts.count >= n && imaginaryParts.count >= n)
      // The split complex points into the arrays' storage, as the API intends:
      // it is valid only while they are neither resized nor freed.
      let real = realParts.withUnsafeMutableBufferPointer { $0.baseAddress! }
      let imaginary = imaginaryParts.withUnsafeMutableBufferPointer { $0.baseAddress! }
      self.init(realp: real, imagp: imaginary)
      var split = self
      inputArray.withUnsafeBufferPointer { buffer in
          guard let base = buffer.baseAddress, n > 0 else { return }
          base.withMemoryRebound(to: DSPDoubleComplex.self, capacity: n) { vDSP_ctozD($0, 2, &split, 1, Accelerate::vDSP_Length(n)) }
      }
  }
}
@available(macOS 15.0, *)
public struct BLAS {
  public struct ThreadingModel : Swift::Equatable, Swift::RawRepresentable {
    public static let multiThreaded: Accelerate::BLAS.Accelerate::ThreadingModel = Accelerate::BLAS.Accelerate::ThreadingModel(rawValue: Swift::UInt32(BLAS_THREADING_MULTI_THREADED.rawValue))
    public static let singleThreaded: Accelerate::BLAS.Accelerate::ThreadingModel = Accelerate::BLAS.Accelerate::ThreadingModel(rawValue: Swift::UInt32(BLAS_THREADING_SINGLE_THREADED.rawValue))
    public init(rawValue: Swift::UInt32) {
        self.rawValue = rawValue
    }
    public var rawValue: Swift::UInt32
    @available(macOS 15.0, *)
    public typealias RawValue = Swift::UInt32
  }
  public static var threadingModel: Accelerate::BLAS.Accelerate::ThreadingModel {
    get { Accelerate::BLAS.Accelerate::ThreadingModel(rawValue: Swift::UInt32(BLASGetThreading().rawValue)) }
    set { _ = BLASSetThreading(BLAS_THREADING(rawValue: numericCast(newValue.rawValue))) }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public struct Biquad<T> where T : Accelerate::vDSP_FloatingPointBiquadFilterable {
    internal let state: Accelerate::_vDSPBiquadState<T>
    public init?(coefficients: [Swift::Double], channelCount: Accelerate::vDSP_Length, sectionCount: Accelerate::vDSP_Length, ofType: T.Type) {
        precondition(coefficients.count == 5 * Swift::Int(sectionCount) * Swift::Int(channelCount), "a biquad needs 5 coefficients per section and channel")
        guard channelCount > 0, let setup = T.BiquadFunctions.makeBiquadSetup(channelCount: channelCount, coefficients: coefficients, sectionCount: sectionCount) else { return nil }
        state = Accelerate::_vDSPBiquadState(setup: setup, channelCount: channelCount, sectionCount: sectionCount)
    }
    public mutating func apply<U>(input: U) -> [T] where T == U.Element, U : Accelerate::AccelerateBuffer {
        var output = [T](repeating: 0, count: input.count)
        apply(input: input, output: &output)
        return output
    }
    public mutating func apply<U, V>(input: U, output: inout V) where T == U.Element, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == V.Element {
        let n = output.count
        precondition(input.count >= n)
        let state = self.state
        if state.channelCount == 1 {
            T.BiquadFunctions.applySingle(source: input, destination: &output, delays: state.delays, setup: state.setup, sectionCount: state.sectionCount, count: Accelerate::vDSP_Length(n))
            return
        }
        // Several channels: the buffers hold them one after another, each
        // n / channelCount elements long.
        let channels = Swift::Int(state.channelCount)
        let length = n / channels
        _wr(&output) { o in _rd(input) { i in
            var inputs = (0..<channels).map { Swift::UnsafePointer<T.BiquadFunctions.Scalar>(Swift::OpaquePointer(i + $0 * length)) }
            var outputs = (0..<channels).map { Swift::UnsafeMutablePointer<T.BiquadFunctions.Scalar>(Swift::OpaquePointer(o + $0 * length)) }
            T.BiquadFunctions.applyMulti(setup: state.setup, pInputs: &inputs, pOutputs: &outputs, count: Accelerate::vDSP_Length(length))
        } }
    }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol vDSP_FloatingPointBiquadFilterable : Swift::BinaryFloatingPoint {
  associatedtype BiquadFunctions : Accelerate::vDSP_BiquadFunctions where Self == Self.BiquadFunctions.Scalar
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Swift::Float : Accelerate::vDSP_FloatingPointBiquadFilterable {
  public typealias BiquadFunctions = Accelerate::vDSP.Accelerate::VectorizableFloat
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Swift::Double : Accelerate::vDSP_FloatingPointBiquadFilterable {
  public typealias BiquadFunctions = Accelerate::vDSP.Accelerate::VectorizableDouble
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol vDSP_BiquadFunctions {
  associatedtype Scalar
  static func makeBiquadSetup(channelCount: Accelerate::vDSP_Length, coefficients: [Swift::Double], sectionCount: Accelerate::vDSP_Length) -> Swift::OpaquePointer?
  static func applySingle<U, V>(source: U, destination: inout V, delays: Swift::UnsafeMutablePointer<Self.Scalar>, setup: Accelerate::vDSP_biquad_Setup, sectionCount: Accelerate::vDSP_Length, count: Accelerate::vDSP_Length) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, Self.Scalar == U.Element, U.Element == V.Element
  static func applyMulti(setup: Accelerate::vDSP_biquadm_SetupD, pInputs: Swift::UnsafeMutablePointer<Swift::UnsafePointer<Self.Scalar>>, pOutputs: Swift::UnsafeMutablePointer<Swift::UnsafeMutablePointer<Self.Scalar>>, count: Accelerate::vDSP_Length)
  static func destroySetup(channelCount: Swift::UInt, biquadSetup: Swift::OpaquePointer)
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::VectorizableFloat : Accelerate::vDSP_BiquadFunctions {
  public static func makeBiquadSetup(channelCount: Swift::UInt, coefficients: [Swift::Double], sectionCount: Swift::UInt) -> Swift::OpaquePointer? {
      if channelCount == 1 { return vDSP_biquad_CreateSetup(coefficients, sectionCount) }
      return vDSP_biquadm_CreateSetup(coefficients, sectionCount, channelCount)
  }
  public static func applySingle<U, V>(source: U, destination: inout V, delays: Swift::UnsafeMutablePointer<Accelerate::vDSP.Accelerate::VectorizableFloat.Accelerate::Scalar>, setup: Accelerate::vDSP_biquad_Setup, sectionCount: Accelerate::vDSP_Length, count: Accelerate::vDSP_Length) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      _wr(&destination) { d in _rd(source) { s in vDSP_biquad(setup, delays, s, 1, d, 1, count) } }
  }
  public static func applyMulti(setup: Accelerate::vDSP_biquadm_SetupD, pInputs: Swift::UnsafeMutablePointer<Swift::UnsafePointer<Accelerate::vDSP.Accelerate::VectorizableFloat.Accelerate::Scalar>>, pOutputs: Swift::UnsafeMutablePointer<Swift::UnsafeMutablePointer<Accelerate::vDSP.Accelerate::VectorizableFloat.Accelerate::Scalar>>, count: Accelerate::vDSP_Length) {
      vDSP_biquadm(setup, pInputs, 1, pOutputs, 1, count)
  }
  public static func destroySetup(channelCount: Swift::UInt, biquadSetup: Swift::OpaquePointer) {
      if channelCount == 1 { vDSP_biquad_DestroySetup(biquadSetup) } else { vDSP_biquadm_DestroySetup(biquadSetup) }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::VectorizableDouble : Accelerate::vDSP_BiquadFunctions {
  public static func makeBiquadSetup(channelCount: Accelerate::vDSP_Length, coefficients: [Swift::Double], sectionCount: Accelerate::vDSP_Length) -> Swift::OpaquePointer? {
      if channelCount == 1 { return vDSP_biquad_CreateSetupD(coefficients, sectionCount) }
      return vDSP_biquadm_CreateSetupD(coefficients, sectionCount, channelCount)
  }
  public static func applySingle<U, V>(source: U, destination: inout V, delays: Swift::UnsafeMutablePointer<Accelerate::vDSP.Accelerate::VectorizableDouble.Accelerate::Scalar>, setup: Accelerate::vDSP_biquad_Setup, sectionCount: Accelerate::vDSP_Length, count: Accelerate::vDSP_Length) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      _wr(&destination) { d in _rd(source) { s in vDSP_biquadD(setup, delays, s, 1, d, 1, count) } }
  }
  public static func applyMulti(setup: Accelerate::vDSP_biquadm_SetupD, pInputs: Swift::UnsafeMutablePointer<Swift::UnsafePointer<Accelerate::vDSP.Accelerate::VectorizableDouble.Accelerate::Scalar>>, pOutputs: Swift::UnsafeMutablePointer<Swift::UnsafeMutablePointer<Accelerate::vDSP.Accelerate::VectorizableDouble.Accelerate::Scalar>>, count: Accelerate::vDSP_Length) {
      vDSP_biquadmD(setup, pInputs, 1, pOutputs, 1, count)
  }
  public static func destroySetup(channelCount: Swift::UInt, biquadSetup: Swift::OpaquePointer) {
      if channelCount == 1 { vDSP_biquad_DestroySetupD(biquadSetup) } else { vDSP_biquadm_DestroySetupD(biquadSetup) }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func linearInterpolate<T, U>(_ vectorA: T, _ vectorB: U, using interpolationConstant: Swift::Float) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.linearInterpolate(vectorA, vectorB, using: interpolationConstant, result: &result) }
  }
  public static func linearInterpolate<T, U, V>(_ vectorA: T, _ vectorB: U, using interpolationConstant: Swift::Float, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      var t = interpolationConstant
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vintb(a, 1, b, 1, &t, r, 1, vDSP_Length(n)) } } }
  }
  public static func linearInterpolate<T, U>(_ vectorA: T, _ vectorB: U, using interpolationConstant: Swift::Double) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.linearInterpolate(vectorA, vectorB, using: interpolationConstant, result: &result) }
  }
  public static func linearInterpolate<T, U, V>(_ vectorA: T, _ vectorB: U, using interpolationConstant: Swift::Double, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      var t = interpolationConstant
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vintbD(a, 1, b, 1, &t, r, 1, vDSP_Length(n)) } } }
  }
  public static func linearInterpolate<T, U>(elementsOf vector: T, using controlVector: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(controlVector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.linearInterpolate(elementsOf: vector, using: controlVector, result: &result) }
  }
  public static func linearInterpolate<T, U, V>(elementsOf vector: T, using controlVector: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(controlVector.count >= n)
      let m = vector.count
      _wr(&result) { r in _rd(vector) { a in _rd(controlVector) { b in vDSP_vlint(a, b, 1, r, 1, vDSP_Length(n), vDSP_Length(m)) } } }
  }
  public static func linearInterpolate<T, U>(elementsOf vector: T, using controlVector: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(controlVector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.linearInterpolate(elementsOf: vector, using: controlVector, result: &result) }
  }
  public static func linearInterpolate<T, U, V>(elementsOf vector: T, using controlVector: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(controlVector.count >= n)
      let m = vector.count
      _wr(&result) { r in _rd(vector) { a in _rd(controlVector) { b in vDSP_vlintD(a, b, 1, r, 1, vDSP_Length(n), vDSP_Length(m)) } } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vForce {
  public static func ceil<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.ceil(vector, result: &result) }
  }
  public static func ceil<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvceilf(r, v, &c) } }
  }
  public static func ceil<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.ceil(vector, result: &result) }
  }
  public static func ceil<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvceil(r, v, &c) } }
  }
  public static func floor<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.floor(vector, result: &result) }
  }
  public static func floor<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvfloorf(r, v, &c) } }
  }
  public static func floor<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.floor(vector, result: &result) }
  }
  public static func floor<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvfloor(r, v, &c) } }
  }
  public static func copysign<U, V>(magnitudes: U, signs: V) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      return _make(magnitudes.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.copysign(magnitudes: magnitudes, signs: signs, result: &result) }
  }
  public static func copysign<T, U, V>(magnitudes: T, signs: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(magnitudes.count >= n && signs.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(magnitudes) { y in _rd(signs) { x in vvcopysignf(r, y, x, &c) } } }
  }
  public static func copysign<U, V>(magnitudes: U, signs: V) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      return _make(magnitudes.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.copysign(magnitudes: magnitudes, signs: signs, result: &result) }
  }
  public static func copysign<T, U, V>(magnitudes: T, signs: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(magnitudes.count >= n && signs.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(magnitudes) { y in _rd(signs) { x in vvcopysign(r, y, x, &c) } } }
  }
  public static func truncatingRemainder<U, V>(dividends: U, divisors: V) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      return _make(dividends.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.truncatingRemainder(dividends: dividends, divisors: divisors, result: &result) }
  }
  public static func truncatingRemainder<T, U, V>(dividends: T, divisors: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(dividends.count >= n && divisors.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(dividends) { y in _rd(divisors) { x in vvfmodf(r, y, x, &c) } } }
  }
  public static func truncatingRemainder<U, V>(dividends: U, divisors: V) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      return _make(dividends.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.truncatingRemainder(dividends: dividends, divisors: divisors, result: &result) }
  }
  public static func truncatingRemainder<T, U, V>(dividends: T, divisors: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(dividends.count >= n && divisors.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(dividends) { y in _rd(divisors) { x in vvfmod(r, y, x, &c) } } }
  }
  public static func remainder<U, V>(dividends: U, divisors: V) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      return _make(dividends.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.remainder(dividends: dividends, divisors: divisors, result: &result) }
  }
  public static func remainder<T, U, V>(dividends: T, divisors: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(dividends.count >= n && divisors.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(dividends) { y in _rd(divisors) { x in vvremainderf(r, y, x, &c) } } }
  }
  public static func remainder<U, V>(dividends: U, divisors: V) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      return _make(dividends.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.remainder(dividends: dividends, divisors: divisors, result: &result) }
  }
  public static func remainder<T, U, V>(dividends: T, divisors: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(dividends.count >= n && divisors.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(dividends) { y in _rd(divisors) { x in vvremainder(r, y, x, &c) } } }
  }
  public static func trunc<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.trunc(vector, result: &result) }
  }
  public static func trunc<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvintf(r, v, &c) } }
  }
  public static func trunc<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.trunc(vector, result: &result) }
  }
  public static func trunc<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvint(r, v, &c) } }
  }
  public static func nearestInteger<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.nearestInteger(vector, result: &result) }
  }
  public static func nearestInteger<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvnintf(r, v, &c) } }
  }
  public static func nearestInteger<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.nearestInteger(vector, result: &result) }
  }
  public static func nearestInteger<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvnint(r, v, &c) } }
  }
  public static func rsqrt<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.rsqrt(vector, result: &result) }
  }
  public static func rsqrt<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvrsqrtf(r, v, &c) } }
  }
  public static func rsqrt<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.rsqrt(vector, result: &result) }
  }
  public static func rsqrt<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvrsqrt(r, v, &c) } }
  }
  public static func sqrt<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.sqrt(vector, result: &result) }
  }
  public static func sqrt<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvsqrtf(r, v, &c) } }
  }
  public static func sqrt<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.sqrt(vector, result: &result) }
  }
  public static func sqrt<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvsqrt(r, v, &c) } }
  }
  public static func reciprocal<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.reciprocal(vector, result: &result) }
  }
  public static func reciprocal<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvrecf(r, v, &c) } }
  }
  public static func reciprocal<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.reciprocal(vector, result: &result) }
  }
  public static func reciprocal<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvrec(r, v, &c) } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vForce {
  public static func exp<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.exp(vector, result: &result) }
  }
  public static func exp<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvexpf(r, v, &c) } }
  }
  public static func expm1<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.expm1(vector, result: &result) }
  }
  public static func expm1<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvexpm1f(r, v, &c) } }
  }
  public static func exp2<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.exp2(vector, result: &result) }
  }
  public static func exp2<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvexp2f(r, v, &c) } }
  }
  public static func exp<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.exp(vector, result: &result) }
  }
  public static func exp<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvexp(r, v, &c) } }
  }
  public static func expm1<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.expm1(vector, result: &result) }
  }
  public static func expm1<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvexpm1(r, v, &c) } }
  }
  public static func exp2<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.exp2(vector, result: &result) }
  }
  public static func exp2<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvexp2(r, v, &c) } }
  }
  public static func log2<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.log2(vector, result: &result) }
  }
  public static func log2<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvlog2f(r, v, &c) } }
  }
  public static func log10<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.log10(vector, result: &result) }
  }
  public static func log10<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvlog10f(r, v, &c) } }
  }
  public static func log2<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.log2(vector, result: &result) }
  }
  public static func log2<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvlog2(r, v, &c) } }
  }
  public static func log10<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.log10(vector, result: &result) }
  }
  public static func log10<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvlog10(r, v, &c) } }
  }
  public static func logb<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.logb(vector, result: &result) }
  }
  public static func logb<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvlogbf(r, v, &c) } }
  }
  public static func logb<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.logb(vector, result: &result) }
  }
  public static func logb<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvlogb(r, v, &c) } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vForce {
  public static func pow<U, V>(bases: U, exponents: V) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      return _make(bases.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.pow(bases: bases, exponents: exponents, result: &result) }
  }
  public static func pow<T, U, V>(bases: T, exponents: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(exponents.count >= n && bases.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(exponents) { y in _rd(bases) { x in vvpowf(r, y, x, &c) } } }
  }
  public static func pow<U, V>(bases: U, exponents: V) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      return _make(bases.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.pow(bases: bases, exponents: exponents, result: &result) }
  }
  public static func pow<T, U, V>(bases: T, exponents: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(exponents.count >= n && bases.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(exponents) { y in _rd(bases) { x in vvpow(r, y, x, &c) } } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vForce {
  public static func sin<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.sin(vector, result: &result) }
  }
  public static func sin<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvsinf(r, v, &c) } }
  }
  public static func sin<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.sin(vector, result: &result) }
  }
  public static func sin<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvsin(r, v, &c) } }
  }
  public static func sinPi<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.sinPi(vector, result: &result) }
  }
  public static func sinPi<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvsinpif(r, v, &c) } }
  }
  public static func sinPi<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.sinPi(vector, result: &result) }
  }
  public static func sinPi<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvsinpi(r, v, &c) } }
  }
  public static func cos<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.cos(vector, result: &result) }
  }
  public static func cos<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvcosf(r, v, &c) } }
  }
  public static func cos<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.cos(vector, result: &result) }
  }
  public static func cos<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvcos(r, v, &c) } }
  }
  public static func cosPi<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.cosPi(vector, result: &result) }
  }
  public static func cosPi<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvcospif(r, v, &c) } }
  }
  public static func cosPi<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.cosPi(vector, result: &result) }
  }
  public static func cosPi<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvcospi(r, v, &c) } }
  }
  public static func sincos<T, U, V>(_ vector: T, sinResult: inout U, cosResult: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateMutableBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = sinResult.count
      precondition(cosResult.count == n && vector.count >= n)
      var c = Int32(n)
      _wr(&sinResult) { s in _wr(&cosResult) { co in _rd(vector) { v in vvsincosf(s, co, v, &c) } } }
  }
  public static func sincos<T, U, V>(_ vector: T, sinResult: inout U, cosResult: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateMutableBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = sinResult.count
      precondition(cosResult.count == n && vector.count >= n)
      var c = Int32(n)
      _wr(&sinResult) { s in _wr(&cosResult) { co in _rd(vector) { v in vvsincos(s, co, v, &c) } } }
  }
  public static func tan<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.tan(vector, result: &result) }
  }
  public static func tan<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvtanf(r, v, &c) } }
  }
  public static func tan<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.tan(vector, result: &result) }
  }
  public static func tan<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvtan(r, v, &c) } }
  }
  public static func tanPi<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.tanPi(vector, result: &result) }
  }
  public static func tanPi<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvtanpif(r, v, &c) } }
  }
  public static func tanPi<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.tanPi(vector, result: &result) }
  }
  public static func tanPi<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvtanpi(r, v, &c) } }
  }
  public static func asin<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.asin(vector, result: &result) }
  }
  public static func asin<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvasinf(r, v, &c) } }
  }
  public static func asin<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.asin(vector, result: &result) }
  }
  public static func asin<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvasin(r, v, &c) } }
  }
  public static func acos<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.acos(vector, result: &result) }
  }
  public static func acos<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvacosf(r, v, &c) } }
  }
  public static func acos<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.acos(vector, result: &result) }
  }
  public static func acos<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvacos(r, v, &c) } }
  }
  public static func atan<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.atan(vector, result: &result) }
  }
  public static func atan<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvatanf(r, v, &c) } }
  }
  public static func atan<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.atan(vector, result: &result) }
  }
  public static func atan<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvatan(r, v, &c) } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vForce {
  public static func sinh<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.sinh(vector, result: &result) }
  }
  public static func sinh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvsinhf(r, v, &c) } }
  }
  public static func sinh<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.sinh(vector, result: &result) }
  }
  public static func sinh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvsinh(r, v, &c) } }
  }
  public static func cosh<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.cosh(vector, result: &result) }
  }
  public static func cosh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvcoshf(r, v, &c) } }
  }
  public static func cosh<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.cosh(vector, result: &result) }
  }
  public static func cosh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvcosh(r, v, &c) } }
  }
  public static func tanh<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.tanh(vector, result: &result) }
  }
  public static func tanh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvtanhf(r, v, &c) } }
  }
  public static func tanh<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.tanh(vector, result: &result) }
  }
  public static func tanh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvtanh(r, v, &c) } }
  }
  public static func asinh<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.asinh(vector, result: &result) }
  }
  public static func asinh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvasinhf(r, v, &c) } }
  }
  public static func asinh<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.asinh(vector, result: &result) }
  }
  public static func asinh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvasinh(r, v, &c) } }
  }
  public static func acosh<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.acosh(vector, result: &result) }
  }
  public static func acosh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvacoshf(r, v, &c) } }
  }
  public static func acosh<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.acosh(vector, result: &result) }
  }
  public static func acosh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvacosh(r, v, &c) } }
  }
  public static func atanh<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.atanh(vector, result: &result) }
  }
  public static func atanh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvatanhf(r, v, &c) } }
  }
  public static func atanh<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.atanh(vector, result: &result) }
  }
  public static func atanh<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvatanh(r, v, &c) } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func slidingWindowSum<U>(_ vector: U, usingWindowLength windowLength: Swift::Int) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count - windowLength + 1) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.slidingWindowSum(vector, usingWindowLength: windowLength, result: &result) }
  }
  public static func slidingWindowSum<U, V>(_ vector: U, usingWindowLength windowLength: Swift::Int, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n + windowLength - 1)
      _wr(&result) { r in _rd(vector) { v in vDSP_vswsum(v, 1, r, 1, vDSP_Length(n), vDSP_Length(windowLength)) } }
  }
  public static func slidingWindowSum<U>(_ vector: U, usingWindowLength windowLength: Swift::Int) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count - windowLength + 1) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.slidingWindowSum(vector, usingWindowLength: windowLength, result: &result) }
  }
  public static func slidingWindowSum<U, V>(_ vector: U, usingWindowLength windowLength: Swift::Int, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n + windowLength - 1)
      _wr(&result) { r in _rd(vector) { v in vDSP_vswsumD(v, 1, r, 1, vDSP_Length(n), vDSP_Length(windowLength)) } }
  }
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Accelerate::vForce {
  public static func log<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.log(vector, result: &result) }
  }
  public static func log<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvlogf(r, v, &c) } }
  }
  public static func log<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.log(vector, result: &result) }
  }
  public static func log<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvlog(r, v, &c) } }
  }
  public static func log1p<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.log1p(vector, result: &result) }
  }
  public static func log1p<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvlog1pf(r, v, &c) } }
  }
  public static func log1p<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.log1p(vector, result: &result) }
  }
  public static func log1p<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(vector) { v in vvlog1p(r, v, &c) } }
  }
  public static func atan2<T, U, V>(x: T, y: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(x.count >= n && y.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(y) { yp in _rd(x) { xp in vvatan2f(r, yp, xp, &c) } } }
  }
  public static func atan2<U, V>(x: U, y: V) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      return _make(x.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vForce.atan2(x: x, y: y, result: &result) }
  }
  public static func atan2<T, U, V>(x: T, y: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(x.count >= n && y.count >= n)
      var c = Int32(n)
      _wr(&result) { r in _rd(y) { yp in _rd(x) { xp in vvatan2(r, yp, xp, &c) } } }
  }
  public static func atan2<U, V>(x: U, y: V) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      return _make(x.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vForce.atan2(x: x, y: y, result: &result) }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public enum FourierTransformDirection {
    case forward
    case inverse
    public var dftDirection: Accelerate::vDSP_DFT_Direction {
      switch self {
      case .forward: return .FORWARD
      case .inverse: return .INVERSE
      }
    }
    public var fftDirection: Accelerate::FFTDirection {
      switch self {
      case .forward: return Accelerate::FFTDirection(kFFTDirection_Forward)
      case .inverse: return Accelerate::FFTDirection(kFFTDirection_Inverse)
      }
    }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func twoPoleTwoZeroFilter<U>(_ source: U, coefficients: (Swift::Float, Swift::Float, Swift::Float, Swift::Float, Swift::Float)) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(source.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.twoPoleTwoZeroFilter(source, coefficients: coefficients, result: &result) }
  }
  public static func twoPoleTwoZeroFilter<U, V>(_ source: U, coefficients: (Swift::Float, Swift::Float, Swift::Float, Swift::Float, Swift::Float), result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(n >= 2 && source.count >= n)
      var b = [coefficients.0, coefficients.1, coefficients.2, coefficients.3, coefficients.4]
      _wr(&result) { r in _rd(source) { s in vDSP_deq22(s, 1, &b, r, 1, vDSP_Length(n - 2)) } }
  }
  public static func twoPoleTwoZeroFilter<U>(_ source: U, coefficients: (Swift::Double, Swift::Double, Swift::Double, Swift::Double, Swift::Double)) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(source.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.twoPoleTwoZeroFilter(source, coefficients: coefficients, result: &result) }
  }
  public static func twoPoleTwoZeroFilter<U, V>(_ source: U, coefficients: (Swift::Double, Swift::Double, Swift::Double, Swift::Double, Swift::Double), result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(n >= 2 && source.count >= n)
      var b = [coefficients.0, coefficients.1, coefficients.2, coefficients.3, coefficients.4]
      _wr(&result) { r in _rd(source) { s in vDSP_deq22D(s, 1, &b, r, 1, vDSP_Length(n - 2)) } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func minimum<U>(_ vectorA: U, _ vectorB: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.minimum(vectorA, vectorB, result: &result) }
  }
  public static func minimum<U, V>(_ vectorA: U, _ vectorB: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vmin(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func minimum<U>(_ vectorA: U, _ vectorB: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.minimum(vectorA, vectorB, result: &result) }
  }
  public static func minimum<U, V>(_ vectorA: U, _ vectorB: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vminD(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func maximum<U>(_ vectorA: U, _ vectorB: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.maximum(vectorA, vectorB, result: &result) }
  }
  public static func maximum<U, V>(_ vectorA: U, _ vectorB: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vmax(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
  public static func maximum<U>(_ vectorA: U, _ vectorB: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vectorA.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.maximum(vectorA, vectorB, result: &result) }
  }
  public static func maximum<U, V>(_ vectorA: U, _ vectorB: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vectorA.count >= n && vectorB.count >= n)
      _wr(&result) { r in _rd(vectorA) { a in _rd(vectorB) { b in vDSP_vmaxD(a, 1, b, 1, r, 1, vDSP_Length(n)) } } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func absolute<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.absolute(vector, result: &result) }
  }
  public static func absolute<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vabs(v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func absolute<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.absolute(vector, result: &result) }
  }
  public static func absolute<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vabsD(v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func negativeAbsolute<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.negativeAbsolute(vector, result: &result) }
  }
  public static func negativeAbsolute<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vnabs(v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func negativeAbsolute<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.negativeAbsolute(vector, result: &result) }
  }
  public static func negativeAbsolute<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vnabsD(v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func negative<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.negative(vector, result: &result) }
  }
  public static func negative<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vneg(v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func negative<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.negative(vector, result: &result) }
  }
  public static func negative<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vnegD(v, 1, r, 1, vDSP_Length(n)) } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func reverse<V>(_ vector: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Float {
      let n = vector.count
      _wr(&vector) { v in vDSP_vrvrs(v, 1, vDSP_Length(n)) }
  }
  public static func reverse<V>(_ vector: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Double {
      let n = vector.count
      _wr(&vector) { v in vDSP_vrvrsD(v, 1, vDSP_Length(n)) }
  }
  public enum SortOrder : Swift::Int32 {
    case ascending = 1
    case descending = -1
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public typealias RawValue = Swift::Int32
  }
  public static func sort<V>(_ vector: inout V, sortOrder: Accelerate::vDSP.Accelerate::SortOrder) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Float {
      let n = vector.count
      _wr(&vector) { v in vDSP_vsort(v, vDSP_Length(n), sortOrder.rawValue) }
  }
  public static func sort<V>(_ vector: inout V, sortOrder: Accelerate::vDSP.Accelerate::SortOrder) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Double {
      let n = vector.count
      _wr(&vector) { v in vDSP_vsortD(v, vDSP_Length(n), sortOrder.rawValue) }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func square<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.square(vector, result: &result) }
  }
  public static func square<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vsq(v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func square<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.square(vector, result: &result) }
  }
  public static func square<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vsqD(v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func signedSquare<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.signedSquare(vector, result: &result) }
  }
  public static func signedSquare<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vssq(v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func signedSquare<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.signedSquare(vector, result: &result) }
  }
  public static func signedSquare<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vssqD(v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func trunc<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.trunc(vector, result: &result) }
  }
  public static func trunc<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vfrac(v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func trunc<U>(_ vector: U) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.trunc(vector, result: &result) }
  }
  public static func trunc<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      _wr(&result) { r in _rd(vector) { v in vDSP_vfracD(v, 1, r, 1, vDSP_Length(n)) } }
  }
  public static func countZeroCrossings<U>(_ vector: U) -> Swift::UInt where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      let n = vector.count
      var last: vDSP_Length = 0
      var crossings: vDSP_Length = 0
      _rd(vector) { v in vDSP_nzcros(v, 1, vDSP_Length(n), &last, &crossings, vDSP_Length(n)) }
      return UInt(crossings)
  }
  public static func countZeroCrossings<U>(_ vector: U) -> Swift::UInt where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      let n = vector.count
      var last: vDSP_Length = 0
      var crossings: vDSP_Length = 0
      _rd(vector) { v in vDSP_nzcrosD(v, 1, vDSP_Length(n), &last, &crossings, vDSP_Length(n)) }
      return UInt(crossings)
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func phase<V>(_ splitComplex: Accelerate::DSPSplitComplex, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Float {
      let n = result.count
      var a = splitComplex
      _wr(&result) { r in vDSP_zvphas(&a, 1, r, 1, vDSP_Length(n)) }
  }
  public static func phase<V>(_ splitComplex: Accelerate::DSPDoubleSplitComplex, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Double {
      let n = result.count
      var a = splitComplex
      _wr(&result) { r in vDSP_zvphasD(&a, 1, r, 1, vDSP_Length(n)) }
  }
  public static func copy(_ source: Accelerate::DSPSplitComplex, to destination: inout Accelerate::DSPSplitComplex, count: Swift::Int) {
      var a = source
      vDSP_zvmov(&a, 1, &destination, 1, vDSP_Length(count))
  }
  public static func copy(_ source: Accelerate::DSPDoubleSplitComplex, to destination: inout Accelerate::DSPDoubleSplitComplex, count: Swift::Int) {
      var a = source
      vDSP_zvmovD(&a, 1, &destination, 1, vDSP_Length(count))
  }
  public static func conjugate(_ splitComplex: Accelerate::DSPSplitComplex, count: Swift::Int, result: inout Accelerate::DSPSplitComplex) {
      var a = splitComplex
      vDSP_zvconj(&a, 1, &result, 1, vDSP_Length(count))
  }
  public static func conjugate(_ splitComplex: Accelerate::DSPDoubleSplitComplex, count: Swift::Int, result: inout Accelerate::DSPDoubleSplitComplex) {
      var a = splitComplex
      vDSP_zvconjD(&a, 1, &result, 1, vDSP_Length(count))
  }
  public static func divide<U>(_ splitComplex: Accelerate::DSPSplitComplex, by vector: U, result: inout Accelerate::DSPSplitComplex) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      let n = vector.count
      var a = splitComplex
      _rd(vector) { b in vDSP_zrvdiv(&a, 1, b, 1, &result, 1, vDSP_Length(n)) }
  }
  public static func divide<U>(_ splitComplex: Accelerate::DSPDoubleSplitComplex, by vector: U, result: inout Accelerate::DSPDoubleSplitComplex) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      let n = vector.count
      var a = splitComplex
      _rd(vector) { b in vDSP_zrvdivD(&a, 1, b, 1, &result, 1, vDSP_Length(n)) }
  }
  public static func multiply<U>(_ splitComplex: Accelerate::DSPSplitComplex, by vector: U, result: inout Accelerate::DSPSplitComplex) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      let n = vector.count
      var a = splitComplex
      _rd(vector) { b in vDSP_zrvmul(&a, 1, b, 1, &result, 1, vDSP_Length(n)) }
  }
  public static func multiply<U>(_ splitComplex: Accelerate::DSPDoubleSplitComplex, by vector: U, result: inout Accelerate::DSPDoubleSplitComplex) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      let n = vector.count
      var a = splitComplex
      _rd(vector) { b in vDSP_zrvmulD(&a, 1, b, 1, &result, 1, vDSP_Length(n)) }
  }
  public static func multiply(_ splitComplexA: Accelerate::DSPSplitComplex, by splitComplexB: Accelerate::DSPSplitComplex, count: Swift::Int, useConjugate: Swift::Bool, result: inout Accelerate::DSPSplitComplex) {
      var a = splitComplexA
      var b = splitComplexB
      vDSP_zvmul(&a, 1, &b, 1, &result, 1, vDSP_Length(count), useConjugate ? -1 : 1)
  }
  public static func multiply(_ splitComplexA: Accelerate::DSPDoubleSplitComplex, by splitComplexB: Accelerate::DSPDoubleSplitComplex, count: Swift::Int, useConjugate: Swift::Bool, result: inout Accelerate::DSPDoubleSplitComplex) {
      var a = splitComplexA
      var b = splitComplexB
      vDSP_zvmulD(&a, 1, &b, 1, &result, 1, vDSP_Length(count), useConjugate ? -1 : 1)
  }
  public static func add(_ splitComplexA: Accelerate::DSPSplitComplex, to splitComplexB: Accelerate::DSPSplitComplex, count: Swift::Int, result: inout Accelerate::DSPSplitComplex) {
      var a = splitComplexA
      var b = splitComplexB
      vDSP_zvadd(&a, 1, &b, 1, &result, 1, vDSP_Length(count))
  }
  public static func add(_ splitComplexA: Accelerate::DSPDoubleSplitComplex, to splitComplexB: Accelerate::DSPDoubleSplitComplex, count: Swift::Int, result: inout Accelerate::DSPDoubleSplitComplex) {
      var a = splitComplexA
      var b = splitComplexB
      vDSP_zvaddD(&a, 1, &b, 1, &result, 1, vDSP_Length(count))
  }
  public static func divide(_ splitComplexA: Accelerate::DSPSplitComplex, by splitComplexB: Accelerate::DSPSplitComplex, count: Swift::Int, result: inout Accelerate::DSPSplitComplex) {
      var a = splitComplexA
      var b = splitComplexB
      vDSP_zvdiv(&b, 1, &a, 1, &result, 1, vDSP_Length(count))
  }
  public static func divide(_ splitComplexA: Accelerate::DSPDoubleSplitComplex, by splitComplexB: Accelerate::DSPDoubleSplitComplex, count: Swift::Int, result: inout Accelerate::DSPDoubleSplitComplex) {
      var a = splitComplexA
      var b = splitComplexB
      vDSP_zvdivD(&b, 1, &a, 1, &result, 1, vDSP_Length(count))
  }
  public static func subtract(_ splitComplexB: Accelerate::DSPSplitComplex, from splitComplexA: Accelerate::DSPSplitComplex, count: Swift::Int, result: inout Accelerate::DSPSplitComplex) {
      var a = splitComplexA
      var b = splitComplexB
      vDSP_zvsub(&a, 1, &b, 1, &result, 1, vDSP_Length(count))
  }
  public static func subtract(_ splitComplexB: Accelerate::DSPDoubleSplitComplex, from splitComplexA: Accelerate::DSPDoubleSplitComplex, count: Swift::Int, result: inout Accelerate::DSPDoubleSplitComplex) {
      var a = splitComplexA
      var b = splitComplexB
      vDSP_zvsubD(&a, 1, &b, 1, &result, 1, vDSP_Length(count))
  }
  public static func absolute<V>(_ vector: Accelerate::DSPSplitComplex, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Float {
      let n = result.count
      var a = vector
      _wr(&result) { r in vDSP_zvabs(&a, 1, r, 1, vDSP_Length(n)) }
  }
  public static func absolute<V>(_ vector: Accelerate::DSPDoubleSplitComplex, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Double {
      let n = result.count
      var a = vector
      _wr(&result) { r in vDSP_zvabsD(&a, 1, r, 1, vDSP_Length(n)) }
  }
  public static func squareMagnitudes<V>(_ splitComplex: Accelerate::DSPSplitComplex, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Float {
      let n = result.count
      var a = splitComplex
      _wr(&result) { r in vDSP_zvmags(&a, 1, r, 1, vDSP_Length(n)) }
  }
  public static func squareMagnitudes<V>(_ splitComplex: Accelerate::DSPDoubleSplitComplex, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Double {
      let n = result.count
      var a = splitComplex
      _wr(&result) { r in vDSP_zvmagsD(&a, 1, r, 1, vDSP_Length(n)) }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public enum DCTTransformType : Swift::CaseIterable {
    case II
    case III
    case IV
    public var dctType: Accelerate::vDSP_DCT_Type {
      switch self {
      case .II: return .II
      case .III: return .III
      case .IV: return .IV
      }
    }
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public typealias AllCases = [Accelerate::vDSP.Accelerate::DCTTransformType]
  }
  public class DCT {
    internal let setup: Swift::OpaquePointer
    internal let count: Swift::Int
    public init?(previous: Accelerate::vDSP.Accelerate::DCT? = nil, count: Swift::Int, transformType: Accelerate::vDSP.Accelerate::DCTTransformType) {
        guard let setup = vDSP_DCT_CreateSetup(previous?.setup, Accelerate::vDSP_Length(count), transformType.dctType) else { return nil }
        self.setup = setup
        self.count = count
    }
    public func transform<U>(_ vector: U) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
        return _make(count) { (result: inout Swift::UnsafeMutableBufferPointer<Swift::Float>) in transform(vector, result: &result) }
    }
    public func transform<U, V>(_ vector: U, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
        precondition(vector.count >= count && result.count >= count)
        let setup = self.setup
        _wr(&result) { r in _rd(vector) { v in vDSP_DCT_Execute(setup, v, r) } }
    }
    deinit { vDSP_DFT_DestroySetup(setup) }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol vDSP_FloatingPointGeneratable : Swift::BinaryFloatingPoint {
}
extension Swift::Float : Accelerate::vDSP_FloatingPointGeneratable {
}
extension Swift::Double : Accelerate::vDSP_FloatingPointGeneratable {
}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Accelerate::vDSP {
  @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
  public static func linearInterpolate<T, U, V>(values: T, atIndices indices: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(indices.count >= n)
      let m = values.count
      _wr(&result) { r in _rd(values) { a in _rd(indices) { b in vDSP_vlint(a, b, 1, r, 1, vDSP_Length(n), vDSP_Length(m)) } } }
  }
  @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
  public static func linearInterpolate<T, U>(values: T, atIndices indices: U) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(indices.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.linearInterpolate(values: values, atIndices: indices, result: &result) }
  }
  @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
  public static func linearInterpolate<T, U, V>(values: T, atIndices indices: U, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(indices.count >= n)
      let m = values.count
      _wr(&result) { r in _rd(values) { a in _rd(indices) { b in vDSP_vlintD(a, b, 1, r, 1, vDSP_Length(n), vDSP_Length(m)) } } }
  }
  @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
  public static func linearInterpolate<T, U>(values: T, atIndices indices: U) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(indices.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.linearInterpolate(values: values, atIndices: indices, result: &result) }
  }
  @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
  public static func linearInterpolate<T, U, V>(lookupTable: T, withOffsets offsets: U, scale: Swift::Float = 1, baseOffset: Swift::Float = 0, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Float, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(offsets.count >= n)
      let m = lookupTable.count
      var s = scale
      var o = baseOffset
      _wr(&result) { r in _rd(offsets) { a in _rd(lookupTable) { t in vDSP_vtabi(a, 1, &s, &o, t, vDSP_Length(m), r, 1, vDSP_Length(n)) } } }
  }
  @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
  public static func linearInterpolate<T, U>(lookupTable: T, withOffsets offsets: U, scale: Swift::Float = 1, baseOffset: Swift::Float = 0) -> [Swift::Float] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Float, U.Element == Swift::Float {
      return _make(offsets.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.linearInterpolate(lookupTable: lookupTable, withOffsets: offsets, scale: scale, baseOffset: baseOffset, result: &result) }
  }
  @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
  public static func linearInterpolate<T, U, V>(lookupTable: T, withOffsets offsets: U, scale: Swift::Double = 1, baseOffset: Swift::Double = 0, result: inout V) where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, T.Element == Swift::Double, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(offsets.count >= n)
      let m = lookupTable.count
      var s = scale
      var o = baseOffset
      _wr(&result) { r in _rd(offsets) { a in _rd(lookupTable) { t in vDSP_vtabiD(a, 1, &s, &o, t, vDSP_Length(m), r, 1, vDSP_Length(n)) } } }
  }
  @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
  public static func linearInterpolate<T, U>(lookupTable: T, withOffsets offsets: U, scale: Swift::Double = 1, baseOffset: Swift::Double = 0) -> [Swift::Double] where T : Accelerate::AccelerateBuffer, U : Accelerate::AccelerateBuffer, T.Element == Swift::Double, U.Element == Swift::Double {
      return _make(offsets.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.linearInterpolate(lookupTable: lookupTable, withOffsets: offsets, scale: scale, baseOffset: baseOffset, result: &result) }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP {
  public static func fill<V>(_ vector: inout V, with value: Swift::Float) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Float {
      let n = vector.count
      var value = value
      _wr(&vector) { v in vDSP_vfill(&value, v, 1, vDSP_Length(n)) }
  }
  public static func fill<V>(_ vector: inout V, with value: Swift::Double) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Double {
      let n = vector.count
      var value = value
      _wr(&vector) { v in vDSP_vfillD(&value, v, 1, vDSP_Length(n)) }
  }
  public static func clear<V>(_ vector: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Float {
      let n = vector.count
      _wr(&vector) { v in vDSP_vclr(v, 1, vDSP_Length(n)) }
  }
  public static func clear<V>(_ vector: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Double {
      let n = vector.count
      _wr(&vector) { v in vDSP_vclrD(v, 1, vDSP_Length(n)) }
  }
  public enum WindowSequence {
    case hanningNormalized
    case hanningDenormalized
    case hamming
    case blackman
  }
  public static func window<T>(ofType: T.Type, usingSequence sequence: Accelerate::vDSP.Accelerate::WindowSequence, count: Swift::Int, isHalfWindow: Swift::Bool) -> [T] where T : Accelerate::vDSP_FloatingPointGeneratable {
      if T.self == Float.self {
          var r = [Float](repeating: 0, count: count)
          vDSP.formWindow(usingSequence: sequence, result: &r, isHalfWindow: isHalfWindow)
          return unsafeBitCast(r, to: [T].self)
      }
      var r = [Double](repeating: 0, count: count)
      vDSP.formWindow(usingSequence: sequence, result: &r, isHalfWindow: isHalfWindow)
      return unsafeBitCast(r, to: [T].self)
  }
  public static func formWindow<V>(usingSequence sequence: Accelerate::vDSP.Accelerate::WindowSequence, result: inout V, isHalfWindow: Swift::Bool) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Float {
      let n = result.count
      let half = isHalfWindow ? Int32(vDSP_HALF_WINDOW) : 0
      _wr(&result) { r in
          switch sequence {
          case .hanningNormalized: vDSP_hann_window(r, vDSP_Length(n), Int32(vDSP_HANN_NORM) | half)
          case .hanningDenormalized: vDSP_hann_window(r, vDSP_Length(n), Int32(vDSP_HANN_DENORM) | half)
          case .hamming: vDSP_hamm_window(r, vDSP_Length(n), half)
          case .blackman: vDSP_blkman_window(r, vDSP_Length(n), half)
          }
      }
  }
  public static func formWindow<V>(usingSequence sequence: Accelerate::vDSP.Accelerate::WindowSequence, result: inout V, isHalfWindow: Swift::Bool) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Double {
      let n = result.count
      let half = isHalfWindow ? Int32(vDSP_HALF_WINDOW) : 0
      _wr(&result) { r in
          switch sequence {
          case .hanningNormalized: vDSP_hann_windowD(r, vDSP_Length(n), Int32(vDSP_HANN_NORM) | half)
          case .hanningDenormalized: vDSP_hann_windowD(r, vDSP_Length(n), Int32(vDSP_HANN_DENORM) | half)
          case .hamming: vDSP_hamm_windowD(r, vDSP_Length(n), half)
          case .blackman: vDSP_blkman_windowD(r, vDSP_Length(n), half)
          }
      }
  }
  public static func ramp(withInitialValue initialValue: Swift::Float, increment: Swift::Float, count: Swift::Int) -> [Swift::Float] {
      return _make(count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.formRamp(withInitialValue: initialValue, increment: increment, result: &result) }
  }
  public static func formRamp<V>(withInitialValue initialValue: Swift::Float, increment: Swift::Float, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Float {
      let n = result.count
      var a = initialValue
      var b = increment
      _wr(&result) { r in vDSP_vramp(&a, &b, r, 1, vDSP_Length(n)) }
  }
  public static func ramp(withInitialValue initialValue: Swift::Double, increment: Swift::Double, count: Swift::Int) -> [Swift::Double] {
      return _make(count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.formRamp(withInitialValue: initialValue, increment: increment, result: &result) }
  }
  public static func formRamp<V>(withInitialValue initialValue: Swift::Double, increment: Swift::Double, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Double {
      let n = result.count
      var a = initialValue
      var b = increment
      _wr(&result) { r in vDSP_vrampD(&a, &b, r, 1, vDSP_Length(n)) }
  }
  public static func ramp(in range: Swift::ClosedRange<Swift::Float>, count: Swift::Int) -> [Swift::Float] {
      return _make(count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.formRamp(in: range, result: &result) }
  }
  public static func formRamp<V>(in range: Swift::ClosedRange<Swift::Float>, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Float {
      let n = result.count
      var a = range.lowerBound
      var b = range.upperBound
      _wr(&result) { r in vDSP_vgen(&a, &b, r, 1, vDSP_Length(n)) }
  }
  public static func ramp(in range: Swift::ClosedRange<Swift::Double>, count: Swift::Int) -> [Swift::Double] {
      return _make(count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.formRamp(in: range, result: &result) }
  }
  public static func formRamp<V>(in range: Swift::ClosedRange<Swift::Double>, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Double {
      let n = result.count
      var a = range.lowerBound
      var b = range.upperBound
      _wr(&result) { r in vDSP_vgenD(&a, &b, r, 1, vDSP_Length(n)) }
  }
  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
  public static func ramp(from start: Swift::Float, through end: Swift::Float, count: Swift::Int) -> [Swift::Float] {
      return _make(count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.formRamp(from: start, through: end, result: &result) }
  }
  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
  public static func formRamp<V>(from start: Swift::Float, through end: Swift::Float, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Float {
      let n = result.count
      var a = start
      var b = end
      _wr(&result) { r in vDSP_vgen(&a, &b, r, 1, vDSP_Length(n)) }
  }
  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
  public static func ramp(from start: Swift::Double, through end: Swift::Double, count: Swift::Int) -> [Swift::Double] {
      return _make(count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.formRamp(from: start, through: end, result: &result) }
  }
  @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
  public static func formRamp<V>(from start: Swift::Double, through end: Swift::Double, result: inout V) where V : Accelerate::AccelerateMutableBuffer, V.Element == Swift::Double {
      let n = result.count
      var a = start
      var b = end
      _wr(&result) { r in vDSP_vgenD(&a, &b, r, 1, vDSP_Length(n)) }
  }
  public static func ramp<U>(withInitialValue initialValue: inout Swift::Float, multiplyingBy vector: U, increment: Swift::Float) -> [Swift::Float] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Float>) in vDSP.formRamp(withInitialValue: &initialValue, multiplyingBy: vector, increment: increment, result: &result) }
  }
  public static func formRamp<U, V>(withInitialValue initialValue: inout Swift::Float, multiplyingBy vector: U, increment: Swift::Float, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = result.count
      precondition(vector.count >= n)
      var step = increment
      _wr(&result) { r in _rd(vector) { v in vDSP_vrampmul(v, 1, &initialValue, &step, r, 1, vDSP_Length(n)) } }
  }
  public static func ramp<U>(withInitialValue initialValue: inout Swift::Double, multiplyingBy vector: U, increment: Swift::Double) -> [Swift::Double] where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      return _make(vector.count) { (result: inout UnsafeMutableBufferPointer<Double>) in vDSP.formRamp(withInitialValue: &initialValue, multiplyingBy: vector, increment: increment, result: &result) }
  }
  public static func formRamp<U, V>(withInitialValue initialValue: inout Swift::Double, multiplyingBy vector: U, increment: Swift::Double, result: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = result.count
      precondition(vector.count >= n)
      var step = increment
      _wr(&result) { r in _rd(vector) { v in vDSP_vrampmulD(v, 1, &initialValue, &step, r, 1, vDSP_Length(n)) } }
  }
  public static func stereoRamp<U>(withInitialValue initialValue: inout Swift::Float, multiplyingBy multiplierOne: U, _ multiplierTwo: U, increment: Swift::Float) -> (firstOutput: [Swift::Float], secondOutput: [Swift::Float]) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Float {
      let n = multiplierOne.count
      var first = [Float](repeating: 0, count: n)
      var second = [Float](repeating: 0, count: n)
      vDSP.formStereoRamp(withInitialValue: &initialValue, multiplyingBy: multiplierOne, multiplierTwo, increment: increment, results: &first, &second)
      return (first, second)
  }
  public static func formStereoRamp<U, V>(withInitialValue initialValue: inout Swift::Float, multiplyingBy multiplierOne: U, _ multiplierTwo: U, increment: Swift::Float, results resultOne: inout V, _ resultTwo: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float {
      let n = resultOne.count
      precondition(resultTwo.count == n && multiplierOne.count >= n && multiplierTwo.count >= n)
      var step = increment
      _wr(&resultOne) { o0 in _wr(&resultTwo) { o1 in _rd(multiplierOne) { i0 in _rd(multiplierTwo) { i1 in vDSP_vrampmul2(i0, i1, 1, &initialValue, &step, o0, o1, 1, vDSP_Length(n)) } } } }
  }
  public static func stereoRamp<U>(withInitialValue initialValue: inout Swift::Double, multiplyingBy multiplierOne: U, _ multiplierTwo: U, increment: Swift::Double) -> (firstOutput: [Swift::Double], secondOutput: [Swift::Double]) where U : Accelerate::AccelerateBuffer, U.Element == Swift::Double {
      let n = multiplierOne.count
      var first = [Double](repeating: 0, count: n)
      var second = [Double](repeating: 0, count: n)
      vDSP.formStereoRamp(withInitialValue: &initialValue, multiplyingBy: multiplierOne, multiplierTwo, increment: increment, results: &first, &second)
      return (first, second)
  }
  public static func formStereoRamp<U, V>(withInitialValue initialValue: inout Swift::Double, multiplyingBy multiplierOne: U, _ multiplierTwo: U, increment: Swift::Double, results resultOne: inout V, _ resultTwo: inout V) where U : Accelerate::AccelerateBuffer, V : Accelerate::AccelerateMutableBuffer, U.Element == Swift::Double, V.Element == Swift::Double {
      let n = resultOne.count
      precondition(resultTwo.count == n && multiplierOne.count >= n && multiplierTwo.count >= n)
      var step = increment
      _wr(&resultOne) { o0 in _wr(&resultTwo) { o1 in _rd(multiplierOne) { i0 in _rd(multiplierTwo) { i1 in vDSP_vrampmul2D(i0, i1, 1, &initialValue, &step, o0, o1, 1, vDSP_Length(n)) } } } }
  }
}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::RoundingMode : Swift::Equatable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::RoundingMode : Swift::Hashable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::DFTTransformType : Swift::Equatable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::DFTTransformType : Swift::Hashable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::IntegrationRule : Swift::Equatable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::IntegrationRule : Swift::Hashable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::Quadrature.Accelerate::Error : Swift::Equatable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::Quadrature.Accelerate::Error : Swift::Hashable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::Radix : Swift::Equatable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::Radix : Swift::Hashable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::FourierTransformDirection : Swift::Equatable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::FourierTransformDirection : Swift::Hashable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::SortOrder : Swift::Equatable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::SortOrder : Swift::Hashable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::SortOrder : Swift::RawRepresentable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::DCTTransformType : Swift::Equatable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::DCTTransformType : Swift::Hashable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::WindowSequence : Swift::Equatable {}
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Accelerate::vDSP.Accelerate::WindowSequence : Swift::Hashable {}
extension Swift::Array where Element == Swift::Float {
  @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
  public init(fromSplitComplex splitComplex: Accelerate::DSPSplitComplex, scale: Swift::Float, count: Swift::Int) {
      var split = splitComplex
      self = [Float](repeating: 0, count: count)
      let pairs = count / 2
      var scale = scale
      withUnsafeMutableBufferPointer { buffer in
          guard let base = buffer.baseAddress else { return }
          base.withMemoryRebound(to: DSPComplex.self, capacity: pairs) { vDSP_ztoc(&split, 1, $0, 2, Accelerate::vDSP_Length(pairs)) }
          vDSP_vsmul(base, 1, &scale, base, 1, Accelerate::vDSP_Length(count))
      }
  }
}
extension Swift::Array where Element == Swift::Double {
  @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
  public init(fromSplitComplex splitComplex: Accelerate::DSPDoubleSplitComplex, scale: Swift::Double, count: Swift::Int) {
      var split = splitComplex
      self = [Double](repeating: 0, count: count)
      let pairs = count / 2
      var scale = scale
      withUnsafeMutableBufferPointer { buffer in
          guard let base = buffer.baseAddress else { return }
          base.withMemoryRebound(to: DSPDoubleComplex.self, capacity: pairs) { vDSP_ztocD(&split, 1, $0, 2, Accelerate::vDSP_Length(pairs)) }
          vDSP_vsmulD(base, 1, &scale, base, 1, Accelerate::vDSP_Length(count))
      }
  }
}
