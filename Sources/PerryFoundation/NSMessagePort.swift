import FoundationEssentials
import PerryObjCInterop

// NSMessagePort, NSPortMessage, and how messages go between ports here.
//
// An NSMachPort's messages go to its delegate on the port's run loop, as
// Darwin delivers them: -handleMachMessage: with the Mach header when the
// delegate has it, else -handlePortMessage: with an NSPortMessage whose
// receive port is the port and whose send port is the one to reply on.
// Data is carried as a copy and ports as themselves, as within one process
// on Darwin.
//
// An NSMessagePort is a CFMessagePort's, which reaches only a port that has
// a name: names come from NSMessagePortNameServer, which iOS doesn't have,
// so a message port can't be reached and sending fails (NO), and sending on
// an invalid one raises NSPortSendException, as on Darwin.

enum PortMessages {
    nonisolated(unsafe) static var messagePortClass: Class!

    private static func responds(_ object: id, _ name: String) -> Bool {
        ObjC.sendBool(object, ObjC.selector("respondsToSelector:"), UnsafeMutableRawPointer(mutating: ObjC.selector(name)))
    }

    /// Sends to `port`: true once the message is on its way.
    static func send(to port: id, msgid: UInt32, components: id?, from receivePort: id?) -> Bool {
        let storage = Ports.storage(port)
        if let messageClass = messagePortClass, ObjC.isKind(port, of: messageClass) {
            guard storage.valid else {
                Exceptions.raise(name: "NSPortSendException", reason: "[NSMessagePort sendBeforeDate:] Cannot send (-3)")
            }
            return false
        }
        guard storage.valid else { return false }
        let loop = storage.loop ?? RunLoops.mainLoop
        // Each +1 until delivered.
        let parts: [id] = Arrays.elements(components).compactMap { part in
            ObjC.isKind(part, of: DataObjects.dataClass) ? DataObjects.make(DataStorage(DataObjects.data(part))) : ObjC.retain(part)
        }
        let target = ObjC.retain(port), reply = ObjC.retain(receivePort)
        loop.perform(work: {
            if let target { deliver(to: target, msgid: msgid, components: parts, from: reply) }
            parts.forEach { ObjC.release($0) }
            ObjC.release(target)
            ObjC.release(reply)
        })
        return true
    }

    private static func deliver(to port: id, msgid: UInt32, components: [id], from reply: id?) {
        let storage = Ports.storage(port)
        guard storage.valid, let delegate = storage.delegate else { return }
        ObjC.autoreleasepool {
            if responds(delegate, "handleMachMessage:") {
                // mach_msg_header_t: bits, size, remote port, local port,
                // voucher, ID.
                let remote = reply.map { Ports.storage($0).machPort } ?? 0
                var header: [UInt32] = [0, 24, remote, storage.machPort, 0, msgid]
                header.withUnsafeMutableBytes { _ = ObjC.send(delegate, ObjC.selector("handleMachMessage:"), $0.baseAddress) }
            } else if responds(delegate, "handlePortMessage:") {
                let message = NSPortMessage.make(sendPort: reply, receivePort: port, components: components, msgid: msgid)
                _ = ObjC.send(delegate, ObjC.selector("handlePortMessage:"), message)
            }
        }
    }
}

@ObjCClass("NSMessagePort")
public final class NSMessagePort: NSPort {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        PortMessages.messagePortClass = cls.storage
    }
}

/// A message's ports and contents, each retained.
final class PortMessageStorage {
    var sendPort: id?
    var receivePort: id?
    var components: [id] = []
    var msgid: UInt32 = 0

    init(sendPort: id?, receivePort: id?, components: [id], msgid: UInt32) {
        self.sendPort = ObjC.retain(sendPort)
        self.receivePort = ObjC.retain(receivePort)
        self.components = components.compactMap { ObjC.retain($0) }
        self.msgid = msgid
    }

    deinit {
        ObjC.release(sendPort)
        ObjC.release(receivePort)
        components.forEach { ObjC.release($0) }
    }
}

/// NSPortMessage: what a port's delegate is given, and a message to send.
@ObjCClass("NSPortMessage")
public final class NSPortMessage: NSObject {
    nonisolated(unsafe) static var messageClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        messageClass = cls.storage
    }

    /// A message, autoreleased.
    static func make(sendPort: id?, receivePort: id?, components: [id], msgid: UInt32) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(messageClass)) else { return nil }
        Storage.set(object, PortMessageStorage(sendPort: sendPort, receivePort: receivePort, components: components, msgid: msgid))
        return ObjC.autorelease(object)
    }

    private var storage: PortMessageStorage {
        if let storage = Storage.get(objcObject, as: PortMessageStorage.self) { return storage }
        let storage = PortMessageStorage(sendPort: nil, receivePort: nil, components: [], msgid: 0)
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("initWithSendPort:receivePort:components:")
    func initialize(sendPort: UnsafeMutableRawPointer?, receivePort: UnsafeMutableRawPointer?, components: UnsafeMutableRawPointer?) -> Self {
        Storage.set(objcObject, PortMessageStorage(sendPort: sendPort, receivePort: receivePort,
                                                   components: Arrays.elements(components), msgid: 0))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSPortMessage.messageClass)
    }

    @ObjCMethod("sendPort") func sendPort() -> UnsafeMutableRawPointer? { storage.sendPort }
    @ObjCMethod("receivePort") func receivePort() -> UnsafeMutableRawPointer? { storage.receivePort }
    @ObjCMethod("components") func components() -> UnsafeMutableRawPointer? { Arrays.autoreleased(storage.components) }
    @ObjCMethod("msgid") func msgid() -> UInt32 { storage.msgid }
    @ObjCMethod("setMsgid:") func setMsgid(_ msgid: UInt32) { storage.msgid = msgid }

    /// Sends the components to the send port, to be answered on the
    /// receive port.
    @ObjCMethod("sendBeforeDate:")
    func send(beforeDate date: UnsafeMutableRawPointer?) -> Bool {
        guard let port = storage.sendPort else { return false }
        return PortMessages.send(to: port, msgid: storage.msgid, components: Arrays.autoreleased(storage.components),
                                 from: storage.receivePort)
    }
}
