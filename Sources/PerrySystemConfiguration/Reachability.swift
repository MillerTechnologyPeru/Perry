import Glibc
import PerryObjCInterop

// SCNetworkReachability over Linux's routing table. A target is reachable
// when a route could carry packets to it: a loopback address always, as a
// local and direct one; anything else when a default route is up (IPv4 in
// /proc/net/route, IPv6 in /proc/net/ipv6_route). Like iOS, it does not
// look up names or send anything. There is no cellular data: IsWWAN is
// never set, so apps see Wi-Fi.
//
// A target scheduled on a run loop or a dispatch queue gets its callback
// once with its flags, and again whenever they change; they are checked
// every two seconds.

/// SCNetworkReachabilityFlags.
enum ReachabilityFlags {
    static let reachable: UInt32 = 1 << 1
    static let isLocalAddress: UInt32 = 1 << 16
    static let isDirect: UInt32 = 1 << 17
}

/// What a target is: an address, or a name.
enum ReachabilityTarget {
    case loopback
    case remote
}

final class ReachabilityState: @unchecked Sendable {
    let target: ReachabilityTarget
    let lock = Lock()
    var callback: (@convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Void)?
    var info: UnsafeMutableRawPointer?
    var release: (@convention(c) (UnsafeRawPointer?) -> Void)?
    /// Where callbacks go, while scheduled: a queue, or nil for the main queue.
    var scheduled = false
    var queue: UnsafeMutableRawPointer?
    var lastFlags: UInt32?
    var alive = true

    init(_ target: ReachabilityTarget) { self.target = target }

    var flags: UInt32 {
        switch target {
        case .loopback: return ReachabilityFlags.reachable | ReachabilityFlags.isLocalAddress | ReachabilityFlags.isDirect
        case .remote: return Routes.hasDefaultRoute() ? ReachabilityFlags.reachable : 0
        }
    }

    func releaseInfo() {
        if let info, let release { release(info) }
        info = nil
        release = nil
    }
}

enum Routes {
    /// Whether a default route is up, in IPv4 or IPv6.
    static func hasDefaultRoute() -> Bool {
        if let table = read("/proc/net/route") {
            // Iface Destination Gateway Flags ...: RTF_UP is 1.
            for line in table.split(separator: "\n").dropFirst() {
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if fields.count > 3, fields[1] == "00000000", let flags = Int(fields[3], radix: 16), flags & 1 != 0, fields[0] != "lo" {
                    return true
                }
            }
        }
        if let table = read("/proc/net/ipv6_route") {
            // Destination, prefix length, ..., flags, interface.
            for line in table.split(separator: "\n") {
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                if fields.count >= 10, fields[0] == String(repeating: "0", count: 32), fields[1] == "00",
                   let flags = Int(fields[8], radix: 16), flags & 1 != 0, fields[9] != "lo" {
                    return true
                }
            }
        }
        return false
    }

    private static func read(_ path: String) -> String? {
        guard let file = fopen(path, "r") else { return nil }
        defer { fclose(file) }
        var text = ""
        var buffer = [CChar](repeating: 0, count: 4096)
        while fgets(&buffer, Int32(buffer.count), file) != nil { text += String(cString: buffer) }
        return text
    }
}

/// A reachability target: an object, as CFRelease expects.
@ObjCClass("__SCNetworkReachability")
open class SCNetworkReachability: NSObject {
    static let states = StateTable<ReachabilityState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        if let state = SCNetworkReachability.states[objcObject] {
            state.lock.withLock {
                state.alive = false
                state.releaseInfo()
            }
        }
        SCNetworkReachability.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNetworkReachability.objCClass.pointer)
    }
}

/// Swift state per Objective-C object, from creation until -dealloc.
final class StateTable<State: AnyObject>: @unchecked Sendable {
    private let lock = Lock()
    private var states: [UnsafeMutableRawPointer: State] = [:]

    subscript(object: UnsafeMutableRawPointer?) -> State? {
        guard let object else { return nil }
        return lock.withLock { states[object] }
    }

    func set(_ object: UnsafeMutableRawPointer, _ state: State) { lock.withLock { states[object] = state } }
    func remove(_ object: UnsafeMutableRawPointer) { _ = lock.withLock { states.removeValue(forKey: object) } }
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

private func makeTarget(_ target: ReachabilityTarget) -> UnsafeMutableRawPointer? {
    let object = NSObject(SCNetworkReachability.objCClass.pointer).newInstance()
    SCNetworkReachability.states.set(object.objcObject, ReachabilityState(target))
    return object.objCOwnedReturnValue()
}

/// A Darwin sockaddr: a loopback address (127/8, ::1), or another.
private func target(of address: UnsafeRawPointer?) -> ReachabilityTarget {
    guard let address else { return .remote }
    let family = address.load(fromByteOffset: 1, as: UInt8.self)
    if family == 2 {        // AF_INET: sin_addr at 4, in network order
        return address.load(fromByteOffset: 4, as: UInt8.self) == 127 ? .loopback : .remote
    }
    if family == 30 {       // Darwin's AF_INET6: sin6_addr at 8
        let bytes = (0..<16).map { address.load(fromByteOffset: 8 + $0, as: UInt8.self) }
        return bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1 ? .loopback : .remote
    }
    return .remote
}

@c(_SCNetworkReachabilityCreateWithName)
public func SCNetworkReachabilityCreateWithName(_ allocator: UnsafeRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let host = String(cString: name).lowercased()
    return makeTarget(host == "localhost" || host.hasPrefix("127.") || host == "::1" ? .loopback : .remote)
}

@c(_SCNetworkReachabilityCreateWithAddress)
public func SCNetworkReachabilityCreateWithAddress(_ allocator: UnsafeRawPointer?, _ address: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    guard address != nil else { return nil }
    return makeTarget(target(of: address))
}

@c(_SCNetworkReachabilityCreateWithAddressPair)
public func SCNetworkReachabilityCreateWithAddressPair(_ allocator: UnsafeRawPointer?, _ local: UnsafeRawPointer?,
                                                       _ remote: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    makeTarget(remote.map { target(of: $0) } ?? target(of: local))
}

@c(_SCNetworkReachabilityGetTypeID)
public func SCNetworkReachabilityGetTypeID() -> UInt { 0x5C4E }

@c(_SCNetworkReachabilityGetFlags)
public func SCNetworkReachabilityGetFlags(_ target: UnsafeMutableRawPointer?, _ flags: UnsafeMutablePointer<UInt32>?) -> Bool {
    guard let state = SCNetworkReachability.states[target] else { return false }
    flags?.pointee = state.flags
    return true
}

/// SCNetworkReachabilityContext: version, info, retain, release, copyDescription.
@c(_SCNetworkReachabilitySetCallback)
public func SCNetworkReachabilitySetCallback(_ target: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                             _ context: UnsafeRawPointer?) -> Bool {
    guard let state = SCNetworkReachability.states[target] else { return false }
    typealias Retain = @convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?
    typealias Release = @convention(c) (UnsafeRawPointer?) -> Void
    state.lock.withLock {
        state.releaseInfo()
        state.callback = callback.map { unsafeBitCast($0, to: (@convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Void).self) }
        guard let context, callback != nil else { return }
        var info = context.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UnsafeMutableRawPointer?.self)
        if let retain = context.load(fromByteOffset: 2 * MemoryLayout<UnsafeRawPointer>.size, as: UnsafeRawPointer?.self) {
            info = unsafeBitCast(retain, to: Retain.self)(info).map { UnsafeMutableRawPointer(mutating: $0) }
        }
        state.info = info
        state.release = context.load(fromByteOffset: 3 * MemoryLayout<UnsafeRawPointer>.size, as: UnsafeRawPointer?.self).map { unsafeBitCast($0, to: Release.self) }
    }
    return true
}

/// Starts or stops delivering callbacks for `target`.
private func schedule(_ target: UnsafeMutableRawPointer?, on queue: UnsafeMutableRawPointer?, _ scheduled: Bool) -> Bool {
    guard let target, let state = SCNetworkReachability.states[target] else { return false }
    let start = state.lock.withLock { () -> Bool in
        let wasScheduled = state.scheduled
        state.scheduled = scheduled
        state.queue = queue
        state.lastFlags = nil
        return scheduled && !wasScheduled
    }
    if start { check(target, state) }
    return true
}

/// Calls back if the flags changed, then checks again in two seconds.
private func check(_ target: UnsafeMutableRawPointer, _ state: ReachabilityState) {
    let flags = state.flags
    let delivery = state.lock.withLock { () -> (UnsafeMutableRawPointer?, Bool)? in
        guard state.alive, state.scheduled else { return nil }
        let changed = state.lastFlags != flags
        state.lastFlags = flags
        return (state.queue, changed)
    }
    guard let (queue, changed) = delivery else { return }
    if changed {
        Dispatch.on(queue) {
            let call = state.lock.withLock { state.alive && state.scheduled ? (state.callback, state.info) : (nil, nil) }
            call.0?(target, flags, call.1)
        }
    }
    Dispatch.after(2) { check(target, state) }
}

@c(_SCNetworkReachabilityScheduleWithRunLoop)
public func SCNetworkReachabilityScheduleWithRunLoop(_ target: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                                     _ mode: UnsafeMutableRawPointer?) -> Bool {
    schedule(target, on: nil, true)
}

@c(_SCNetworkReachabilityUnscheduleFromRunLoop)
public func SCNetworkReachabilityUnscheduleFromRunLoop(_ target: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                                       _ mode: UnsafeMutableRawPointer?) -> Bool {
    schedule(target, on: nil, false)
}

/// A queue to call back on; NULL stops the callbacks.
@c(_SCNetworkReachabilitySetDispatchQueue)
public func SCNetworkReachabilitySetDispatchQueue(_ target: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) -> Bool {
    schedule(target, on: queue, queue != nil)
}
