import Glibc
import PerryObjCInterop

// nw_ethernet_channel_t: Ethernet frames of one EtherType on one interface,
// over a Linux packet socket (AF_PACKET). Those need CAP_NET_RAW; without
// it the channel fails with the socket's error (EPERM), as a sandboxed
// Darwin app's does.

final class EthernetChannelState: NWState {
    var object: UnsafeMutableRawPointer?
    let etherType: UInt16
    let interface: UnsafeMutableRawPointer?
    let queue: UnsafeMutableRawPointer

    private let lock = Lock()
    private var userQueue: UnsafeMutableRawPointer?
    private var stateHandler: ObjCBlock?
    private var receiveHandler: ObjCBlock?
    private var status = ConnectionStatus.invalid
    private var started = false
    private var holdsItself = false
    private var fd: Int32 = -1
    private var index: Int32 = 0
    private var hardwareAddress = [UInt8](repeating: 0, count: 6)

    init(etherType: UInt16, interface: UnsafeMutableRawPointer?) {
        self.etherType = etherType
        self.interface = ObjCRuntime.retain(interface)
        queue = Dispatch.serialQueue("com.apple.network.ethernet-channel")
    }

    deinit {
        ObjCRuntime.release(interface)
        ObjCRuntime.release(queue)
        ObjCRuntime.release(userQueue)
    }

    override func objectDeallocated() {
        object = nil
        Dispatch.on(queue) { self.closeSocket() }
    }

    func setQueue(_ queue: UnsafeMutableRawPointer?) {
        let held = ObjCRuntime.retain(queue)
        let old = lock.withLock { () -> UnsafeMutableRawPointer? in
            let old = userQueue
            userQueue = held
            return old
        }
        ObjCRuntime.release(old)
    }

    func setStateHandler(_ block: ObjCBlock?) { lock.withLock { stateHandler = block } }
    func setReceiveHandler(_ block: ObjCBlock?) { lock.withLock { receiveHandler = block } }

    private func onUserQueue(_ body: @escaping () -> Void) {
        let queue = lock.withLock { userQueue }
        Dispatch.on(queue, body)
    }

    private func setStatus(_ new: Int32, _ error: NetworkError?) {
        let handler = lock.withLock { () -> ObjCBlock? in
            status = new
            return stateHandler
        }
        guard let handler else { return }
        onUserQueue {
            let object = error?.object()
            handler.call(state: new, object)
            ObjCRuntime.release(object)
        }
    }

    func start() {
        let first = lock.withLock { () -> Bool in
            guard !started, status != ConnectionStatus.cancelled else { return false }
            started = true
            return true
        }
        guard first, let object else { return }
        _ = ObjCRuntime.retain(object)
        lock.withLock { holdsItself = true }
        Dispatch.on(queue) { self.open() }
    }

    /// struct sockaddr_ll for this channel's EtherType and interface.
    private func linkAddress() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 20)
        withUnsafeBytes(of: UInt16(AF_PACKET)) { bytes[0] = $0[0]; bytes[1] = $0[1] }
        withUnsafeBytes(of: etherType.bigEndian) { bytes[2] = $0[0]; bytes[3] = $0[1] }
        withUnsafeBytes(of: index) { for offset in 0..<4 { bytes[4 + offset] = $0[offset] } }
        return bytes
    }

    private func open() {
        setStatus(ConnectionStatus.preparing, nil)
        guard let name = Interfaces.state(interface)?.nameText else {
            setStatus(ConnectionStatus.failed, .posix(darwin: 6))
            return
        }
        index = Int32(if_nametoindex(name))
        let socket = Sockets.make(family: Int32(AF_PACKET), type: Int32(SOCK_RAW.rawValue), protocol: Int32(etherType.bigEndian))
        guard socket >= 0 else {
            setStatus(ConnectionStatus.failed, .posix(linux: errno))
            return
        }
        let address = linkAddress()
        guard address.withUnsafeBytes({ bind(socket, $0.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t($0.count)) }) == 0 else {
            let error = NetworkError.posix(linux: errno)
            close(socket)
            setStatus(ConnectionStatus.failed, error)
            return
        }
        // struct ifreq: the name, then SIOCGIFHWADDR's sockaddr.
        var request = [UInt8](repeating: 0, count: 40)
        for (offset, byte) in name.utf8.prefix(15).enumerated() { request[offset] = byte }
        if request.withUnsafeMutableBytes({ ioctl(socket, 0x8927 /* SIOCGIFHWADDR */, $0.baseAddress!) }) == 0 { hardwareAddress = Array(request[18..<24]) }
        fd = socket
        EventLoop.shared.register(socket, queue: queue, events: EventLoop.readable) { [weak self] _ in self?.readable() }
        setStatus(ConnectionStatus.ready, nil)
    }

    private func readable() {
        guard fd >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 65536)
        while fd >= 0 {
            let count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            guard count >= 14 else { break }
            var offset = 12
            var vlan: UInt16 = 0
            if buffer[12] == 0x81, buffer[13] == 0x00, count >= 18 {
                vlan = UInt16(buffer[14]) << 8 | UInt16(buffer[15])
                offset = 16
            }
            let payload = Array(buffer[(offset + 2)..<count])
            var destination = Array(buffer[0..<6])
            var source = Array(buffer[6..<12])
            guard let handler = lock.withLock({ receiveHandler }) else { continue }
            let content = Dispatch.data(payload)
            onUserQueue {
                typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UInt16, UnsafeMutablePointer<UInt8>?,
                                                   UnsafeMutablePointer<UInt8>?) -> Void
                destination.withUnsafeMutableBufferPointer { local in
                    source.withUnsafeMutableBufferPointer { remote in
                        handler.function(as: Invoke.self)(handler.object, content, vlan, local.baseAddress, remote.baseAddress)
                    }
                }
                ObjCRuntime.release(content)
            }
        }
        if fd >= 0 { EventLoop.shared.arm(fd, events: EventLoop.readable) }
    }

    func send(_ payload: [UInt8], vlan: UInt16, to remote: [UInt8], completion: ObjCBlock?) {
        Dispatch.on(queue) {
            var error: NetworkError?
            if self.fd < 0 {
                error = .posix(darwin: 57)
            } else {
                var frame = remote + self.hardwareAddress
                if vlan != 0 { frame += [0x81, 0x00, UInt8(vlan >> 8), UInt8(vlan & 0xFF)] }
                frame += [UInt8(self.etherType >> 8), UInt8(self.etherType & 0xFF)]
                frame += payload
                let address = self.linkAddress()
                let sent = frame.withUnsafeBytes { bytes in
                    address.withUnsafeBytes {
                        sendto(self.fd, bytes.baseAddress, bytes.count, 0, $0.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t($0.count))
                    }
                }
                if sent < 0 { error = .posix(linux: errno) }
            }
            guard let completion else { return }
            self.onUserQueue {
                let object = error?.object()
                completion.call(object)
                ObjCRuntime.release(object)
            }
        }
    }

    func cancel() {
        Dispatch.on(queue) {
            guard self.lock.withLock({ self.status }) != ConnectionStatus.cancelled else { return }
            self.closeSocket()
            self.setStatus(ConnectionStatus.cancelled, nil)
            let release = self.lock.withLock { () -> Bool in
                let held = self.holdsItself
                self.holdsItself = false
                return held
            }
            if release, let object = self.object { self.onUserQueue { ObjCRuntime.release(object) } }
        }
    }

    private func closeSocket() {
        guard fd >= 0 else { return }
        EventLoop.shared.remove(fd)
        close(fd)
        fd = -1
    }
}

@ObjCClass("OS_nw_ethernet_channel")
open class NWEthernetChannelObject: NWObject {}

private func channel(_ object: UnsafeMutableRawPointer?) -> EthernetChannelState? { NWObjects.state(object, EthernetChannelState.self) }

@c(_nw_ethernet_channel_create)
public func nw_ethernet_channel_create(_ etherType: UInt16, _ interface: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let state = EthernetChannelState(etherType: etherType, interface: interface)
    let object = NWObjects.make(NWEthernetChannelObject.objCClass, state)
    state.object = object
    return object
}

@c(_nw_ethernet_channel_create_with_parameters)
public func nw_ethernet_channel_create_with_parameters(_ etherType: UInt16, _ interface: UnsafeMutableRawPointer?,
                                                       _ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    nw_ethernet_channel_create(etherType, interface)
}

@c(_nw_ethernet_channel_set_queue)
public func nw_ethernet_channel_set_queue(_ object: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) { channel(object)?.setQueue(queue) }

@c(_nw_ethernet_channel_set_state_changed_handler)
public func nw_ethernet_channel_set_state_changed_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    channel(object)?.setStateHandler(ObjCBlock.from(handler))
}

@c(_nw_ethernet_channel_set_receive_handler)
public func nw_ethernet_channel_set_receive_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    channel(object)?.setReceiveHandler(ObjCBlock.from(handler))
}

@c(_nw_ethernet_channel_start)
public func nw_ethernet_channel_start(_ object: UnsafeMutableRawPointer?) { channel(object)?.start() }

@c(_nw_ethernet_channel_cancel)
public func nw_ethernet_channel_cancel(_ object: UnsafeMutableRawPointer?) { channel(object)?.cancel() }

@c(_nw_ethernet_channel_get_maximum_payload_size)
public func nw_ethernet_channel_get_maximum_payload_size(_ object: UnsafeMutableRawPointer?) -> UInt32 { channel(object) == nil ? 0 : 1500 }

@c(_nw_ethernet_channel_send)
public func nw_ethernet_channel_send(_ object: UnsafeMutableRawPointer?, _ content: UnsafeMutableRawPointer?, _ vlan: UInt16,
                                     _ remote: UnsafePointer<UInt8>?, _ completion: UnsafeMutableRawPointer?) {
    guard let state = channel(object), let remote else { return }
    state.send(Dispatch.bytes(content), vlan: vlan, to: Array(UnsafeBufferPointer(start: remote, count: 6)), completion: ObjCBlock.from(completion))
}
