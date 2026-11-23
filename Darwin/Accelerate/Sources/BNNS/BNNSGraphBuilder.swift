import Swift
import Darwin
import simd

// BNNSGraph.Builder: a graph built operation by operation in Swift. Each
// operation is a node of a program Perry runs itself (see
// BNNSGraphValues.swift); each node is computed once on zero-valued
// arguments as it's added, which gives its shape.

/// A node of a builder's graph.
final class _GraphNode {
    let dataType: BNNSDataType
    let inputs: [_GraphNode]
    let compute: ([_GraphValue]) -> _GraphValue
    /// The node's value on zero arguments: its shape and, for constants and
    /// nodes computed from them alone, its value.
    let sample: _GraphValue
    var name: String?
    var isArgument = false

    init(dataType: BNNSDataType, inputs: [_GraphNode], compute: @escaping ([_GraphValue]) -> _GraphValue) {
        self.dataType = dataType
        self.inputs = inputs
        self.compute = compute
        sample = _GraphNode.coerce(compute(inputs.map { $0.sample }), dataType)
    }

    var shape: [Int] { sample.shape }

    var opaque: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    static func coerce(_ v: _GraphValue, _ type: BNNSDataType) -> _GraphValue {
        v.map { _GraphOps.coerce($0, type) }
    }
}

/// A builder's graph: its nodes, arguments and (once made) outputs.
final class _GraphProgram {
    var nodes: [_GraphNode] = []
    var argumentNodes: [_GraphNode] = []
    var outputs: [_GraphNode] = []

    func add(_ type: BNNSDataType, _ inputs: [_GraphNode], _ compute: @escaping ([_GraphValue]) -> _GraphValue) -> _GraphNode {
        let node = _GraphNode(dataType: type, inputs: inputs, compute: compute)
        nodes.append(node)
        return node
    }

    /// Outputs precede inputs, as BNNSGraph orders a function's arguments.
    var argumentList: [_GraphNode] { outputs + argumentNodes }

    var argumentNames: [String] {
        outputs.enumerated().map { $0.element.name ?? "output_\($0.offset)" } +
            argumentNodes.enumerated().map { $0.element.name ?? "input_\($0.offset)" }
    }

    /// The outputs' values given the arguments'.
    func run(_ inputs: [_GraphValue], nanChecks: Bool) throws -> [_GraphValue] {
        var values = [ObjectIdentifier: _GraphValue]()
        for (node, value) in zip(argumentNodes, inputs) {
            values[ObjectIdentifier(node)] = _GraphNode.coerce(value, node.dataType)
        }
        func value(_ node: _GraphNode) -> _GraphValue {
            if let v = values[ObjectIdentifier(node)] { return v }
            let v = _GraphNode.coerce(node.compute(node.inputs.map(value)), node.dataType)
            values[ObjectIdentifier(node)] = v
            return v
        }
        let results = outputs.map(value)
        if nanChecks, results.contains(where: { $0.data.contains { !$0.isFinite } }) {
            throw BNNSGraph.Error.unableToExecute
        }
        return results
    }

    func execute(_ arguments: inout [BNNSTensor], nanChecks: Bool) throws {
        let list = argumentList
        guard arguments.count == list.count else { throw BNNSGraph.Error.unableToExecute }
        var inputs = [_GraphValue]()
        for (i, node) in argumentNodes.enumerated() {
            let tensor = arguments[outputs.count + i]
            guard let data = tensor.data else { throw BNNSGraph.Error.unableToExecute }
            let shape = tensor.rank == 0 && !node.shape.isEmpty ? node.shape : tensor.shapeArray
            guard shape.reduce(1, *) == node.shape.reduce(1, *) else { throw BNNSGraph.Error.unableToExecute }
            let stride = tensor.rank == 0 ? _contiguousStrides(shape) : tensor.strideArray
            inputs.append(_GraphOps.read(UnsafeRawPointer(data), type: tensor.data_type, shape: shape, stride: stride).reshaped(node.shape))
        }
        let results = try run(inputs, nanChecks: nanChecks)
        for (i, result) in results.enumerated() {
            var tensor = arguments[i]
            if tensor.data == nil {
                let type = outputs[i].dataType
                let size = Swift.max(result.count * _bnnsElementSize(type), 1)
                tensor = _makeTensor(type: type, shape: result.shape, stride: [],
                                     data: UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 64), size: result.count * _bnnsElementSize(type))
            }
            let stride = tensor.rank == 0 || tensor.rank != result.rank ? _contiguousStrides(result.shape) : tensor.strideArray
            _GraphOps.write(result, to: tensor.data!, type: tensor.data_type, stride: stride)
            arguments[i] = tensor
        }
    }

    func execute(pointers: [(UnsafeMutableRawPointer?, Int)], nanChecks: Bool) throws {
        let list = argumentList
        guard pointers.count == list.count else { throw BNNSGraph.Error.unableToExecute }
        var inputs = [_GraphValue]()
        for (i, node) in argumentNodes.enumerated() {
            guard let data = pointers[outputs.count + i].0 else { throw BNNSGraph.Error.unableToExecute }
            inputs.append(_GraphOps.read(UnsafeRawPointer(data), type: node.dataType, shape: node.shape, stride: _contiguousStrides(node.shape)))
        }
        let results = try run(inputs, nanChecks: nanChecks)
        for (i, result) in results.enumerated() {
            guard let data = pointers[i].0 else { throw BNNSGraph.Error.unableToExecute }
            _GraphOps.write(result, to: data, type: outputs[i].dataType, stride: _contiguousStrides(result.shape))
        }
    }
}

/// What makes a tensor of a builder's graph from a node.
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension BNNSGraph.Builder.Tensor {
    init(_ node: _GraphNode, _ program: _GraphProgram) {
        self.node = node
        self.program = program
    }

    var builder: BNNSGraph.Builder { BNNSGraph.Builder(program: program) }

    /// A tensor of this one's type computed from it.
    func unary(_ f: @escaping (_GraphValue) -> _GraphValue) -> BNNSGraph.Builder.Tensor<T> {
        .init(program.add(T.bnnsDataType, [node]) { f($0[0]) }, program)
    }

    func elementwise(_ f: @escaping (Double) -> Double) -> BNNSGraph.Builder.Tensor<T> {
        unary { $0.map(f) }
    }

    func binary<U>(_ other: BNNSGraph.Builder.Tensor<U>, _ f: @escaping (_GraphValue, _GraphValue) -> _GraphValue) -> BNNSGraph.Builder.Tensor<T> {
        .init(program.add(T.bnnsDataType, [node, other.node]) { f($0[0], $0[1]) }, program)
    }

    func zipped(_ other: BNNSGraph.Builder.Tensor<T>, _ f: @escaping (Double, Double) -> Double) -> BNNSGraph.Builder.Tensor<T> {
        binary(other) { _GraphOps.zip($0, $1, f) }
    }

    func compare(_ other: BNNSGraph.Builder.Tensor<T>, _ f: @escaping (Double, Double) -> Bool) -> BNNSGraph.Builder.Tensor<Bool> {
        .init(program.add(Bool.bnnsDataType, [node, other.node]) { _GraphOps.zip($0[0], $0[1]) { f($0, $1) ? 1 : 0 } }, program)
    }

    func tensor(_ parameter: some BNNSGraph.Builder.OperationParameter<T>) -> BNNSGraph.Builder.Tensor<T> {
        parameter.graphBuilderTensor(builder)
    }

    func reduced(_ axes: [Int], _ keep: Bool, _ f: @escaping ([Double]) -> Double) -> BNNSGraph.Builder.Tensor<T> {
        unary { _GraphOps.reduce($0, axes: axes, keep: keep, f) }
    }

    func indices<U: BNNSScalar>(as type: U.Type, _ f: @escaping (_GraphValue) -> _GraphValue) -> BNNSGraph.Builder.Tensor<U> {
        .init(program.add(U.bnnsDataType, [node]) { f($0[0]) }, program)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph {
    public protocol TensorDescriptor {
        var tensorData: Swift::UnsafeMutableRawPointer? { get }
    }

    /// Builds a graph with the block, whose returned tensors are its
    /// outputs, into a context that runs it.
    public static func makeContext(options: Accelerate::BNNSGraph.Accelerate::CompileOptions = CompileOptions(), _ block: (inout Accelerate::BNNSGraph.Accelerate::Builder) -> [any Accelerate::BNNSGraph.Accelerate::TensorDescriptor]) throws -> Accelerate::BNNSGraph.Accelerate::Context {
        let program = _GraphProgram()
        var builder = Builder(program: program)
        let outputs = block(&builder)
        guard !outputs.isEmpty else { throw Error.unableToMakeGraph("the graph has no outputs") }
        for output in outputs {
            guard let data = output.tensorData,
                  let node = program.nodes.first(where: { $0.opaque == data }) else {
                throw Error.unableToMakeGraph("an output isn't a tensor of this graph")
            }
            program.outputs.append(node)
        }
        return Context(program: program)
    }

    public struct Builder {
        let program: _GraphProgram

        init(program: _GraphProgram) {
            self.program = program
        }

        public struct Tensor<T>: Accelerate::BNNSGraph.Accelerate::TensorDescriptor, Swift::CustomStringConvertible where T: Accelerate::BNNSScalar {
            let node: _GraphNode
            let program: _GraphProgram

            /// An opaque reference to the tensor's node.
            public var tensorData: Swift::UnsafeMutableRawPointer? { node.opaque }

            public var description: Swift::String {
                "Tensor<\(T.self)>(shape: \(node.shape))"
            }

            public var dataType: Accelerate::BNNSDataType? { node.dataType }
            public var rank: Swift::Int? { node.shape.count }
            public var shape: [Swift::Int]? { node.shape }
            public var stride: [Swift::Int]? { _contiguousStrides(node.shape) }
        }

        public enum Intent: Swift::Hashable {
            case input
            case inputOutput
        }

        public func argument<T>(name: Swift::String? = nil, dataType: T.Type, shape: [Swift::Int], intent: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Intent = .input) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> where T: Accelerate::BNNSScalar {
            let node = program.add(T.bnnsDataType, []) { _ in _GraphValue(zeros: shape) }
            node.name = name
            node.isArgument = true
            program.argumentNodes.append(node)
            return Tensor(node, program)
        }

        public func constant<T>(name: Swift::String? = nil, value: T) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> where T: Accelerate::BNNSScalar {
            constant(name: name, values: [value], shape: [])
        }

        public func constant<T>(name: Swift::String? = nil, values: some AccelerateBuffer<T>, shape: [Swift::Int]? = nil) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> where T: Accelerate::BNNSScalar {
            let doubles: [Double] = values.withUnsafeBufferPointer { buffer in
                UnsafeRawBufferPointer(buffer).baseAddress.map { base in
                    (0..<buffer.count).map { _GraphOps.load(base + $0 * MemoryLayout<T>.stride, T.bnnsDataType) }
                } ?? []
            }
            let value = _GraphValue(shape: shape ?? [doubles.count], data: doubles)
            let node = program.add(T.bnnsDataType, []) { _ in value }
            node.name = name
            return Tensor(node, program)
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder {
    /// A matrix from rows (rowMajor) or columns.
    public func constant(values: Swift::Array<Swift::Array<Swift::Float>>, rowMajor: Swift::Bool = false) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Float> {
        let outer = values.count, inner = values.first?.count ?? 0
        var flat = [Float]()
        if rowMajor {
            flat = values.flatMap { $0 }
            return constant(values: flat, shape: [outer, inner])
        }
        for r in 0..<inner {
            for c in 0..<outer { flat.append(r < values[c].count ? values[c][r] : 0) }
        }
        return constant(values: flat, shape: [inner, outer])
    }
}

// MARK: - Operation parameters

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder {
    public protocol OperationParameter<Element> {
        associatedtype Element: Accelerate::BNNSScalar
        func graphBuilderTensor(_ builder: Accelerate::BNNSGraph.Accelerate::Builder) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element>
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter {
    public func graphBuilderTensor(_ builder: Accelerate::BNNSGraph.Accelerate::Builder) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        self
    }
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public typealias Element = T
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::Array: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter where Element: Accelerate::BNNSScalar {
    public func graphBuilderTensor(_ builder: Accelerate::BNNSGraph.Accelerate::Builder) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Element> {
        builder.constant(values: self)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::ContiguousArray: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter where Element: Accelerate::BNNSScalar {
    public func graphBuilderTensor(_ builder: Accelerate::BNNSGraph.Accelerate::Builder) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Element> {
        builder.constant(values: self)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::ArraySlice: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter where Element: Accelerate::BNNSScalar {
    public func graphBuilderTensor(_ builder: Accelerate::BNNSGraph.Accelerate::Builder) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Element> {
        builder.constant(values: self)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::UnsafeBufferPointer: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter where Element: Accelerate::BNNSScalar {
    public func graphBuilderTensor(_ builder: Accelerate::BNNSGraph.Accelerate::Builder) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Element> {
        builder.constant(values: self)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::UnsafeMutableBufferPointer: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter where Element: Accelerate::BNNSScalar {
    public func graphBuilderTensor(_ builder: Accelerate::BNNSGraph.Accelerate::Builder) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Element> {
        builder.constant(values: UnsafeBufferPointer(self))
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::Float: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter {
    public typealias Element = Swift::Float
    public func graphBuilderTensor(_ builder: Accelerate::BNNSGraph.Accelerate::Builder) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Float> {
        builder.constant(value: self)
    }
}

// MARK: - Arithmetic operators

/// Floored modulo, as the graph's % computes it.
func _floorMod(_ a: Double, _ b: Double) -> Double {
    guard b != 0 else { return .nan }
    let r = a.truncatingRemainder(dividingBy: b)
    return r != 0 && (r < 0) != (b < 0) ? r + b : r
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter {
    @_disfavoredOverload public static func * (lhs: Self, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element> {
        lhs.graphBuilderTensor(rhs.builder).zipped(rhs, *)
    }
    public static func * (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element>, rhs: Self) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element> {
        lhs.zipped(rhs.graphBuilderTensor(lhs.builder), *)
    }
    @_disfavoredOverload public static func + (lhs: Self, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element> {
        lhs.graphBuilderTensor(rhs.builder).zipped(rhs, +)
    }
    public static func + (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element>, rhs: Self) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element> {
        lhs.zipped(rhs.graphBuilderTensor(lhs.builder), +)
    }
    @_disfavoredOverload public static func / (lhs: Self, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element> {
        lhs.graphBuilderTensor(rhs.builder).zipped(rhs, /)
    }
    public static func / (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element>, rhs: Self) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element> {
        lhs.zipped(rhs.graphBuilderTensor(lhs.builder), /)
    }
    @_disfavoredOverload public static func - (lhs: Self, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element> {
        lhs.graphBuilderTensor(rhs.builder).zipped(rhs, -)
    }
    public static func - (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element>, rhs: Self) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element> {
        lhs.zipped(rhs.graphBuilderTensor(lhs.builder), -)
    }
    public static func % (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element>, rhs: Self) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Self.Element> {
        lhs.zipped(rhs.graphBuilderTensor(lhs.builder), _floorMod)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor where T: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter {
    public static func .== (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool> {
        lhs.compare(rhs, ==)
    }
    public static func .!= (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool> {
        lhs.compare(rhs, !=)
    }
    public static func .< (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool> {
        lhs.compare(rhs, <)
    }
    public static func .<= (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool> {
        lhs.compare(rhs, <=)
    }
    public static func .> (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool> {
        lhs.compare(rhs, >)
    }
    public static func .>= (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool> {
        lhs.compare(rhs, >=)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor where T == Swift::Bool {
    prefix public static func .! (rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool> {
        rhs.elementwise { $0 != 0 ? 0 : 1 }
    }
    public static func .& (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool>, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool> {
        lhs.zipped(rhs) { $0 != 0 && $1 != 0 ? 1 : 0 }
    }
    public static func .| (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool>, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool> {
        lhs.zipped(rhs) { $0 != 0 || $1 != 0 ? 1 : 0 }
    }
    public static func .^ (lhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool>, rhs: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Bool> {
        lhs.zipped(rhs) { ($0 != 0) != ($1 != 0) ? 1 : 0 }
    }

    /// valueIfTrue where the condition holds, valueIfFalse elsewhere.
    public func select<U>(_ valueIfTrue: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<U>, _ valueIfFalse: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<U>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<U> where U: Accelerate::BNNSScalar {
        .init(program.add(U.bnnsDataType, [node, valueIfTrue.node, valueIfFalse.node]) { v in
            _GraphOps.zip3(v[0], v[1], v[2]) { $0 != 0 ? $1 : $2 }
        }, program)
    }

    public func select<U>(_ valueIfTrue: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<U>, _ valueIfFalse: any Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter<U>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<U> where U: Accelerate::BNNSScalar {
        select(valueIfTrue, valueIfFalse.graphBuilderTensor(builder))
    }

    public func select<U>(_ valueIfTrue: any Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter<U>, _ valueIfFalse: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<U>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<U> where U: Accelerate::BNNSScalar {
        select(valueIfTrue.graphBuilderTensor(builder), valueIfFalse)
    }
}

// MARK: - Elementwise functions

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor {
    public func matmul(transpose: Swift::Bool = false, other: some BNNSGraph.Builder.OperationParameter<T>, transposeOther: Swift::Bool = false, bias: some BNNSGraph.Builder.OperationParameter<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        matmul(transpose: transpose, other: other, transposeOther: transposeOther) + tensor(bias)
    }

    public func matmul(transpose: Swift::Bool = false, other: some BNNSGraph.Builder.OperationParameter<T>, transposeOther: Swift::Bool = false) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        binary(tensor(other)) { a, b in
            _GraphOps.matmul(transpose ? _GraphOps.transposeLast(a) : a, transposeOther ? _GraphOps.transposeLast(b) : b)
        }
    }

    /// x · weightᵀ + bias, with weights [outputs, inputs].
    public func linear(weight: some BNNSGraph.Builder.OperationParameter<T>, bias: some BNNSGraph.Builder.OperationParameter<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        linear(weight: weight) + tensor(bias)
    }

    public func linear(weight: some BNNSGraph.Builder.OperationParameter<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        matmul(other: weight, transposeOther: true)
    }

    public func cast<U>(to type: U.Type) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<U> where U: Accelerate::BNNSScalar {
        indices(as: U.self) { $0 }
    }

    public func conv(weight: some BNNSGraph.Builder.OperationParameter<T>, strides: [Swift::Int], padding: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::ConvolutionPadding, dilations: [Swift::Int]? = nil, groupCount: Swift::Int = 1) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        binary(tensor(weight)) { _GraphOps.convolution($0, $1, bias: nil, strides: strides, padding: padding, dilations: dilations, groups: groupCount) }
    }

    public func conv(weight: some BNNSGraph.Builder.OperationParameter<T>, strides: [Swift::Int], bias: some BNNSGraph.Builder.OperationParameter<T>, padding: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::ConvolutionPadding, dilations: [Swift::Int]? = nil, groupCount: Swift::Int = 1) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let w = tensor(weight), b = tensor(bias)
        return .init(program.add(T.bnnsDataType, [node, w.node, b.node]) {
            _GraphOps.convolution($0[0], $0[1], bias: $0[2], strides: strides, padding: padding, dilations: dilations, groups: groupCount)
        }, program)
    }

    public func convTranspose(weight: some BNNSGraph.Builder.OperationParameter<T>, strides: [Swift::Int], padding: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::ConvolutionPadding, outputPaddingValues: [Swift::Int]? = nil, dilations: [Swift::Int]? = nil, groupCount: Swift::Int = 1) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        binary(tensor(weight)) {
            _GraphOps.convolutionTranspose($0, $1, bias: nil, strides: strides, padding: padding, outputPadding: outputPaddingValues, dilations: dilations, groups: groupCount)
        }
    }

    public func convTranspose(weight: some BNNSGraph.Builder.OperationParameter<T>, strides: [Swift::Int], bias: some BNNSGraph.Builder.OperationParameter<T>, padding: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::ConvolutionPadding, outputPaddingValues: [Swift::Int]? = nil, dilations: [Swift::Int]? = nil, groupCount: Swift::Int = 1) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let w = tensor(weight), b = tensor(bias)
        return .init(program.add(T.bnnsDataType, [node, w.node, b.node]) {
            _GraphOps.convolutionTranspose($0[0], $0[1], bias: $0[2], strides: strides, padding: padding, outputPadding: outputPaddingValues,
                                           dilations: dilations, groups: groupCount)
        }, program)
    }

    public func softmax(axis: Swift::Int) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        unary { _GraphOps.softmax($0, axis: axis, log: false) }
    }

    public func logSoftmax(axis: Swift::Int) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        unary { _GraphOps.softmax($0, axis: axis, log: true) }
    }

    /// log(1 + exp(αx)) / α.
    public func softplus(alpha: Swift::Float) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let a = Double(alpha == 0 ? 1 : alpha)
        return elementwise { Darwin.log1p(Darwin.exp(a * $0)) / a }
    }

    public func relu() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise { Swift.max($0, 0) } }
    public func relu6() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise { Swift.min(Swift.max($0, 0), 6) } }
    public func leakyReLU(alpha: Swift::Float = 0.01) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let a = Double(alpha)
        return elementwise { $0 >= 0 ? $0 : a * $0 }
    }
    public func sigmoid() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(_GraphOps.sigmoid) }
    /// min(β, x) for x ≥ 0, min(β, αx) below.
    public func clampedReLU(alpha: Swift::Float, beta: Swift::Float) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let a = Double(alpha), b = Double(beta)
        return elementwise { Swift.min(b, $0 >= 0 ? $0 : a * $0) }
    }
    public func scaledTanh(alpha: Swift::Float, beta: Swift::Float) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let a = Double(alpha), b = Double(beta)
        return elementwise { a * Darwin.tanh(b * $0) }
    }
    public func hardSigmoid(alpha: Swift::Float, beta: Swift::Float) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let a = Double(alpha), b = Double(beta)
        return elementwise { Swift.min(Swift.max(a * $0 + b, 0), 1) }
    }
    public func softsign() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise { $0 / (1 + Swift.abs($0)) } }
    public func elu(alpha: Swift::Float) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let a = Double(alpha)
        return elementwise { $0 > 0 ? $0 : a * (Darwin.exp($0) - 1) }
    }
    public func thresholdedReLU(alpha: Swift::Float) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let a = Double(alpha)
        return elementwise { $0 > a ? $0 : 0 }
    }
    public func hardSwish() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        elementwise { $0 * Swift.min(Swift.max($0 + 3, 0), 6) / 6 }
    }
    public func silu() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise { $0 * _GraphOps.sigmoid($0) } }
    public func erf() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(_GraphOps.erf) }
    public func gelu() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        elementwise { 0.5 * $0 * (1 + Darwin.erf($0 / 2.0.squareRoot())) }
    }
    public func geluTanhApproximation() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let c = (2 / Double.pi).squareRoot()
        return elementwise { 0.5 * $0 * (1 + Darwin.tanh(c * ($0 + 0.044715 * $0 * $0 * $0))) }
    }
    public func geluSigmoidApproximation() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        elementwise { $0 * _GraphOps.sigmoid(1.702 * $0) }
    }
    /// Leaky ReLU with a slope per channel (axis 1), or one for all.
    public func prelu(alpha: [Swift::Float]) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let slopes = _GraphValue(shape: [alpha.count], data: alpha.map { Double($0) })
        return unary { x in
            let a = slopes.count == 1 ? slopes : _GraphOps.channelwise(slopes, rank: x.rank)
            return _GraphOps.zip(x, a) { $0 >= 0 ? $0 : $1 * $0 }
        }
    }
    public func fma(y: some BNNSGraph.Builder.OperationParameter<T>, z: some BNNSGraph.Builder.OperationParameter<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let b = tensor(y), c = tensor(z)
        return .init(program.add(T.bnnsDataType, [node, b.node, c.node]) { _GraphOps.zip3($0[0], $0[1], $0[2]) { $0 * $1 + $2 } }, program)
    }
    public func unsqueeze(axis: Swift::Int) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        unary { v in
            var shape = v.shape
            let a = axis < 0 ? axis + v.rank + 1 : axis
            shape.insert(1, at: Swift.min(Swift.max(a, 0), shape.count))
            return v.reshaped(shape)
        }
    }
    public func squeeze(axis: Swift::Int) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        unary { v in
            var shape = v.shape
            let a = _GraphOps.axis(axis, v.rank)
            if a < shape.count, shape[a] == 1 { shape.remove(at: a) }
            return v.reshaped(shape)
        }
    }
    public func cos() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.cos) }
    public func cosh() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.cosh) }
    public func sin() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.sin) }
    public func sinh() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.sinh) }
    public func tan() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.tan) }
    public func tanh() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.tanh) }
    public func acos() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.acos) }
    public func acosh() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.acosh) }
    public func asin() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.asin) }
    public func asinh() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.asinh) }
    public func atan() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.atan) }
    public func atanh() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.atanh) }
    public func exp() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.exp) }
    public func exp2() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise(Darwin.exp2) }
    /// log(x + ε).
    public func log(epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let e = Double(epsilon)
        return elementwise { Darwin.log($0 + e) }
    }
    public func sqrt() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise { $0.squareRoot() } }
    /// 1 / sqrt(x + ε).
    public func rsqrt(epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let e = Double(epsilon)
        return elementwise { 1 / ($0 + e).squareRoot() }
    }
    public func pow(y: some BNNSGraph.Builder.OperationParameter<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        zipped(tensor(y)) { Darwin.pow($0, $1) }
    }
    public func max(y: some BNNSGraph.Builder.OperationParameter<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        zipped(tensor(y)) { Swift.max($0, $1) }
    }
    public func min(y: some BNNSGraph.Builder.OperationParameter<T>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        zipped(tensor(y)) { Swift.min($0, $1) }
    }
    public func abs() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise { Swift.abs($0) } }
    public func ceil() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise { $0.rounded(.up) } }
    public func clip(to bounds: Swift::ClosedRange<Swift::Float>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let lo = Double(bounds.lowerBound), hi = Double(bounds.upperBound)
        return elementwise { Swift.min(Swift.max($0, lo), hi) }
    }
    public func floor() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise { $0.rounded(.down) } }
    /// 1 / (x + ε).
    public func reciprocal(epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let e = Double(epsilon)
        return elementwise { 1 / ($0 + e) }
    }
    public func round() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> { elementwise { $0.rounded(.toNearestOrEven) } }
    /// max(x, lowerBound).
    public func threshold(to lowerBound: Swift::Float) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let lo = Double(lowerBound)
        return elementwise { Swift.max($0, lo) }
    }
}

// MARK: - Reductions

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor {
    public func sum(axes: [Swift::Int], keepDimensions: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        reduced(axes, keepDimensions) { $0.reduce(0, +) }
    }
    public func sumOfSquares(axes: [Swift::Int], keepDimensions: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        reduced(axes, keepDimensions) { $0.reduce(0) { $0 + $1 * $1 } }
    }
    public func product(axes: [Swift::Int], keepDimensions: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        reduced(axes, keepDimensions) { $0.reduce(1, *) }
    }
    public func mean(axes: [Swift::Int], keepDimensions: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        reduced(axes, keepDimensions) { $0.isEmpty ? 0 : $0.reduce(0, +) / Double($0.count) }
    }
    public func minimum(axes: [Swift::Int], keepDimensions: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        reduced(axes, keepDimensions) { $0.min() ?? 0 }
    }
    public func maximum(axes: [Swift::Int], keepDimensions: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        reduced(axes, keepDimensions) { $0.max() ?? 0 }
    }
    public func l1Norm(axes: [Swift::Int], keepDimensions: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        reduced(axes, keepDimensions) { $0.reduce(0) { $0 + Swift.abs($1) } }
    }
    public func l2Norm(axes: [Swift::Int], keepDimensions: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        reduced(axes, keepDimensions) { $0.reduce(0) { $0 + $1 * $1 }.squareRoot() }
    }
    public func logSum(axes: [Swift::Int], keepDimensions: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        reduced(axes, keepDimensions) { Darwin.log($0.reduce(0, +)) }
    }
    public func logSumExp(axes: [Swift::Int], keepDimensions: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        reduced(axes, keepDimensions) { values in
            let m = values.max() ?? 0
            return m + Darwin.log(values.reduce(0) { $0 + Darwin.exp($1 - m) })
        }
    }

    public func argMin(axis: Swift::Int, keepDimension: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Int32> {
        indices(as: Int32.self) { _GraphOps.reduce($0, axes: [axis], keep: keepDimension) { v in Double(v.indices.min { v[$0] < v[$1] } ?? 0) } }
    }

    public func argMax(axis: Swift::Int, keepDimension: Swift::Bool) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Int32> {
        indices(as: Int32.self) { _GraphOps.reduce($0, axes: [axis], keep: keepDimension) { v in Double(v.indices.max { v[$0] < v[$1] || (v[$0] == v[$1] && $0 > $1) } ?? 0) } }
    }

    /// The indices that sort each line along the axis (stably).
    public func argSort(axis: Swift::Int, sortOrder: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SortOrder) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Int32> {
        indices(as: Int32.self) { v in
            var result = v
            for line in _GraphOps.lines(v.shape, axis: _GraphOps.axis(axis, v.rank)) {
                let order = line.indices.sorted { a, b in
                    let x = v.data[line[a]], y = v.data[line[b]]
                    if x == y { return a < b }
                    return sortOrder == .ascending ? x < y : x > y
                }
                for (i, o) in line.enumerated() { result.data[o] = Double(order[i]) }
            }
            return result
        }
    }

    public func cumulativeSum(axis: Swift::Int) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        unary { v in
            var result = v
            for line in _GraphOps.lines(v.shape, axis: _GraphOps.axis(axis, v.rank)) {
                var s = 0.0
                for o in line { s += v.data[o]; result.data[o] = s }
            }
            return result
        }
    }

    /// The k largest (or smallest) values along the axis and their indices.
    public func topK(_ k: Swift::Int, axis: Swift::Int, findLargest: Swift::Bool) -> (values: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, indices: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Int32>) {
        func top(_ v: _GraphValue, _ wantIndices: Bool) -> _GraphValue {
            let a = _GraphOps.axis(axis, v.rank)
            var shape = v.shape
            shape[a] = Swift.min(k, v.shape[a])
            var result = _GraphValue(zeros: shape)
            let outLines = _GraphOps.lines(shape, axis: a)
            for (line, outLine) in zip(_GraphOps.lines(v.shape, axis: a), outLines) {
                let order = line.indices.sorted { x, y in
                    let p = v.data[line[x]], q = v.data[line[y]]
                    if p == q { return x < y }
                    return findLargest ? p > q : p < q
                }
                for (i, o) in outLine.enumerated() { result.data[o] = wantIndices ? Double(order[i]) : v.data[line[order[i]]] }
            }
            return result
        }
        return (unary { top($0, false) }, indices(as: Int32.self) { top($0, true) })
    }
}

// MARK: - Normalization and pooling

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor {
    /// (x - mean) / sqrt(variance + ε) · weight + bias, per channel (axis 1).
    public func batchNorm(mean: some BNNSGraph.Builder.OperationParameter<T>, variance: some BNNSGraph.Builder.OperationParameter<T>, weight: some BNNSGraph.Builder.OperationParameter<T>, bias: some BNNSGraph.Builder.OperationParameter<T>, epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let m = tensor(mean), v = tensor(variance), w = tensor(weight), b = tensor(bias)
        let e = Double(epsilon)
        return .init(program.add(T.bnnsDataType, [node, m.node, v.node, w.node, b.node]) { x in
            let r = x[0].rank
            let centered = _GraphOps.zip(x[0], _GraphOps.channelwise(x[1], rank: r), -)
            let scaled = _GraphOps.zip(centered, _GraphOps.channelwise(x[2], rank: r)) { $0 / ($1 + e).squareRoot() }
            return _GraphOps.zip3(scaled, _GraphOps.channelwise(x[3], rank: r), _GraphOps.channelwise(x[4], rank: r)) { $0 * $1 + $2 }
        }, program)
    }

    public func batchNorm(mean: some BNNSGraph.Builder.OperationParameter<T>, variance: some BNNSGraph.Builder.OperationParameter<T>, epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let m = tensor(mean), v = tensor(variance)
        let e = Double(epsilon)
        return .init(program.add(T.bnnsDataType, [node, m.node, v.node]) { x in
            let r = x[0].rank
            let centered = _GraphOps.zip(x[0], _GraphOps.channelwise(x[1], rank: r), -)
            return _GraphOps.zip(centered, _GraphOps.channelwise(x[2], rank: r)) { $0 / ($1 + e).squareRoot() }
        }, program)
    }

    /// Normalizes across the channels (axis 1) at each position.
    public func channelNorm(weight: some BNNSGraph.Builder.OperationParameter<T>, bias: some BNNSGraph.Builder.OperationParameter<T>, epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        normalized(axes: { _ in [1] }, epsilon: epsilon, weight: tensor(weight), bias: tensor(bias), perChannel: true)
    }

    public func channelNorm(epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        normalized(axes: { _ in [1] }, epsilon: epsilon, weight: nil, bias: nil, perChannel: true)
    }

    /// Normalizes each channel of each item over its spatial axes.
    public func instanceNorm(weight: some BNNSGraph.Builder.OperationParameter<T>, bias: some BNNSGraph.Builder.OperationParameter<T>, epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        normalized(axes: { Array(2..<Swift.max($0, 2)) }, epsilon: epsilon, weight: tensor(weight), bias: tensor(bias), perChannel: true)
    }

    public func instanceNorm(epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        normalized(axes: { Array(2..<Swift.max($0, 2)) }, epsilon: epsilon, weight: nil, bias: nil, perChannel: true)
    }

    public func layerNorm(weight: some BNNSGraph.Builder.OperationParameter<T>, bias: some BNNSGraph.Builder.OperationParameter<T>, axes: [Swift::Int], epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        normalized(axes: { _ in axes }, epsilon: epsilon, weight: tensor(weight), bias: tensor(bias), perChannel: false)
    }

    public func layerNorm(axes: [Swift::Int], epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        normalized(axes: { _ in axes }, epsilon: epsilon, weight: nil, bias: nil, perChannel: false)
    }

    /// x / sqrt(Σx² + ε) over all axes but the first.
    public func l2Norm(epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let e = Double(epsilon)
        return unary { x in
            let axes = x.rank > 1 ? Array(1..<x.rank) : [0]
            let norms = _GraphOps.reduce(x, axes: axes, keep: true) { ($0.reduce(0) { $0 + $1 * $1 } + e).squareRoot() }
            return _GraphOps.zip(x, norms, /)
        }
    }

    /// x / sqrt(mean(x²) + ε) · scale over the last axis.
    public func rmsNorm(scale: some BNNSGraph.Builder.OperationParameter<T>, epsilon: Swift::Float = .ulpOfOne.squareRoot()) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let e = Double(epsilon)
        return binary(tensor(scale)) { x, s in
            let rms = _GraphOps.reduce(x, axes: [x.rank - 1], keep: true) { ($0.reduce(0) { $0 + $1 * $1 } / Double(Swift.max($0.count, 1)) + e).squareRoot() }
            return _GraphOps.zip(_GraphOps.zip(x, rms, /), s, *)
        }
    }

    func normalized(axes: @escaping (Int) -> [Int], epsilon: Float, weight: BNNSGraph.Builder.Tensor<T>?, bias: BNNSGraph.Builder.Tensor<T>?,
                    perChannel: Bool) -> BNNSGraph.Builder.Tensor<T> {
        let e = Double(epsilon)
        let inputs = [node] + [weight?.node, bias?.node].compactMap { $0 }
        let hasWeight = weight != nil, hasBias = bias != nil
        return .init(program.add(T.bnnsDataType, inputs) { x in
            let rank = x[0].rank
            let axisList = axes(rank).map { _GraphOps.axis($0, rank) }
            var y = _GraphOps.normalize(x[0], axes: axisList, epsilon: e)
            func shaped(_ v: _GraphValue) -> _GraphValue {
                if perChannel { return v.count == 1 ? v : _GraphOps.channelwise(v, rank: rank) }
                var shape = Array(repeating: 1, count: rank)
                for a in axisList where v.count != 1 { shape[a] = x[0].shape[a] }
                return v.count == shape.reduce(1, *) ? v.reshaped(shape) : v
            }
            var next = 1
            if hasWeight { y = _GraphOps.zip(y, shaped(x[next]), *); next += 1 }
            if hasBias { y = _GraphOps.zip(y, shaped(x[next]), +) }
            return y
        }, program)
    }

    public func pooling(_ function: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::PoolingFunction, kernelSize: [Swift::Int], strides: [Swift::Int], padding: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::PoolingPadding, ceilingMode: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::CeilingMode) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let code: Int
        switch function {
        case .max: code = 0
        case let .average(includePadding): code = includePadding ? 1 : 2
        case .l2Norm: code = 3
        }
        return unary { _GraphOps.pool($0, function: code, kernel: kernelSize, strides: strides, padding: padding, ceiling: ceilingMode == .ceiling) }
    }
}

// MARK: - Shapes and indexing

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor {
    /// Pads the last padding.count / 2 axes, padding giving each one's
    /// before and after counts in turn.
    public func pad(_ type: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Padding, padding: [Swift::Int]) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let (mode, constant): (Int, Double)
        switch type {
        case let .constant(value): (mode, constant) = (0, Double(value))
        case .reflection: (mode, constant) = (1, 0)
        case .replication: (mode, constant) = (2, 0)
        }
        return unary { v in
            let padded = padding.count / 2
            var pads = Array(repeating: (0, 0), count: v.rank)
            for i in 0..<Swift.min(padded, v.rank) {
                pads[v.rank - padded + i] = (padding[2 * i], padding[2 * i + 1])
            }
            return _GraphOps.pad(v, pads, mode: mode, constant: constant)
        }
    }

    public func tensorShape() -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Int32> {
        indices(as: Int32.self) { _GraphValue(shape: [$0.rank], data: $0.shape.map { Double($0) }) }
    }

    public func reshape(to shape: some BNNSGraph.Builder.OperationParameter<Int32>) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let s = shape.graphBuilderTensor(builder)
        return binary(s) { v, s in v.reshaped(_resolvedShape(s.data.map { Int($0) }, v)) }
    }

    /// A shape of the value's element count: -1 for the dimension left
    /// over, 0 for the value's own.
    public func reshape(to shape: [Swift::Int]) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        unary { $0.reshaped(_resolvedShape(shape, $0)) }
    }

    public func transpose(axes: [Swift::Int]) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        unary { v in _GraphOps.transpose(v, axes.count == v.rank ? axes.map { _GraphOps.axis($0, v.rank) } : Array((0..<v.rank).reversed())) }
    }

    public func gather(indices: some BNNSGraph.Builder.OperationParameter<Int32>, axis: Swift::Int, batchDimensionCount: Swift::Int) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        binary(indices.graphBuilderTensor(builder)) { _gather($0, $1, axis: axis, batchDimensions: batchDimensionCount) }
    }

    public func gatherAlongAxis(indices: some BNNSGraph.Builder.OperationParameter<Int32>, axis: Swift::Int) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        binary(indices.graphBuilderTensor(builder)) { v, i in
            let a = _GraphOps.axis(axis, v.rank)
            var result = _GraphValue(zeros: i.shape)
            var o = 0
            _GraphOps.forEachIndex(i.shape) { index in
                var source = index
                source[a] = _wrap(Int(i.data[o]), v.shape[a])
                result.data[o] = v[source]
                o += 1
            }
            return result
        }
    }

    public func gatherND(indices: some BNNSGraph.Builder.OperationParameter<Int32>, batchDimensionCount: Swift::Int) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        binary(indices.graphBuilderTensor(builder)) { _gatherND($0, $1, batchDimensions: batchDimensionCount) }
    }

    public func scatter(updates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, indices: some BNNSGraph.Builder.OperationParameter<Int32>, mode: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::ScatterMode, axis: Swift::Int) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let i = indices.graphBuilderTensor(builder)
        return .init(program.add(T.bnnsDataType, [node, updates.node, i.node]) { v in
            var result = v[0]
            let a = _GraphOps.axis(axis, result.rank)
            let u = v[1], idx = v[2]
            var o = 0
            _GraphOps.forEachIndex(u.shape) { index in
                var target = index
                let n = idx.count == u.shape[a] ? Int(idx.data[index[a]]) : Int(idx.data[Swift.min(o, idx.count - 1)])
                target[a] = _wrap(n, result.shape[a])
                result[target] = _scatterCombine(mode, result[target], u.data[o])
                o += 1
            }
            return result
        }, program)
    }

    public func scatterAlongAxis(updates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, indices: some BNNSGraph.Builder.OperationParameter<Int32>, mode: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::ScatterMode, axis: Swift::Int) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let i = indices.graphBuilderTensor(builder)
        return .init(program.add(T.bnnsDataType, [node, updates.node, i.node]) { v in
            var result = v[0]
            let a = _GraphOps.axis(axis, result.rank)
            var o = 0
            _GraphOps.forEachIndex(v[2].shape) { index in
                var target = index
                target[a] = _wrap(Int(v[2].data[o]), result.shape[a])
                result[target] = _scatterCombine(mode, result[target], v[1].data[Swift.min(o, v[1].count - 1)])
                o += 1
            }
            return result
        }, program)
    }

    public func scatterND(updates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, indices: some BNNSGraph.Builder.OperationParameter<Int32>, mode: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::ScatterMode) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        let i = indices.graphBuilderTensor(builder)
        return .init(program.add(T.bnnsDataType, [node, updates.node, i.node]) { v in
            var result = v[0]
            let idx = v[2]
            let depth = idx.shape.last ?? 1
            let points = idx.count / Swift.max(depth, 1)
            let sliceShape = Array(result.shape.dropFirst(depth))
            let sliceCount = sliceShape.reduce(1, *)
            let st = _GraphOps.strides(result.shape)
            for p in 0..<points {
                var base = 0
                for d in 0..<depth { base += _wrap(Int(idx.data[p * depth + d]), result.shape[d]) * st[d] }
                for s in 0..<sliceCount {
                    let u = v[1].data[Swift.min(p * sliceCount + s, v[1].count - 1)]
                    result.data[base + s] = _scatterCombine(mode, result.data[base + s], u)
                }
            }
            return result
        }, program)
    }

    /// Slices: an Int picks (and drops) a dimension, ranges keep part of it.
    public subscript(ranges: any Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SliceIndex...) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> {
        get {
            unary { v in
                let s = _slicing(ranges, v.shape)
                return _GraphOps.slice(v, start: s.start, count: s.count, step: Array(repeating: 1, count: v.rank)).reshaped(s.resultShape)
            }
        }
        set {
            let update = newValue
            self = binary(update) { v, u in
                let s = _slicing(ranges, v.shape)
                var result = v
                let source = _GraphOps.broadcast(u.reshaped(u.count == s.count.reduce(1, *) ? s.count : u.shape), to: s.count)
                var o = 0
                _GraphOps.forEachIndex(s.count) { index in
                    result[zip(index, s.start).map { $0 + $1 }] = source.data[o]
                    o += 1
                }
                return result
            }
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder {
    public func concatenate<T>(_ tensors: [Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>], axis: Swift::Int) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T> where T: Accelerate::BNNSScalar {
        .init(program.add(T.bnnsDataType, tensors.map { $0.node }) { _GraphOps.concatenate($0, axis: axis) }, program)
    }
}

func _wrap(_ i: Int, _ n: Int) -> Int {
    guard n > 0 else { return 0 }
    let r = i < 0 ? i + n : i
    return Swift.min(Swift.max(r, 0), n - 1)
}

func _resolvedShape(_ shape: [Int], _ v: _GraphValue) -> [Int] {
    var shape = shape.enumerated().map { $0.element == 0 && $0.offset < v.rank ? v.shape[$0.offset] : $0.element }
    if let unknown = shape.firstIndex(of: -1) {
        let known = shape.enumerated().filter { $0.offset != unknown }.reduce(1) { $0 * $1.element }
        shape[unknown] = known == 0 ? 0 : v.count / known
    }
    return shape
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
func _scatterCombine(_ mode: BNNSGraph.Builder.ScatterMode, _ old: Double, _ new: Double) -> Double {
    switch mode {
    case .update: return new
    case .add: return old + new
    case .subtract: return old - new
    case .multiply: return old * new
    case .divide: return old / new
    case .maximum: return Swift.max(old, new)
    case .minimum: return Swift.min(old, new)
    }
}

/// NumPy's take along an axis, the first batchDimensions axes shared by the
/// value and the indices.
func _gather(_ v: _GraphValue, _ indices: _GraphValue, axis: Int, batchDimensions b: Int) -> _GraphValue {
    let a = _GraphOps.axis(axis, v.rank)
    let b = Swift.min(Swift.max(b, 0), a)
    let outShape = Array(v.shape[0..<a]) + Array(indices.shape[b...]) + Array(v.shape[(a + 1)...])
    var result = _GraphValue(zeros: outShape)
    let ist = _GraphOps.strides(indices.shape)
    var o = 0
    _GraphOps.forEachIndex(outShape) { index in
        let batch = Array(index[0..<b])
        let middle = Array(index[a..<(a + indices.rank - b)])
        var source = Array(index[0..<a])
        let n = _GraphOps.offset(batch + middle, ist)
        source.append(_wrap(Int(indices.data[n]), v.shape[a]))
        source += Array(index[(a + indices.rank - b)...])
        result.data[o] = v[source]
        o += 1
    }
    return result
}

func _gatherND(_ v: _GraphValue, _ indices: _GraphValue, batchDimensions b: Int) -> _GraphValue {
    let depth = indices.shape.last ?? 1
    let points = Array(indices.shape.dropLast())
    let b = Swift.max(b, 0)
    let sliceShape = Array(v.shape[Swift.min(b + depth, v.rank)...])
    let outShape = points + sliceShape
    var result = _GraphValue(zeros: outShape)
    let st = _GraphOps.strides(v.shape)
    let sliceCount = sliceShape.reduce(1, *)
    let pointCount = points.reduce(1, *)
    let batchStrides = _GraphOps.strides(Array(points.prefix(b)))
    for p in 0..<pointCount {
        var base = 0
        // Shared batch axes come from the point's own position.
        var rest = p / Swift.max(points.dropFirst(b).reduce(1, *), 1)
        for d in 0..<b {
            let i = rest / batchStrides[d]
            rest %= batchStrides[d]
            base += i * st[d]
        }
        for d in 0..<depth where b + d < v.rank {
            base += _wrap(Int(indices.data[p * depth + d]), v.shape[b + d]) * st[b + d]
        }
        for s in 0..<sliceCount { result.data[p * sliceCount + s] = v.data[base + s] }
    }
    return result
}

/// Where a slice starts, its extent and the shape the subscript returns.
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
func _slicing(_ ranges: [any BNNSGraph.Builder.SliceIndex], _ shape: [Int]) -> (start: [Int], count: [Int], resultShape: [Int]) {
    var start = Array(repeating: 0, count: shape.count)
    var count = shape
    var dropped = Set<Int>()
    for (d, r) in ranges.enumerated() where d < shape.count {
        let n = shape[d]
        func clamp(_ i: Int) -> Int { Swift.min(Swift.max(i < 0 ? i + n : i, 0), n) }
        var lower = 0, upper = n
        switch r {
        case let i as Int:
            lower = _wrap(i, n); upper = lower + 1
            dropped.insert(d)
        case let r as Range<Int>: lower = clamp(r.lowerBound); upper = clamp(r.upperBound)
        case let r as ClosedRange<Int>: lower = clamp(r.lowerBound); upper = clamp(r.upperBound + 1)
        case let r as PartialRangeFrom<Int>: lower = clamp(r.lowerBound)
        case let r as PartialRangeThrough<Int>: upper = clamp(r.upperBound + 1)
        case let r as PartialRangeUpTo<Int>: upper = clamp(r.upperBound)
        case let r as BNNSGraph.Builder.SliceRange:
            lower = clamp(r.startIndex)
            upper = r.endIndex == Int.max ? n : clamp(r.endIndex)
        default: break
        }
        start[d] = lower
        count[d] = Swift.max(upper - lower, 0)
    }
    let resultShape = count.enumerated().filter { !dropped.contains($0.offset) }.map { $0.element }
    return (start, count, resultShape)
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder {
    public protocol SliceIndex {
    }

    public struct SliceRange: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SliceIndex, Swift::Equatable, Swift::Sendable {
        public let startIndex: Swift::Int
        public let endIndex: Swift::Int
        /// The whole dimension.
        public static let fillAll: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SliceRange = SliceRange(startIndex: 0, endIndex: Int.max)
        public init(startIndex: Swift::Int = 0, endIndex: Swift::Int) {
            self.startIndex = startIndex
            self.endIndex = endIndex
        }
        public static func == (a: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SliceRange, b: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SliceRange) -> Swift::Bool {
            a.startIndex == b.startIndex && a.endIndex == b.endIndex
        }
    }

    public enum ScatterMode: Swift::Hashable, Swift::Sendable {
        case update
        case add
        case subtract
        case multiply
        case divide
        case maximum
        case minimum
    }

    public enum Direction: Swift::Hashable, Swift::Sendable {
        case forward
        case reverse
    }

    public enum Activation: Swift::Hashable, Swift::Sendable {
        case hardSigmoid
        case linear
        case relu
        case scaledTanh
        case sigmoid
        case tanh
    }

    public enum SortOrder: Swift::Hashable, Swift::Sendable {
        case ascending
        case descending
    }

    public enum PoolingFunction: Swift::Hashable, Swift::Sendable {
        case average(includePadding: Swift::Bool)
        case l2Norm
        case max
    }

    public enum CeilingMode: Swift::Hashable, Swift::Sendable {
        case floor
        case ceiling
    }

    public enum Padding: Swift::Hashable, Swift::Sendable {
        case constant(value: Swift::Float)
        case reflection
        case replication
    }

    public typealias PoolingPadding = Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::ConvolutionPadding

    public enum ConvolutionPadding: Swift::Hashable, Swift::Sendable {
        case valid
        case custom(padding: [Swift::Int])
        case same
        case lower
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::Range: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SliceIndex where Bound == Swift::Int {
}
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::ClosedRange: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SliceIndex where Bound == Swift::Int {
}
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::PartialRangeFrom: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SliceIndex where Bound == Swift::Int {
}
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::PartialRangeThrough: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SliceIndex where Bound == Swift::Int {
}
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::PartialRangeUpTo: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SliceIndex where Bound == Swift::Int {
}
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::Int: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::SliceIndex {
}

// MARK: - Recurrent layers

/// One direction of an RNN over x [sequence, batch, input]: per step, the
/// gates (gateCount × hidden) of W·x + R·h + b, combined by step.
private func _recurrent(_ x: _GraphValue, h0: _GraphValue, c0: _GraphValue?, w: _GraphValue, r: _GraphValue, bias: _GraphValue, inputBias: _GraphValue?,
                        hidden: Int, reverse: Bool,
                        step: (_ gatesX: [Double], _ gatesH: [Double], _ h: inout [Double], _ c: inout [Double]) -> Void)
    -> (outputs: [[Double]], h: [Double], c: [Double]) {
    let steps = x.shape[0], batch = x.shape[1], inputs = x.shape[2]
    let gates = w.shape[0]
    var h = h0.data, c = c0?.data ?? Array(repeating: 0, count: batch * hidden)
    var outputs = Array(repeating: [Double](), count: steps)
    for s in 0..<steps {
        let t = reverse ? steps - 1 - s : s
        var newH = [Double](), newC = [Double]()
        for b in 0..<batch {
            var gx = [Double](repeating: 0, count: gates), gh = [Double](repeating: 0, count: gates)
            for g in 0..<gates {
                var sx = g < bias.count ? bias.data[g] : 0
                for i in 0..<inputs { sx += w.data[g * inputs + i] * x.data[(t * batch + b) * inputs + i] }
                var sh = inputBias.map { g < $0.count ? $0.data[g] : 0 } ?? 0
                for j in 0..<hidden { sh += r.data[g * hidden + j] * h[b * hidden + j] }
                gx[g] = sx
                gh[g] = sh
            }
            var hb = Array(h[(b * hidden)..<((b + 1) * hidden)])
            var cb = Array(c[(b * hidden)..<((b + 1) * hidden)])
            step(gx, gh, &hb, &cb)
            newH += hb
            newC += cb
        }
        h = newH
        c = newC
        outputs[t] = h
    }
    return (outputs, h, c)
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor {
    /// The sequence's output ([sequence or 1, batch, hidden]) and final hidden state.
    func sequence(_ outputs: [[Double]], _ steps: Int, _ batch: Int, _ hidden: Int, reverse: Bool, all: Bool) -> _GraphValue {
        if all { return _GraphValue(shape: [steps, batch, hidden], data: outputs.flatMap { $0 }) }
        let last = reverse ? outputs.first ?? [] : outputs.last ?? []
        return _GraphValue(shape: [1, batch, hidden], data: last)
    }

    public func rnn(initialHiddenStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, inputHiddenWeight: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, hiddenHiddenWeight: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, bias: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, direction: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Direction, activation: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Activation, outputSequence: Swift::Bool) -> (output: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, hiddenStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>) {
        let inputs = [node, initialHiddenStates.node, inputHiddenWeight.node, hiddenHiddenWeight.node, bias.node]
        func run(_ v: [_GraphValue]) -> (_GraphValue, _GraphValue) {
            let hidden = v[2].shape[0], batch = v[0].shape[1], steps = v[0].shape[0]
            let reverse = direction == .reverse
            let r = _recurrent(v[0], h0: v[1], c0: nil, w: v[2], r: v[3], bias: v[4], inputBias: nil, hidden: hidden, reverse: reverse) { gx, gh, h, _ in
                for j in 0..<hidden { h[j] = _GraphOps.activation(activation, gx[j] + gh[j]) }
            }
            return (sequence(r.outputs, steps, batch, hidden, reverse: reverse, all: outputSequence), _GraphValue(shape: [batch, hidden], data: r.h))
        }
        return (.init(program.add(T.bnnsDataType, inputs) { run($0).0 }, program),
                .init(program.add(T.bnnsDataType, inputs) { run($0).1 }, program))
    }

    /// Gates in the order update (z), reset (r), new (n).
    public func gru(initialHiddenStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, inputHiddenWeight: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, hiddenHiddenWeight: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, bias: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, inputBias: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, direction: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Direction, activation: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Activation, recurrentActivation: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Activation, applyResetGateAfterMatMul: Swift::Bool, outputSequence: Swift::Bool) -> (output: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, hiddenStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>) {
        let inputs = [node, initialHiddenStates.node, inputHiddenWeight.node, hiddenHiddenWeight.node, bias.node, inputBias.node]
        func run(_ v: [_GraphValue]) -> (_GraphValue, _GraphValue) {
            let hidden = v[2].shape[0] / 3, batch = v[0].shape[1], steps = v[0].shape[0]
            let reverse = direction == .reverse
            let rWeights = v[3]
            let r = _recurrent(v[0], h0: v[1], c0: nil, w: v[2], r: rWeights, bias: v[4], inputBias: v[5], hidden: hidden, reverse: reverse) { gx, gh, h, _ in
                var next = h
                for j in 0..<hidden {
                    let z = _GraphOps.activation(recurrentActivation, gx[j] + gh[j])
                    let rg = _GraphOps.activation(recurrentActivation, gx[hidden + j] + gh[hidden + j])
                    let candidate: Double
                    if applyResetGateAfterMatMul {
                        candidate = gx[2 * hidden + j] + rg * gh[2 * hidden + j]
                    } else {
                        // Reset applied to h before its product with the weights.
                        var s = v[5].count > 2 * hidden + j ? v[5].data[2 * hidden + j] : 0
                        for k in 0..<hidden { s += rWeights.data[(2 * hidden + j) * hidden + k] * h[k] * rg }
                        candidate = gx[2 * hidden + j] + s
                    }
                    let n = _GraphOps.activation(activation, candidate)
                    next[j] = (1 - z) * n + z * h[j]
                }
                h = next
            }
            return (sequence(r.outputs, steps, batch, hidden, reverse: reverse, all: outputSequence), _GraphValue(shape: [batch, hidden], data: r.h))
        }
        return (.init(program.add(T.bnnsDataType, inputs) { run($0).0 }, program),
                .init(program.add(T.bnnsDataType, inputs) { run($0).1 }, program))
    }

    /// Gates in the order input, forget, output, cell.
    public func lstm(initialHiddenStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, initialCellStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, inputHiddenWeight: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, hiddenHiddenWeight: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, bias: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, direction: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Direction, activation: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Activation, recurrentActivation: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Activation, cellActivation: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Activation, outputSequence: Swift::Bool) -> (output: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, hiddenStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, memoryStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>) {
        let inputs = [node, initialHiddenStates.node, initialCellStates.node, inputHiddenWeight.node, hiddenHiddenWeight.node, bias.node]
        func run(_ v: [_GraphValue]) -> (_GraphValue, _GraphValue, _GraphValue) {
            let result = _lstm(v[0], h0: v[1], c0: v[2], w: v[3], r: v[4], bias: v[5], reverse: direction == .reverse,
                               activation: activation, recurrent: recurrentActivation, cell: cellActivation)
            let hidden = v[3].shape[0] / 4, batch = v[0].shape[1], steps = v[0].shape[0]
            return (sequence(result.outputs, steps, batch, hidden, reverse: direction == .reverse, all: outputSequence),
                    _GraphValue(shape: [batch, hidden], data: result.h), _GraphValue(shape: [batch, hidden], data: result.c))
        }
        return (.init(program.add(T.bnnsDataType, inputs) { run($0).0 }, program),
                .init(program.add(T.bnnsDataType, inputs) { run($0).1 }, program),
                .init(program.add(T.bnnsDataType, inputs) { run($0).2 }, program))
    }

    /// A forward and a reverse LSTM, their outputs and states side by side
    /// ([..., 2 × hidden]); the initial states hold both directions'.
    public func bidirectionalLSTM(initialHiddenStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, initialCellStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, inputHiddenWeight: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, hiddenHiddenWeight: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, bias: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, inputHiddenWeightBack: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, hiddenHiddenWeightBack: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, biasBack: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, activation: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Activation, recurrentActivation: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Activation, cellActivation: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Activation, outputSequence: Swift::Bool) -> (output: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, hiddenStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>, memoryStates: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<T>) {
        let inputs = [node, initialHiddenStates.node, initialCellStates.node, inputHiddenWeight.node, hiddenHiddenWeight.node, bias.node,
                      inputHiddenWeightBack.node, hiddenHiddenWeightBack.node, biasBack.node]
        func run(_ v: [_GraphValue]) -> (_GraphValue, _GraphValue, _GraphValue) {
            let hidden = v[3].shape[0] / 4, batch = v[0].shape[1], steps = v[0].shape[0]
            func half(_ s: _GraphValue, _ second: Bool) -> _GraphValue {
                guard s.count == batch * 2 * hidden else { return s }
                var data = [Double]()
                for b in 0..<batch {
                    let base = b * 2 * hidden + (second ? hidden : 0)
                    data += s.data[base..<(base + hidden)]
                }
                return _GraphValue(shape: [batch, hidden], data: data)
            }
            let f = _lstm(v[0], h0: half(v[1], false), c0: half(v[2], false), w: v[3], r: v[4], bias: v[5], reverse: false,
                          activation: activation, recurrent: recurrentActivation, cell: cellActivation)
            let b = _lstm(v[0], h0: half(v[1], true), c0: half(v[2], true), w: v[6], r: v[7], bias: v[8], reverse: true,
                          activation: activation, recurrent: recurrentActivation, cell: cellActivation)
            func join(_ x: [Double], _ y: [Double]) -> [Double] {
                var data = [Double]()
                for i in 0..<batch { data += x[(i * hidden)..<((i + 1) * hidden)] + y[(i * hidden)..<((i + 1) * hidden)] }
                return data
            }
            let output: _GraphValue
            if outputSequence {
                output = _GraphValue(shape: [steps, batch, 2 * hidden], data: (0..<steps).flatMap { join(f.outputs[$0], b.outputs[$0]) })
            } else {
                output = _GraphValue(shape: [1, batch, 2 * hidden], data: join(f.outputs.last ?? f.h, b.outputs.first ?? b.h))
            }
            return (output, _GraphValue(shape: [batch, 2 * hidden], data: join(f.h, b.h)), _GraphValue(shape: [batch, 2 * hidden], data: join(f.c, b.c)))
        }
        return (.init(program.add(T.bnnsDataType, inputs) { run($0).0 }, program),
                .init(program.add(T.bnnsDataType, inputs) { run($0).1 }, program),
                .init(program.add(T.bnnsDataType, inputs) { run($0).2 }, program))
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
private func _lstm(_ x: _GraphValue, h0: _GraphValue, c0: _GraphValue, w: _GraphValue, r: _GraphValue, bias: _GraphValue, reverse: Bool,
                   activation: BNNSGraph.Builder.Activation, recurrent: BNNSGraph.Builder.Activation, cell: BNNSGraph.Builder.Activation)
    -> (outputs: [[Double]], h: [Double], c: [Double]) {
    let hidden = w.shape[0] / 4
    return _recurrent(x, h0: h0, c0: c0, w: w, r: r, bias: bias, inputBias: nil, hidden: hidden, reverse: reverse) { gx, gh, h, c in
        for j in 0..<hidden {
            let i = _GraphOps.activation(recurrent, gx[j] + gh[j])
            let f = _GraphOps.activation(recurrent, gx[hidden + j] + gh[hidden + j])
            let o = _GraphOps.activation(recurrent, gx[2 * hidden + j] + gh[2 * hidden + j])
            let g = _GraphOps.activation(cell, gx[3 * hidden + j] + gh[3 * hidden + j])
            c[j] = f * c[j] + i * g
            h[j] = o * _GraphOps.activation(activation, c[j])
        }
    }
}

// MARK: - vImage

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::vImage.Accelerate::PixelBuffer where Format: Accelerate::StaticPixelFormat, Format.ComponentType: Accelerate::BNNSScalar {
    /// The pixels as a [height, width, channels] tensor over the buffer.
    public func withBNNSTensor<R>(_ body: (Accelerate::BNNSTensor) throws -> R) rethrows -> R {
        try withUnsafeVImageBuffer { buffer in
            let channels = Format.channelCount
            let component = MemoryLayout<Format.ComponentType>.stride
            let tensor = _makeTensor(type: Format.ComponentType.bnnsDataType,
                                     shape: [Int(buffer.height), Int(buffer.width), channels],
                                     stride: [buffer.rowBytes / component, channels, 1],
                                     data: buffer.data, size: buffer.rowBytes * Int(buffer.height))
            return try body(tensor)
        }
    }
}
