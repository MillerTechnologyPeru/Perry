import Glibc
import PerryObjCInterop

// TLS over the stream below, with Security's Secure Transport (SSLContext):
// records go to and come from this layer's buffers through the context's
// I/O functions. Security's provider applies the sec_protocol_options_t
// (versions, ALPN, ciphers, identity, server name) to the context, calls the
// program's verify block when there is one, and makes the
// sec_protocol_metadata_t the connection reports.

/// Security's functions, looked up when TLS is first used.
enum SecurityBridge {
    typealias IOFunction = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?) -> Int32
    typealias CreateContext = @convention(c) (UnsafeRawPointer?, Int32, Int32) -> UnsafeMutableRawPointer?
    typealias SetIOFuncs = @convention(c) (UnsafeMutableRawPointer?, IOFunction?, IOFunction?) -> Int32
    typealias SetConnection = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Int32
    typealias SetPeerDomainName = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Int32
    typealias Handshake = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias ReadWrite = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int, UnsafeMutablePointer<Int>?) -> Int32
    typealias OptionsCreate = @convention(c) () -> UnsafeMutableRawPointer?
    typealias Configure = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Bool, UnsafeMutablePointer<Bool>?) -> Int32
    typealias VerifyCallback = @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void
    typealias Verify = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, VerifyCallback?,
                                       UnsafeMutableRawPointer?) -> Void
    typealias MetadataCreate = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

    struct Functions {
        let createContext: CreateContext
        let setIOFuncs: SetIOFuncs
        let setConnection: SetConnection
        let setPeerDomainName: SetPeerDomainName
        let handshake: Handshake
        let read: ReadWrite
        let write: ReadWrite
        let close: Handshake
        let optionsCreate: OptionsCreate
        let configure: Configure
        let verify: Verify
        let metadataCreate: MetadataCreate
    }

    private static let lock = Lock()
    nonisolated(unsafe) private static var loaded: Functions??

    static var functions: Functions? {
        lock.withLock {
            if let loaded { return loaded }
            func symbol<T>(_ name: String, _ type: T.Type) -> T? {
                lookupSymbol(securityFramework, name).map { unsafeBitCast($0, to: type) }
            }
            var made: Functions?
            if let createContext = symbol("_SSLCreateContext", CreateContext.self),
               let setIOFuncs = symbol("_SSLSetIOFuncs", SetIOFuncs.self),
               let setConnection = symbol("_SSLSetConnection", SetConnection.self),
               let setPeerDomainName = symbol("_SSLSetPeerDomainName", SetPeerDomainName.self),
               let handshake = symbol("_SSLHandshake", Handshake.self),
               let read = symbol("_SSLRead", ReadWrite.self),
               let write = symbol("_SSLWrite", ReadWrite.self),
               let close = symbol("_SSLClose", Handshake.self),
               let optionsCreate = symbol("_perry_sec_protocol_options_create", OptionsCreate.self),
               let configure = symbol("_perry_sec_protocol_configure", Configure.self),
               let verify = symbol("_perry_sec_protocol_verify", Verify.self),
               let metadataCreate = symbol("_perry_sec_protocol_metadata_create", MetadataCreate.self) {
                made = Functions(createContext: createContext, setIOFuncs: setIOFuncs, setConnection: setConnection,
                                 setPeerDomainName: setPeerDomainName, handshake: handshake, read: read, write: write, close: close,
                                 optionsCreate: optionsCreate, configure: configure, verify: verify, metadataCreate: metadataCreate)
            } else {
                networkWarning("Security's TLS (libPerrySecurity) is missing or too old: TLS connections fail")
            }
            loaded = .some(made)
            return made
        }
    }

    /// New sec_protocol_options_t (+1), for TLS and QUIC options.
    static func makeOptions() -> UnsafeMutableRawPointer? { functions?.optionsCreate() }
}

/// Secure Transport's status codes.
private enum SSLStatus {
    static let wouldBlock: Int32 = -9803
    static let closedGraceful: Int32 = -9805
    static let closedAbort: Int32 = -9806
    static let closedNoNotify: Int32 = -9816
    static let peerAuthCompleted: Int32 = -9841
    static let badCertificate: Int32 = -9808
    static let `internal`: Int32 = -9810
}

final class TLSLayer: Layer {
    let options: OptionsState
    let serverName: String?
    let isServer: Bool
    private var context: UnsafeMutableRawPointer?
    private var input: [UInt8] = []
    private var inputEnded = false
    private var output: [UInt8] = []
    private var established = false
    private var verifying = false
    private var stopped = false
    private var startTime: UInt64 = 0
    private var secMetadata: UnsafeMutableRawPointer?

    override var kind: ProtocolKind { .tls }
    override var deliversMessages: Bool { false }

    init(options: OptionsState, serverName: String?, isServer: Bool) {
        self.options = options
        self.serverName = serverName
        self.isServer = isServer
    }

    deinit {
        ObjCRuntime.release(context)
        ObjCRuntime.release(secMetadata)
    }

    private static let readFunction: SecurityBridge.IOFunction = { connection, data, length in
        guard let connection, let length else { return SSLStatus.internal }
        let layer = Unmanaged<TLSLayer>.fromOpaque(connection).takeUnretainedValue()
        let wanted = length.pointee
        let count = min(wanted, layer.input.count)
        if count > 0, let data {
            layer.input.withUnsafeBytes { data.copyMemory(from: $0.baseAddress!, byteCount: count) }
            layer.input.removeFirst(count)
        }
        length.pointee = count
        if count < wanted { return layer.inputEnded ? SSLStatus.closedNoNotify : SSLStatus.wouldBlock }
        return 0
    }

    private static let writeFunction: SecurityBridge.IOFunction = { connection, data, length in
        guard let connection, let length else { return SSLStatus.internal }
        let layer = Unmanaged<TLSLayer>.fromOpaque(connection).takeUnretainedValue()
        if let data, length.pointee > 0 { layer.output += UnsafeRawBufferPointer(start: data, count: length.pointee) }
        return 0
    }

    override func lowerReady() {
        startTime = monotonicMilliseconds()
        guard let functions = SecurityBridge.functions,
              let context = functions.createContext(nil, isServer ? 0 : 1, 0) else {
            failUp(.tls(SSLStatus.internal))
            return
        }
        self.context = context
        _ = functions.setIOFuncs(context, TLSLayer.readFunction, TLSLayer.writeFunction)
        _ = functions.setConnection(context, Unmanaged.passUnretained(self).toOpaque())
        if !isServer, let serverName {
            _ = serverName.withCString { functions.setPeerDomainName(context, $0, strlen($0)) }
        }
        var verifies = false
        let status = functions.configure(options.secOptions, context, isServer, &verifies)
        guard status == 0 else {
            failUp(.tls(status))
            return
        }
        handshake()
    }

    private func handshake() {
        guard let functions = SecurityBridge.functions, let context, !stopped, !verifying else { return }
        let status = functions.handshake(context)
        flushOutput(completion: nil)
        switch status {
        case 0:
            established = true
            secMetadata = functions.metadataCreate(context, options.secOptions)
            connection.handshakeTimes.append((.tls, monotonicMilliseconds() - startTime))
            readyUp()
            // Records that came with the end of the handshake.
            if !input.isEmpty || inputEnded { readPlaintext() }
        case SSLStatus.wouldBlock:
            if inputEnded { failUp(.tls(SSLStatus.closedAbort)) }
        case SSLStatus.peerAuthCompleted:
            verifying = true
            let box = Unmanaged.passRetained(VerifyBox(self)).toOpaque()
            let metadata = functions.metadataCreate(context, options.secOptions)
            functions.verify(options.secOptions, context, metadata, TLSLayer.verified, box)
            ObjCRuntime.release(metadata)
        default:
            failUp(.tls(status))
        }
    }

    final class VerifyBox {
        weak var layer: TLSLayer?
        init(_ layer: TLSLayer) { self.layer = layer }
    }

    private static let verified: SecurityBridge.VerifyCallback = { info, trusted in
        guard let info else { return }
        let box = Unmanaged<VerifyBox>.fromOpaque(info).takeRetainedValue()
        guard let layer = box.layer else { return }
        Dispatch.on(layer.connection.queue) {
            layer.verifying = false
            if trusted { layer.handshake() } else { layer.failUp(.tls(SSLStatus.badCertificate)) }
        }
    }

    override func lowerReceived(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool) {
        guard !stopped else { return }
        input += data
        if isComplete { inputEnded = true }
        if established { readPlaintext() } else { handshake() }
    }

    private func readPlaintext() {
        guard let functions = SecurityBridge.functions, let context else { return }
        var buffer = [UInt8](repeating: 0, count: 16384)
        while !stopped {
            var count = 0
            let status = buffer.withUnsafeMutableBytes { functions.read(context, $0.baseAddress, $0.count, &count) }
            if count > 0 { deliverUp(Array(buffer[0..<count]), context: nil, isComplete: false) }
            flushOutput(completion: nil)
            switch status {
            case 0: continue
            case SSLStatus.wouldBlock:
                if inputEnded, input.isEmpty { endUp() }
                return
            case SSLStatus.closedGraceful, SSLStatus.closedNoNotify:
                endUp()
                return
            default:
                failUp(.tls(status))
                return
            }
        }
    }

    override func send(_ data: [UInt8], context: UnsafeMutableRawPointer?, isComplete: Bool, completion: SendCompletion?) {
        guard let functions = SecurityBridge.functions, let tls = self.context, established, !stopped else {
            completion?(.cancelled)
            return
        }
        var offset = 0
        while offset < data.count {
            var written = 0
            let status = data.withUnsafeBytes {
                functions.write(tls, UnsafeMutableRawPointer(mutating: $0.baseAddress! + offset), data.count - offset, &written)
            }
            offset += written
            if status != 0, status != SSLStatus.wouldBlock {
                completion?(.tls(status))
                failUp(.tls(status))
                return
            }
            if written == 0, status == SSLStatus.wouldBlock { break }
        }
        flushOutput(completion: completion)
    }

    private func flushOutput(completion: SendCompletion?) {
        guard !output.isEmpty else {
            completion?(nil)
            return
        }
        let records = output
        output = []
        lower?.send(records, context: nil, isComplete: false, completion: completion)
    }

    override func stop() {
        guard !stopped else { return }
        stopped = true
        if let functions = SecurityBridge.functions, let context, established {
            _ = functions.close(context)
            let records = output
            output = []
            if !records.isEmpty { lower?.send(records, context: nil, isComplete: false, completion: nil) }
        }
    }

    override func copyMetadata() -> UnsafeMutableRawPointer? {
        let (object, state) = Metadata.make(.tls)
        state.secMetadata = ObjCRuntime.retain(secMetadata)
        return object
    }
}
