import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSTask, a program run as a child process, and NSPipe, the pipe its
// standard input, output or error can be: both on Linux's posix_spawn and
// pipe(2). The task is reaped on a thread of its own, which reports its end
// on the main run loop through NSTaskDidTerminateNotification and the
// termination handler.

@ObjCClass("NSPipe")
public final class NSPipe: NSObject {
    var reading: id?
    var writing: id?

    @ObjCClassMethod("pipe")
    static func pipe(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        ObjC.autorelease(ObjC.send(ObjC.send(cls.pointer, ObjC.selector("alloc")), ObjC.selector("init")))
    }

    @ObjCMethod("init")
    public required override init() {
        super.init()
        var descriptors: [Int32] = [-1, -1]
        guard Glibc.pipe(&descriptors) == 0 else { return }
        for descriptor in descriptors { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
        reading = FileHandles.make(nil, descriptor: descriptors[0], closeOnDealloc: true).flatMap { ObjC.retain($0) }
        writing = FileHandles.make(nil, descriptor: descriptors[1], closeOnDealloc: true).flatMap { ObjC.retain($0) }
    }

    deinit {
        if let reading { ObjC.release(reading) }
        if let writing { ObjC.release(writing) }
    }

    @ObjCMethod("fileHandleForReading") func fileHandleForReading() -> UnsafeMutableRawPointer? { reading }
    @ObjCMethod("fileHandleForWriting") func fileHandleForWriting() -> UnsafeMutableRawPointer? { writing }
}

enum Tasks {
    /// The descriptor a standard stream setting stands for: a file handle's,
    /// or a pipe's end (reading for input, writing for output).
    static func descriptor(_ object: id?, input: Bool) -> Int32? {
        guard let object else { return nil }
        if ObjC.className(object) == "NSPipe" || ObjC.send(object, ObjC.selector("fileHandleForReading")) != nil
            && ObjC.className(object).hasSuffix("Pipe") {
            let handle = ObjC.send(object, ObjC.selector(input ? "fileHandleForReading" : "fileHandleForWriting"))
            return handleDescriptor(handle)
        }
        return handleDescriptor(object)
    }

    static func handleDescriptor(_ handle: id?) -> Int32? {
        guard let handle else { return nil }
        typealias Fn = @convention(c) (id?, SEL) -> Int32
        return unsafeBitCast(ObjC.msgSend, to: Fn.self)(handle, ObjC.selector("fileDescriptor"))
    }

    /// The pipe end the parent no longer needs once the child has its copy.
    static func closeChildEnd(_ object: id?, input: Bool) {
        guard let object, ObjC.className(object).hasSuffix("Pipe") else { return }
        let handle = ObjC.send(object, ObjC.selector(input ? "fileHandleForReading" : "fileHandleForWriting"))
        _ = ObjC.send(handle, ObjC.selector("closeFile"))
    }

    static func strings(_ array: id?) -> [String] {
        ObjC.enumerated(ObjC.send(array, ObjC.selector("objectEnumerator"))).compactMap { Strings.value(of: $0) }
    }

    static func environment(_ dictionary: id?) -> [String]? {
        guard let dictionary else { return nil }
        return ObjC.enumerated(ObjC.send(dictionary, ObjC.selector("keyEnumerator"))).compactMap { key in
            guard let name = Strings.value(of: key),
                  let value = Strings.value(of: ObjC.send(ObjC.send(dictionary, ObjC.selector("objectForKey:"), key), ObjC.selector("description")))
            else { return nil }
            return name + "=" + value
        }
    }
}

@ObjCClass("NSTask")
open class NSTask: NSObject {
    var launchPath: String?
    var arguments: id?
    var environment: id?
    var currentDirectory: String?
    var standardInput: id?
    var standardOutput: id?
    var standardError: id?
    var terminationHandler: id?
    var pid: pid_t = 0
    var running = false
    var status: Int32 = 0
    var reason = 1 // NSTaskTerminationReasonExit; 2 is uncaught signal.

    @ObjCMethod("init")
    public required override init() { super.init() }

    deinit {
        for object in [arguments, environment, standardInput, standardOutput, standardError, terminationHandler] {
            if let object { ObjC.release(object) }
        }
    }

    private func replace(_ slot: inout id?, _ value: id?) {
        if let slot { ObjC.release(slot) }
        slot = value.flatMap { ObjC.retain($0) }
    }

    @ObjCClassMethod("launchedTaskWithLaunchPath:arguments:")
    static func launched(_ cls: ObjCClass, launchPath: String, arguments: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let task = ObjC.autorelease(ObjC.send(ObjC.send(cls.pointer, ObjC.selector("alloc")), ObjC.selector("init"))) else { return nil }
        _ = ObjC.send(task, ObjC.selector("setLaunchPath:"), Strings.autoreleased(launchPath))
        _ = ObjC.send(task, ObjC.selector("setArguments:"), arguments)
        _ = ObjC.send(task, ObjC.selector("launch"))
        return task
    }

    @ObjCMethod("launchPath") func launchPathValue() -> String? { launchPath }
    @ObjCMethod("setLaunchPath:") func setLaunchPath(_ path: String?) { launchPath = path }
    @ObjCMethod("executableURL") func executableURL() -> NSURL? { URLs.wrapped(launchPath.map { URL(filePath: $0) }) }
    @ObjCMethod("setExecutableURL:") func setExecutableURL(_ url: NSURL?) { launchPath = url?.url.path(percentEncoded: false) }
    @ObjCMethod("arguments") func argumentsValue() -> UnsafeMutableRawPointer? { arguments }
    @ObjCMethod("setArguments:") func setArguments(_ value: UnsafeMutableRawPointer?) { replace(&arguments, ObjC.send(value, ObjC.selector("copy")).map { ObjC.autorelease($0) } ?? nil) }
    @ObjCMethod("environment") func environmentValue() -> UnsafeMutableRawPointer? { environment }
    @ObjCMethod("setEnvironment:") func setEnvironment(_ value: UnsafeMutableRawPointer?) { replace(&environment, value) }
    @ObjCMethod("currentDirectoryPath") func currentDirectoryPath() -> String { currentDirectory ?? FileManager.default.currentDirectoryPath }
    @ObjCMethod("setCurrentDirectoryPath:") func setCurrentDirectoryPath(_ path: String?) { currentDirectory = path }
    @ObjCMethod("currentDirectoryURL") func currentDirectoryURL() -> NSURL? { URLs.wrapped(URL(filePath: currentDirectoryPath(), directoryHint: .isDirectory)) }
    @ObjCMethod("setCurrentDirectoryURL:") func setCurrentDirectoryURL(_ url: NSURL?) { currentDirectory = url?.url.path(percentEncoded: false) }
    @ObjCMethod("standardInput") func standardInputValue() -> UnsafeMutableRawPointer? { standardInput }
    @ObjCMethod("setStandardInput:") func setStandardInput(_ value: UnsafeMutableRawPointer?) { replace(&standardInput, value) }
    @ObjCMethod("standardOutput") func standardOutputValue() -> UnsafeMutableRawPointer? { standardOutput }
    @ObjCMethod("setStandardOutput:") func setStandardOutput(_ value: UnsafeMutableRawPointer?) { replace(&standardOutput, value) }
    @ObjCMethod("standardError") func standardErrorValue() -> UnsafeMutableRawPointer? { standardError }
    @ObjCMethod("setStandardError:") func setStandardError(_ value: UnsafeMutableRawPointer?) { replace(&standardError, value) }
    @ObjCMethod("terminationHandler") func terminationHandlerValue() -> UnsafeMutableRawPointer? { terminationHandler }
    @ObjCMethod("setTerminationHandler:")
    func setTerminationHandler(_ value: UnsafeMutableRawPointer?) {
        if let terminationHandler { ObjC.release(terminationHandler) }
        terminationHandler = value.flatMap { ObjC.retainBlock($0) }
    }

    @ObjCMethod("processIdentifier") func processIdentifier() -> Int32 { pid }
    @ObjCMethod("isRunning") func isRunning() -> Bool { running }
    @ObjCMethod("terminationStatus") func terminationStatus() -> Int32 { status }
    @ObjCMethod("terminationReason") func terminationReason() -> Int { reason }

    @ObjCMethod("launch")
    func launch() { _ = launch(error: nil) }

    @ObjCMethod("launchAndReturnError:")
    func launch(error: UnsafeMutablePointer<id?>?) -> Bool { spawn(error: error) }

    private func spawn(error: UnsafeMutablePointer<id?>?) -> Bool {
        guard !running, let launchPath else { return false }
        let arguments = [launchPath] + Tasks.strings(self.arguments)
        let environment = Tasks.environment(self.environment)

        var actions = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        let streams: [(object: id?, target: Int32, input: Bool)] = [
            (standardInput, 0, true), (standardOutput, 1, false), (standardError, 2, false),
        ]
        for stream in streams {
            if let descriptor = Tasks.descriptor(stream.object, input: stream.input), descriptor >= 0 {
                posix_spawn_file_actions_adddup2(&actions, descriptor, stream.target)
            }
        }
        if let currentDirectory { posix_spawn_file_actions_addchdir_np(&actions, currentDirectory) }

        var child: pid_t = 0
        let result: Int32 = withCStrings(arguments) { argv in
            if let environment {
                return withCStrings(environment) { envp in posix_spawn(&child, launchPath, &actions, nil, argv, envp) }
            }
            return posix_spawn(&child, launchPath, &actions, nil, argv, environ)
        }
        guard result == 0 else {
            error?.pointee = Errors.autoreleased(domain: Strings.autoreleased("NSPOSIXErrorDomain"), code: Int(result),
                                                   description: String(cString: strerror(result)))
            return false
        }
        Tasks.closeChildEnd(standardInput, input: true)
        Tasks.closeChildEnd(standardOutput, input: false)
        Tasks.closeChildEnd(standardError, input: false)
        pid = child
        running = true
        _ = ObjC.retain(objcObject)
        let waiter = Waiter(pid: child) { code, reason in
            RunLoops.mainLoop.perform(work: { self.ended(status: code, reason: reason) })
        }
        var thread = pthread_t()
        let context = Unmanaged.passRetained(waiter).toOpaque()
        if pthread_create(&thread, nil, { context in
            Unmanaged<Waiter>.fromOpaque(context!).takeRetainedValue().wait()
            return nil
        }, context) == 0 {
            pthread_detach(thread)
        } else {
            Unmanaged<Waiter>.fromOpaque(context).release()
        }
        return true
    }

    /// The task has ended: what launching it retained is let go.
    private func ended(status: Int32, reason: Int) {
        finish(status: status, reason: reason)
        ObjC.release(objcObject)
    }

    func finish(status: Int32, reason: Int) {
        self.status = status
        self.reason = reason
        running = false
        if let handler = terminationHandler {
            typealias Invoke = @convention(c) (id, id) -> Void
            Blocks.invoke(handler, as: Invoke.self)(handler, objcObject)
        }
        if let center = "NSNotificationCenter".withCString({ ObjC.getClass($0) }),
           let defaultCenter = ObjC.send(UnsafeMutableRawPointer(center), ObjC.selector("defaultCenter")) {
            _ = ObjC.send(defaultCenter, ObjC.selector("postNotificationName:object:"),
                          Strings.autoreleased("NSTaskDidTerminateNotification"), objcObject)
        }
    }

    @ObjCMethod("waitUntilExit")
    func waitUntilExit() {
        while running {
            _ = RunLoops.current.run(until: absoluteTimeNow() + 0.05, returnAfterSourceHandled: true)
        }
    }

    @ObjCMethod("terminate") func terminate() { if running { kill(pid, SIGTERM) } }
    @ObjCMethod("interrupt") func interrupt() { if running { kill(pid, SIGINT) } }
    @ObjCMethod("suspend") func suspend() -> Bool { running && kill(pid, SIGSTOP) == 0 }
    @ObjCMethod("resume") func resume() -> Bool { running && kill(pid, SIGCONT) == 0 }
}

/// Waits for a child to end, on a thread of its own: its exit status, or
/// the signal that ended it.
private final class Waiter {
    let pid: pid_t
    let done: (Int32, Int) -> Void

    init(pid: pid_t, done: @escaping (Int32, Int) -> Void) {
        self.pid = pid
        self.done = done
    }

    func wait() {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        let exited = status & 0x7f == 0
        done(exited ? (status >> 8) & 0xff : status & 0x7f, exited ? 1 : 2)
    }
}

/// Calls `body` with a NULL-terminated C array of `strings`.
private func withCStrings<Result>(_ strings: [String], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> Result) -> Result {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    pointers.append(nil)
    defer { for pointer in pointers { free(pointer) } }
    return pointers.withUnsafeBufferPointer { body($0.baseAddress!) }
}
