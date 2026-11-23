import Swift
import Darwin
import simd

// BNNS's data types, activation and pooling constants, the descriptors and
// layer parameters of the original (macOS 10.12) API, the BNNSScalar types,
// BNNS.Shape and BNNS.DataLayout, and the BNNSNDArrayDescriptor helpers.
//
// The C constants are written as their values: this module declares Swift
// globals of the same names (BNNSDataTypeFloat16 and so on), which hide
// the C ones.

// MARK: - Constants

enum _BNNSConstant {
    static let float16 = BNNSDataType(rawValue: 0x10010)
    static let float32 = BNNSDataType(rawValue: 0x10020)
    static let bfloat16 = BNNSDataType(rawValue: 0x18010)
    static let int8 = BNNSDataType(rawValue: 0x20008)
    static let int16 = BNNSDataType(rawValue: 0x20010)
    static let int32 = BNNSDataType(rawValue: 0x20020)
    static let int64 = BNNSDataType(rawValue: 0x20040)
    static let uint8 = BNNSDataType(rawValue: 0x40008)
    static let uint16 = BNNSDataType(rawValue: 0x40010)
    static let uint32 = BNNSDataType(rawValue: 0x40020)
    static let uint64 = BNNSDataType(rawValue: 0x40040)
    static let indexed8 = BNNSDataType(rawValue: 0x80008)
    static let boolean = BNNSDataType(rawValue: 0x100008)

    static let poolingMax = BNNSPoolingFunction(rawValue: 0)
    static let poolingAverage = BNNSPoolingFunction(rawValue: 1)

    static let clientPointer = BNNSFlags(rawValue: 1)
}

/// The size in bytes of one element of a data type (at least one byte).
func _bnnsElementSize(_ type: BNNSDataType) -> Int {
    Swift.max(1, Int(type.rawValue & 0xFFFF) / 8)
}

/// Whether a data type is a floating-point one.
func _bnnsIsFloat(_ type: BNNSDataType) -> Bool {
    type.rawValue & 0x10000 != 0
}

// MARK: - The original API's constants

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
extension Accelerate::BNNSDataType {
    public static var float16: Accelerate::BNNSDataType { _BNNSConstant.float16 }
    public static var float: Accelerate::BNNSDataType { _BNNSConstant.float32 }
    public static var int8: Accelerate::BNNSDataType { _BNNSConstant.int8 }
    public static var int16: Accelerate::BNNSDataType { _BNNSConstant.int16 }
    public static var int32: Accelerate::BNNSDataType { _BNNSConstant.int32 }
    public static var indexed8: Accelerate::BNNSDataType { _BNNSConstant.indexed8 }
}

@available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)
extension Accelerate::BNNSDataType {
    public static var uint8: Accelerate::BNNSDataType { _BNNSConstant.uint8 }
    public static var uint16: Accelerate::BNNSDataType { _BNNSConstant.uint16 }
    public static var uint32: Accelerate::BNNSDataType { _BNNSConstant.uint32 }
}

// The deprecated globals are variables, as the overlay declared them; each
// starts out as its constant.

private var _dataTypeFloat16 = _BNNSConstant.float16
private var _dataTypeFloat32 = _BNNSConstant.float32
private var _dataTypeInt8 = _BNNSConstant.int8
private var _dataTypeInt16 = _BNNSConstant.int16
private var _dataTypeInt32 = _BNNSConstant.int32
private var _dataTypeIndexed8 = _BNNSConstant.indexed8

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSDataType.float16")
public var BNNSDataTypeFloat16: Accelerate::BNNSDataType {
    get { _dataTypeFloat16 }
    set { _dataTypeFloat16 = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSDataType.float")
public var BNNSDataTypeFloat32: Accelerate::BNNSDataType {
    get { _dataTypeFloat32 }
    set { _dataTypeFloat32 = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSDataType.int8")
public var BNNSDataTypeInt8: Accelerate::BNNSDataType {
    get { _dataTypeInt8 }
    set { _dataTypeInt8 = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSDataType.int16")
public var BNNSDataTypeInt16: Accelerate::BNNSDataType {
    get { _dataTypeInt16 }
    set { _dataTypeInt16 = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSDataType.int32")
public var BNNSDataTypeInt32: Accelerate::BNNSDataType {
    get { _dataTypeInt32 }
    set { _dataTypeInt32 = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSDataType.indexed8")
public var BNNSDataTypeIndexed8: Accelerate::BNNSDataType {
    get { _dataTypeIndexed8 }
    set { _dataTypeIndexed8 = newValue }
}

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNSPoolingFunction {
    public static var max: Accelerate::BNNSPoolingFunction { _BNNSConstant.poolingMax }
    @available(macOS, introduced: 10.15, deprecated: 12.0, message: "Use 'BNNSPoolingFunctionAverageCountIncludePadding' instead.")
    @available(iOS, introduced: 13.0, deprecated: 15.0, message: "Use 'BNNSPoolingFunctionAverageCountIncludePadding' instead.")
    @available(watchOS, introduced: 6.0, deprecated: 8.0, message: "Use 'BNNSPoolingFunctionAverageCountIncludePadding' instead.")
    @available(tvOS, introduced: 13.0, deprecated: 15.0, message: "Use 'BNNSPoolingFunctionAverageCountIncludePadding' instead.")
    @available(*, deprecated, message: "Use 'BNNSPoolingFunctionAverageCountIncludePadding' instead.")
    public static var average: Accelerate::BNNSPoolingFunction { _BNNSConstant.poolingAverage }
}

private var _poolingMax = _BNNSConstant.poolingMax
private var _poolingAverage = _BNNSConstant.poolingAverage

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSPoolingFunction.max")
public var BNNSPoolingFunctionMax: Accelerate::BNNSPoolingFunction {
    get { _poolingMax }
    set { _poolingMax = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSPoolingFunction.average")
public var BNNSPoolingFunctionAverage: Accelerate::BNNSPoolingFunction {
    get { _poolingAverage }
    set { _poolingAverage = newValue }
}

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNSActivationFunction {
    public static var identity: Accelerate::BNNSActivationFunction { .init(rawValue: 0) }
    public static var rectifiedLinear: Accelerate::BNNSActivationFunction { .init(rawValue: 1) }
    public static var leakyRectifiedLinear: Accelerate::BNNSActivationFunction { .init(rawValue: 2) }
    public static var sigmoid: Accelerate::BNNSActivationFunction { .init(rawValue: 3) }
    public static var tanh: Accelerate::BNNSActivationFunction { .init(rawValue: 4) }
    public static var scaledTanh: Accelerate::BNNSActivationFunction { .init(rawValue: 5) }
    public static var abs: Accelerate::BNNSActivationFunction { .init(rawValue: 6) }
}

@available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNSActivationFunction {
    public static var linear: Accelerate::BNNSActivationFunction { .init(rawValue: 7) }
    public static var clamp: Accelerate::BNNSActivationFunction { .init(rawValue: 8) }
    public static var integerLinearSaturate: Accelerate::BNNSActivationFunction { .init(rawValue: 9) }
    public static var integerLinearSaturatePerChannel: Accelerate::BNNSActivationFunction { .init(rawValue: 10) }
    public static var softmax: Accelerate::BNNSActivationFunction { .init(rawValue: 11) }
}

private var _activationIdentity = BNNSActivationFunction(rawValue: 0)
private var _activationRectifiedLinear = BNNSActivationFunction(rawValue: 1)
private var _activationLeakyRectifiedLinear = BNNSActivationFunction(rawValue: 2)
private var _activationSigmoid = BNNSActivationFunction(rawValue: 3)
private var _activationTanh = BNNSActivationFunction(rawValue: 4)
private var _activationScaledTanh = BNNSActivationFunction(rawValue: 5)
private var _activationAbs = BNNSActivationFunction(rawValue: 6)

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSActivationFunction.identity")
public var BNNSActivationFunctionIdentity: Accelerate::BNNSActivationFunction {
    get { _activationIdentity }
    set { _activationIdentity = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSActivationFunction.rectifiedLinear")
public var BNNSActivationFunctionRectifiedLinear: Accelerate::BNNSActivationFunction {
    get { _activationRectifiedLinear }
    set { _activationRectifiedLinear = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSActivationFunction.leakyRectifiedLinear")
public var BNNSActivationFunctionLeakyRectifiedLinear: Accelerate::BNNSActivationFunction {
    get { _activationLeakyRectifiedLinear }
    set { _activationLeakyRectifiedLinear = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSActivationFunction.sigmoid")
public var BNNSActivationFunctionSigmoid: Accelerate::BNNSActivationFunction {
    get { _activationSigmoid }
    set { _activationSigmoid = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSActivationFunction.tanh")
public var BNNSActivationFunctionTanh: Accelerate::BNNSActivationFunction {
    get { _activationTanh }
    set { _activationTanh = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSActivationFunction.scaledTanh")
public var BNNSActivationFunctionScaledTanh: Accelerate::BNNSActivationFunction {
    get { _activationScaledTanh }
    set { _activationScaledTanh = newValue }
}
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSActivationFunction.abs")
public var BNNSActivationFunctionAbs: Accelerate::BNNSActivationFunction {
    get { _activationAbs }
    set { _activationAbs = newValue }
}

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
extension Accelerate::BNNSFlags {
    public static var useClientPointer: Accelerate::BNNSFlags { _BNNSConstant.clientPointer }
}

private var _flagsUseClientPointer = _BNNSConstant.clientPointer

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, renamed: "BNNSFlags.useClientPointer")
public var BNNSFlagsUseClientPtr: Accelerate::BNNSFlags {
    get { _flagsUseClientPointer }
    set { _flagsUseClientPointer = newValue }
}

extension Accelerate::BNNSFlags: Swift::OptionSet {
    public typealias ArrayLiteralElement = Accelerate::BNNSFlags
    public typealias Element = Accelerate::BNNSFlags
}

// MARK: - The original API's descriptors and parameters

@available(macOS, introduced: 10.12, deprecated: 12.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(iOS, introduced: 10.0, deprecated: 15.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(watchOS, introduced: 3.0, deprecated: 8.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(tvOS, introduced: 10.0, deprecated: 15.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(*, deprecated, message: "BNNS switched to new Layer Parameters data structures.")
extension Accelerate::BNNSImageStackDescriptor {
    public init(width: Swift::Int, height: Swift::Int, channels: Swift::Int, row_stride: Swift::Int, image_stride: Swift::Int, data_type: Accelerate::BNNSDataType) {
        self.init(width: width, height: height, channels: channels, row_stride: row_stride, image_stride: image_stride,
                  data_type: data_type, data_scale: 1, data_bias: 0)
    }
}

@available(macOS, introduced: 10.12, deprecated: 12.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(iOS, introduced: 10.0, deprecated: 15.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(watchOS, introduced: 3.0, deprecated: 8.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(tvOS, introduced: 10.0, deprecated: 15.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(*, deprecated, message: "BNNS switched to new Layer Parameters data structures.")
extension Accelerate::BNNSVectorDescriptor {
    public init(size: Swift::Int, data_type: Accelerate::BNNSDataType) {
        self.init(size: size, data_type: data_type, data_scale: 1, data_bias: 0)
    }
}

@available(macOS, introduced: 10.12, deprecated: 12.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(iOS, introduced: 10.0, deprecated: 15.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(watchOS, introduced: 3.0, deprecated: 8.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(tvOS, introduced: 10.0, deprecated: 15.0, message: "BNNS switched to new Layer Parameters data structures.")
@available(*, deprecated, message: "BNNS switched to new Layer Parameters data structures.")
extension Accelerate::BNNSLayerData {
    public init(data: Swift::UnsafeRawPointer?, data_type: Accelerate::BNNSDataType, data_scale: Swift::Float = 1, data_bias: Swift::Float = 0) {
        self.init(data: data, data_type: data_type, data_scale: data_scale, data_bias: data_bias, data_table: nil)
    }

    /// No data: a layer's bias or weights left out.
    public static var zero: Accelerate::BNNSLayerData {
        BNNSLayerData(data: nil, data_type: _BNNSConstant.float32, data_scale: 0, data_bias: 0, data_table: nil)
    }

    /// 8-bit indices into a table of 256 floats.
    public static func indexed8(data: Swift::UnsafePointer<Swift::Int8>?, data_table: Swift::UnsafePointer<Swift::Float>) -> Accelerate::BNNSLayerData {
        BNNSLayerData(data: UnsafeRawPointer(data), data_type: _BNNSConstant.indexed8, data_scale: 1, data_bias: 0, data_table: data_table)
    }
}

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNSActivation {
    public init(function: Accelerate::BNNSActivationFunction, alpha: Swift::Float = .nan, beta: Swift::Float = .nan) {
        self.init(function: function, alpha: alpha, beta: beta, iscale: 1, ioffset: 0, ishift: 0,
                  iscale_per_channel: nil, ioffset_per_channel: nil, ishift_per_channel: nil)
    }

    public static var identity: Accelerate::BNNSActivation {
        BNNSActivation(function: .init(rawValue: 0), alpha: .nan, beta: .nan)
    }
}

@available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNSActivation {
    public static func integerLinearSaturate(scale: Swift::Int32 = 1, offset: Swift::Int32 = 0, shift: Swift::Int32 = 0) -> Accelerate::BNNSActivation {
        BNNSActivation(function: .init(rawValue: 9), alpha: .nan, beta: .nan, iscale: scale, ioffset: offset, ishift: shift,
                       iscale_per_channel: nil, ioffset_per_channel: nil, ishift_per_channel: nil)
    }

    public static func integerLinearSaturatePerChannel(scale: Swift::UnsafePointer<Swift::Int32>, offset: Swift::UnsafePointer<Swift::Int32>, shift: Swift::UnsafePointer<Swift::Int32>) -> Accelerate::BNNSActivation {
        BNNSActivation(function: .init(rawValue: 10), alpha: .nan, beta: .nan, iscale: 1, ioffset: 0, ishift: 0,
                       iscale_per_channel: scale, ioffset_per_channel: offset, ishift_per_channel: shift)
    }
}

@available(macOS, introduced: 10.12, deprecated: 12.0, message: "Use 'BNNSLayerParametersConvolution' instead.")
@available(iOS, introduced: 10.0, deprecated: 15.0, message: "Use 'BNNSLayerParametersConvolution' instead")
@available(watchOS, introduced: 3.0, deprecated: 8.0, message: "Use 'BNNSLayerParametersConvolution' instead")
@available(tvOS, introduced: 10.0, deprecated: 15.0, message: "Use 'BNNSLayerParametersConvolution' instead")
@available(*, deprecated, message: "Use 'BNNSLayerParametersConvolution' instead")
extension Accelerate::BNNSConvolutionLayerParameters {
    public init(x_stride: Swift::Int, y_stride: Swift::Int, x_padding: Swift::Int, y_padding: Swift::Int, k_width: Swift::Int, k_height: Swift::Int, in_channels: Swift::Int, out_channels: Swift::Int, weights: Accelerate::BNNSLayerData) {
        self.init(x_stride: x_stride, y_stride: y_stride, x_padding: x_padding, y_padding: y_padding, k_width: k_width, k_height: k_height,
                  in_channels: in_channels, out_channels: out_channels, weights: weights, bias: .zero, activation: .identity)
    }
}

@available(macOS, introduced: 10.12, deprecated: 12.0, message: "Use 'BNNSLayerParametersPooling' instead.")
@available(iOS, introduced: 10.0, deprecated: 15.0, message: "Use 'BNNSLayerParametersPooling' instead")
@available(watchOS, introduced: 3.0, deprecated: 8.0, message: "Use 'BNNSLayerParametersPooling' instead")
@available(tvOS, introduced: 10.0, deprecated: 15.0, message: "Use 'BNNSLayerParametersPooling' instead")
@available(*, deprecated, message: "Use 'BNNSLayerParametersPooling' instead")
extension Accelerate::BNNSPoolingLayerParameters {
    public init(x_stride: Swift::Int, y_stride: Swift::Int, x_padding: Swift::Int, y_padding: Swift::Int, k_width: Swift::Int, k_height: Swift::Int, in_channels: Swift::Int, out_channels: Swift::Int, pooling_function: Accelerate::BNNSPoolingFunction) {
        self.init(x_stride: x_stride, y_stride: y_stride, x_padding: x_padding, y_padding: y_padding, k_width: k_width, k_height: k_height,
                  in_channels: in_channels, out_channels: out_channels, pooling_function: pooling_function, bias: .zero, activation: .identity)
    }
}

@available(macOS, introduced: 10.12, deprecated: 12.0, message: "Use 'BNNSLayerParametersFullyConnected' instead.")
@available(iOS, introduced: 10.0, deprecated: 15.0, message: "Use 'BNNSLayerParametersFullyConnected' instead")
@available(watchOS, introduced: 3.0, deprecated: 8.0, message: "Use 'BNNSLayerParametersFullyConnected' instead")
@available(tvOS, introduced: 10.0, deprecated: 15.0, message: "Use 'BNNSLayerParametersFullyConnected' instead")
@available(*, deprecated, message: "Use 'BNNSLayerParametersFullyConnected' instead")
extension Accelerate::BNNSFullyConnectedLayerParameters {
    public init(in_size: Swift::Int, out_size: Swift::Int, weights: Accelerate::BNNSLayerData) {
        self.init(in_size: in_size, out_size: out_size, weights: weights, bias: .zero, activation: .identity)
    }
}

extension Accelerate::BNNSFilterParameters {
    public init(options: Accelerate::BNNSFlags, threadCount: Swift::Int, allocator: Accelerate::BNNSAlloc?, deallocator: Accelerate::BNNSFree?) {
        self.init(flags: options.rawValue, n_threads: threadCount, alloc_memory: allocator, free_memory: deallocator)
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public var options: Accelerate::BNNSFlags {
        get { BNNSFlags(rawValue: flags) }
        set { flags = newValue.rawValue }
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public var threadCount: Swift::Int {
        get { n_threads }
        set { n_threads = newValue }
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public var allocator: Accelerate::BNNSAlloc? {
        get { alloc_memory }
        set { alloc_memory = newValue }
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public var deallocator: Accelerate::BNNSFree? {
        get { free_memory }
        set { free_memory = newValue }
    }
}

// MARK: - Scalars

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public protocol BNNSScalar {
    static var bnnsDataType: Accelerate::BNNSDataType { get }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Swift::Float: Accelerate::BNNSScalar {
    public static var bnnsDataType: Accelerate::BNNSDataType { _BNNSConstant.float32 }
}

#if arch(arm64)
@available(iOS 14, tvOS 14, watchOS 7, macOS 26.0, macCatalyst 26.0, *)
extension Swift::Float16: Accelerate::BNNSScalar {
    public static var bnnsDataType: Accelerate::BNNSDataType { _BNNSConstant.float16 }
}
#endif

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Swift::Int8: Accelerate::BNNSScalar {
    public static var bnnsDataType: Accelerate::BNNSDataType { _BNNSConstant.int8 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Swift::Int16: Accelerate::BNNSScalar {
    public static var bnnsDataType: Accelerate::BNNSDataType { _BNNSConstant.int16 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Swift::Int32: Accelerate::BNNSScalar {
    public static var bnnsDataType: Accelerate::BNNSDataType { _BNNSConstant.int32 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Swift::UInt8: Accelerate::BNNSScalar {
    public static var bnnsDataType: Accelerate::BNNSDataType { _BNNSConstant.uint8 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Swift::UInt16: Accelerate::BNNSScalar {
    public static var bnnsDataType: Accelerate::BNNSDataType { _BNNSConstant.uint16 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Swift::UInt32: Accelerate::BNNSScalar {
    public static var bnnsDataType: Accelerate::BNNSDataType { _BNNSConstant.uint32 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Swift::Bool: Accelerate::BNNSScalar {
    public static var bnnsDataType: Accelerate::BNNSDataType { _BNNSConstant.boolean }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Swift::Int64: Accelerate::BNNSScalar {
    public static var bnnsDataType: Accelerate::BNNSDataType { _BNNSConstant.int64 }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Swift::UInt64: Accelerate::BNNSScalar {
    public static var bnnsDataType: Accelerate::BNNSDataType { _BNNSConstant.uint64 }
}

// MARK: - Layouts and shapes

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Accelerate::BNNS {
    public enum DataLayout: Swift::CaseIterable, Swift::Hashable {
        case vector
        case matrixRowMajor
        case matrixColumnMajor
        case matrixFirstMajor
        case matrixLastMajor
        case imageCHW
        case tensor3DFirstMajor
        case tensor3DLastMajor
        case convolutionWeightsOIHW
        case tensor4DFirstMajor
        case tensor4DLastMajor
        case tensor5DFirstMajor
        case tensor5DLastMajor
        case tensor6DFirstMajor
        case tensor6DLastMajor
        case tensor7DFirstMajor
        case tensor7DLastMajor
        case tensor8DFirstMajor
        case tensor8DLastMajor
        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
        case tensor3DSNE
        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
        case tensor3DNSE

        public static var allCases: [Accelerate::BNNS.Accelerate::DataLayout] {
            [.vector, .matrixRowMajor, .matrixColumnMajor, .matrixFirstMajor, .matrixLastMajor, .imageCHW,
             .tensor3DFirstMajor, .tensor3DLastMajor, .convolutionWeightsOIHW, .tensor4DFirstMajor, .tensor4DLastMajor,
             .tensor5DFirstMajor, .tensor5DLastMajor, .tensor6DFirstMajor, .tensor6DLastMajor,
             .tensor7DFirstMajor, .tensor7DLastMajor, .tensor8DFirstMajor, .tensor8DLastMajor,
             .tensor3DSNE, .tensor3DNSE]
        }

        public var rank: Swift::Int {
            switch self {
            case .vector: return 1
            case .matrixRowMajor, .matrixColumnMajor, .matrixFirstMajor, .matrixLastMajor: return 2
            case .imageCHW, .tensor3DFirstMajor, .tensor3DLastMajor, .tensor3DSNE, .tensor3DNSE: return 3
            case .convolutionWeightsOIHW, .tensor4DFirstMajor, .tensor4DLastMajor: return 4
            case .tensor5DFirstMajor, .tensor5DLastMajor: return 5
            case .tensor6DFirstMajor, .tensor6DLastMajor: return 6
            case .tensor7DFirstMajor, .tensor7DLastMajor: return 7
            case .tensor8DFirstMajor, .tensor8DLastMajor: return 8
            }
        }

        @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
        public typealias AllCases = [Accelerate::BNNS.Accelerate::DataLayout]

        /// The C layout.
        var bnnsLayout: BNNSDataLayout {
            switch self {
            case .vector: return BNNSDataLayout(rawValue: 0x10000)
            case .matrixRowMajor: return BNNSDataLayout(rawValue: 0x20000)
            case .matrixColumnMajor: return BNNSDataLayout(rawValue: 0x20001)
            case .matrixFirstMajor: return BNNSDataLayout(rawValue: 0x28001)
            case .matrixLastMajor: return BNNSDataLayout(rawValue: 0x28000)
            case .imageCHW: return BNNSDataLayout(rawValue: 0x30000)
            case .tensor3DSNE: return BNNSDataLayout(rawValue: 0x30001)
            case .tensor3DNSE: return BNNSDataLayout(rawValue: 0x30002)
            case .tensor3DFirstMajor: return BNNSDataLayout(rawValue: 0x38001)
            case .tensor3DLastMajor: return BNNSDataLayout(rawValue: 0x38000)
            case .convolutionWeightsOIHW: return BNNSDataLayout(rawValue: 0x40000)
            case .tensor4DFirstMajor: return BNNSDataLayout(rawValue: 0x48001)
            case .tensor4DLastMajor: return BNNSDataLayout(rawValue: 0x48000)
            case .tensor5DFirstMajor: return BNNSDataLayout(rawValue: 0x58001)
            case .tensor5DLastMajor: return BNNSDataLayout(rawValue: 0x58000)
            case .tensor6DFirstMajor: return BNNSDataLayout(rawValue: 0x68001)
            case .tensor6DLastMajor: return BNNSDataLayout(rawValue: 0x68000)
            case .tensor7DFirstMajor: return BNNSDataLayout(rawValue: 0x78001)
            case .tensor7DLastMajor: return BNNSDataLayout(rawValue: 0x78000)
            case .tensor8DFirstMajor: return BNNSDataLayout(rawValue: 0x88001)
            case .tensor8DLastMajor: return BNNSDataLayout(rawValue: 0x88000)
            }
        }

        init?(_ layout: BNNSDataLayout) {
            guard let match = DataLayout.allCases.first(where: { $0.bnnsLayout.rawValue == layout.rawValue }) else {
                switch layout.rawValue {
                case 0x18000, 0x18001: self = .vector
                case 0x40001, 0x40002, 0x40010: self = .convolutionWeightsOIHW
                default: return nil
                }
                return
            }
            self = match
        }

        /// The layout a shape of this rank gets when none is given.
        static func `default`(rank: Int) -> DataLayout {
            switch rank {
            case 0, 1: return .vector
            case 2: return .matrixRowMajor
            case 3: return .imageCHW
            case 4: return .tensor4DFirstMajor
            case 5: return .tensor5DFirstMajor
            case 6: return .tensor6DFirstMajor
            case 7: return .tensor7DFirstMajor
            default: return .tensor8DFirstMajor
            }
        }
    }
}

typealias _Tuple8 = (Int, Int, Int, Int, Int, Int, Int, Int)

func _tuple8(_ values: [Int]) -> _Tuple8 {
    var v = values + Array(repeating: 0, count: Swift.max(0, 8 - values.count))
    if v.count > 8 { v = Array(v.prefix(8)) }
    return (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7])
}

func _array8(_ t: _Tuple8) -> [Int] {
    [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7]
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Accelerate::BNNS {
    public enum Shape {
        public init(_ size: [Swift::Int], dataLayout: Accelerate::BNNS.Accelerate::DataLayout? = nil, stride: [Swift::Int]? = nil) {
            let layout = dataLayout ?? .default(rank: size.count)
            precondition(size.count == layout.rank, "the size must have as many dimensions as the layout")
            let stride = stride ?? Array(repeating: 0, count: size.count)
            self.init(layout: layout, size: size, stride: stride)
        }

        case vector(_: Swift::Int, stride: Swift::Int = 0)
        case matrixColumnMajor(_: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int) = (0, 0))
        case matrixRowMajor(_: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int) = (0, 0))
        case matrixFirstMajor(_: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int) = (0, 0))
        case matrixLastMajor(_: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int) = (0, 0))
        case imageCHW(_: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0))
        case tensor3DFirstMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0))
        case tensor3DLastMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0))
        case tensor3DSNE(_: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0))
        case tensor3DNSE(_: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0))
        case convolutionWeightsOIHW(_: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0, 0))
        case tensor4DFirstMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0, 0))
        case tensor4DLastMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0, 0))
        case tensor5DFirstMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0, 0, 0))
        case tensor5DLastMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0, 0, 0))
        case tensor6DFirstMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0, 0, 0, 0))
        case tensor6DLastMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0, 0, 0, 0))
        case tensor7DFirstMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0, 0, 0, 0, 0))
        case tensor7DLastMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0, 0, 0, 0, 0))
        case tensor8DFirstMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0, 0, 0, 0, 0, 0))
        case tensor8DLastMajor(_: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, _: Swift::Int, stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int) = (0, 0, 0, 0, 0, 0, 0, 0))

        /// A shape of a layout from its sizes and strides.
        init(layout: DataLayout, size s: [Int], stride t: [Int]) {
            func z(_ a: [Int], _ n: Int) -> [Int] { a + Array(repeating: 0, count: Swift.max(0, n - a.count)) }
            let s = z(s, 8), t = z(t, 8)
            switch layout {
            case .vector: self = .vector(s[0], stride: t[0])
            case .matrixColumnMajor: self = .matrixColumnMajor(s[0], s[1], stride: (t[0], t[1]))
            case .matrixRowMajor: self = .matrixRowMajor(s[0], s[1], stride: (t[0], t[1]))
            case .matrixFirstMajor: self = .matrixFirstMajor(s[0], s[1], stride: (t[0], t[1]))
            case .matrixLastMajor: self = .matrixLastMajor(s[0], s[1], stride: (t[0], t[1]))
            case .imageCHW: self = .imageCHW(s[0], s[1], s[2], stride: (t[0], t[1], t[2]))
            case .tensor3DFirstMajor: self = .tensor3DFirstMajor(s[0], s[1], s[2], stride: (t[0], t[1], t[2]))
            case .tensor3DLastMajor: self = .tensor3DLastMajor(s[0], s[1], s[2], stride: (t[0], t[1], t[2]))
            case .tensor3DSNE: self = .tensor3DSNE(s[0], s[1], s[2], stride: (t[0], t[1], t[2]))
            case .tensor3DNSE: self = .tensor3DNSE(s[0], s[1], s[2], stride: (t[0], t[1], t[2]))
            case .convolutionWeightsOIHW: self = .convolutionWeightsOIHW(s[0], s[1], s[2], s[3], stride: (t[0], t[1], t[2], t[3]))
            case .tensor4DFirstMajor: self = .tensor4DFirstMajor(s[0], s[1], s[2], s[3], stride: (t[0], t[1], t[2], t[3]))
            case .tensor4DLastMajor: self = .tensor4DLastMajor(s[0], s[1], s[2], s[3], stride: (t[0], t[1], t[2], t[3]))
            case .tensor5DFirstMajor: self = .tensor5DFirstMajor(s[0], s[1], s[2], s[3], s[4], stride: (t[0], t[1], t[2], t[3], t[4]))
            case .tensor5DLastMajor: self = .tensor5DLastMajor(s[0], s[1], s[2], s[3], s[4], stride: (t[0], t[1], t[2], t[3], t[4]))
            case .tensor6DFirstMajor: self = .tensor6DFirstMajor(s[0], s[1], s[2], s[3], s[4], s[5], stride: (t[0], t[1], t[2], t[3], t[4], t[5]))
            case .tensor6DLastMajor: self = .tensor6DLastMajor(s[0], s[1], s[2], s[3], s[4], s[5], stride: (t[0], t[1], t[2], t[3], t[4], t[5]))
            case .tensor7DFirstMajor: self = .tensor7DFirstMajor(s[0], s[1], s[2], s[3], s[4], s[5], s[6], stride: (t[0], t[1], t[2], t[3], t[4], t[5], t[6]))
            case .tensor7DLastMajor: self = .tensor7DLastMajor(s[0], s[1], s[2], s[3], s[4], s[5], s[6], stride: (t[0], t[1], t[2], t[3], t[4], t[5], t[6]))
            case .tensor8DFirstMajor: self = .tensor8DFirstMajor(s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7], stride: (t[0], t[1], t[2], t[3], t[4], t[5], t[6], t[7]))
            case .tensor8DLastMajor: self = .tensor8DLastMajor(s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7], stride: (t[0], t[1], t[2], t[3], t[4], t[5], t[6], t[7]))
            }
        }

        /// The layout, sizes and strides (without padding).
        var parts: (layout: DataLayout, size: [Int], stride: [Int]) {
            switch self {
            case let .vector(a, stride: t): return (.vector, [a], [t])
            case let .matrixColumnMajor(a, b, stride: t): return (.matrixColumnMajor, [a, b], [t.0, t.1])
            case let .matrixRowMajor(a, b, stride: t): return (.matrixRowMajor, [a, b], [t.0, t.1])
            case let .matrixFirstMajor(a, b, stride: t): return (.matrixFirstMajor, [a, b], [t.0, t.1])
            case let .matrixLastMajor(a, b, stride: t): return (.matrixLastMajor, [a, b], [t.0, t.1])
            case let .imageCHW(a, b, c, stride: t): return (.imageCHW, [a, b, c], [t.0, t.1, t.2])
            case let .tensor3DFirstMajor(a, b, c, stride: t): return (.tensor3DFirstMajor, [a, b, c], [t.0, t.1, t.2])
            case let .tensor3DLastMajor(a, b, c, stride: t): return (.tensor3DLastMajor, [a, b, c], [t.0, t.1, t.2])
            case let .tensor3DSNE(a, b, c, stride: t): return (.tensor3DSNE, [a, b, c], [t.0, t.1, t.2])
            case let .tensor3DNSE(a, b, c, stride: t): return (.tensor3DNSE, [a, b, c], [t.0, t.1, t.2])
            case let .convolutionWeightsOIHW(a, b, c, d, stride: t): return (.convolutionWeightsOIHW, [a, b, c, d], [t.0, t.1, t.2, t.3])
            case let .tensor4DFirstMajor(a, b, c, d, stride: t): return (.tensor4DFirstMajor, [a, b, c, d], [t.0, t.1, t.2, t.3])
            case let .tensor4DLastMajor(a, b, c, d, stride: t): return (.tensor4DLastMajor, [a, b, c, d], [t.0, t.1, t.2, t.3])
            case let .tensor5DFirstMajor(a, b, c, d, e, stride: t): return (.tensor5DFirstMajor, [a, b, c, d, e], [t.0, t.1, t.2, t.3, t.4])
            case let .tensor5DLastMajor(a, b, c, d, e, stride: t): return (.tensor5DLastMajor, [a, b, c, d, e], [t.0, t.1, t.2, t.3, t.4])
            case let .tensor6DFirstMajor(a, b, c, d, e, f, stride: t): return (.tensor6DFirstMajor, [a, b, c, d, e, f], [t.0, t.1, t.2, t.3, t.4, t.5])
            case let .tensor6DLastMajor(a, b, c, d, e, f, stride: t): return (.tensor6DLastMajor, [a, b, c, d, e, f], [t.0, t.1, t.2, t.3, t.4, t.5])
            case let .tensor7DFirstMajor(a, b, c, d, e, f, g, stride: t): return (.tensor7DFirstMajor, [a, b, c, d, e, f, g], [t.0, t.1, t.2, t.3, t.4, t.5, t.6])
            case let .tensor7DLastMajor(a, b, c, d, e, f, g, stride: t): return (.tensor7DLastMajor, [a, b, c, d, e, f, g], [t.0, t.1, t.2, t.3, t.4, t.5, t.6])
            case let .tensor8DFirstMajor(a, b, c, d, e, f, g, h, stride: t): return (.tensor8DFirstMajor, [a, b, c, d, e, f, g, h], [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7])
            case let .tensor8DLastMajor(a, b, c, d, e, f, g, h, stride: t): return (.tensor8DLastMajor, [a, b, c, d, e, f, g, h], [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7])
            }
        }

        public var rank: Swift::Int { parts.size.count }

        public var size: (Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int) {
            _tuple8(parts.size)
        }

        public var stride: (Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int, Swift::Int) {
            _tuple8(parts.stride)
        }

        /// The strides with BNNS's defaults (contiguous, first dimension
        /// fastest) in place of zeros.
        var effectiveStride: [Int] {
            let (_, size, stride) = parts
            var result = [Int]()
            var next = 1
            for i in 0..<size.count {
                let s = stride[i] == 0 ? next : stride[i]
                result.append(s)
                next = s * Swift.max(size[i], 1)
            }
            return result
        }

        /// The number of elements between the starts of two batch items.
        public var batchStride: Swift::Int {
            let size = parts.size
            let stride = effectiveStride
            var extent = 0
            for i in 0..<size.count {
                extent = Swift.max(extent, stride[i] * size[i])
            }
            return extent
        }

        /// The number of elements the shape holds.
        var elementCount: Int {
            parts.size.reduce(1, *)
        }

        public var layout: Accelerate::BNNSDataLayout { parts.layout.bnnsLayout }
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Accelerate::BNNS.Accelerate::Shape: Swift::ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = Swift::Int
    public init(arrayLiteral: Accelerate::BNNS.Accelerate::Shape.Accelerate::ArrayLiteralElement...) {
        self.init(arrayLiteral)
    }
}

// MARK: - Descriptors

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Accelerate::BNNSNDArrayDescriptor {
    public init(dataType: Accelerate::BNNSDataType, shape: Accelerate::BNNS.Accelerate::Shape) {
        self.init(flags: BNNSNDArrayFlags(rawValue: 0), layout: shape.layout, size: shape.size, stride: shape.stride,
                  data: nil, data_type: dataType, table_data: nil, table_data_type: dataType, data_scale: 1, data_bias: 0)
    }

    public init?(data: Swift::UnsafeMutableRawBufferPointer, scalarType: any Accelerate::BNNSScalar.Type, shape: Accelerate::BNNS.Accelerate::Shape) {
        self.init(data: data, scalarType: scalarType, shape: shape, batchSize: 1)
    }

    public init?<T>(data: Swift::UnsafeMutableBufferPointer<T>, shape: Accelerate::BNNS.Accelerate::Shape) where T: Accelerate::BNNSScalar {
        self.init(data: UnsafeMutableRawBufferPointer(data), scalarType: T.self, shape: shape, batchSize: 1)
    }

    public static func allocateUninitialized(scalarType: any Accelerate::BNNSScalar.Type, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int = 1) -> Accelerate::BNNSNDArrayDescriptor {
        var descriptor = BNNSNDArrayDescriptor(dataType: scalarType.bnnsDataType, shape: shape)
        let bytes = Swift.max(shape.batchStride * Swift.max(batchSize, 1) * _bnnsElementSize(descriptor.data_type), 1)
        descriptor.data = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
        return descriptor
    }

    public static func allocate<C>(initializingFrom source: C, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int = 1) -> Accelerate::BNNSNDArrayDescriptor where C: Swift::Collection, C.Element: Accelerate::BNNSScalar {
        let descriptor = allocateUninitialized(scalarType: C.Element.self, shape: shape, batchSize: batchSize)
        let capacity = shape.batchStride * Swift.max(batchSize, 1)
        let pointer = descriptor.data!.bindMemory(to: C.Element.self, capacity: capacity)
        var i = 0
        for element in source where i < capacity {
            (pointer + i).initialize(to: element)
            i += 1
        }
        return descriptor
    }

    public static func allocate<Scalar>(randomIn range: Swift::ClosedRange<Scalar>, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int = 1) -> Accelerate::BNNSNDArrayDescriptor where Scalar: Accelerate::BNNSScalar, Scalar: Swift::FixedWidthInteger {
        var generator = SystemRandomNumberGenerator()
        return allocate(randomIn: range, using: &generator, shape: shape, batchSize: batchSize)
    }

    public static func allocate<Scalar>(randomIn range: Swift::ClosedRange<Scalar>, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int = 1) -> Accelerate::BNNSNDArrayDescriptor where Scalar: Accelerate::BNNSScalar, Scalar: Swift::BinaryFloatingPoint, Scalar.RawSignificand: Swift::FixedWidthInteger {
        var generator = SystemRandomNumberGenerator()
        return allocate(randomIn: range, using: &generator, shape: shape, batchSize: batchSize)
    }

    public static func allocate<Scalar, Generator>(randomIn range: Swift::ClosedRange<Scalar>, using generator: inout Generator, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int = 1) -> Accelerate::BNNSNDArrayDescriptor where Scalar: Accelerate::BNNSScalar, Scalar: Swift::FixedWidthInteger, Generator: Swift::RandomNumberGenerator {
        let count = shape.batchStride * Swift.max(batchSize, 1)
        var values = [Scalar]()
        values.reserveCapacity(count)
        for _ in 0..<count { values.append(Scalar.random(in: range, using: &generator)) }
        return allocate(initializingFrom: values, shape: shape, batchSize: batchSize)
    }

    public static func allocate<Scalar, Generator>(randomIn range: Swift::ClosedRange<Scalar>, using generator: inout Generator, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int = 1) -> Accelerate::BNNSNDArrayDescriptor where Scalar: Accelerate::BNNSScalar, Scalar: Swift::BinaryFloatingPoint, Generator: Swift::RandomNumberGenerator, Scalar.RawSignificand: Swift::FixedWidthInteger {
        let count = shape.batchStride * Swift.max(batchSize, 1)
        var values = [Scalar]()
        values.reserveCapacity(count)
        for _ in 0..<count { values.append(Scalar.random(in: range, using: &generator)) }
        return allocate(initializingFrom: values, shape: shape, batchSize: batchSize)
    }

    public static func allocate<T>(repeating repeatedValue: T, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int = 1) -> Accelerate::BNNSNDArrayDescriptor where T: Accelerate::BNNSScalar {
        let count = shape.batchStride * Swift.max(batchSize, 1)
        return allocate(initializingFrom: repeatElement(repeatedValue, count: count), shape: shape, batchSize: batchSize)
    }

    /// The elements, if T is the descriptor's data type.
    public func makeArray<T>(of scalarType: T.Type, batchSize: Swift::Int = 1) -> [T]? {
        guard let data,
              let scalar = T.self as? any BNNSScalar.Type,
              scalar.bnnsDataType.rawValue == data_type.rawValue,
              MemoryLayout<T>.stride == _bnnsElementSize(data_type) else { return nil }
        let count = shape.batchStride * Swift.max(batchSize, 1)
        let pointer = data.bindMemory(to: T.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    public var shape: Accelerate::BNNS.Accelerate::Shape {
        let size = _array8(self.size)
        let stride = _array8(self.stride)
        if let layout = BNNS.DataLayout(self.layout) {
            return BNNS.Shape(layout: layout, size: Array(size.prefix(layout.rank)), stride: Array(stride.prefix(layout.rank)))
        }
        let rank = Swift.max(1, BNNSDataLayoutGetRank(self.layout))
        let layout = BNNS.DataLayout.default(rank: rank)
        return BNNS.Shape(layout: layout, size: Array(size.prefix(rank)), stride: Array(stride.prefix(rank)))
    }

    /// Frees the data allocate(...) and allocateUninitialized(...) made.
    public func deallocate() {
        data?.deallocate()
    }

    /// The number of elements between the starts of two batch items.
    var batchStride: Int { shape.batchStride }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::BNNSNDArrayDescriptor {
    public init?(data: Swift::UnsafeMutableRawBufferPointer, scalarType: any Accelerate::BNNSScalar.Type, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int) {
        let needed = shape.batchStride * Swift.max(batchSize, 1) * _bnnsElementSize(scalarType.bnnsDataType)
        guard let base = data.baseAddress, data.count >= needed else { return nil }
        self.init(dataType: scalarType.bnnsDataType, shape: shape)
        self.data = base
    }

    public init?<T>(data: Swift::UnsafeMutableBufferPointer<T>, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int) where T: Accelerate::BNNSScalar {
        self.init(data: UnsafeMutableRawBufferPointer(data), scalarType: T.self, shape: shape, batchSize: batchSize)
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension Accelerate::BNNSNDArrayDescriptor {
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public var dataSize: Swift::Int {
        var copy = self
        return BNNSNDArrayGetDataSize(&copy)
    }
}

// MARK: - Calling BNNS

/// Calls body with a pointer to the filter parameters, or nil.
func _withFilterParameters<R>(_ parameters: BNNSFilterParameters?, _ body: (UnsafePointer<BNNSFilterParameters>?) throws -> R) rethrows -> R {
    guard var parameters else { return try body(nil) }
    return try withUnsafePointer(to: &parameters) { try body($0) }
}

/// A descriptor with no data, standing for an optional argument left out.
func _emptyDescriptor() -> BNNSNDArrayDescriptor {
    BNNSNDArrayDescriptor()
}

/// Throws the error if BNNS returned nonzero.
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _check(_ status: Int32, _ error: BNNS.Error = .layerApplyFail) throws {
    if status != 0 { throw error }
}

/// The bit mask of the given axes.
func _axisFlags(_ axes: [Int]?) -> UInt32 {
    (axes ?? []).reduce(0) { $0 | (1 << UInt32($1)) }
}

/// Calls body with pointers to a copy of each descriptor (nil for nil ones).
func _withDescriptorPointers<R>(_ descriptors: [BNNSNDArrayDescriptor?], _ body: ([UnsafeMutablePointer<BNNSNDArrayDescriptor>?]) throws -> R) rethrows -> R {
    let storage = UnsafeMutablePointer<BNNSNDArrayDescriptor>.allocate(capacity: Swift.max(descriptors.count, 1))
    defer { storage.deallocate() }
    var pointers = [UnsafeMutablePointer<BNNSNDArrayDescriptor>?]()
    for (i, descriptor) in descriptors.enumerated() {
        (storage + i).initialize(to: descriptor ?? BNNSNDArrayDescriptor())
        pointers.append(descriptor == nil ? nil : storage + i)
    }
    return try body(pointers)
}
