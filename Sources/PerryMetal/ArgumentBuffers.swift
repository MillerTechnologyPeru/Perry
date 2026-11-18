import CPerryGeometry
import Glibc
import CPerryMetal
import PerryObjCInterop

// Argument buffers: MTLArgumentDescriptor, MTLArgumentEncoder and the shared
// event a renderer makes beside them. An encoder writes each argument's 8
// bytes into its argument buffer, as metal2vulkan lays them out: a buffer's
// GPU address plus the offset, a texture's or sampler state's resource ID.
// What a function then reaches through the buffer an encoder's -useResource:
// makes resident (Render.swift, Commands.swift).

/// An NSArray's objects.
@ObjCWrapper("NSArray")
class NSArray: NSObject {
    @ObjCMethod("count") func count() -> UInt
    @ObjCMethod("objectAtIndex:") func object(at index: UInt) -> NSObject
}

@ObjCClass("MTLArgumentDescriptor")
open class MTLArgumentDescriptor: NSObject {
    var value = perry_m2v_argument_descriptor(data_type: 0, index: 0, array_length: 0, access: 0, texture_type: 2,
                                              constant_block_alignment: 0)

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCClassMethod("argumentDescriptor") static func argumentDescriptor() -> MTLArgumentDescriptor { MTLArgumentDescriptor() }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLArgumentDescriptor {
        let copy = MTLArgumentDescriptor()
        copy.value = value
        return copy
    }

    @ObjCMethod("dataType") func dataType() -> UInt { UInt(value.data_type) }
    @ObjCMethod("setDataType:") func setDataType(_ type: UInt) { value.data_type = UInt32(type) }
    @ObjCMethod("index") func index() -> UInt { UInt(value.index) }
    @ObjCMethod("setIndex:") func setIndex(_ index: UInt) { value.index = UInt32(index) }
    @ObjCMethod("arrayLength") func arrayLength() -> UInt { UInt(value.array_length) }
    @ObjCMethod("setArrayLength:") func setArrayLength(_ length: UInt) { value.array_length = UInt32(length) }
    @ObjCMethod("access") func access() -> UInt { UInt(value.access) }
    @ObjCMethod("setAccess:") func setAccess(_ access: UInt) { value.access = UInt32(access) }
    @ObjCMethod("textureType") func textureType() -> UInt { UInt(value.texture_type) }
    @ObjCMethod("setTextureType:") func setTextureType(_ type: UInt) { value.texture_type = UInt32(type) }
    @ObjCMethod("constantBlockAlignment") func constantBlockAlignment() -> UInt { UInt(value.constant_block_alignment) }
    @ObjCMethod("setConstantBlockAlignment:") func setConstantBlockAlignment(_ alignment: UInt) {
        value.constant_block_alignment = UInt32(alignment)
    }
}

@ObjCProtocol("MTLArgumentEncoder")
protocol MTLArgumentEncoderProtocol {}

@ObjCClass("_MTLArgumentEncoder")
open class MTLArgumentEncoder: NSObject, MTLArgumentEncoderProtocol {
    var handle: perry_m2v_handle?
    var owner: MTLDevice?
    var label: String?
    /// The argument buffer, kept while it is the encoder's.
    var target: MTLBuffer?

    init(handle: perry_m2v_handle, device: MTLDevice?) {
        self.handle = handle
        owner = device
        super.init()
    }

    deinit {
        if let handle { M2V.api.argument_encoder_release?(handle) }
    }

    private func encode(_ selector: String, _ body: (perry_m2v_error) -> Bool?) {
        let (done, message) = M2V.call { body($0) }
        if done != true { metalWarning("-[MTLArgumentEncoder \(selector)]: \(message ?? "not in this metal2vulkan")") }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
    @ObjCMethod("encodedLength") func encodedLength() -> UInt { UInt(M2V.api.argument_encoder_encoded_length?(handle) ?? 0) }
    @ObjCMethod("alignment") func alignment() -> UInt { UInt(M2V.api.argument_encoder_alignment?(handle) ?? 1) }

    @ObjCMethod("setArgumentBuffer:offset:")
    func setArgumentBuffer(_ buffer: MTLBuffer?, offset: UInt) {
        target = buffer
        encode("setArgumentBuffer:offset:") {
            M2V.api.argument_encoder_set_argument_buffer?(handle, buffer?.handle, UInt64(offset), $0)
        }
    }

    @ObjCMethod("setArgumentBuffer:startOffset:arrayElement:")
    func setArgumentBuffer(_ buffer: MTLBuffer?, startOffset: UInt, arrayElement: UInt) {
        target = buffer
        encode("setArgumentBuffer:startOffset:arrayElement:") {
            M2V.api.argument_encoder_set_argument_buffer_array_element?(handle, buffer?.handle, UInt64(startOffset),
                                                                        UInt64(arrayElement), $0)
        }
    }

    @ObjCMethod("setBuffer:offset:atIndex:")
    func setBuffer(_ buffer: MTLBuffer?, offset: UInt, index: UInt) {
        encode("setBuffer:offset:atIndex:") {
            M2V.api.argument_encoder_set_buffer?(handle, buffer?.handle, UInt64(offset), UInt32(index), $0)
        }
    }

    @ObjCMethod("setBuffers:offsets:withRange:")
    func setBuffers(_ buffers: UnsafePointer<UnsafeMutableRawPointer?>?, offsets: UnsafePointer<UInt>?, range: PerryRange) {
        for i in 0..<Int(range.length) {
            setBuffer(buffers?[i].map { MTLBuffer.objCInstance($0, ownership: .retain) }, offset: offsets?[i] ?? 0,
                      index: range.location + UInt(i))
        }
    }

    @ObjCMethod("setTexture:atIndex:")
    func setTexture(_ texture: MTLTexture?, index: UInt) {
        encode("setTexture:atIndex:") { M2V.api.argument_encoder_set_texture?(handle, texture?.handle, UInt32(index), $0) }
    }

    @ObjCMethod("setTextures:withRange:")
    func setTextures(_ textures: UnsafePointer<UnsafeMutableRawPointer?>?, range: PerryRange) {
        for i in 0..<Int(range.length) {
            setTexture(textures?[i].map { MTLTexture.objCInstance($0, ownership: .retain) }, index: range.location + UInt(i))
        }
    }

    @ObjCMethod("setSamplerState:atIndex:")
    func setSamplerState(_ sampler: MTLSamplerState?, index: UInt) {
        encode("setSamplerState:atIndex:") {
            M2V.api.argument_encoder_set_sampler_state?(handle, sampler?.handle, UInt32(index), $0)
        }
    }

    @ObjCMethod("setSamplerStates:withRange:")
    func setSamplerStates(_ samplers: UnsafePointer<UnsafeMutableRawPointer?>?, range: PerryRange) {
        for i in 0..<Int(range.length) {
            setSamplerState(samplers?[i].map { MTLSamplerState.objCInstance($0, ownership: .retain) },
                            index: range.location + UInt(i))
        }
    }

    /// Where a constant's bytes go in the argument buffer.
    @ObjCMethod("constantDataAtIndex:")
    func constantData(at index: UInt) -> UnsafeMutableRawPointer? {
        let (pointer, message) = M2V.call { M2V.api.argument_encoder_constant_data?(handle, UInt32(index), $0) ?? nil }
        if pointer == nil { metalWarning("-[MTLArgumentEncoder constantDataAtIndex:]: \(message ?? "failed")") }
        return pointer
    }

    @ObjCMethod("newArgumentEncoderForBufferAtIndex:")
    func newArgumentEncoder(forBufferAt index: UInt) -> MTLArgumentEncoder? {
        let (nested, _) = M2V.call { M2V.api.argument_encoder_new_for_buffer_at_index?(handle, UInt32(index), $0) ?? nil }
        return nested.map { MTLArgumentEncoder(handle: $0, device: owner) }
    }
}

extension MTLArgumentEncoder {
    /// An encoder of the arguments an array of MTLArgumentDescriptors gives.
    static func make(device: MTLDevice, arguments: NSObject?) -> MTLArgumentEncoder? {
        guard let make = M2V.api.device_new_argument_encoder_with_arguments else {
            metalWarning("newArgumentEncoderWithArguments: this metal2vulkan makes no argument encoders")
            return nil
        }
        guard let arguments else { return nil }
        let list = arguments.unsafeCast(to: NSArray.self)
        let values = (0..<list.count()).map { list.object(at: $0).unsafeCast(to: MTLArgumentDescriptor.self).value }
        let (encoder, message) = M2V.call { error in
            values.withUnsafeBufferPointer { make(device.handle, $0.baseAddress, $0.count, error) }
        }
        guard let encoder else {
            metalWarning("newArgumentEncoderWithArguments: \(message ?? "failed")")
            return nil
        }
        return MTLArgumentEncoder(handle: encoder, device: device)
    }
}

// MARK: - Shared events

@ObjCProtocol("MTLSharedEvent")
protocol MTLSharedEventProtocol {}

/// MTLSharedEvent: a value a command buffer signals and a program waits on.
/// Command buffers here signal none, so the value is what the program sets.
/// What a shared event's blocks are registered with. Its queue is kept;
/// the blocks are called on the thread that signals the event.
@ObjCClass("MTLSharedEventListener")
open class MTLSharedEventListener: NSObject {
    var queue: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithDispatchQueue:") public required init(dispatchQueue: NSObject?) {
        queue = dispatchQueue
        super.init()
    }

    @ObjCMethod("dispatchQueue") func dispatchQueue() -> NSObject? { queue }
}

@ObjCClass("_MTLSharedEvent")
open class MTLSharedEvent: NSObject, MTLSharedEventProtocol {
    var owner: MTLDevice?
    var label: String?
    var value: UInt64 = 0

    init(device: MTLDevice) {
        owner = device
        super.init()
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
    private let lock = Lock()
    /// The blocks to call once the event is at their values.
    private var listeners: [(value: UInt64, block: ObjCBlock)] = []

    @ObjCMethod("signaledValue") func signaledValue() -> UInt64 { lock.withLock { value } }
    @ObjCMethod("setSignaledValue:") func setSignaledValue(_ value: UInt64) { signal(value) }

    /// The event is at the value: the listeners' blocks waiting for it or
    /// less are called, here, with the event and the value.
    func signal(_ value: UInt64) {
        let due = lock.withLock { () -> [ObjCBlock] in
            self.value = value
            let due = listeners.filter { $0.value <= value }.map(\.block)
            listeners.removeAll { $0.value <= value }
            return due
        }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UInt64) -> Void
        for block in due {
            ObjCRuntime.autoreleasepool { block.function(as: Invoke.self)(block.object, objcObject, value) }
        }
    }

    /// The block is called when the event is at the value, on the thread
    /// that signals it and not the listener's queue.
    @ObjCMethod("notifyListener:atValue:block:")
    func notify(listener: NSObject?, atValue value: UInt64, block: ObjCBlock?) {
        guard let block else { return }
        let current = lock.withLock { () -> UInt64? in
            if self.value >= value { return self.value }
            listeners.append((value, block))
            return nil
        }
        guard let current else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UInt64) -> Void
        block.function(as: Invoke.self)(block.object, objcObject, current)
    }

    @ObjCMethod("newSharedEventHandle") func newSharedEventHandle() -> NSObject? { nil }

    /// Waits, a millisecond at a time, until the event is at the value or
    /// the time is up.
    @ObjCMethod("waitUntilSignaledValue:timeoutMS:") func wait(untilSignaledValue value: UInt64, timeoutMS: UInt64) -> Bool {
        var waited: UInt64 = 0
        while lock.withLock({ self.value }) < value {
            guard waited < timeoutMS else { return false }
            usleep(1000)
            waited += 1
        }
        return true
    }
}
