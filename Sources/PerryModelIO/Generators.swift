import Glibc

// The geometry of MDLMesh's generated shapes: boxes, ellipsoids and
// hemispheres, planes, cylinders, cones, capsules and icosahedra, with
// normals and texture coordinates, in the vertex order, index order and
// proportions Model I/O's own give them (an extent is a box's or plane's
// size, but a sphere's or cylinder's radii and a cone's diameters).

/// A generated shape: positions, normals and texture coordinates, indices.
struct Shape {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []
    var geometryType = Geometry.triangles
    /// The names Model I/O gives the mesh, its submesh and its material.
    var name = ""
    var submeshName = ""
    var materialName = "material"

    @discardableResult
    mutating func add(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float>) -> UInt32 {
        positions.append(p)
        normals.append(n)
        uvs.append(uv)
        return UInt32(positions.count - 1)
    }

    /// Normals reversed and triangles wound the other way.
    mutating func turnInward() {
        normals = normals.map { -$0 }
        guard geometryType == Geometry.triangles else { return }
        var i = 0
        while i + 2 < indices.count {
            indices.swapAt(i + 1, i + 2)
            i += 3
        }
    }

    /// Triangles' edges, for a shape asked for as lines.
    mutating func makeLines() {
        guard geometryType == Geometry.triangles else { return }
        var lines: [UInt32] = []
        var i = 0
        while i + 2 < indices.count {
            lines += [indices[i], indices[i + 1], indices[i + 1], indices[i + 2], indices[i + 2], indices[i]]
            i += 3
        }
        indices = lines
        geometryType = Geometry.lines
    }

    /// Lines for a `lines` geometry type; triangles for anything else
    /// a shape doesn't make itself.
    mutating func finish(geometryType requested: Int, inward: Bool) {
        if inward { turnInward() }
        if requested == Geometry.lines { makeLines() }
    }
}

enum Shapes {
    // MARK: Box

    static func box(extent: SIMD3<Float>, segments: SIMD3<UInt32>, inward: Bool, geometryType: Int) -> Shape {
        var shape = Shape(name: "box", submeshName: "box-0", materialName: "box-Material")
        let h = extent / 2
        let s = SIMD3<Int>(Int(max(segments.x, 1)), Int(max(segments.y, 1)), Int(max(segments.z, 1)))
        // Each face: its first corner, the directions of u and v across it,
        // their segment counts, and its normal.
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, Int, Int, SIMD3<Float>)] = [
            (SIMD3(h.x, h.y, h.z), SIMD3(0, 0, -extent.z), SIMD3(0, -extent.y, 0), s.z, s.y, SIMD3(1, 0, 0)),
            (SIMD3(-h.x, h.y, -h.z), SIMD3(0, 0, extent.z), SIMD3(0, -extent.y, 0), s.z, s.y, SIMD3(-1, 0, 0)),
            (SIMD3(-h.x, h.y, -h.z), SIMD3(extent.x, 0, 0), SIMD3(0, 0, extent.z), s.x, s.z, SIMD3(0, 1, 0)),
            (SIMD3(-h.x, -h.y, h.z), SIMD3(extent.x, 0, 0), SIMD3(0, 0, -extent.z), s.x, s.z, SIMD3(0, -1, 0)),
            (SIMD3(-h.x, h.y, h.z), SIMD3(extent.x, 0, 0), SIMD3(0, -extent.y, 0), s.x, s.y, SIMD3(0, 0, 1)),
            (SIMD3(h.x, h.y, -h.z), SIMD3(-extent.x, 0, 0), SIMD3(0, -extent.y, 0), s.x, s.y, SIMD3(0, 0, -1)),
        ]
        for (origin, u, v, su, sv, normal) in faces {
            let base = UInt32(shape.positions.count)
            let width = su + 1
            for j in 0...sv {
                for i in 0...su {
                    let fu = Float(i) / Float(su), fv = Float(j) / Float(sv)
                    shape.add(origin + u * fu + v * fv, normal, SIMD2(fu, fv))
                }
            }
            for j in 0..<sv {
                for i in 0..<su {
                    let a = base + UInt32(j * width + i), b = a + 1, c = a + UInt32(width), d = c + 1
                    switch geometryType {
                    case Geometry.lines: shape.indices += [a, b, a, c, b, d, c, d]
                    case Geometry.quads: shape.indices += [a, c, d, b]
                    default: shape.indices += [a, d, b, a, c, d]
                    }
                }
            }
        }
        shape.geometryType = [Geometry.lines, Geometry.quads].contains(geometryType) ? geometryType : Geometry.triangles
        if inward { shape.turnInward() }
        return shape
    }

    // MARK: Ellipsoid

    /// An ellipsoid of `radii`, or its upper half: rows of vertices from
    /// the top pole down (a hemisphere's to as far as its bands reach), and
    /// a row of zeros after a sphere's, and after a hemisphere's of an odd
    /// number of rows, as Model I/O's have.
    static func ellipsoid(radii: SIMD3<Float>, segments: SIMD2<UInt32>, inward: Bool, hemisphere: Bool, geometryType: Int) -> Shape {
        var shape = hemisphere ? Shape(name: "sphere", submeshName: "sphere-0") : Shape(name: "ellipsoid", submeshName: "ellipsoid-0")
        let radial = Int(max(segments.x, 3)), vertical = Int(max(segments.y, 2))
        let width = radial + 1
        for j in 0...vertical {
            let phi = Float(j) * .pi / Float(vertical)
            for i in 0...radial {
                let theta = Float(i) * 2 * .pi / Float(radial)
                let unit = SIMD3(sinf(phi) * cosf(theta), cosf(phi), sinf(phi) * sinf(theta))
                let p = unit * radii
                shape.add(p, normalize(p / (radii * radii)), SIMD2(Float(i) / Float(radial), Float(j) / Float(vertical)))
            }
        }
        if !hemisphere || vertical % 2 == 1 {
            for _ in 0..<width { shape.add(.zero, .zero, .zero) }
        }
        let bands = hemisphere ? vertical / 2 : vertical
        for j in 0..<bands {
            for i in 0..<radial {
                let a = UInt32(j * width + i), w = UInt32(width)
                shape.indices += [a, a + w + 1, a + w, a, a + 1, a + w + 1]
            }
        }
        shape.finish(geometryType: geometryType, inward: inward)
        return shape
    }

    // MARK: Plane

    static func plane(extent: SIMD3<Float>, segments: SIMD2<UInt32>, geometryType: Int) -> Shape {
        var shape = Shape(name: "plane", submeshName: "submesh", materialName: "plane-Material")
        // The plane lies across the two largest dimensions.
        let flat = extent.x < extent.y && extent.x <= extent.z ? 0 : extent.z < extent.y && extent.z < extent.x ? 2 : 1
        let (ua, va) = flat == 0 ? (1, 2) : flat == 2 ? (0, 1) : (0, 2)
        var normal = SIMD3<Float>.zero
        normal[flat] = 1
        let su = Int(max(segments.x, 1)), sv = Int(max(segments.y, 1))
        let width = su + 1
        for j in 0...sv {
            for i in 0...su {
                let fu = Float(i) / Float(su), fv = Float(j) / Float(sv)
                var p = SIMD3<Float>.zero
                p[ua] = (fu - 0.5) * extent[ua]
                p[va] = (fv - 0.5) * extent[va]
                shape.add(p, normal, SIMD2(fu, fv))
            }
        }
        for j in 0..<sv {
            for i in 0..<su {
                let a = UInt32(j * width + i), b = a + 1, c = a + UInt32(width), d = c + 1
                switch geometryType {
                case Geometry.lines: shape.indices += [a, b, a, c, b, d, c, d]
                case Geometry.quads: shape.indices += [a, c, d, b]
                default: shape.indices += [b, a, c, b, c, d]
                }
            }
        }
        shape.geometryType = [Geometry.lines, Geometry.quads].contains(geometryType) ? geometryType : Geometry.triangles
        return shape
    }

    // MARK: Cylinder

    /// A ring's point at segment `i`: Model I/O's start at +Z and turn
    /// toward -X.
    static func ring(_ i: Int, _ segments: Int) -> (sin: Float, cos: Float) {
        let theta = Float(i) * 2 * .pi / Float(segments)
        return (sinf(theta), cosf(theta))
    }

    static func cylinder(extent: SIMD3<Float>, segments: SIMD2<UInt32>, inward: Bool, topCap: Bool, bottomCap: Bool,
                         geometryType: Int) -> Shape {
        var shape = Shape(name: "cylinder", submeshName: "")
        let radial = Int(max(segments.x, 3)), vertical = Int(max(segments.y, 1))
        let width = radial + 1
        let (rx, rz, half) = (extent.x, extent.z, extent.y / 2)
        func point(_ i: Int, _ y: Float) -> SIMD3<Float> {
            let (s, c) = ring(i, radial)
            return SIMD3(-s * rx, y, c * rz)
        }
        var bottomRing: UInt32?
        if bottomCap {
            bottomRing = UInt32(shape.positions.count)
            for i in 0...radial {
                let (s, c) = ring(i, radial)
                shape.add(point(i, -half), SIMD3(0, -1, 0), SIMD2(0.5 + 0.5 * s, 5.0 / 6 + c / 6))
            }
        }
        let side = UInt32(shape.positions.count)
        for j in 0...vertical {
            let y = -half + Float(j) * 2 * half / Float(vertical)
            for i in 0...radial {
                let p = point(i, y)
                shape.add(p, normalize(SIMD3(p.x / (rx * rx), 0, p.z / (rz * rz))),
                          SIMD2(Float(i) / Float(radial), 2.0 / 3 - Float(j) / Float(3 * vertical)))
            }
        }
        var topRing: UInt32?
        if topCap {
            topRing = UInt32(shape.positions.count)
            for i in 0...radial {
                let (s, c) = ring(i, radial)
                shape.add(point(i, half), SIMD3(0, 1, 0), SIMD2(0.5 + 0.5 * s, 1.0 / 6 - c / 6))
            }
        }
        let bottomCenter = bottomCap ? shape.add(SIMD3(0, -half, 0), SIMD3(0, -1, 0), SIMD2(0.5, 5.0 / 6)) : 0
        let topCenter = topCap ? shape.add(SIMD3(0, half, 0), SIMD3(0, 1, 0), SIMD2(0.5, 1.0 / 6)) : 0
        let w = UInt32(width)
        if let bottomRing {
            for i in 0..<w { shape.indices += [bottomCenter, bottomRing + i, bottomRing + (i + 1) % w] }
        }
        bands(&shape, first: side, rows: vertical + 1, width: width)
        if let topRing {
            for i in 0..<w { shape.indices += [topCenter, topRing + (i + 1) % w, topRing + i] }
        }
        shape.finish(geometryType: geometryType, inward: inward)
        return shape
    }

    /// Two triangles between each pair of neighbors in each pair of rows,
    /// the last joining the first.
    static func bands(_ shape: inout Shape, first: UInt32, rows: Int, width: Int) {
        guard rows > 1 else { return }
        let w = UInt32(width)
        for j in 0..<UInt32(rows - 1) {
            for i in 0..<w {
                let next = (i + 1) % w
                let a = first + j * w + i, an = first + j * w + next, b = a + w, bn = an + w
                shape.indices += [a, b, bn, an, a, bn]
            }
        }
    }

    // MARK: Cone

    /// A cone of base diameters extent.x and extent.z and height extent.y,
    /// its point up, always with its base.
    static func cone(extent: SIMD3<Float>, segments: SIMD2<UInt32>, inward: Bool, geometryType: Int) -> Shape {
        var shape = Shape(name: "cone", submeshName: "cone-Submesh", materialName: "cone-Material")
        let radial = Int(max(segments.x, 3)), vertical = Int(max(segments.y, 1))
        let width = radial + 1
        let (rx, rz, height) = (extent.x / 2, extent.z / 2, extent.y)
        let half = height / 2
        let slope = (rx + rz) / 2
        for i in 0...radial {
            let (s, c) = ring(i, radial)
            shape.add(SIMD3(-s * rx, -half, c * rz), SIMD3(0, -1, 0), SIMD2(0.5 - 0.5 * s, 5.0 / 6 - c / 6))
        }
        let side = UInt32(shape.positions.count)
        for j in 0...vertical {
            let t = Float(j) / Float(vertical)
            for i in 0...radial {
                let (s, c) = ring(i, radial)
                shape.add(SIMD3(-s * rx * (1 - t), -half + t * height, c * rz * (1 - t)), normalize(SIMD3(-s * height, slope, c * height)),
                          SIMD2(Float(i) / Float(radial), 2.0 / 3 * (1 - t)))
            }
        }
        let center = shape.add(SIMD3(0, -half, 0), SIMD3(0, -1, 0), SIMD2(0.5, 5.0 / 6))
        for i in 0..<UInt32(radial) { shape.indices += [center, i, i + 1] }
        let w = UInt32(width)
        for j in 0..<UInt32(vertical) {
            for i in 0..<UInt32(radial) {
                let a = side + j * w + i, b = a + w
                shape.indices += [a, b, b + 1, a, b + 1, a + 1]
            }
        }
        shape.finish(geometryType: geometryType, inward: inward)
        return shape
    }

    // MARK: Capsule

    /// A capsule extent.y tall: a cylinder of radii extent.x and extent.z
    /// between two half ellipsoids extent.x high.
    static func capsule(extent: SIMD3<Float>, segments: SIMD2<UInt32>, hemisphereSegments: Int, inward: Bool, geometryType: Int) -> Shape {
        var shape = Shape(name: "capsule", submeshName: "")
        let radial = Int(max(segments.x, 3)), vertical = Int(max(segments.y, 1)), cap = max(hemisphereSegments, 1)
        let width = radial + 1
        let (rx, rz, ry) = (extent.x, extent.z, extent.x)
        let half = max(extent.y / 2 - ry, 0)
        func addRing(scale: Float, y: Float, normalY: Float, v: Float) {
            for i in 0...radial {
                let (s, c) = ring(i, radial)
                let p = SIMD3(-s * rx * scale, y, c * rz * scale)
                shape.add(p, normalize(SIMD3(-s * scale / rx, normalY / ry, c * scale / rz)), SIMD2(Float(i) / Float(radial), v))
            }
        }
        var rows = 0
        for k in 1..<cap {
            let alpha = Float(k) * .pi / 2 / Float(cap)
            addRing(scale: sinf(alpha), y: -half - ry * cosf(alpha), normalY: -cosf(alpha), v: 2.0 / 3 + cosf(alpha) / 3)
            rows += 1
        }
        for j in 0...vertical {
            addRing(scale: 1, y: -half + Float(j) * 2 * half / Float(vertical), normalY: 0, v: 2.0 / 3 - Float(j) / Float(3 * vertical))
            rows += 1
        }
        for k in stride(from: cap - 1, through: 1, by: -1) {
            let alpha = Float(k) * .pi / 2 / Float(cap)
            addRing(scale: sinf(alpha), y: half + ry * cosf(alpha), normalY: cosf(alpha), v: 1.0 / 3 - cosf(alpha) / 3)
            rows += 1
        }
        let bottom = shape.add(SIMD3(0, -half - ry, 0), SIMD3(0, -1, 0), SIMD2(0.5, 1))
        let top = shape.add(SIMD3(0, half + ry, 0), SIMD3(0, 1, 0), SIMD2(0.5, 0))
        let w = UInt32(width)
        for i in 0..<w { shape.indices += [bottom, i, (i + 1) % w] }
        bands(&shape, first: 0, rows: rows, width: width)
        let last = UInt32(rows - 1) * w
        for i in 0..<w { shape.indices += [top, last + (i + 1) % w, last + i] }
        shape.finish(geometryType: geometryType, inward: inward)
        return shape
    }

    // MARK: Icosahedron

    static func icosahedron(extent: SIMD3<Float>, inward: Bool, geometryType: Int) -> Shape {
        var shape = Shape(name: "icosahedron", submeshName: "icosahedron-0", materialName: "icosahedron-Material")
        let y = 1 / Float(5).squareRoot(), r = 2 / Float(5).squareRoot()
        func add(_ unit: SIMD3<Float>, _ uv: SIMD2<Float>) {
            let p = unit * extent
            shape.add(p, normalize(p / (extent * extent)), uv)
        }
        for k in 0..<5 {
            let angle = (36 + 72 * Float(k)) * .pi / 180
            add(SIMD3(r * cosf(angle), y, r * sinf(angle)), SIMD2(0.5 + 0.5 * cosf(angle / 2), (1 + y) / 2))
        }
        for k in 0..<5 {
            let angle = 72 * Float(k) * .pi / 180
            add(SIMD3(r * cosf(angle), -y, r * sinf(angle)), SIMD2(0.5 + 0.5 * cosf(angle / 2), (1 - y) / 2))
        }
        add(SIMD3(0, 1, 0), SIMD2(0.5, 1))
        add(SIMD3(0, -1, 0), SIMD2(0.5, 0))
        for i in 0..<UInt32(5) { shape.indices += [10, (i + 1) % 5, i] }
        for i in 0..<UInt32(5) {
            let next = (i + 1) % 5
            shape.indices += [i, 5 + next, 5 + i, next, 5 + next, i]
        }
        for i in 0..<UInt32(5) { shape.indices += [11, 5 + i, 5 + (i + 1) % 5] }
        shape.finish(geometryType: geometryType, inward: inward)
        return shape
    }
}
