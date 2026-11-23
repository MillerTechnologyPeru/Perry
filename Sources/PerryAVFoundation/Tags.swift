import Glibc
import PerryObjCInterop

// CoreMedia's tag collections and tagged buffer groups, which multi-view
// (stereo) video hands out: a set of tags that says which view a buffer
// is, and the buffers of one moment with their tags. And AVFoundation's
// attaching of a content key to a sample buffer, which has no decryption
// here to attach one for.

/// A CMTag: its category and data type, four-byte codes, and its value's
/// eight bytes, 16 bytes in all.
struct MediaTag: Hashable, Comparable {
    var category: UInt32
    var dataType: UInt32
    var value: UInt64

    static let invalid = MediaTag(category: 0, dataType: 0, value: 0)

    init(category: UInt32, dataType: UInt32, value: UInt64) {
        (self.category, self.dataType, self.value) = (category, dataType, value)
    }

    init(_ bytes: UnsafeRawPointer) {
        self.init(category: bytes.loadUnaligned(as: UInt32.self), dataType: bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self),
                  value: bytes.loadUnaligned(fromByteOffset: 8, as: UInt64.self))
    }

    func store(to bytes: UnsafeMutableRawPointer) {
        bytes.storeBytes(of: category, as: UInt32.self)
        bytes.storeBytes(of: dataType, toByteOffset: 4, as: UInt32.self)
        bytes.storeBytes(of: value, toByteOffset: 8, as: UInt64.self)
    }

    static func < (a: MediaTag, b: MediaTag) -> Bool {
        (a.category, a.dataType, a.value) < (b.category, b.dataType, b.value)
    }
}

final class TagCollectionState {
    /// Each tag once, by category, data type and value, as Darwin keeps
    /// them.
    var tags: [MediaTag] = []
}

/// A CMTagCollection: an object, retained and released as any
/// CoreFoundation one.
@ObjCClass("__PerryCMTagCollection")
open class TagCollection: NSObject {
    static let states = StateTable<TagCollectionState>()

    static func make(_ tags: [MediaTag]) -> UnsafeMutableRawPointer? {
        let collection = NSObject(objCClass.pointer).newInstance().unsafeCast(to: TagCollection.self)
        let state = TagCollectionState()
        state.tags = Array(Set(tags)).sorted()
        states.set(collection.objcObject, state)
        return collection.objCOwnedReturnValue()
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        TagCollection.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: TagCollection.objCClass.pointer)
    }
}

let kCMTagCollectionError_ParamErr: Int32 = -15740
let kCMTagCollectionError_ExhaustedBufferSize: Int32 = -15748
let kCMTaggedBufferGroupError_ParamErr: Int32 = -15780

/// (allocator, tags, count, out). Tags may be NULL only with no count.
@c(_CMTagCollectionCreate)
public func CMTagCollectionCreate(_ allocator: UnsafeRawPointer?, _ tags: UnsafeRawPointer?, _ count: Int,
                                  _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out, count >= 0, tags != nil || count == 0 else { return kCMTagCollectionError_ParamErr }
    var list: [MediaTag] = []
    if let tags { for index in 0..<count { list.append(MediaTag(tags + index * 16)) } }
    out.pointee = TagCollection.make(list)
    return 0
}

@c(_CMTagCollectionGetCount)
public func CMTagCollectionGetCount(_ collection: UnsafeMutableRawPointer?) -> Int {
    TagCollection.states[collection]?.tags.count ?? 0
}

/// Fills the buffer with the tags, and what's left of it with
/// kCMTagInvalid; a buffer too small for them all takes what fits, and
/// kCMTagCollectionError_ExhaustedBufferSize says so.
@c(_CMTagCollectionGetTags)
public func CMTagCollectionGetTags(_ collection: UnsafeMutableRawPointer?, _ buffer: UnsafeMutableRawPointer?, _ capacity: Int,
                                   _ copied: UnsafeMutablePointer<Int>?) -> Int32 {
    guard let state = TagCollection.states[collection], capacity >= 0, buffer != nil || capacity == 0 else {
        return kCMTagCollectionError_ParamErr
    }
    let count = min(capacity, state.tags.count)
    if let buffer {
        for index in 0..<capacity { (index < count ? state.tags[index] : .invalid).store(to: buffer + index * 16) }
    }
    copied?.pointee = count
    return count < state.tags.count ? kCMTagCollectionError_ExhaustedBufferSize : 0
}

final class TaggedBufferGroupState {
    /// Each buffer's tag collection and the buffer, retained.
    var entries: [(tags: UnsafeMutableRawPointer, buffer: UnsafeMutableRawPointer)] = []

    deinit {
        for entry in entries {
            ObjCRuntime.release(entry.tags)
            ObjCRuntime.release(entry.buffer)
        }
    }
}

/// A CMTaggedBufferGroup: an object, retained and released as any
/// CoreFoundation one.
@ObjCClass("__PerryCMTaggedBufferGroup")
open class TaggedBufferGroup: NSObject {
    static let states = StateTable<TaggedBufferGroupState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        TaggedBufferGroup.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: TaggedBufferGroup.objCClass.pointer)
    }
}

/// (allocator, tag collections, buffers, out): two arrays of one length,
/// a buffer's tag collection at its index.
@c(_CMTaggedBufferGroupCreate)
public func CMTaggedBufferGroupCreate(_ allocator: UnsafeRawPointer?, _ tagCollections: UnsafeMutableRawPointer?,
                                      _ buffers: UnsafeMutableRawPointer?,
                                      _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out, let tagCollections, let buffers else { return kCMTaggedBufferGroupError_ParamErr }
    out.pointee = nil
    let (collections, objects) = (NSObject(tagCollections), NSObject(buffers))
    let count = collections.sendCount()
    guard count == objects.sendCount() else { return kCMTaggedBufferGroupError_ParamErr }
    let state = TaggedBufferGroupState()
    for index in 0..<count {
        guard let tags = ObjCRuntime.retain(collections.sendObject(at: index).objcObject),
              let buffer = ObjCRuntime.retain(objects.sendObject(at: index).objcObject) else { continue }
        state.entries.append((tags, buffer))
    }
    let group = NSObject(TaggedBufferGroup.objCClass.pointer).newInstance()
    TaggedBufferGroup.states.set(group.objcObject, state)
    out.pointee = group.objCOwnedReturnValue()
    return 0
}

@c(_CMTaggedBufferGroupGetCount)
public func CMTaggedBufferGroupGetCount(_ group: UnsafeMutableRawPointer?) -> Int {
    TaggedBufferGroup.states[group]?.entries.count ?? 0
}

private func entry(_ group: UnsafeMutableRawPointer?, _ index: Int) -> (tags: UnsafeMutableRawPointer, buffer: UnsafeMutableRawPointer)? {
    guard let entries = TaggedBufferGroup.states[group]?.entries, index >= 0, index < entries.count else { return nil }
    return entries[index]
}

@c(_CMTaggedBufferGroupGetTagCollectionAtIndex)
public func CMTaggedBufferGroupGetTagCollectionAtIndex(_ group: UnsafeMutableRawPointer?, _ index: Int) -> UnsafeMutableRawPointer? {
    entry(group, index)?.tags
}

/// The buffer at the index if it is a pixel buffer, else NULL.
@c(_CMTaggedBufferGroupGetCVPixelBufferAtIndex)
public func CMTaggedBufferGroupGetCVPixelBufferAtIndex(_ group: UnsafeMutableRawPointer?, _ index: Int) -> UnsafeMutableRawPointer? {
    guard let buffer = entry(group, index)?.buffer, PixelBuffer.states[buffer] != nil else { return nil }
    return buffer
}

/// The buffer at the index if it is a sample buffer, else NULL.
@c(_CMTaggedBufferGroupGetCMSampleBufferAtIndex)
public func CMTaggedBufferGroupGetCMSampleBufferAtIndex(_ group: UnsafeMutableRawPointer?, _ index: Int) -> UnsafeMutableRawPointer? {
    guard let buffer = entry(group, index)?.buffer, SampleBuffer.states[buffer] != nil else { return nil }
    return buffer
}

// MARK: - Content keys

/// AVErrorOperationNotAllowed: nothing here decrypts a sample buffer, so
/// no key is attached to one. Without a buffer or key, NO and no error, as
/// on Darwin.
@c(_AVSampleBufferAttachContentKey)
public func AVSampleBufferAttachContentKey(_ sampleBuffer: UnsafeMutableRawPointer?, _ contentKey: UnsafeMutableRawPointer?,
                                           _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    guard sampleBuffer != nil, contentKey != nil else { return false }
    error?.pointee = Writers.error(code: -11862, description: "Operation Not Allowed")?.objcObject
    return false
}
