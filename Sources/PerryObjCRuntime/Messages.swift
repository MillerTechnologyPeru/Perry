import CPerryObjC

/// Sends Objective-C messages from Swift through objc_msgSend, cast to the
/// method's C signature.
public enum Messages {
    nonisolated(unsafe) static let msgSend = perry_objc_msgSend_address()!

    typealias Send0 = @convention(c) (ObjectPointer?, SEL) -> ObjectPointer?
    typealias Send1 = @convention(c) (ObjectPointer?, SEL, UnsafeRawPointer?) -> ObjectPointer?
    typealias Send2 = @convention(c) (ObjectPointer?, SEL, UnsafeRawPointer?, UnsafeRawPointer?) -> ObjectPointer?
    typealias Send0Void = @convention(c) (ObjectPointer?, SEL) -> Void
    typealias Send1Void = @convention(c) (ObjectPointer?, SEL, UnsafeRawPointer?) -> Void
    typealias Send1Bool = @convention(c) (ObjectPointer?, SEL, UnsafeRawPointer?) -> Bool

    @inline(__always)
    public static func send(_ receiver: ObjectPointer?, _ selector: SEL) -> ObjectPointer? {
        unsafeBitCast(msgSend, to: Send0.self)(receiver, selector)
    }

    @inline(__always)
    public static func send(_ receiver: ObjectPointer?, _ selector: SEL, _ argument: UnsafeRawPointer?) -> ObjectPointer? {
        unsafeBitCast(msgSend, to: Send1.self)(receiver, selector, argument)
    }

    @inline(__always)
    public static func send(_ receiver: ObjectPointer?, _ selector: SEL, _ first: UnsafeRawPointer?,
                            _ second: UnsafeRawPointer?) -> ObjectPointer? {
        unsafeBitCast(msgSend, to: Send2.self)(receiver, selector, first, second)
    }

    @inline(__always)
    public static func sendVoid(_ receiver: ObjectPointer?, _ selector: SEL) {
        unsafeBitCast(msgSend, to: Send0Void.self)(receiver, selector)
    }

    @inline(__always)
    public static func sendVoid(_ receiver: ObjectPointer?, _ selector: SEL, _ argument: UnsafeRawPointer?) {
        unsafeBitCast(msgSend, to: Send1Void.self)(receiver, selector, argument)
    }

    @inline(__always)
    public static func sendBool(_ receiver: ObjectPointer?, _ selector: SEL, _ argument: UnsafeRawPointer?) -> Bool {
        unsafeBitCast(msgSend, to: Send1Bool.self)(receiver, selector, argument)
    }
}
