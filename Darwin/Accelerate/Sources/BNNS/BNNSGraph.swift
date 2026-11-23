import Swift
import Darwin

// BNNSGraph: compiling a Core ML model (.mlmodelc) into a graph and
// running it in a context, over BNNSGraphCompileFromFile and the
// BNNSGraphContext functions. A context made by BNNSGraph.makeContext runs
// the builder's graph in Perry's own interpreter instead.

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
public enum BNNSGraph {
    public protocol PointerArgument {
        associatedtype Element
        var baseAddress: Swift::UnsafeMutablePointer<Self.Element>? { get }
        var count: Swift::Int { get }
    }

    public struct CompileOptions {
        public init() {
            self.init(useSingleThread: false, generateDebugInfo: false, optimizationPreference: .performance)
        }

        public init(useSingleThread: Swift::Bool = false, generateDebugInfo: Swift::Bool = false, optimizationPreference: Accelerate::BNNSGraph.Accelerate::CompileOptions.Accelerate::OptimizationPreference = .performance) {
            self.useSingleThread = useSingleThread
            self.generateDebugInfo = generateDebugInfo
            self.optimizationPreference = optimizationPreference
            self.predefinedOptimizations = 0
            predefinedOptimizationsSet = false
        }

        public var useSingleThread: Swift::Bool
        public var generateDebugInfo: Swift::Bool

        public struct OptimizationPreference: Swift::Equatable {
            @usableFromInline
            internal var value: Accelerate::BNNSGraphOptimizationPreference
            @usableFromInline
            @inline(__always) internal init(_ value: Accelerate::BNNSGraphOptimizationPreference) {
                self.value = value
            }
            @inlinable public static var performance: Accelerate::BNNSGraph.Accelerate::CompileOptions.Accelerate::OptimizationPreference {
                .init(BNNSGraphOptimizationPreference(rawValue: 0))
            }
            @inlinable public static var internalRepresentationSize: Accelerate::BNNSGraph.Accelerate::CompileOptions.Accelerate::OptimizationPreference {
                .init(BNNSGraphOptimizationPreference(rawValue: 1))
            }
            public static func == (a: Accelerate::BNNSGraph.Accelerate::CompileOptions.Accelerate::OptimizationPreference, b: Accelerate::BNNSGraph.Accelerate::CompileOptions.Accelerate::OptimizationPreference) -> Swift::Bool {
                a.value.rawValue == b.value.rawValue
            }
        }

        public var optimizationPreference: Accelerate::BNNSGraph.Accelerate::CompileOptions.Accelerate::OptimizationPreference

        /// The compiler's predefined optimization bits (not in the
        /// interface, but exported by the OS's overlay), passed on when set.
        public var predefinedOptimizations: Swift::UInt32 {
            didSet { predefinedOptimizationsSet = true }
        }

        var predefinedOptimizationsSet: Bool

        /// The C options object; the caller destroys it.
        func makeOptions() -> bnns_graph_compile_options_t {
            let options = BNNSGraphCompileOptionsMakeDefault()
            BNNSGraphCompileOptionsSetTargetSingleThread(options, useSingleThread)
            BNNSGraphCompileOptionsSetGenerateDebugInfo(options, generateDebugInfo)
            BNNSGraphCompileOptionsSetOptimizationPreference(options, optimizationPreference.value)
            if predefinedOptimizationsSet, let set = _setPredefinedOptimizations {
                set(options, predefinedOptimizations)
            }
            return options
        }
    }

    @_hasMissingDesignatedInitializers public class Context {
        /// A compiled graph and its context, or nil for a builder's graph.
        var graph: bnns_graph_t?
        var context: bnns_graph_context_t?
        /// A builder's graph: its program, outputs and their names.
        var program: _GraphProgram?
        var nanChecks = false
        var advanceCount = 0

        /// A context running a builder's program.
        init(program: _GraphProgram) {
            self.program = program
        }

        deinit {
            if let context { BNNSGraphContextDestroy(context) }
            if let graph { free(graph.data) }
        }

        static func compile(_ path: String, _ functionName: String?, _ options: CompileOptions) throws -> (bnns_graph_t, bnns_graph_context_t) {
            let cOptions = options.makeOptions()
            defer { BNNSGraphCompileOptionsDestroy(cOptions) }
            let graph = BNNSGraphCompileFromFile(path, functionName, cOptions)
            guard graph.data != nil else { throw Error.unableToCreateGraph }
            let context = BNNSGraphContextMake(graph)
            guard context.data != nil else {
                free(graph.data)
                throw Error.unableToCreateContext
            }
            return (graph, context)
        }

        public init(compileFromPath path: Swift::String, functionName: Swift::String? = nil, options: Accelerate::BNNSGraph.Accelerate::CompileOptions = CompileOptions()) async throws {
            let (graph, context) = try Context.compile(path, functionName, options)
            self.graph = graph
            self.context = context
        }

        @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
        public init(compileFromPath path: Swift::String, functionName: Swift::String? = nil, options: Accelerate::BNNSGraph.Accelerate::CompileOptions = CompileOptions()) throws {
            let (graph, context) = try Context.compile(path, functionName, options)
            self.graph = graph
            self.context = context
        }

        public func setDynamicShapes(_ shapes: [Accelerate::BNNSGraph.Accelerate::Shape], forFunction function: Swift::String? = nil) async throws -> [Accelerate::BNNSGraph.Accelerate::Shape] {
            guard let context else {
                // A builder's graph has static shapes: these must be them.
                guard let program, shapes.map({ $0.dimensions }) == program.argumentNodes.map({ $0.shape }) else {
                    throw Error.unableToSetDynamicShapes
                }
                return shapes
            }
            var storage = shapes.map { $0.dimensions.map { UInt64(Swift.max($0, 0)) } }
            let pointers = storage.indices.map { i -> UnsafeMutablePointer<UInt64> in
                let p = UnsafeMutablePointer<UInt64>.allocate(capacity: Swift.max(storage[i].count, 1))
                p.initialize(from: storage[i], count: storage[i].count)
                return p
            }
            defer { pointers.forEach { $0.deallocate() } }
            var cShapes = storage.indices.map { bnns_graph_shape_t(rank: storage[$0].count, shape: pointers[$0]) }
            let status = BNNSGraphContextSetDynamicShapes(context, function, cShapes.count, &cShapes)
            guard status >= 0 else { throw Error.unableToSetDynamicShapes }
            for i in storage.indices {
                storage[i] = Array(UnsafeBufferPointer(start: pointers[i], count: cShapes[i].rank))
            }
            return storage.map { Shape($0.map { Int($0) }) }
        }

        public func setBatchSize(_ batchSize: Swift::Int, forFunction function: Swift::String? = nil) async {
            _setBatchSize(batchSize, function)
        }

        @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
        public func setBatchSize(_ batchSize: Swift::Int, forFunction function: Swift::String? = nil) {
            _setBatchSize(batchSize, function)
        }

        func _setBatchSize(_ batchSize: Int, _ function: String?) {
            if let context { _ = BNNSGraphContextSetBatchSize(context, function, UInt64(Swift.max(batchSize, 0))) }
        }

        public var checkForNaNsAndInfinities: Swift::Bool {
            get { nanChecks }
            set {
                nanChecks = newValue
                if let context { BNNSGraphContextEnableNanAndInfChecks(context, newValue) }
            }
        }

        public func executeFunction(_ function: Swift::String? = nil, arguments: inout [Accelerate::BNNSTensor]) async throws {
            try _execute(function, &arguments)
        }

        func _execute(_ function: String?, _ arguments: inout [BNNSTensor]) throws {
            if let program {
                try program.execute(&arguments, nanChecks: nanChecks)
                return
            }
            guard let context else { throw Error.unableToExecute }
            guard BNNSGraphContextSetArgumentType(context, BNNSGraphArgumentType(rawValue: 2)) == 0 else { throw Error.unableToExecute }
            let count = arguments.count
            let status = arguments.withUnsafeMutableBufferPointer { tensors -> Int32 in
                var cArguments = (0..<count).map { i -> bnns_graph_argument_t in
                    var a = bnns_graph_argument_t()
                    a.tensor = tensors.baseAddress! + i
                    return a
                }
                for i in 0..<count { cArguments[i].data_ptr_size = tensors[i].data_size_in_bytes }
                return BNNSGraphContextExecute(context, function, count, &cArguments, 0, nil)
            }
            guard status == 0 else { throw Error.unableToExecute }
        }

        public func executeFunction<T>(_ function: Swift::String? = nil, arguments: [T]) throws where T: Accelerate::BNNSGraph.Accelerate::PointerArgument {
            if let program {
                try program.execute(pointers: arguments.map { (UnsafeMutableRawPointer($0.baseAddress), $0.count) }, nanChecks: nanChecks)
                return
            }
            guard let context else { throw Error.unableToExecute }
            guard BNNSGraphContextSetArgumentType(context, BNNSGraphArgumentType(rawValue: 0)) == 0 else { throw Error.unableToExecute }
            var cArguments = arguments.map { argument -> bnns_graph_argument_t in
                var a = bnns_graph_argument_t()
                a.data_ptr = UnsafeMutableRawPointer(argument.baseAddress)
                a.data_ptr_size = argument.count * MemoryLayout<T.Element>.stride
                return a
            }
            guard BNNSGraphContextExecute(context, function, cArguments.count, &cArguments, 0, nil) == 0 else { throw Error.unableToExecute }
        }

        public func argumentPosition(forFunction function: Swift::String? = nil, argument: Swift::String) -> Swift::Int {
            if let program { return program.argumentNames.firstIndex(of: argument) ?? -1 }
            guard let graph else { return -1 }
            let position = BNNSGraphGetArgumentPosition(graph, function, argument)
            return position == Int.max || position == -1 ? -1 : position
        }

        public func tensor(forFunction function: Swift::String? = nil, argument: Swift::String, fillKnownDynamicShapes: Swift::Bool) -> Accelerate::BNNSTensor? {
            if let program {
                guard let i = program.argumentNames.firstIndex(of: argument) else { return nil }
                let node = program.argumentList[i]
                return _makeTensor(type: node.dataType, shape: node.shape, stride: [], data: nil, size: 0)
            }
            guard let context else { return nil }
            var tensor = BNNSTensor()
            guard BNNSGraphContextGetTensor(context, function, argument, fillKnownDynamicShapes, &tensor) == 0 else { return nil }
            return tensor
        }

        public func argumentCount(forFunction function: Swift::String? = nil) -> Swift::Int {
            if let program { return program.argumentList.count }
            guard let graph else { return 0 }
            return BNNSGraphGetArgumentCount(graph, function)
        }

        public var functionCount: Swift::Int {
            if program != nil { return 1 }
            guard let graph else { return 0 }
            return BNNSGraphGetFunctionCount(graph)
        }

        public func argumentNames(forFunction function: Swift::String? = nil) -> [Swift::String] {
            if let program { return program.argumentNames }
            guard let graph else { return [] }
            let count = BNNSGraphGetArgumentCount(graph, function)
            var names = [UnsafePointer<CChar>?](repeating: nil, count: count)
            guard count > 0, BNNSGraphGetArgumentNames(graph, function, count, &names) == 0 else { return [] }
            return names.map { $0.map { String(cString: $0) } ?? "" }
        }

        public var functionNames: [Swift::String] {
            if program != nil { return ["main"] }
            guard let graph else { return [] }
            let count = BNNSGraphGetFunctionCount(graph)
            var names = [UnsafePointer<CChar>?](repeating: nil, count: count)
            guard count > 0, BNNSGraphGetFunctionNames(graph, count, &names) == 0 else { return [] }
            return names.map { $0.map { String(cString: $0) } ?? "" }
        }

        @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
        public var streamingAdvanceCount: Swift::Int {
            get { advanceCount }
            set {
                advanceCount = newValue
                if let context { _ = BNNSGraphContextSetStreamingAdvanceCount(context, newValue) }
            }
        }
    }

    public struct Shape: Swift::ExpressibleByArrayLiteral {
        public init(arrayLiteral elements: Swift::Int...) {
            dimensions = elements
        }
        public typealias ArrayLiteralElement = Swift::Int
        public private(set) var dimensions: [Swift::Int]
        public init(_ shape: [Swift::Int]) {
            dimensions = shape
        }
    }

    public enum Error: Swift::Error {
        case unableToCreateGraph
        case unableToCreateContext
        case unableToExecute
        case unableToSetDynamicShapes
        case unableToMakeGraph(_: Swift::String)
    }
}

/// BNNSGraphCompileOptionsSetPredefinedOptimizations, which libBNNS
/// exports and no header declares.
private let _setPredefinedOptimizations: (@convention(c) (bnns_graph_compile_options_t, UInt32) -> Void)? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "BNNSGraphCompileOptionsSetPredefinedOptimizations") else { return nil }
    return unsafeBitCast(symbol, to: (@convention(c) (bnns_graph_compile_options_t, UInt32) -> Void).self)
}()

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension Swift::UnsafeMutableBufferPointer: Accelerate::BNNSGraph.Accelerate::PointerArgument where Element: Accelerate::BNNSScalar {
}

@available(*, unavailable)
extension Accelerate::BNNSGraph.Accelerate::Context: Swift::Sendable {
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Context {
    public func executeFunction(_ function: Swift::String? = nil, arguments: inout [Accelerate::BNNSTensor]) throws {
        try _execute(function, &arguments)
    }

    /// The argument's tensor with data allocated for it (the caller frees it
    /// with deallocate()).
    public func allocateTensor(forFunction function: Swift::String? = nil, argument: Swift::String, fillKnownDynamicShapes: Swift::Bool) -> Accelerate::BNNSTensor? {
        guard var tensor = tensor(forFunction: function, argument: argument, fillKnownDynamicShapes: fillKnownDynamicShapes) else { return nil }
        if program == nil, let graph {
            _ = BNNSGraphTensorFillStrides(graph, function, argument, &tensor)
        }
        var size = BNNSTensorGetAllocationSize(&tensor)
        if size <= 0 { size = Swift.max(tensor.count * _bnnsElementSize(tensor.data_type), 1) }
        tensor.data = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 64)
        tensor.data_size_in_bytes = size
        return tensor
    }
}

// MARK: - BNNSTensor

/// Contiguous first-major strides of a shape.
func _contiguousStrides(_ shape: [Int]) -> [Int] {
    var stride = Array(repeating: 1, count: shape.count)
    var s = 1
    for i in stride.indices.reversed() {
        stride[i] = s
        s *= Swift.max(shape[i], 1)
    }
    return stride
}

func _makeTensor(type: BNNSDataType, shape: [Int], stride: [Int], data: UnsafeMutableRawPointer?, size: Int) -> BNNSTensor {
    let stride = stride.isEmpty ? _contiguousStrides(shape) : stride
    var tensor = BNNSTensor()
    tensor.data_type = type
    tensor.rank = UInt8(Swift.min(shape.count, 8))
    tensor.shape = _tuple8(shape)
    tensor.stride = _tuple8(stride)
    tensor.data = data
    tensor.data_size_in_bytes = size
    return tensor
}

extension BNNSTensor {
    var shapeArray: [Int] { Array(_array8(shape).prefix(Int(rank))) }
    var strideArray: [Int] { Array(_array8(stride).prefix(Int(rank))) }

    /// The number of bytes from the first element to past the last.
    var extentInBytes: Int {
        let s = shapeArray, t = strideArray
        var last = 0
        for i in 0..<s.count where s[i] > 0 { last += (s[i] - 1) * Swift.max(t[i], 0) }
        return s.contains(0) ? 0 : (last + 1) * _bnnsElementSize(data_type)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSTensor {
    public func makeArray<T>(of scalarType: T.Type) -> [T] where T: Accelerate::BNNSScalar {
        guard let data else { return [] }
        let value = _GraphOps.read(UnsafeRawPointer(data), type: data_type, shape: shapeArray, stride: strideArray)
        if T.bnnsDataType.rawValue == data_type.rawValue, strideArray == _contiguousStrides(shapeArray) {
            return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: T.self), count: count))
        }
        // Another type or layout: convert element by element.
        var result = [T]()
        result.reserveCapacity(value.count)
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 16)
        defer { scratch.deallocate() }
        for x in value.data {
            _GraphOps.store(x, scratch, T.bnnsDataType)
            result.append(scratch.load(as: T.self))
        }
        return result
    }

    public mutating func allocate<T>(initializingFrom source: some AccelerateBuffer<T>) where T: Accelerate::BNNSScalar {
        allocate(as: T.self, count: source.count)
        let destination = data!.assumingMemoryBound(to: T.self)
        source.withUnsafeBufferPointer { buffer in
            for i in 0..<buffer.count { (destination + i).initialize(to: buffer[i]) }
        }
    }

    public mutating func allocate<T>(as scalarType: T.Type, count: Swift::Int) where T: Accelerate::BNNSScalar {
        let size = Swift.max(count * MemoryLayout<T>.stride, 1)
        data = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: Swift.max(MemoryLayout<T>.alignment, 16))
        data_size_in_bytes = count * MemoryLayout<T>.stride
        data_type = T.bnnsDataType
    }

    public init<T>(initializingFrom source: some AccelerateBuffer<T>, shape: [Swift::Int], stride: [Swift::Int]) where T: Accelerate::BNNSScalar {
        self = _makeTensor(type: T.bnnsDataType, shape: shape, stride: stride, data: nil, size: 0)
        allocate(initializingFrom: source)
    }

    public init(shape: [Swift::Int], stride: [Swift::Int], dataType: Accelerate::BNNSDataType) {
        self = _makeTensor(type: dataType, shape: shape, stride: stride, data: nil, size: 0)
    }

    public init(dataType: Accelerate::BNNSDataType, shape: [Swift::Int], stride: [Swift::Int]) {
        self = _makeTensor(type: dataType, shape: shape, stride: stride, data: nil, size: 0)
    }

    public init(data: Swift::UnsafeMutableRawBufferPointer, shape: [Swift::Int], stride: [Swift::Int], dataType: Accelerate::BNNSDataType) {
        self = _makeTensor(type: dataType, shape: shape, stride: stride, data: data.baseAddress, size: data.count)
    }

    public init<T>(data: Swift::UnsafeMutableBufferPointer<T>, shape: [Swift::Int], stride: [Swift::Int]) where T: Accelerate::BNNSScalar {
        self = _makeTensor(type: T.bnnsDataType, shape: shape, stride: stride, data: data.baseAddress.map { UnsafeMutableRawPointer($0) },
                           size: data.count * MemoryLayout<T>.stride)
    }

    public static func allocateUninitialized(scalarType: any Accelerate::BNNSScalar.Type, shape: [Swift::Int], stride: [Swift::Int]) -> Accelerate::BNNSTensor {
        var tensor = _makeTensor(type: scalarType.bnnsDataType, shape: shape, stride: stride, data: nil, size: 0)
        let size = Swift.max(tensor.extentInBytes, 1)
        tensor.data = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 64)
        tensor.data_size_in_bytes = tensor.extentInBytes
        return tensor
    }

    public static func allocate<C>(initializingFrom source: C, shape: [Swift::Int], stride: [Swift::Int]) -> Accelerate::BNNSTensor where C: Accelerate::AccelerateBuffer, C.Element: Accelerate::BNNSScalar {
        var tensor = _makeTensor(type: C.Element.bnnsDataType, shape: shape, stride: stride, data: nil, size: 0)
        tensor.allocate(initializingFrom: source)
        return tensor
    }

    public static func allocate<T>(repeating repeatedValue: T, shape: [Swift::Int], stride: [Swift::Int]) -> Accelerate::BNNSTensor where T: Accelerate::BNNSScalar {
        var tensor = _makeTensor(type: T.bnnsDataType, shape: shape, stride: stride, data: nil, size: 0)
        let count = Swift.max(tensor.extentInBytes / Swift.max(MemoryLayout<T>.stride, 1), shape.reduce(1, *))
        tensor.allocate(initializingFrom: Array(repeating: repeatedValue, count: count))
        return tensor
    }

    public func deallocate() {
        data?.deallocate()
    }

    /// The number of elements the shape holds.
    public var count: Swift::Int {
        shapeArray.reduce(1) { $0 * Swift.max($1, 0) }
    }
}
