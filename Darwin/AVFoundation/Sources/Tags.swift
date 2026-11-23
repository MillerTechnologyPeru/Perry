import Foundation
import CoreMedia
import CoreVideo

// Core Media tag collections and tagged buffer groups as Swift arrays of
// tags and tagged buffers, the shapes AVFoundation's Swift API takes.

/// A tag collection of the tags; nil when Core Media can't make one.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
func tagCollection(_ tags: [CMTag]) -> __CMTagCollection? {
    var collection: __CMTagCollection?
    let raw = tags.map(rawTag)
    let status = raw.withUnsafeBufferPointer {
        __CMTagCollectionCreate(kCFAllocatorDefault, $0.baseAddress, CMItemCount($0.count), &collection)
    }
    return status == noErr ? collection : nil
}

/// The tags of a collection.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
func tags(of collection: __CMTagCollection) -> [CMTag] {
    let count = Int(__CMTagCollectionGetCount(collection))
    guard count > 0 else { return [] }
    let raw = [__CMTag](unsafeUninitializedCapacity: count) { buffer, initialized in
        var retrieved: CMItemCount = 0
        _ = __CMTagCollectionGetTags(collection, buffer.baseAddress!, CMItemCount(count), &retrieved)
        initialized = Int(retrieved)
    }
    return raw.compactMap(swiftTag)
}

/// A tag as Core Media's C struct: its category, the type of its value
/// and the value's 64 bits.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
func rawTag(_ tag: CMTag) -> __CMTag {
    // Categories and data types are open sets of FourCCs and numbers.
    let category = unsafeBitCast(tag.rawCategory, to: __CMTagCategory.self)
    switch tag.rawTagValue {
    case let .int64(value): return __CMTag(category: category, dataType: unsafeBitCast(UInt32(2), to: __CMTagDataType.self), value: UInt64(bitPattern: value))
    case let .float64(value): return __CMTag(category: category, dataType: unsafeBitCast(UInt32(3), to: __CMTagDataType.self), value: value.bitPattern)
    case let .osType(value): return __CMTag(category: category, dataType: unsafeBitCast(UInt32(5), to: __CMTagDataType.self), value: UInt64(value))
    case let .flags(value): return __CMTag(category: category, dataType: unsafeBitCast(UInt32(7), to: __CMTagDataType.self), value: value)
    @unknown default: return __CMTag(category: category, dataType: unsafeBitCast(UInt32(0), to: __CMTagDataType.self), value: 0)
    }
}

/// A C tag as a Swift one; nil for an invalid tag.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
func swiftTag(_ tag: __CMTag) -> CMTag? {
    let category = unsafeBitCast(tag.category, to: FourCharCode.self)
    switch unsafeBitCast(tag.dataType, to: UInt32.self) {
    case 2: return CMTag(rawCategory: category, rawTagValue: .int64(Int64(bitPattern: tag.value)))
    case 3: return CMTag(rawCategory: category, rawTagValue: .float64(Float64(bitPattern: tag.value)))
    case 5: return CMTag(rawCategory: category, rawTagValue: .osType(OSType(truncatingIfNeeded: tag.value)))
    case 7: return CMTag(rawCategory: category, rawTagValue: .flags(tag.value))
    default: return nil
    }
}

/// Tag collections, as arrays of tags, from an array of CMTagCollections.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
func tagArrays(_ collections: [Any]) -> [[CMTag]] {
    collections.map { tags(of: $0 as! __CMTagCollection) }
}

/// An array of CMTagCollections of arrays of tags.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
func tagCollections(_ arrays: [[CMTag]]) -> [Any] {
    arrays.compactMap { tagCollection($0) }
}

/// A tagged buffer group of tagged buffers.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
func taggedBufferGroup(_ buffers: [CMTaggedBuffer]) -> __CMTaggedBufferGroup? {
    var collections: [__CMTagCollection] = []
    var objects: [AnyObject] = []
    for buffer in buffers {
        guard let collection = tagCollection(buffer.tags) else { return nil }
        collections.append(collection)
        switch buffer.buffer {
        case let .pixelBuffer(pixelBuffer): objects.append(pixelBuffer)
        case let .sampleBuffer(sampleBuffer): objects.append(sampleBuffer)
        @unknown default: return nil
        }
    }
    var group: __CMTaggedBufferGroup?
    let status = __CMTaggedBufferGroupCreate(kCFAllocatorDefault, collections as CFArray, objects as CFArray, &group)
    return status == noErr ? group : nil
}

/// The tagged buffers of a group.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, *)
func taggedBuffers(of group: __CMTaggedBufferGroup) -> [CMTaggedBuffer] {
    (0..<Int(__CMTaggedBufferGroupGetCount(group))).compactMap { index in
        let tagList = __CMTaggedBufferGroupGetTagCollectionAtIndex(group, CFIndex(index)).map { tags(of: $0) } ?? []
        if let pixelBuffer = __CMTaggedBufferGroupGetCVPixelBufferAtIndex(group, CFIndex(index)) {
            return CMTaggedBuffer(tags: tagList, pixelBuffer: pixelBuffer)
        }
        if let sampleBuffer = __CMTaggedBufferGroupGetCMSampleBufferAtIndex(group, CFIndex(index)) {
            return CMTaggedBuffer(tags: tagList, sampleBuffer: sampleBuffer)
        }
        return nil
    }
}

/// A tagged buffer group of tagged dynamic buffers.
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
func taggedBufferGroup(_ buffers: [CMTaggedDynamicBuffer]) -> __CMTaggedBufferGroup? {
    buffers.withUnsafeTaggedBuffers { taggedBufferGroup($0) }
}

/// The tagged dynamic buffers of a group.
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
func taggedDynamicBuffers(of group: __CMTaggedBufferGroup) -> [CMTaggedDynamicBuffer] {
    taggedBuffers(of: group).map { CMTaggedDynamicBuffer(unsafeBuffer: $0) }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension Array where Element == CMTag {
    /// The tags of a monoscopic video output: video, one view.
    public static func monoscopicForVideoOutput() -> [CMTag] {
        [.mediaType(.video)]
    }

    /// The tags of a stereoscopic video output: video of both eyes' views.
    public static func stereoscopicForVideoOutput() -> [CMTag] {
        [.mediaType(.video), .stereoView([.leftEye, .rightEye])]
    }
}
