import Swift
import Darwin

// The tensors BNNSGraph.Builder's graphs compute with: row-major arrays of
// Double with a shape, and the operations on them. Perry builds a graph a
// program of these (the SDK's builder hands it to private BNNS entry points
// no header declares) and runs it when its context executes.

struct _GraphValue {
    var shape: [Int]
    var data: [Double]

    init(shape: [Int], data: [Double]) {
        self.shape = shape
        self.data = data
    }

    init(zeros shape: [Int]) {
        self.shape = shape
        data = Array(repeating: 0, count: shape.reduce(1, *))
    }

    init(scalar: Double) {
        shape = []
        data = [scalar]
    }

    var rank: Int { shape.count }
    var count: Int { data.count }

    func reshaped(_ shape: [Int]) -> _GraphValue {
        _GraphValue(shape: shape, data: data)
    }

    func map(_ f: (Double) -> Double) -> _GraphValue {
        _GraphValue(shape: shape, data: data.map(f))
    }

    /// The value at a multi-index.
    subscript(_ index: [Int]) -> Double {
        get { data[_GraphOps.offset(index, _GraphOps.strides(shape))] }
        set { data[_GraphOps.offset(index, _GraphOps.strides(shape))] = newValue }
    }
}

enum _GraphOps {
    static func strides(_ shape: [Int]) -> [Int] {
        var result = Array(repeating: 1, count: shape.count)
        var s = 1
        for i in stride(from: shape.count - 1, through: 0, by: -1) {
            result[i] = s
            s *= Swift.max(shape[i], 1)
        }
        return result
    }

    static func offset(_ index: [Int], _ strides: [Int]) -> Int {
        var o = 0
        for i in 0..<index.count { o += index[i] * strides[i] }
        return o
    }

    /// Calls body with each multi-index of a shape, in row-major order.
    static func forEachIndex(_ shape: [Int], _ body: ([Int]) -> Void) {
        let count = shape.reduce(1, *)
        guard count > 0 else { return }
        var index = Array(repeating: 0, count: shape.count)
        for _ in 0..<count {
            body(index)
            var d = shape.count - 1
            while d >= 0 {
                index[d] += 1
                if index[d] < shape[d] { break }
                index[d] = 0
                d -= 1
            }
        }
    }

    static func axis(_ a: Int, _ rank: Int) -> Int {
        let r = a < 0 ? a + rank : a
        return Swift.min(Swift.max(r, 0), Swift.max(rank - 1, 0))
    }

    /// NumPy's broadcasting of two shapes.
    static func broadcastShape(_ a: [Int], _ b: [Int]) -> [Int] {
        let n = Swift.max(a.count, b.count)
        var result = [Int]()
        for i in 0..<n {
            let x = i < n - a.count ? 1 : a[i - (n - a.count)]
            let y = i < n - b.count ? 1 : b[i - (n - b.count)]
            result.append(x == 1 ? y : (y == 1 ? x : Swift.max(x, y)))
        }
        return result
    }

    /// A value repeated out to a shape it broadcasts to.
    static func broadcast(_ v: _GraphValue, to shape: [Int]) -> _GraphValue {
        if v.shape == shape { return v }
        let pad = shape.count - v.rank
        let source = Array(repeating: 1, count: Swift.max(pad, 0)) + v.shape
        let sourceStrides = strides(source)
        var data = [Double]()
        data.reserveCapacity(shape.reduce(1, *))
        forEachIndex(shape) { index in
            var o = 0
            for d in 0..<shape.count where source[d] != 1 {
                o += index[d] * sourceStrides[d]
            }
            data.append(v.data.isEmpty ? 0 : v.data[o])
        }
        return _GraphValue(shape: shape, data: data)
    }

    static func zip(_ a: _GraphValue, _ b: _GraphValue, _ f: (Double, Double) -> Double) -> _GraphValue {
        let shape = broadcastShape(a.shape, b.shape)
        let x = broadcast(a, to: shape), y = broadcast(b, to: shape)
        var data = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count { data[i] = f(x.data[i], y.data[i]) }
        return _GraphValue(shape: shape, data: data)
    }

    static func zip3(_ a: _GraphValue, _ b: _GraphValue, _ c: _GraphValue, _ f: (Double, Double, Double) -> Double) -> _GraphValue {
        let shape = broadcastShape(broadcastShape(a.shape, b.shape), c.shape)
        let x = broadcast(a, to: shape), y = broadcast(b, to: shape), z = broadcast(c, to: shape)
        var data = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count { data[i] = f(x.data[i], y.data[i], z.data[i]) }
        return _GraphValue(shape: shape, data: data)
    }

    /// Reduces the axes (all when empty) with a function of the values.
    static func reduce(_ v: _GraphValue, axes: [Int], keep: Bool, _ f: ([Double]) -> Double) -> _GraphValue {
        let rank = v.rank
        let axes = Set((axes.isEmpty ? Array(0..<rank) : axes).map { axis($0, rank) })
        let outShape = v.shape.enumerated().map { axes.contains($0.offset) ? 1 : $0.element }
        var groups = [[Double]](repeating: [], count: outShape.reduce(1, *))
        let outStrides = strides(outShape)
        var i = 0
        forEachIndex(v.shape) { index in
            var o = 0
            for d in 0..<rank where !axes.contains(d) { o += index[d] * outStrides[d] }
            groups[o].append(v.data[i])
            i += 1
        }
        let data = groups.map(f)
        let shape = keep ? outShape : v.shape.enumerated().filter { !axes.contains($0.offset) }.map { $0.element }
        return _GraphValue(shape: shape, data: data)
    }

    /// The lines of a value along an axis: for each position of the other
    /// axes, the offsets of the line's elements.
    static func lines(_ shape: [Int], axis a: Int) -> [[Int]] {
        let st = strides(shape)
        var outer = shape
        outer[a] = 1
        var result = [[Int]]()
        forEachIndex(outer) { index in
            let base = offset(index, st)
            result.append((0..<shape[a]).map { base + $0 * st[a] })
        }
        return result
    }

    static func transpose(_ v: _GraphValue, _ perm: [Int]) -> _GraphValue {
        let shape = perm.map { v.shape[$0] }
        let st = strides(v.shape)
        var data = [Double]()
        data.reserveCapacity(v.count)
        forEachIndex(shape) { index in
            var o = 0
            for d in 0..<perm.count { o += index[d] * st[perm[d]] }
            data.append(v.data[o])
        }
        return _GraphValue(shape: shape, data: data)
    }

    /// Swaps the last two axes.
    static func transposeLast(_ v: _GraphValue) -> _GraphValue {
        guard v.rank >= 2 else { return v }
        var perm = Array(0..<v.rank)
        perm.swapAt(v.rank - 1, v.rank - 2)
        return transpose(v, perm)
    }

    /// Batched matrix multiplication with broadcast batch dimensions.
    static func matmul(_ a: _GraphValue, _ b: _GraphValue) -> _GraphValue {
        var a = a, b = b
        let aVector = a.rank == 1, bVector = b.rank == 1
        if aVector { a = a.reshaped([1, a.shape[0]]) }
        if bVector { b = b.reshaped([b.shape[0], 1]) }
        let m = a.shape[a.rank - 2], k = a.shape[a.rank - 1], n = b.shape[b.rank - 1]
        let batch = broadcastShape(Array(a.shape.dropLast(2)), Array(b.shape.dropLast(2)))
        let x = broadcast(a, to: batch + [m, k]), y = broadcast(b, to: batch + [k, n])
        let batches = batch.reduce(1, *)
        var data = [Double](repeating: 0, count: batches * m * n)
        for p in 0..<batches {
            let ao = p * m * k, bo = p * k * n, co = p * m * n
            for i in 0..<m {
                for l in 0..<k {
                    let s = x.data[ao + i * k + l]
                    if s == 0 { continue }
                    for j in 0..<n { data[co + i * n + j] += s * y.data[bo + l * n + j] }
                }
            }
        }
        var shape = batch + [m, n]
        if aVector { shape.remove(at: shape.count - 2) }
        if bVector { shape.removeLast() }
        return _GraphValue(shape: shape, data: data)
    }

    static func softmax(_ v: _GraphValue, axis a: Int, log: Bool) -> _GraphValue {
        var result = v
        for line in lines(v.shape, axis: axis(a, v.rank)) {
            let m = line.map { v.data[$0] }.max() ?? 0
            let sum = line.reduce(0.0) { $0 + Darwin.exp(v.data[$1] - m) }
            for o in line {
                result.data[o] = log ? v.data[o] - m - Darwin.log(sum) : Darwin.exp(v.data[o] - m) / sum
            }
        }
        return result
    }

    static func concatenate(_ values: [_GraphValue], axis a: Int) -> _GraphValue {
        guard let first = values.first else { return _GraphValue(zeros: [0]) }
        let a = axis(a, first.rank)
        var shape = first.shape
        shape[a] = values.reduce(0) { $0 + $1.shape[a] }
        var result = _GraphValue(zeros: shape)
        var start = 0
        for v in values {
            var i = 0
            forEachIndex(v.shape) { index in
                var target = index
                target[a] += start
                result[target] = v.data[i]
                i += 1
            }
            start += v.shape[a]
        }
        return result
    }

    /// The elements at start + i * step along each axis.
    static func slice(_ v: _GraphValue, start: [Int], count: [Int], step: [Int]) -> _GraphValue {
        var data = [Double]()
        let st = strides(v.shape)
        forEachIndex(count) { index in
            var o = 0
            for d in 0..<index.count { o += (start[d] + index[d] * step[d]) * st[d] }
            data.append(v.data[o])
        }
        return _GraphValue(shape: count, data: data)
    }

    /// Pads each axis by before/after elements (constant, reflection or
    /// replication).
    static func pad(_ v: _GraphValue, _ pads: [(Int, Int)], mode: Int, constant: Double) -> _GraphValue {
        let shape = v.shape.enumerated().map { $0.element + pads[$0.offset].0 + pads[$0.offset].1 }
        var data = [Double]()
        data.reserveCapacity(shape.reduce(1, *))
        let st = strides(v.shape)
        forEachIndex(shape) { index in
            var o = 0
            var inside = true
            for d in 0..<index.count {
                var s = index[d] - pads[d].0
                let n = v.shape[d]
                if s < 0 || s >= n {
                    switch mode {
                    case 1 where n > 1: // reflection
                        let period = 2 * (n - 1)
                        s = ((s % period) + period) % period
                        if s >= n { s = period - s }
                    case 1, 2: // replication
                        s = Swift.min(Swift.max(s, 0), n - 1)
                    default:
                        inside = false
                    }
                }
                o += s * st[d]
            }
            data.append(inside ? v.data[o] : constant)
        }
        return _GraphValue(shape: shape, data: data)
    }

    /// Before and after padding of a spatial axis for a kernel.
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    static func padding(_ padding: BNNSGraph.Builder.ConvolutionPadding, axis i: Int, input: Int, kernel: Int, stride: Int, dilation: Int,
                        transposed: Bool) -> (Int, Int) {
        let extent = dilation * (kernel - 1) + 1
        switch padding {
        case .valid: return (0, 0)
        case let .custom(values):
            let b = 2 * i < values.count ? values[2 * i] : 0
            let a = 2 * i + 1 < values.count ? values[2 * i + 1] : b
            return (b, a)
        case .same, .lower:
            let total: Int
            if transposed {
                total = Swift.max((input - 1) * stride + extent - input * stride, 0)
            } else {
                let out = (input + stride - 1) / stride
                total = Swift.max((out - 1) * stride + extent - input, 0)
            }
            if case .lower = padding { return ((total + 1) / 2, total / 2) }
            return (total / 2, total - total / 2)
        }
    }

    /// N-dimensional convolution over [N, C, spatial...] with weights
    /// [Cout, Cin / groups, kernel...].
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    static func convolution(_ x: _GraphValue, _ w: _GraphValue, bias: _GraphValue?, strides s: [Int], padding: BNNSGraph.Builder.ConvolutionPadding,
                            dilations: [Int]?, groups: Int) -> _GraphValue {
        let spatial = x.rank - 2
        guard spatial >= 1, w.rank == x.rank else { return x }
        let n = x.shape[0], cin = x.shape[1], cout = w.shape[0]
        let g = Swift.max(groups, 1), cinPerGroup = cin / g, coutPerGroup = Swift.max(cout / g, 1)
        let kernel = Array(w.shape.dropFirst(2))
        let st = (0..<spatial).map { $0 < s.count ? Swift.max(s[$0], 1) : 1 }
        let dil = (0..<spatial).map { i in dilations.map { i < $0.count ? Swift.max($0[i], 1) : 1 } ?? 1 }
        var pads = [(Int, Int)]()
        var outSpatial = [Int]()
        for i in 0..<spatial {
            let p = Self.padding(padding, axis: i, input: x.shape[2 + i], kernel: kernel[i], stride: st[i], dilation: dil[i], transposed: false)
            pads.append(p)
            let extent = dil[i] * (kernel[i] - 1) + 1
            outSpatial.append(Swift.max((x.shape[2 + i] + p.0 + p.1 - extent) / st[i] + 1, 0))
        }
        let outShape = [n, cout] + outSpatial
        var out = _GraphValue(zeros: outShape)
        let xs = strides(x.shape), ws = strides(w.shape)
        var o = 0
        forEachIndex(outShape) { index in
            let b = index[0], co = index[1]
            let group = co / coutPerGroup
            var sum = bias.map { $0.data.count == 1 ? $0.data[0] : $0.data[Swift.min(co, $0.data.count - 1)] } ?? 0
            for ci in 0..<cinPerGroup {
                let c = group * cinPerGroup + ci
                forEachIndex(kernel) { k in
                    var xo = b * xs[0] + c * xs[1]
                    for i in 0..<spatial {
                        let p = index[2 + i] * st[i] - pads[i].0 + k[i] * dil[i]
                        if p < 0 || p >= x.shape[2 + i] { return }
                        xo += p * xs[2 + i]
                    }
                    var wo = co * ws[0] + ci * ws[1]
                    for i in 0..<spatial { wo += k[i] * ws[2 + i] }
                    sum += x.data[xo] * w.data[wo]
                }
            }
            out.data[o] = sum
            o += 1
        }
        return out
    }

    /// Transposed convolution over [N, Cin, spatial...] with weights
    /// [Cin, Cout / groups, kernel...].
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    static func convolutionTranspose(_ x: _GraphValue, _ w: _GraphValue, bias: _GraphValue?, strides s: [Int], padding: BNNSGraph.Builder.ConvolutionPadding,
                                     outputPadding: [Int]?, dilations: [Int]?, groups: Int) -> _GraphValue {
        let spatial = x.rank - 2
        guard spatial >= 1, w.rank == x.rank else { return x }
        let n = x.shape[0], cin = x.shape[1]
        let g = Swift.max(groups, 1), cinPerGroup = Swift.max(cin / g, 1), coutPerGroup = w.shape[1], cout = coutPerGroup * g
        let kernel = Array(w.shape.dropFirst(2))
        let st = (0..<spatial).map { $0 < s.count ? Swift.max(s[$0], 1) : 1 }
        let dil = (0..<spatial).map { i in dilations.map { i < $0.count ? Swift.max($0[i], 1) : 1 } ?? 1 }
        var pads = [(Int, Int)]()
        var outSpatial = [Int]()
        for i in 0..<spatial {
            let p = Self.padding(padding, axis: i, input: x.shape[2 + i], kernel: kernel[i], stride: st[i], dilation: dil[i], transposed: true)
            pads.append(p)
            let extra = outputPadding.map { i < $0.count ? $0[i] : 0 } ?? 0
            outSpatial.append(Swift.max((x.shape[2 + i] - 1) * st[i] + dil[i] * (kernel[i] - 1) + 1 - p.0 - p.1 + extra, 0))
        }
        let outShape = [n, cout] + outSpatial
        var out = _GraphValue(zeros: outShape)
        let os = strides(outShape), ws = strides(w.shape)
        var i = 0
        forEachIndex(x.shape) { index in
            let value = x.data[i]
            i += 1
            let b = index[0], c = index[1], group = c / cinPerGroup
            for co in 0..<coutPerGroup {
                forEachIndex(kernel) { k in
                    var oo = b * os[0] + (group * coutPerGroup + co) * os[1]
                    for d in 0..<spatial {
                        let p = index[2 + d] * st[d] + k[d] * dil[d] - pads[d].0
                        if p < 0 || p >= outSpatial[d] { return }
                        oo += p * os[2 + d]
                    }
                    var wo = c * ws[0] + co * ws[1]
                    for d in 0..<spatial { wo += k[d] * ws[2 + d] }
                    out.data[oo] += value * w.data[wo]
                }
            }
        }
        if let bias {
            var o = 0
            forEachIndex(outShape) { index in
                out.data[o] += bias.data.count == 1 ? bias.data[0] : bias.data[Swift.min(index[1], bias.data.count - 1)]
                o += 1
            }
        }
        return out
    }

    /// Pooling over [N, C, spatial...]: 0 max, 1 average with padding,
    /// 2 average without, 3 L2 norm.
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    static func pool(_ x: _GraphValue, function: Int, kernel: [Int], strides s: [Int], padding: BNNSGraph.Builder.ConvolutionPadding, ceiling: Bool) -> _GraphValue {
        let spatial = x.rank - 2
        guard spatial >= 1 else { return x }
        let k = (0..<spatial).map { $0 < kernel.count ? Swift.max(kernel[$0], 1) : 1 }
        let st = (0..<spatial).map { $0 < s.count ? Swift.max(s[$0], 1) : 1 }
        var pads = [(Int, Int)]()
        var outSpatial = [Int]()
        for i in 0..<spatial {
            let p = Self.padding(padding, axis: i, input: x.shape[2 + i], kernel: k[i], stride: st[i], dilation: 1, transposed: false)
            pads.append(p)
            let span = x.shape[2 + i] + p.0 + p.1 - k[i]
            outSpatial.append(Swift.max((ceiling ? (span + st[i] - 1) / st[i] : span / st[i]) + 1, 0))
        }
        let outShape = Array(x.shape.prefix(2)) + outSpatial
        var out = _GraphValue(zeros: outShape)
        let xs = strides(x.shape)
        var o = 0
        forEachIndex(outShape) { index in
            var best = -Double.infinity, sum = 0.0, count = 0, padded = 0
            forEachIndex(k) { kk in
                var xo = index[0] * xs[0] + index[1] * xs[1]
                var inPadding = false
                for i in 0..<spatial {
                    let p = index[2 + i] * st[i] - pads[i].0 + kk[i]
                    if p < -pads[i].0 || p >= x.shape[2 + i] + pads[i].1 { return }
                    if p < 0 || p >= x.shape[2 + i] { inPadding = true; continue }
                    xo += p * xs[2 + i]
                }
                padded += 1
                if inPadding { return }
                let v = x.data[xo]
                best = Swift.max(best, v)
                sum += function == 3 ? v * v : v
                count += 1
            }
            switch function {
            case 0: out.data[o] = count > 0 ? best : 0
            case 1: out.data[o] = padded > 0 ? sum / Double(padded) : 0
            case 2: out.data[o] = count > 0 ? sum / Double(count) : 0
            default: out.data[o] = sum.squareRoot()
            }
            o += 1
        }
        return out
    }

    /// Values (and their element offsets) along an axis, normalized:
    /// (x - mean) / sqrt(variance + epsilon) over the axes' groups.
    static func normalize(_ x: _GraphValue, axes: [Int], epsilon: Double) -> _GraphValue {
        let rank = x.rank
        let axes = Set(axes.map { axis($0, rank) })
        let keepShape = x.shape.enumerated().map { axes.contains($0.offset) ? 1 : $0.element }
        let ks = strides(keepShape)
        var groups = [[Int]](repeating: [], count: keepShape.reduce(1, *))
        var i = 0
        forEachIndex(x.shape) { index in
            var o = 0
            for d in 0..<rank where !axes.contains(d) { o += index[d] * ks[d] }
            groups[o].append(i)
            i += 1
        }
        var result = x
        for group in groups where !group.isEmpty {
            let mean = group.reduce(0.0) { $0 + x.data[$1] } / Double(group.count)
            let variance = group.reduce(0.0) { $0 + (x.data[$1] - mean) * (x.data[$1] - mean) } / Double(group.count)
            let scale = 1 / (variance + epsilon).squareRoot()
            for o in group { result.data[o] = (x.data[o] - mean) * scale }
        }
        return result
    }

    /// A per-channel (axis 1) value reshaped to broadcast against a rank.
    static func channelwise(_ v: _GraphValue, rank: Int) -> _GraphValue {
        guard rank >= 2 else { return v }
        return v.reshaped([1, v.count] + Array(repeating: 1, count: rank - 2))
    }

    static func erf(_ x: Double) -> Double { Darwin.erf(x) }

    static func sigmoid(_ x: Double) -> Double { 1 / (1 + Darwin.exp(-x)) }

    /// An RNN gate activation.
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    static func activation(_ a: BNNSGraph.Builder.Activation, _ x: Double) -> Double {
        switch a {
        case .hardSigmoid: return Swift.min(Swift.max(0.2 * x + 0.5, 0), 1)
        case .linear: return x
        case .relu: return Swift.max(x, 0)
        case .scaledTanh: return Darwin.tanh(x)
        case .sigmoid: return sigmoid(x)
        case .tanh: return Darwin.tanh(x)
        }
    }

    /// Rounds a value to what a data type can hold.
    static func coerce(_ x: Double, _ type: BNNSDataType) -> Double {
        let raw = type.rawValue
        if raw == 0x100008 { return x != 0 ? 1 : 0 }
        if raw & 0x10000 != 0 {
            switch raw & 0xFFFF {
            case 32: return Double(Float(x))
            default: return x
            }
        }
        if raw & 0x20000 != 0 || raw & 0x40000 != 0 {
            guard x.isFinite else { return 0 }
            let bits = Int(raw & 0xFFFF)
            let t = x.rounded(.towardZero)
            if bits >= 64 { return t }
            let unsigned = raw & 0x40000 != 0
            let lo = unsigned ? 0.0 : -Darwin.pow(2.0, Double(bits - 1))
            let hi = unsigned ? Darwin.pow(2.0, Double(bits)) - 1 : Darwin.pow(2.0, Double(bits - 1)) - 1
            return Swift.min(Swift.max(t, lo), hi)
        }
        return x
    }

    // MARK: Memory

    /// Reads count elements of a data type, at strides, as doubles.
    static func read(_ pointer: UnsafeRawPointer, type: BNNSDataType, shape: [Int], stride: [Int]) -> _GraphValue {
        let size = _bnnsElementSize(type)
        var data = [Double]()
        data.reserveCapacity(shape.reduce(1, *))
        forEachIndex(shape) { index in
            let o = offset(index, stride) * size
            data.append(load(pointer + o, type))
        }
        return _GraphValue(shape: shape, data: data)
    }

    static func write(_ value: _GraphValue, to pointer: UnsafeMutableRawPointer, type: BNNSDataType, stride: [Int]) {
        let size = _bnnsElementSize(type)
        var i = 0
        forEachIndex(value.shape) { index in
            store(value.data[i], pointer + offset(index, stride) * size, type)
            i += 1
        }
    }

    static func load(_ p: UnsafeRawPointer, _ type: BNNSDataType) -> Double {
        switch type.rawValue {
        case 0x10020: return Double(p.loadUnaligned(as: Float.self))
        case 0x10010:
            #if arch(arm64)
            return Double(p.loadUnaligned(as: Float16.self))
            #else
            return Double(_halfToFloat(p.loadUnaligned(as: UInt16.self)))
            #endif
        case 0x18010: return Double(Float(bitPattern: UInt32(p.loadUnaligned(as: UInt16.self)) << 16))
        case 0x20008: return Double(p.loadUnaligned(as: Int8.self))
        case 0x20010: return Double(p.loadUnaligned(as: Int16.self))
        case 0x20020: return Double(p.loadUnaligned(as: Int32.self))
        case 0x20040: return Double(p.loadUnaligned(as: Int64.self))
        case 0x40008, 0x100008: return Double(p.loadUnaligned(as: UInt8.self))
        case 0x40010: return Double(p.loadUnaligned(as: UInt16.self))
        case 0x40020: return Double(p.loadUnaligned(as: UInt32.self))
        case 0x40040: return Double(p.loadUnaligned(as: UInt64.self))
        default: return Double(p.loadUnaligned(as: Float.self))
        }
    }

    static func store(_ x: Double, _ p: UnsafeMutableRawPointer, _ type: BNNSDataType) {
        let v = coerce(x, type)
        switch type.rawValue {
        case 0x10020: p.storeBytes(of: Float(v), as: Float.self)
        case 0x10010:
            #if arch(arm64)
            p.storeBytes(of: Float16(v), as: Float16.self)
            #else
            p.storeBytes(of: _floatToHalf(Float(v)), as: UInt16.self)
            #endif
        case 0x18010: p.storeBytes(of: UInt16(truncatingIfNeeded: Float(v).bitPattern >> 16), as: UInt16.self)
        case 0x20008: p.storeBytes(of: Int8(v), as: Int8.self)
        case 0x20010: p.storeBytes(of: Int16(v), as: Int16.self)
        case 0x20020: p.storeBytes(of: Int32(v), as: Int32.self)
        case 0x20040: p.storeBytes(of: Int64(v), as: Int64.self)
        case 0x40008, 0x100008: p.storeBytes(of: UInt8(v), as: UInt8.self)
        case 0x40010: p.storeBytes(of: UInt16(v), as: UInt16.self)
        case 0x40020: p.storeBytes(of: UInt32(v), as: UInt32.self)
        case 0x40040: p.storeBytes(of: UInt64(v), as: UInt64.self)
        default: p.storeBytes(of: Float(v), as: Float.self)
        }
    }
}

/// IEEE half precision, for x86_64 where Swift has no Float16.
func _halfToFloat(_ h: UInt16) -> Float {
    let sign = UInt32(h >> 15) << 31
    let exponent = Int((h >> 10) & 0x1F)
    let mantissa = UInt32(h & 0x3FF)
    if exponent == 0 {
        let value = Float(mantissa) * Float(sign == 0 ? 1 : -1) / Float(1 << 24)
        return value
    }
    if exponent == 31 {
        return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13))
    }
    return Float(bitPattern: sign | UInt32(exponent - 15 + 127) << 23 | (mantissa << 13))
}

func _floatToHalf(_ f: Float) -> UInt16 {
    let bits = f.bitPattern
    let sign = UInt16((bits >> 16) & 0x8000)
    if f.isNaN { return sign | 0x7E00 }
    let magnitude = Swift.abs(f)
    if magnitude >= 65520 { return sign | 0x7C00 }
    if magnitude < 6.1035156e-05 {
        return sign | UInt16((magnitude * Float(1 << 24)).rounded(.toNearestOrEven))
    }
    let exponent = Int((bits >> 23) & 0xFF) - 127 + 15
    var mantissa = (bits & 0x7F_FFFF) >> 13
    let rest = bits & 0x1FFF
    var e = UInt16(exponent)
    if rest > 0x1000 || (rest == 0x1000 && mantissa & 1 == 1) {
        mantissa += 1
        if mantissa == 0x400 { mantissa = 0; e += 1 }
    }
    return sign | (e << 10) | UInt16(mantissa)
}
