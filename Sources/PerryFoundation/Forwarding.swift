import CPerryFoundation
import Glibc
import PerryObjCInterop

// Message forwarding's last step, as Foundation has it on Darwin: a message
// no method took, and no -forwardingTargetForSelector: redirected, becomes
// an NSInvocation with the arguments as they were sent, which the receiver's
// -forwardInvocation: gets; what the invocation's return value is set to is
// what the message answers. A receiver without a signature for the selector
// (-methodSignatureForSelector:) doesn't recognize the message. arm64 only:
// elsewhere such a message ends as unrecognized without this.

#if arch(arm64)
enum Forwarding {
    nonisolated(unsafe) static let methodSignatureForSelector = ObjC.selector("methodSignatureForSelector:")
    nonisolated(unsafe) static let forwardInvocation = ObjC.selector("forwardInvocation:")

    /// Fills the invocation's arguments from where Darwin's arm64 convention
    /// put them: the reverse of Invocations.invokeARM64.
    static func capture(_ storage: InvocationStorage, _ details: MethodSignatureStorage,
                        general: UnsafePointer<UInt64>, vector: UnsafePointer<UInt64>, stack: UnsafeRawPointer) {
        var usedGeneral = 0, usedVector = 0, offset = 0

        func pop(_ size: Int, alignment: Int) -> UnsafeRawPointer {
            offset = (offset + alignment - 1) / alignment * alignment
            defer { offset += size }
            return stack + offset
        }

        for index in storage.arguments.indices {
            let type = String(cString: details.parts[index + 1]), size = details.sizes[index + 1]
            guard size > 0 else { continue }
            storage.arguments[index].withUnsafeMutableBytes { bytes in
                let target = bytes.baseAddress!
                if let (kind, count) = Structures.floatingMembers(type) {
                    let member = kind == "d" ? 8 : 4
                    if usedVector + count <= 8 {
                        for position in 0..<count {
                            (target + position * member).copyMemory(from: vector + usedVector + position, byteCount: member)
                        }
                        usedVector += count
                    } else {
                        usedVector = 8
                        target.copyMemory(from: pop(size, alignment: member), byteCount: size)
                    }
                    return
                }
                if size > 16 {
                    // Passed as a pointer to the caller's copy.
                    let pointer: UInt
                    if usedGeneral < 8 {
                        pointer = UInt(general[usedGeneral])
                        usedGeneral += 1
                    } else {
                        pointer = pop(8, alignment: 8).loadUnaligned(as: UInt.self)
                    }
                    if let source = UnsafeRawPointer(bitPattern: pointer) { target.copyMemory(from: source, byteCount: size) }
                    return
                }
                let words = (size + 7) / 8
                if usedGeneral + words <= 8 {
                    target.copyMemory(from: general + usedGeneral, byteCount: size)
                    usedGeneral += words
                } else {
                    usedGeneral = 8
                    let alignment = Invocations.alignment(of: type, size: size)
                    target.copyMemory(from: pop(size, alignment: alignment), byteCount: size)
                }
            }
        }
    }

    /// Puts the invocation's return value where the caller reads it: x0 and
    /// x1, d0-d3, or the memory x8 named.
    static func answer(_ storage: InvocationStorage, _ details: MethodSignatureStorage,
                       indirect: UInt64, out: UnsafeMutablePointer<UInt64>) {
        let size = details.sizes[0]
        guard size > 0 else { return }
        storage.result.withUnsafeBytes { result in
            if let (kind, count) = Structures.floatingMembers(String(cString: details.parts[0])) {
                let member = kind == "d" ? 8 : 4
                for position in 0..<count {
                    UnsafeMutableRawPointer(out + 2 + position).copyMemory(from: result.baseAddress! + position * member, byteCount: member)
                }
            } else if size <= 16 {
                UnsafeMutableRawPointer(out).copyMemory(from: result.baseAddress!, byteCount: size)
            } else if let target = UnsafeMutableRawPointer(bitPattern: UInt(indirect)) {
                target.copyMemory(from: result.baseAddress!, byteCount: min(size, result.count))
            }
        }
    }

    static func responds(_ receiver: id, _ selector: SEL) -> Bool {
        ObjC.instanceMethod(ObjC.objectGetClass(receiver), selector) != nil
    }
}

/// The forward handler's work, called by perry_foundation_forward with the
/// registers the message was sent with (x0-x8, d0-d7), the caller's stack,
/// and six words for x0, x1 and d0-d3 to return.
@c(perry_foundation_forward_invocation)
public func perry_foundation_forward_invocation(_ general: UnsafePointer<UInt64>, _ vector: UnsafePointer<UInt64>,
                                                _ stack: UnsafeRawPointer, _ out: UnsafeMutablePointer<UInt64>) {
    for word in 0..<6 { out[word] = 0 }
    guard let receiver = id(bitPattern: UInt(general[0])), let selector = SEL(bitPattern: UInt(general[1])) else { return }
    // The two messages forwarding itself sends can't be forwarded.
    guard selector != Forwarding.methodSignatureForSelector, selector != Forwarding.forwardInvocation,
          Forwarding.responds(receiver, Forwarding.methodSignatureForSelector),
          Forwarding.responds(receiver, Forwarding.forwardInvocation),
          let signature = ObjC.send(receiver, Forwarding.methodSignatureForSelector, UnsafeMutableRawPointer(mutating: selector)),
          let details = MethodSignatures.storage(signature), details.parts.count >= 3 else {
        ObjC.notForwarded?(receiver, selector)
        return
    }
    // No autorelease pool of this function's own: what the method returns
    // autoreleased has to outlive it, in the caller's pool.
    typealias Make = @convention(c) (id?, SEL, id?) -> id?
    let make = unsafeBitCast(ObjC.msgSend, to: Make.self)
    guard let invocation = make(UnsafeMutableRawPointer(Invocations.invocationClass),
                                ObjC.selector("invocationWithMethodSignature:"), signature),
          let storage = Invocations.storage(invocation) else { return }
    Forwarding.capture(storage, details, general: general, vector: vector, stack: stack)
    _ = ObjC.send(receiver, Forwarding.forwardInvocation, invocation)
    Forwarding.answer(storage, details, indirect: general[8], out: out)
}
#endif

@ObjCCategory("Forwarding")
extension NSObject {
    /// NSObject's own: nothing to forward to, so the message is one the
    /// receiver doesn't recognize, which is an exception as on Darwin. Code
    /// that gives a signature for any selector and catches around this
    /// (crash guards do) carries on.
    @ObjCMethod("forwardInvocation:")
    func forward(invocation: UnsafeMutableRawPointer?) {
        guard let storage = Invocations.storage(invocation), let selector = storage.object(at: 1) else { return }
        let name = String(cString: selector.assumingMemoryBound(to: CChar.self))
        Exceptions.raise(name: "NSInvalidArgumentException",
                         reason: "-[\(ObjC.className(objcObject)) \(name)]: unrecognized selector sent to instance \(objcObject)")
    }
}

/// NSGetSizeAndAlignment: the size and alignment of the first type in an
/// Objective-C type encoding, and where the next begins.
@c(_NSGetSizeAndAlignment)
public func NSGetSizeAndAlignment(_ type: UnsafePointer<CChar>?, _ size: UnsafeMutablePointer<UInt>?,
                                  _ alignment: UnsafeMutablePointer<UInt>?) -> UnsafePointer<CChar>? {
    guard let type else { return nil }
    var parser = TypeEncoding.Parser(bytes: Array(UnsafeBufferPointer(start: type, count: strlen(type))).map { UInt8(bitPattern: $0) })
    guard let (bytes, align) = parser.type() else {
        foundationFatal("NSGetSizeAndAlignment(): unsupported type encoding spec '\(String(cString: type))'")
    }
    size?.pointee = UInt(bytes)
    alignment?.pointee = UInt(align)
    return type + parser.index
}
