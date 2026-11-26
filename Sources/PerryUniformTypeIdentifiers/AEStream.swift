import Glibc
import PerryObjCInterop

// Mac apps' alone, as the rest of the Apple Event Manager here is.
#if !arch(arm)
// AEStream: a descriptor or Apple event written piece by piece. A stream
// keeps a stack of what is open: the root (one value), an event's
// parameters, lists, records and a descriptor whose data is being written;
// each value written goes into the innermost, under the key written before
// it in a record or event. Closing something out of order is
// errAEStreamBadNesting.

final class AEStreamState {
    enum Frame {
        case root(AEItem?)
        case event(AEValue)
        case list([AEItem])
        case record(UInt32, [AEItem])
        case desc(UInt32, [UInt8], key: UInt32?)
        /// Beneath an open record: the key it goes under, put aside while
        /// its own keys are written.
        case saved(UInt32?)
    }

    var frames: [Frame]
    /// The key the next value in a record or event goes under.
    var pendingKey: UInt32?

    init(_ root: Frame) { frames = [root] }

    static func of(_ reference: UnsafeMutableRawPointer?) -> AEStreamState? {
        reference.map { Unmanaged<AEStreamState>.fromOpaque($0).takeUnretainedValue() }
    }

    var reference: UnsafeMutableRawPointer { Unmanaged.passRetained(self).toOpaque() }

    static let badNesting: Int32 = -1737   // errAEStreamBadNesting

    /// Puts a finished value into the innermost open container.
    func add(_ item: AEItem) -> Int32 {
        guard let top = frames.popLast() else { return Self.badNesting }
        switch top {
        case .root(nil):
            frames.append(.root(item))
        case .list(var items):
            items.append(item)
            frames.append(.list(items))
        case .record(let type, var items):
            guard let key = pendingKey else {
                frames.append(top)
                return Self.badNesting
            }
            var keyed = item
            keyed.keyword = key
            items.removeAll { $0.keyword == key }
            items.append(keyed)
            pendingKey = nil
            frames.append(.record(type, items))
        case .event(var event):
            guard let key = pendingKey else {
                frames.append(top)
                return Self.badNesting
            }
            var keyed = item
            keyed.keyword = key
            event.items.removeAll { $0.keyword == key }
            event.items.append(keyed)
            pendingKey = nil
            frames.append(.event(event))
        case .root, .desc, .saved:
            frames.append(top)
            return Self.badNesting
        }
        return 0
    }
}

private func stream(_ reference: UnsafeMutableRawPointer?) -> AEStreamState? { AEStreamState.of(reference) }

/// AEStreamRef AEStreamOpen(void): a stream for one value.
@c(_AEStreamOpen)
public func AEStreamOpen() -> UnsafeMutableRawPointer? { AEStreamState(.root(nil)).reference }

/// AEStreamRef AEStreamCreateEvent(AEEventClass, AEEventID, DescType targetType,
/// const void *targetData, Size, SInt16 returnID, SInt32 transactionID):
/// a stream for a new event's parameters.
@c(_AEStreamCreateEvent)
public func AEStreamCreateEvent(_ eventClass: UInt32, _ eventID: UInt32, _ targetType: UInt32, _ targetData: UnsafeRawPointer?,
                                _ targetLength: Int, _ returnID: Int16, _ transactionID: Int32) -> UnsafeMutableRawPointer? {
    var event = (UInt32(0), UInt16(0), UInt16(0), UInt16(0), UInt16(0))   // a 12-byte AEDesc
    return withUnsafeMutableBytes(of: &event) { buffer -> UnsafeMutableRawPointer? in
        var address = (UInt32(0), UInt16(0), UInt16(0), UInt16(0), UInt16(0))
        let created = withUnsafeMutableBytes(of: &address) { target -> Int16 in
            AE.set(target.baseAddress!, targetType, AEValue(bytes: AE.bytes(targetData, targetLength)))
            defer { AE.dispose(target.baseAddress!) }
            return AECreateAppleEvent(eventClass, eventID, target.baseAddress, returnID, transactionID, buffer.baseAddress)
        }
        guard created == AE.noErr else { return nil }
        defer { AE.dispose(buffer.baseAddress!) }
        return AEStreamState(.event(AE.value(buffer.baseAddress!))).reference
    }
}

/// AEStreamRef AEStreamOpenEvent(AppleEvent *): a stream that adds to an
/// existing event's parameters. The event is the stream's now: it is
/// disposed of, and AEStreamClose gives it back.
@c(_AEStreamOpenEvent)
public func AEStreamOpenEvent(_ event: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let event, AE.type(event) == AE.typeAppleEvent else { return nil }
    let state = AEStreamState(.event(AE.value(event)))
    AE.dispose(event)
    return state.reference
}

/// OSStatus AEStreamClose(AEStreamRef, AEDesc *): the value or event
/// written, and the stream freed; NULL discards it.
@c(_AEStreamClose)
public func AEStreamClose(_ reference: UnsafeMutableRawPointer?, _ result: UnsafeMutableRawPointer?) -> Int32 {
    guard let reference, let state = stream(reference) else { return Int32(AE.paramErr) }
    defer { Unmanaged<AEStreamState>.fromOpaque(reference).release() }
    if let result { AE.set(result, AE.typeNull, AEValue()) }
    guard state.frames.count == 1, let only = state.frames.first else { return AEStreamState.badNesting }
    guard let result else { return 0 }
    switch only {
    case .root(let item?): AE.set(result, item.type, item.value)
    case .root(nil): break
    case .event(let event): AE.set(result, AE.typeAppleEvent, event)
    default: return AEStreamState.badNesting
    }
    return 0
}

/// OSStatus AEStreamOpenDesc(AEStreamRef, DescType): a descriptor whose
/// data AEStreamWriteData writes, until AEStreamCloseDesc.
@c(_AEStreamOpenDesc)
public func AEStreamOpenDesc(_ reference: UnsafeMutableRawPointer?, _ type: UInt32) -> Int32 {
    guard let state = stream(reference) else { return Int32(AE.paramErr) }
    state.frames.append(.desc(type, [], key: nil))
    return 0
}

@c(_AEStreamOpenKeyDesc)
public func AEStreamOpenKeyDesc(_ reference: UnsafeMutableRawPointer?, _ key: UInt32, _ type: UInt32) -> Int32 {
    guard let state = stream(reference) else { return Int32(AE.paramErr) }
    state.pendingKey = key
    state.frames.append(.desc(type, [], key: key))
    return 0
}

@c(_AEStreamWriteData)
public func AEStreamWriteData(_ reference: UnsafeMutableRawPointer?, _ data: UnsafeRawPointer?, _ length: Int) -> Int32 {
    guard let state = stream(reference), length >= 0 else { return Int32(AE.paramErr) }
    guard case .desc(let type, var bytes, let key)? = state.frames.popLast() else { return AEStreamState.badNesting }
    bytes += AE.bytes(data, length)
    state.frames.append(.desc(type, bytes, key: key))
    return 0
}

@c(_AEStreamCloseDesc)
public func AEStreamCloseDesc(_ reference: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = stream(reference) else { return Int32(AE.paramErr) }
    guard case .desc(let type, let bytes, let key)? = state.frames.last else { return AEStreamState.badNesting }
    state.frames.removeLast()
    if let key { state.pendingKey = key }
    return state.add(AEItem(keyword: 0, type: type, value: AEValue(bytes: bytes)))
}

/// OSStatus AEStreamWriteDesc(AEStreamRef, DescType, const void *, Size).
@c(_AEStreamWriteDesc)
public func AEStreamWriteDesc(_ reference: UnsafeMutableRawPointer?, _ type: UInt32, _ data: UnsafeRawPointer?, _ length: Int) -> Int32 {
    guard let state = stream(reference), length >= 0 else { return Int32(AE.paramErr) }
    return state.add(AEItem(keyword: 0, type: type, value: AEValue(bytes: AE.bytes(data, length))))
}

@c(_AEStreamWriteAEDesc)
public func AEStreamWriteAEDesc(_ reference: UnsafeMutableRawPointer?, _ desc: UnsafeRawPointer?) -> Int32 {
    guard let state = stream(reference), let desc else { return Int32(AE.paramErr) }
    return state.add(AE.item(desc))
}

@c(_AEStreamOpenList)
public func AEStreamOpenList(_ reference: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = stream(reference) else { return Int32(AE.paramErr) }
    state.frames.append(.list([]))
    return 0
}

@c(_AEStreamCloseList)
public func AEStreamCloseList(_ reference: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = stream(reference) else { return Int32(AE.paramErr) }
    guard case .list(let items)? = state.frames.last else { return AEStreamState.badNesting }
    state.frames.removeLast()
    return state.add(AEItem(keyword: 0, type: AE.typeAEList, value: AEValue(items: items)))
}

/// OSStatus AEStreamOpenRecord(AEStreamRef, DescType): a record of the type.
@c(_AEStreamOpenRecord)
public func AEStreamOpenRecord(_ reference: UnsafeMutableRawPointer?, _ type: UInt32) -> Int32 {
    guard let state = stream(reference) else { return Int32(AE.paramErr) }
    state.frames.append(.saved(state.pendingKey))
    state.pendingKey = nil
    state.frames.append(.record(type, []))
    return 0
}

@c(_AEStreamSetRecordType)
public func AEStreamSetRecordType(_ reference: UnsafeMutableRawPointer?, _ type: UInt32) -> Int32 {
    guard let state = stream(reference) else { return Int32(AE.paramErr) }
    guard case .record(_, let items)? = state.frames.last else { return AEStreamState.badNesting }
    state.frames[state.frames.count - 1] = .record(type, items)
    return 0
}

@c(_AEStreamCloseRecord)
public func AEStreamCloseRecord(_ reference: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = stream(reference) else { return Int32(AE.paramErr) }
    guard case .record(let type, let items)? = state.frames.last, state.frames.count >= 2,
          case .saved(let key) = state.frames[state.frames.count - 2] else { return AEStreamState.badNesting }
    state.frames.removeLast(2)
    state.pendingKey = key
    return state.add(AEItem(keyword: 0, type: type, value: AEValue(items: items, keyed: true)))
}

/// OSStatus AEStreamWriteKey(AEStreamRef, AEKeyword): the key of the next
/// value written into a record or event.
@c(_AEStreamWriteKey)
public func AEStreamWriteKey(_ reference: UnsafeMutableRawPointer?, _ key: UInt32) -> Int32 {
    guard let state = stream(reference) else { return Int32(AE.paramErr) }
    switch state.frames.last {
    case .record?, .event?: state.pendingKey = key
    default: return AEStreamState.badNesting
    }
    return 0
}

@c(_AEStreamWriteKeyDesc)
public func AEStreamWriteKeyDesc(_ reference: UnsafeMutableRawPointer?, _ key: UInt32, _ type: UInt32, _ data: UnsafeRawPointer?,
                                 _ length: Int) -> Int32 {
    let status = AEStreamWriteKey(reference, key)
    return status == 0 ? AEStreamWriteDesc(reference, type, data, length) : status
}

/// OSStatus AEStreamOptionalParam(AEStreamRef, AEKeyword): marks an event's
/// parameter optional, which matters only to a receiving process; there
/// is none other here.
@c(_AEStreamOptionalParam)
public func AEStreamOptionalParam(_ reference: UnsafeMutableRawPointer?, _ key: UInt32) -> Int32 {
    guard let state = stream(reference) else { return Int32(AE.paramErr) }
    if case .event? = state.frames.last { return 0 }
    return AEStreamState.badNesting
}
#endif
