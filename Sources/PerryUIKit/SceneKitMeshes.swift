import Glibc

// The triangles of SceneKit's built-in shapes, wound counter-clockwise from
// outside. A vertex is eight floats: position, normal, and the texture
// coordinates. Boxes have six elements (front, right, back, left, top,
// bottom as SceneKit orders its materials), cylinders and cones three (side,
// top, bottom); spheres and planes one.

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
        case .custom: break
        }
        return mesh
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
                    vertex(&mesh, p, face.n, (i + 1) / 2, (j + 1) / 2)
                }
                corner(-1, -1); corner(1, -1); corner(1, 1)
                corner(-1, -1); corner(1, 1); corner(-1, 1)
            }
        }
    }

    private static func plane(_ mesh: inout SCNMesh, _ width: Float, _ height: Float) {
        element(&mesh) { mesh in
            func corner(_ i: Float, _ j: Float) { vertex(&mesh, (i * width / 2, j * height / 2, 0), (0, 0, 1), (i + 1) / 2, (j + 1) / 2) }
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
                vertex(&mesh, (sinf(phi) * radius, isTop ? half : -half, cosf(phi) * radius), n, Float(j) / Float(slices), isTop ? 1 : 0)
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
