import Metal
import ModelIO

// MetalKit's calls that report failure through an NSError out parameter
// (Swift-private in the headers), given Swift's throwing form.

@available(macOS 10.11, iOS 9.0, tvOS 9.0, *)
extension MTKMesh {
    public class func newMeshes(asset: MDLAsset, device: MTLDevice) throws
        -> (modelIOMeshes: [MDLMesh], metalKitMeshes: [MTKMesh]) {
        var sourceMeshes: NSArray?
        let meshes = try MTKMesh.__newMeshes(from: asset, device: device, sourceMeshes: &sourceMeshes)
        return (sourceMeshes as? [MDLMesh] ?? [], meshes)
    }
}

@available(swift 4)
@available(macOS 10.12, iOS 10.0, tvOS 10.0, *)
public func MTKModelIOVertexDescriptorFromMetalWithError(_ metalDescriptor: MTLVertexDescriptor) throws -> MDLVertexDescriptor {
    var error: NSError?
    let descriptor = __MTKModelIOVertexDescriptorFromMetalWithError(metalDescriptor, &error)
    if let error { throw error }
    return descriptor
}

@available(swift 4)
@available(macOS 10.12, iOS 10.0, tvOS 10.0, *)
public func MTKMetalVertexDescriptorFromModelIOWithError(_ modelIODescriptor: MDLVertexDescriptor) throws -> MTLVertexDescriptor? {
    var error: NSError?
    let descriptor = __MTKMetalVertexDescriptorFromModelIOWithError(modelIODescriptor, &error)
    if let error { throw error }
    return descriptor
}
