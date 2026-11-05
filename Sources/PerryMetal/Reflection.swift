import CPerryMetal
import PerryObjCInterop

// Pipeline reflection: what newRenderPipelineStateWithDescriptor:options:
// reflection:error: and newComputePipelineStateWithFunction:options:
// reflection:error: return, from metal2vulkan's. Engines read the arguments
// to learn where a function's uniforms and textures bind, so an app given
// none binds nothing. Each argument answers as an MTLArgument and
// as an MTLBinding; structs, members and arrays are built from the
// reflection's tables.

@ObjCProtocol("MTLBinding")
protocol MTLBindingProtocol {}

@ObjCProtocol("MTLBufferBinding")
protocol MTLBufferBindingProtocol: MTLBindingProtocol {}

@ObjCProtocol("MTLTextureBinding")
protocol MTLTextureBindingProtocol: MTLBindingProtocol {}

@ObjCProtocol("MTLThreadgroupBinding")
protocol MTLThreadgroupBindingProtocol: MTLBindingProtocol {}

/// The C tables, read into objects.
struct ReflectionTables {
    let reflection: perry_m2v_reflection

    func arguments(_ list: UnsafeMutablePointer<perry_m2v_argument>?, _ count: Int) -> [MTLArgument] {
        (0..<count).compactMap { list?[$0] }.map { MTLArgument(argument: $0, tables: self) }
    }

    func structType(_ index: Int64) -> MTLStructType? {
        guard index >= 0, Int(index) < reflection.struct_count, let s = reflection.structs?[Int(index)] else { return nil }
        let members = (0..<Int(s.member_count)).compactMap { i -> MTLStructMember? in
            let at = Int(s.first_member) + i
            guard at < reflection.member_count, let m = reflection.members?[at] else { return nil }
            return MTLStructMember(member: m, tables: self)
        }
        return MTLStructType(members: members)
    }

    func arrayType(_ index: Int64) -> MTLArrayType? {
        guard index >= 0, Int(index) < reflection.array_count, let a = reflection.arrays?[Int(index)] else { return nil }
        return MTLArrayType(array: a, tables: self)
    }
}

final class ReflectionState {
    var vertex: [MTLArgument] = []
    var fragment: [MTLArgument] = []
}

@ObjCClass("MTLRenderPipelineReflection")
open class MTLRenderPipelineReflection: NSObject {
    var stages = ReflectionState()

    /// The reflection of a pipeline state, or nil when metal2vulkan has none.
    static func of(_ handle: perry_m2v_handle) -> MTLRenderPipelineReflection? {
        var reflection = perry_m2v_reflection()
        let (read, message) = M2V.call { M2V.api.render_pipeline_reflection(handle, &reflection, $0) }
        guard read else {
            metalWarning("render pipeline reflection: \(message ?? "failed")")
            return nil
        }
        defer { M2V.api.reflection_free(&reflection) }
        let tables = ReflectionTables(reflection: reflection)
        let object = MTLRenderPipelineReflection()
        object.stages.vertex = tables.arguments(reflection.vertex, reflection.vertex_count)
        object.stages.fragment = tables.arguments(reflection.fragment, reflection.fragment_count)
        return object
    }

    @ObjCMethod("vertexArguments") func vertexArguments() -> NSObject { NSObject.array(stages.vertex) }
    @ObjCMethod("fragmentArguments") func fragmentArguments() -> NSObject { NSObject.array(stages.fragment) }
    @ObjCMethod("tileArguments") func tileArguments() -> NSObject { NSObject.array([]) }
    @ObjCMethod("vertexBindings") func vertexBindings() -> NSObject { NSObject.array(stages.vertex) }
    @ObjCMethod("fragmentBindings") func fragmentBindings() -> NSObject { NSObject.array(stages.fragment) }
    @ObjCMethod("tileBindings") func tileBindings() -> NSObject { NSObject.array([]) }
    @ObjCMethod("objectBindings") func objectBindings() -> NSObject { NSObject.array([]) }
    @ObjCMethod("meshBindings") func meshBindings() -> NSObject { NSObject.array([]) }
}

@ObjCClass("MTLComputePipelineReflection")
open class MTLComputePipelineReflection: NSObject {
    var stages = ReflectionState()

    /// The reflection of a pipeline state, or nil when metal2vulkan has none.
    static func of(_ handle: perry_m2v_handle) -> MTLComputePipelineReflection? {
        var reflection = perry_m2v_reflection()
        let (read, message) = M2V.call { M2V.api.compute_pipeline_reflection(handle, &reflection, $0) }
        guard read else {
            metalWarning("compute pipeline reflection: \(message ?? "failed")")
            return nil
        }
        defer { M2V.api.reflection_free(&reflection) }
        let object = MTLComputePipelineReflection()
        object.stages.vertex = ReflectionTables(reflection: reflection).arguments(reflection.kernel, reflection.kernel_count)
        return object
    }

    @ObjCMethod("arguments") func arguments() -> NSObject { NSObject.array(stages.vertex) }
    @ObjCMethod("bindings") func bindings() -> NSObject { NSObject.array(stages.vertex) }
}

final class ArgumentState {
    var name = ""
    var type: UInt = 0
    var index = 0
    var access: UInt = 0
    var active = false
    var isArgument = false
    var bufferAlignment = 0
    var bufferDataSize = 0
    var bufferDataType: UInt = 0
    var bufferStructType: MTLStructType?
    var textureType: UInt = 0
    var textureDataType: UInt = 0
    var isDepthTexture = false
    var arrayLength = 1
    var threadgroupAlignment = 0
    var threadgroupDataSize = 0
}

@ObjCClass("MTLArgument")
open class MTLArgument: NSObject, MTLBufferBindingProtocol, MTLTextureBindingProtocol, MTLThreadgroupBindingProtocol {
    var argument = ArgumentState()

    init(argument a: perry_m2v_argument, tables: ReflectionTables) {
        super.init()
        argument.name = a.name.map { String(cString: $0) } ?? ""
        argument.type = UInt(a.binding_type)
        argument.index = Int(a.index)
        argument.access = UInt(a.access)
        argument.active = a.active
        argument.isArgument = a.is_argument
        argument.bufferAlignment = Int(a.buffer_alignment)
        argument.bufferDataSize = Int(a.buffer_data_size)
        argument.bufferDataType = UInt(a.buffer_data_type)
        argument.bufferStructType = tables.structType(a.buffer_struct)
        argument.textureType = UInt(a.texture_type)
        argument.textureDataType = UInt(a.texture_data_type)
        argument.isDepthTexture = a.is_depth_texture
        argument.arrayLength = Int(a.array_length)
        argument.threadgroupAlignment = Int(a.threadgroup_alignment)
        argument.threadgroupDataSize = Int(a.threadgroup_data_size)
    }

    @ObjCMethod("name") func name() -> String { argument.name }
    /// MTLArgumentType, which MTLBindingType's values match.
    @ObjCMethod("type") func type() -> UInt { argument.type }
    @ObjCMethod("access") func access() -> UInt { argument.access }
    @ObjCMethod("index") func index() -> UInt { UInt(argument.index) }
    @ObjCMethod("isActive") func isActive() -> Bool { argument.active }
    @ObjCMethod("active") func active() -> Bool { argument.active }
    @ObjCMethod("isUsed") func isUsed() -> Bool { argument.active }
    @ObjCMethod("used") func used() -> Bool { argument.active }
    @ObjCMethod("isArgument") func isArgument() -> Bool { argument.isArgument }
    @ObjCMethod("argument") func getArgument() -> Bool { argument.isArgument }
    @ObjCMethod("bufferAlignment") func bufferAlignment() -> UInt { UInt(argument.bufferAlignment) }
    @ObjCMethod("bufferDataSize") func bufferDataSize() -> UInt { UInt(argument.bufferDataSize) }
    @ObjCMethod("bufferDataType") func bufferDataType() -> UInt { argument.bufferDataType }
    @ObjCMethod("bufferStructType") func bufferStructType() -> MTLStructType? { argument.bufferStructType }
    @ObjCMethod("bufferPointerType") func bufferPointerType() -> NSObject? { nil }
    @ObjCMethod("threadgroupMemoryAlignment") func threadgroupMemoryAlignment() -> UInt { UInt(argument.threadgroupAlignment) }
    @ObjCMethod("threadgroupMemoryDataSize") func threadgroupMemoryDataSize() -> UInt { UInt(argument.threadgroupDataSize) }
    @ObjCMethod("textureType") func textureType() -> UInt { argument.textureType }
    @ObjCMethod("textureDataType") func textureDataType() -> UInt { argument.textureDataType }
    @ObjCMethod("isDepthTexture") func isDepthTexture() -> Bool { argument.isDepthTexture }
    @ObjCMethod("depthTexture") func depthTexture() -> Bool { argument.isDepthTexture }
    @ObjCMethod("arrayLength") func arrayLength() -> UInt { UInt(argument.arrayLength) }
}

final class StructState {
    var members: [MTLStructMember] = []
}

@ObjCClass("MTLStructType")
open class MTLStructType: NSObject {
    var structure = StructState()

    init(members: [MTLStructMember]) {
        super.init()
        structure.members = members
    }

    /// MTLDataTypeStruct.
    @ObjCMethod("dataType") func dataType() -> UInt { 1 }
    @ObjCMethod("members") func members() -> NSObject { NSObject.array(structure.members) }
    @ObjCMethod("memberByName:") func member(name: String?) -> MTLStructMember? {
        structure.members.first { $0.member.name == name }
    }
}

final class MemberState {
    var name = ""
    var offset = 0
    var dataType: UInt = 0
    var argumentIndex = 0
    var structType: MTLStructType?
    var arrayType: MTLArrayType?
}

@ObjCClass("MTLStructMember")
open class MTLStructMember: NSObject {
    var member = MemberState()

    init(member m: perry_m2v_struct_member, tables: ReflectionTables) {
        super.init()
        member.name = m.name.map { String(cString: $0) } ?? ""
        member.offset = Int(m.offset)
        member.dataType = UInt(m.data_type)
        member.argumentIndex = Int(m.argument_index)
        member.structType = tables.structType(m.struct_type)
        member.arrayType = tables.arrayType(m.array_type)
    }

    @ObjCMethod("name") func name() -> String { member.name }
    @ObjCMethod("offset") func offset() -> UInt { UInt(member.offset) }
    @ObjCMethod("dataType") func dataType() -> UInt { member.dataType }
    @ObjCMethod("argumentIndex") func argumentIndex() -> UInt { UInt(member.argumentIndex) }
    @ObjCMethod("structType") func structType() -> MTLStructType? { member.structType }
    @ObjCMethod("arrayType") func arrayType() -> MTLArrayType? { member.arrayType }
    @ObjCMethod("pointerType") func pointerType() -> NSObject? { nil }
    @ObjCMethod("textureReferenceType") func textureReferenceType() -> NSObject? { nil }
}

final class ArrayState {
    var elementType: UInt = 0
    var arrayLength = 0
    var stride = 0
    var argumentIndexStride = 0
    var elementStruct: MTLStructType?
    var elementArray: MTLArrayType?
}

@ObjCClass("MTLArrayType")
open class MTLArrayType: NSObject {
    var array = ArrayState()

    init(array a: perry_m2v_array_type, tables: ReflectionTables) {
        super.init()
        array.elementType = UInt(a.element_type)
        array.arrayLength = Int(a.array_length)
        array.stride = Int(a.stride)
        array.argumentIndexStride = Int(a.argument_index_stride)
        array.elementStruct = tables.structType(a.element_struct)
        array.elementArray = tables.arrayType(a.element_array)
    }

    /// MTLDataTypeArray.
    @ObjCMethod("dataType") func dataType() -> UInt { 2 }
    @ObjCMethod("elementType") func elementType() -> UInt { array.elementType }
    @ObjCMethod("arrayLength") func arrayLength() -> UInt { UInt(array.arrayLength) }
    @ObjCMethod("stride") func stride() -> UInt { UInt(array.stride) }
    @ObjCMethod("argumentIndexStride") func argumentIndexStride() -> UInt { UInt(array.argumentIndexStride) }
    @ObjCMethod("elementStructType") func elementStructType() -> MTLStructType? { array.elementStruct }
    @ObjCMethod("elementArrayType") func elementArrayType() -> MTLArrayType? { array.elementArray }
    @ObjCMethod("elementPointerType") func elementPointerType() -> NSObject? { nil }
    @ObjCMethod("elementTextureReferenceType") func elementTextureReferenceType() -> NSObject? { nil }
}
