// Element subscripts on GLKit's vector, matrix and quaternion unions, which
// Swift imports as structs of their storage: each is that many Floats in a
// row, read at the index's offset.

@inlinable @inline(__always)
public func _indexHomogeneousValue<TTT, T>(_ aggregate: UnsafePointer<TTT>, _ index: Int) -> T {
    UnsafeRawPointer(aggregate).load(fromByteOffset: index * MemoryLayout<T>.stride, as: T.self)
}

extension _GLKMatrix2 {
    @inlinable public subscript(i: Int) -> Float {
        @inline(__always) get {
            precondition(i >= 0, "Negative GLKMatrix2 index out of range")
            precondition(i < 4, "GLKMatrix2 index out of range")
            var copy = self
            return _indexHomogeneousValue(&copy, i)
        }
    }
}

extension _GLKVector2 {
    @inlinable public subscript(i: Int) -> Float {
        @inline(__always) get {
            precondition(i >= 0, "Negative GLKVector2 index out of range")
            precondition(i < 2, "GLKVector2 index out of range")
            var copy = self
            return _indexHomogeneousValue(&copy, i)
        }
    }
}

extension _GLKMatrix3 {
    @inlinable public subscript(i: Int) -> Float {
        @inline(__always) get {
            precondition(i >= 0, "Negative GLKMatrix3 index out of range")
            precondition(i < 9, "GLKMatrix3 index out of range")
            var copy = self
            return _indexHomogeneousValue(&copy, i)
        }
    }
}

extension _GLKVector3 {
    @inlinable public subscript(i: Int) -> Float {
        @inline(__always) get {
            precondition(i >= 0, "Negative GLKVector3 index out of range")
            precondition(i < 3, "GLKVector3 index out of range")
            var copy = self
            return _indexHomogeneousValue(&copy, i)
        }
    }
}

extension _GLKMatrix4 {
    @inlinable public subscript(i: Int) -> Float {
        @inline(__always) get {
            precondition(i >= 0, "Negative GLKMatrix4 index out of range")
            precondition(i < 16, "GLKMatrix4 index out of range")
            var copy = self
            return _indexHomogeneousValue(&copy, i)
        }
    }
}

extension _GLKVector4 {
    @inlinable public subscript(i: Int) -> Float {
        @inline(__always) get {
            precondition(i >= 0, "Negative GLKVector4 index out of range")
            precondition(i < 4, "GLKVector4 index out of range")
            var copy = self
            return _indexHomogeneousValue(&copy, i)
        }
    }
}

extension _GLKQuaternion {
    @inlinable public subscript(i: Int) -> Float {
        @inline(__always) get {
            precondition(i >= 0, "Negative GLKQuaternion index out of range")
            precondition(i < 4, "GLKQuaternion index out of range")
            var copy = self
            return _indexHomogeneousValue(&copy, i)
        }
    }
}
