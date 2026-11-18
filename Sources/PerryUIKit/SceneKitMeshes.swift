import Glibc

// The triangles of SceneKit's built-in shapes, wound counter-clockwise from
// outside. A vertex is eight floats: position, normal, and the texture
// coordinates, which are 0, 0 at a picture's top left. Boxes have six elements (front, right, back, left, top,
// bottom as SceneKit orders its materials), cylinders and cones three (side,
// top, bottom), tubes four (outside, inside, top, bottom), pyramids five (front,
// right, back, left, bottom); spheres, planes and toruses one.

enum SCNMeshes {
    typealias Vector = (x: Float, y: Float, z: Float)

    static func make(_ state: SCNGeometryState) -> SCNMesh {
        var mesh = SCNMesh()
        switch state.kind {
        case .box: box(&mesh, Float(state.width), Float(state.height), Float(state.length))
        case .sphere: sphere(&mesh, Float(state.radius), state.segments)
        case .plane: plane(&mesh, Float(state.width), Float(state.height))
        case .cylinder: cone(&mesh, top: Float(state.radius), bottom: Float(state.radius), height: Float(state.height), segments: state.segments)
        case .cone: cone(&mesh, top: Float(state.topRadius), bottom: Float(state.bottomRadius), height: Float(state.height), segments: state.segments)
        case .floor: floor(&mesh, Float(state.width), Float(state.length))
        case .tube: tube(&mesh, inner: Float(state.innerRadius), outer: Float(state.radius), height: Float(state.height), segments: state.segments)
        case .torus: torus(&mesh, ring: Float(state.radius), pipe: Float(state.pipeRadius), segments: state.segments, pipeSegments: state.pipeSegments)
        case .pyramid: pyramid(&mesh, Float(state.width), Float(state.height), Float(state.length))
        case .custom: break
        }
        return mesh
    }

    /// A floor: the plane of x and z, facing up; one with no width or length reaches far. Its picture is laid
    /// out once to a hundred units, as SceneKit's is, which a material's transform then scales.
    private static func floor(_ mesh: inout SCNMesh, _ width: Float, _ length: Float) {
        let far: Float = 2000
        let w = (width > 0 ? width : far) / 2, l = (length > 0 ? length : far) / 2
        element(&mesh) { mesh in
            func corner(_ i: Float, _ j: Float) { vertex(&mesh, (i * w, 0, j * l), (0, 1, 0), i * w / 100 + 0.5, j * l / 100 + 0.5) }
            corner(-1, 1); corner(1, 1); corner(1, -1)
            corner(-1, 1); corner(1, -1); corner(-1, -1)
        }
    }

    /// A tube about the y axis: its outside, its inside (which faces the axis), and the rings at its ends.
    private static func tube(_ mesh: inout SCNMesh, inner: Float, outer: Float, height: Float, segments: Int) {
        let slices = max(segments, 3), half = height / 2
        func angle(_ j: Int) -> Float { 2 * Float.pi * Float(j) / Float(slices) }
        for (radius, facing) in [(outer, Float(1)), (inner, Float(-1))] {
            element(&mesh) { mesh in
                func point(_ j: Int, top: Bool) {
                    let phi = angle(j)
                    vertex(&mesh, (sinf(phi) * radius, top ? half : -half, cosf(phi) * radius), (sinf(phi) * facing, 0, cosf(phi) * facing),
                           Float(j) / Float(slices), top ? 0 : 1)
                }
                for j in 0..<slices {
                    if facing > 0 {
                        point(j, top: true); point(j, top: false); point(j + 1, top: false)
                        point(j, top: true); point(j + 1, top: false); point(j + 1, top: true)
                    } else {
                        point(j, top: true); point(j + 1, top: false); point(j, top: false)
                        point(j, top: true); point(j + 1, top: true); point(j + 1, top: false)
                    }
                }
            }
        }
        for isTop in [true, false] {
            element(&mesh) { mesh in
                guard outer > inner else { return }
                let y = isTop ? half : -half, n: Vector = (0, isTop ? 1 : -1, 0)
                func rim(_ j: Int, _ radius: Float) {
                    let phi = angle(j), reach = radius / outer / 2
                    vertex(&mesh, (sinf(phi) * radius, y, cosf(phi) * radius), n, 0.5 + sinf(phi) * reach, 0.5 + cosf(phi) * reach)
                }
                for j in 0..<slices {
                    if isTop {
                        rim(j, inner); rim(j, outer); rim(j + 1, outer)
                        rim(j, inner); rim(j + 1, outer); rim(j + 1, inner)
                    } else {
                        rim(j, inner); rim(j + 1, outer); rim(j, outer)
                        rim(j, inner); rim(j + 1, inner); rim(j + 1, outer)
                    }
                }
            }
        }
    }

    /// A torus about the y axis: a pipe bent round a ring in the plane of x and z.
    private static func torus(_ mesh: inout SCNMesh, ring: Float, pipe: Float, segments: Int, pipeSegments: Int) {
        let slices = max(segments, 3), sides = max(pipeSegments, 3)
        element(&mesh) { mesh in
            func point(_ i: Int, _ j: Int) {
                let phi = 2 * Float.pi * Float(i) / Float(slices), theta = 2 * Float.pi * Float(j) / Float(sides)
                // Out from the ring's circle, by the pipe's angle.
                let n = (x: sinf(phi) * cosf(theta), y: sinf(theta), z: cosf(phi) * cosf(theta))
                vertex(&mesh, (sinf(phi) * ring + n.x * pipe, n.y * pipe, cosf(phi) * ring + n.z * pipe), n, Float(i) / Float(slices), Float(j) / Float(sides))
            }
            for i in 0..<slices {
                for j in 0..<sides {
                    point(i, j); point(i + 1, j); point(i + 1, j + 1)
                    point(i, j); point(i + 1, j + 1); point(i, j + 1)
                }
            }
        }
    }

    /// A pyramid standing on the plane of x and z, its point above the middle.
    private static func pyramid(_ mesh: inout SCNMesh, _ width: Float, _ height: Float, _ length: Float) {
        let w = width / 2, l = length / 2
        let apex: Vector = (0, height, 0)
        // The base's corners, counter-clockwise from above, from the front's left.
        let corners: [Vector] = [(-w, 0, l), (w, 0, l), (w, 0, -l), (-w, 0, -l)]
        for side in 0..<4 {
            element(&mesh) { mesh in
                let a = corners[side], b = corners[(side + 1) % 4]
                let u: Vector = (b.x - a.x, b.y - a.y, b.z - a.z), v: Vector = (apex.x - a.x, apex.y - a.y, apex.z - a.z)
                var n: Vector = (u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
                let size = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
                if size > 0 { n = (n.x / size, n.y / size, n.z / size) }
                vertex(&mesh, a, n, 0, 1); vertex(&mesh, b, n, 1, 1); vertex(&mesh, apex, n, 0.5, 0)
            }
        }
        element(&mesh) { mesh in
            let n: Vector = (0, -1, 0)
            vertex(&mesh, (-w, 0, -l), n, 0, 0); vertex(&mesh, (w, 0, -l), n, 1, 0); vertex(&mesh, (w, 0, l), n, 1, 1)
            vertex(&mesh, (-w, 0, -l), n, 0, 0); vertex(&mesh, (w, 0, l), n, 1, 1); vertex(&mesh, (-w, 0, l), n, 0, 1)
        }
    }

    private static func vertex(_ mesh: inout SCNMesh, _ p: Vector, _ n: Vector, _ s: Float, _ t: Float) {
        mesh.vertices.append(contentsOf: [p.x, p.y, p.z, n.x, n.y, n.z, s, t])
    }

    /// Runs `body` as one element: the vertices it adds.
    private static func element(_ mesh: inout SCNMesh, _ body: (inout SCNMesh) -> Void) {
        let first = mesh.vertices.count / 8
        body(&mesh)
        mesh.elements.append((first, mesh.vertices.count / 8 - first))
    }

    private static func box(_ mesh: inout SCNMesh, _ width: Float, _ height: Float, _ length: Float) {
        // Normal, then the axes the texture's s and t run along.
        let faces: [(n: Vector, u: Vector, v: Vector)] = [
            ((0, 0, 1), (1, 0, 0), (0, 1, 0)), ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
            ((0, 0, -1), (-1, 0, 0), (0, 1, 0)), ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),
            ((0, 1, 0), (1, 0, 0), (0, 0, -1)), ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
        ]
        let half: Vector = (width / 2, height / 2, length / 2)
        func extent(_ a: Vector) -> Float { abs(a.x) * half.x + abs(a.y) * half.y + abs(a.z) * half.z }
        for face in faces {
            element(&mesh) { mesh in
                let center = (x: face.n.x * extent(face.n), y: face.n.y * extent(face.n), z: face.n.z * extent(face.n))
                func corner(_ i: Float, _ j: Float) {
                    let a = extent(face.u) * i, b = extent(face.v) * j
                    let p = (x: center.x + face.u.x * a + face.v.x * b, y: center.y + face.u.y * a + face.v.y * b,
                             z: center.z + face.u.z * a + face.v.z * b)
                    vertex(&mesh, p, face.n, (i + 1) / 2, (1 - j) / 2)
                }
                corner(-1, -1); corner(1, -1); corner(1, 1)
                corner(-1, -1); corner(1, 1); corner(-1, 1)
            }
        }
    }

    private static func plane(_ mesh: inout SCNMesh, _ width: Float, _ height: Float) {
        element(&mesh) { mesh in
            func corner(_ i: Float, _ j: Float) { vertex(&mesh, (i * width / 2, j * height / 2, 0), (0, 0, 1), (i + 1) / 2, (1 - j) / 2) }
            corner(-1, -1); corner(1, -1); corner(1, 1)
            corner(-1, -1); corner(1, 1); corner(-1, 1)
        }
    }

    private static func sphere(_ mesh: inout SCNMesh, _ radius: Float, _ segments: Int) {
        let slices = max(segments, 3), stacks = max(slices / 2, 2)
        element(&mesh) { mesh in
            func point(_ i: Int, _ j: Int) {
                let theta = Float.pi * Float(i) / Float(stacks), phi = 2 * Float.pi * Float(j) / Float(slices)
                let n = (x: sinf(theta) * sinf(phi), y: cosf(theta), z: sinf(theta) * cosf(phi))
                vertex(&mesh, (n.x * radius, n.y * radius, n.z * radius), n, Float(j) / Float(slices), Float(i) / Float(stacks))
            }
            for i in 0..<stacks {
                for j in 0..<slices {
                    point(i, j); point(i + 1, j); point(i + 1, j + 1)
                    point(i, j); point(i + 1, j + 1); point(i, j + 1)
                }
            }
        }
    }

    /// A cylinder or cone about the y axis; a cap with no radius is left out.
    private static func cone(_ mesh: inout SCNMesh, top: Float, bottom: Float, height: Float, segments: Int) {
        let slices = max(segments, 3), half = height / 2
        func angle(_ j: Int) -> Float { 2 * Float.pi * Float(j) / Float(slices) }
        element(&mesh) { mesh in
            // The side leans by the radii's difference; its normal does too.
            let slope = bottom - top
            let length = (height * height + slope * slope).squareRoot()
            func point(_ j: Int, top isTop: Bool) {
                let phi = angle(j), radius = isTop ? top : bottom
                let n = (x: sinf(phi) * height / length, y: slope / length, z: cosf(phi) * height / length)
                vertex(&mesh, (sinf(phi) * radius, isTop ? half : -half, cosf(phi) * radius), n, Float(j) / Float(slices), isTop ? 0 : 1)
            }
            for j in 0..<slices {
                point(j, top: true); point(j, top: false); point(j + 1, top: false)
                point(j, top: true); point(j + 1, top: false); point(j + 1, top: true)
            }
        }
        for (isTop, radius) in [(true, top), (false, bottom)] {
            element(&mesh) { mesh in
                guard radius > 0 else { return }
                let y = isTop ? half : -half, n: Vector = (0, isTop ? 1 : -1, 0)
                func rim(_ j: Int) {
                    let phi = angle(j)
                    vertex(&mesh, (sinf(phi) * radius, y, cosf(phi) * radius), n, 0.5 + sinf(phi) / 2, 0.5 + cosf(phi) / 2)
                }
                for j in 0..<slices {
                    vertex(&mesh, (0, y, 0), n, 0.5, 0.5)
                    if isTop { rim(j); rim(j + 1) } else { rim(j + 1); rim(j) }
                }
            }
        }
    }
}
