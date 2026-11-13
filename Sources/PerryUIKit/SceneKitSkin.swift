import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's skinning: a node's geometry deformed by the bones it names.
// Each vertex has up to five bones with weights; a bone moves a vertex by
// its world transform times its inverse bind transform (which takes the
// vertex from the geometry's space into the bone's at rest), and the vertex
// ends up where the bones' weighted sum puts it, in the scene. The sum is
// made on the CPU each frame.

final class SCNSkinnerState: ObjectState {
    var bones: [SCNNode] = []
    /// A bone's inverse bind transform, in the order of `bones`.
    var inverseBind: [Matrix] = []
    var skeleton: SCNNode?
    /// A vertex's bone weights and indices, `influences` of each.
    var weights: [Float] = []
    var indices: [UInt16] = []
    var influences = 4
}

@ObjCClass("SCNSkinner")
open class SCNSkinner: NSObject {
    static let states = StateTable<SCNSkinnerState>()
    var skinner: SCNSkinnerState { SCNSkinner.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNSkinner.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNSkinner.objCClass.pointer)
    }

    @ObjCMethod("skeleton") func skeleton() -> SCNNode? { skinner.skeleton }
    @ObjCMethod("setSkeleton:") func setSkeleton(_ node: SCNNode?) { skinner.skeleton = node }
}

@ObjCCategory("SCNNodeSkinner")
extension SCNNode {
    @ObjCMethod("skinner") func skinner() -> SCNSkinner? { node.skinner }
    @ObjCMethod("setSkinner:") func setSkinner(_ skinner: SCNSkinner?) { node.skinner = skinner }
}

enum SCNSkinning {
    /// The mesh's vertices moved by the bones as they are now: eight floats
    /// each as the mesh has them, positions and normals in the scene.
    static func skin(_ mesh: SCNMesh, with skinner: SCNSkinnerState) -> [Float] {
        let count = skinner.bones.count
        guard count > 0, mesh.sources.count * 8 == mesh.vertices.count else { return mesh.vertices }
        // A bone's turn from its bind pose, as a file's matrices give it, is the inverse of the product of its world
        // transform with its inverse bind transform: the other way round, the arms come out where they are not.
        let matrices = (0..<count).map { SCNMath.inverse(SCNMath.multiply(skinner.bones[$0].world, skinner.inverseBind[$0])) }
        let n = skinner.influences
        var out = mesh.vertices
        for vertex in 0..<mesh.sources.count {
            let source = Int(mesh.sources[vertex])
            let base = vertex * 8
            let p = (mesh.vertices[base], mesh.vertices[base + 1], mesh.vertices[base + 2])
            let q = (mesh.vertices[base + 3], mesh.vertices[base + 4], mesh.vertices[base + 5])
            var position: (Float, Float, Float) = (0, 0, 0), normal: (Float, Float, Float) = (0, 0, 0), total: Float = 0
            for k in 0..<n {
                let at = source * n + k
                guard at < skinner.weights.count, at < skinner.indices.count else { break }
                let w = skinner.weights[at]
                let bone = Int(skinner.indices[at])
                guard w > 0, bone < count else { continue }
                let m = matrices[bone]
                position.0 += w * (m[0] * p.0 + m[4] * p.1 + m[8] * p.2 + m[12])
                position.1 += w * (m[1] * p.0 + m[5] * p.1 + m[9] * p.2 + m[13])
                position.2 += w * (m[2] * p.0 + m[6] * p.1 + m[10] * p.2 + m[14])
                normal.0 += w * (m[0] * q.0 + m[4] * q.1 + m[8] * q.2)
                normal.1 += w * (m[1] * q.0 + m[5] * q.1 + m[9] * q.2)
                normal.2 += w * (m[2] * q.0 + m[6] * q.1 + m[10] * q.2)
                total += w
            }
            // A vertex no bone holds stays where it is.
            guard total > 1e-6 else { continue }
            let length = max((normal.0 * normal.0 + normal.1 * normal.1 + normal.2 * normal.2).squareRoot(), 1e-9)
            out[base] = position.0 / total; out[base + 1] = position.1 / total; out[base + 2] = position.2 / total
            out[base + 3] = normal.0 / length; out[base + 4] = normal.1 / length; out[base + 5] = normal.2 / length
        }
        return out
    }
}
