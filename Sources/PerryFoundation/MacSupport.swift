import FoundationEssentials
import Glibc
import PerryObjCInterop

// Foundation classes macOS apps set up as they start, which on Linux do
// little: Apple events and script commands (no other app sends them), user
// notifications (shown nowhere), NSHost, NSAssertionHandler, background
// activity scheduling and NSByteCountFormatter.

private func named(_ name: String) -> id? { name.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) } }

private func makeInstance(_ cls: ObjCClass) -> id? {
    ObjC.autorelease(ObjC.send(ObjC.send(cls.pointer, ObjC.selector("alloc")), ObjC.selector("init")))
}

/// A global block taking one integer and ignoring it, for completion
/// handlers whose call needs nothing done.
enum IgnoredBlock {
    nonisolated(unsafe) static let block: UnsafeMutableRawPointer = {
        let invoke: @convention(c) (UnsafeMutableRawPointer?, Int) -> Void = { _, _ in }
        let descriptor = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 8)
        descriptor.storeBytes(of: 0, as: UInt.self)
        descriptor.storeBytes(of: UInt(3 * MemoryLayout<UnsafeRawPointer>.size + 8), toByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UInt.self)
        let block = UnsafeMutableRawPointer.allocate(byteCount: 3 * MemoryLayout<UnsafeRawPointer>.size + 8, alignment: 8)
        block.storeBytes(of: Dispatch.globalBlockClass, as: UnsafeMutableRawPointer?.self)
        block.storeBytes(of: Int32(1 << 28), toByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: Int32.self)   // BLOCK_IS_GLOBAL
        block.storeBytes(of: Int32(0), toByteOffset: MemoryLayout<UnsafeRawPointer>.size + 4, as: Int32.self)
        block.storeBytes(of: unsafeBitCast(invoke, to: UnsafeRawPointer.self), toByteOffset: MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(descriptor), toByteOffset: 2 * MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer.self)
        return block
    }()
}

// MARK: - Apple events

/// Handlers are kept, but no events arrive.
@ObjCClass("NSAppleEventManager")
public final class NSAppleEventManager: NSObject {
    nonisolated(unsafe) static var shared: id?

    @ObjCClassMethod("sharedAppleEventManager")
    static func sharedManager(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        if shared == nil { shared = ObjC.retain(makeInstance(cls)) }
        return shared
    }

    @ObjCMethod("setEventHandler:andSelector:forEventClass:andEventID:")
    func setEventHandler(_ handler: UnsafeMutableRawPointer?, selector: ObjCSelector?, eventClass: UInt32, eventID: UInt32) {}

    @ObjCMethod("removeEventHandlerForEventClass:andEventID:")
    func removeEventHandler(eventClass: UInt32, eventID: UInt32) {}

    @ObjCMethod("currentAppleEvent") func currentAppleEvent() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("currentReplyAppleEvent") func currentReplyAppleEvent() -> UnsafeMutableRawPointer? { nil }
}

@ObjCClass("NSAppleEventDescriptor")
open class NSAppleEventDescriptor: NSObject {
    var string: String?
    var type: UInt32 = 0x6E756C6C // 'null'

    @ObjCClassMethod("nullDescriptor") static func nullDescriptor(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { makeInstance(cls) }

    @ObjCClassMethod("descriptorWithString:")
    static func descriptor(_ cls: ObjCClass, string: String) -> UnsafeMutableRawPointer? {
        let descriptor = makeInstance(cls)
        if let descriptor, let object = NSObject(objCReturnValue: descriptor).as(NSAppleEventDescriptor.self) {
            object.string = string
            object.type = 0x75747874 // 'utxt'
        }
        return descriptor
    }

    @ObjCMethod("stringValue") func stringValue() -> String? { string }
    @ObjCMethod("descriptorType") func descriptorType() -> UInt32 { type }
    @ObjCMethod("numberOfItems") func numberOfItems() -> Int { 0 }
    @ObjCMethod("paramDescriptorForKeyword:") func paramDescriptor(forKeyword keyword: UInt32) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("attributeDescriptorForKeyword:") func attributeDescriptor(forKeyword keyword: UInt32) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("descriptorForKeyword:") func descriptor(forKeyword keyword: UInt32) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("descriptorAtIndex:") func descriptor(at index: Int) -> UnsafeMutableRawPointer? { nil }
}

/// A scripting command: an app's subclasses carry out what its scripting
/// definition names, which nothing sends here.
@ObjCClass("NSScriptCommand")
open class NSScriptCommand: NSObject {
    @ObjCClassMethod("currentCommand") static func currentCommand() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("directParameter") func directParameter() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("evaluatedArguments") func evaluatedArguments() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("arguments") func scriptArguments() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("appleEvent") func appleEvent() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("performDefaultImplementation") func performDefaultImplementation() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("executeCommand") func executeCommand() -> UnsafeMutableRawPointer? {
        ObjC.send(objcObject, ObjC.selector("performDefaultImplementation"))
    }
    @ObjCMethod("setScriptErrorNumber:") func setScriptErrorNumber(_ number: Int) {}
    @ObjCMethod("setScriptErrorString:") func setScriptErrorString(_ string: String?) {}
    @ObjCMethod("suspendExecution") func suspendExecution() {}
    @ObjCMethod("resumeExecutionWithResult:") func resumeExecution(withResult result: UnsafeMutableRawPointer?) {}
}

// MARK: - NSAppleScript

/// Looks at a script a program asked to run and reports what it would do.
/// Perry runs none of it, so this is only to make the attempt visible —
/// above all a `do script`, which drives Terminal, and a command that reaches
/// a private framework or asks for `sudo`, which the sandbox never grants.
enum ScriptInspection {
    static func report(_ source: String?) {
        guard let source, source.contains(where: { !$0.isWhitespace }) else { return }
        let firstLine = source.split(whereSeparator: \.isNewline).first.map(String.init) ?? source
        warn("NSAppleScript: not run, as Linux has no AppleScript: \(firstLine.prefix(200))")

        let lower = source.lowercased()
        var notes: [String] = []
        if lower.contains("do script") || lower.contains("tell application \"terminal\"") { notes.append("drives Terminal") }
        if source.contains("/System/Library/PrivateFrameworks/") { notes.append("a private framework") }
        if lower.contains("apple80211") || lower.contains("/resources/airport") { notes.append("the airport Wi-Fi utility") }
        if lower.contains("sudo ") || lower.contains("with administrator privileges") { notes.append("elevated privileges") }
        guard !notes.isEmpty else { return }
        warn("NSAppleScript: declined privileged or private automation (\(notes.joined(separator: ", "))); Perry does not run it")
    }

    private static func warn(_ message: String) {
        let line = "perry: \(message)\n"
        _ = line.withCString { write(2, $0, strlen($0)) }
    }
}

/// Each script's source, by the Objective-C object: the app allocates and
/// uses the object itself, so the state is kept here rather than on the Swift
/// wrapper, which a dispatch may remake.
private enum ScriptSources {
    nonisolated(unsafe) private static var map: [UnsafeMutableRawPointer: String] = [:]
    nonisolated(unsafe) private static var mutex: pthread_mutex_t = {
        var m = pthread_mutex_t(); pthread_mutex_init(&m, nil); return m
    }()

    static func set(_ object: UnsafeMutableRawPointer, _ source: String?) {
        pthread_mutex_lock(&mutex); defer { pthread_mutex_unlock(&mutex) }
        map[object] = source
    }
    static func get(_ object: UnsafeMutableRawPointer) -> String? {
        pthread_mutex_lock(&mutex); defer { pthread_mutex_unlock(&mutex) }
        return map[object]
    }
    static func remove(_ object: UnsafeMutableRawPointer) {
        pthread_mutex_lock(&mutex); defer { pthread_mutex_unlock(&mutex) }
        map[object] = nil
    }
}

/// NSAppleScript on Linux: there is no AppleScript engine, so a script never
/// runs. The stub lets apps that automate through -executeAndReturnError:
/// go on instead of crashing on a missing class, and reports the attempt.
@ObjCClass("NSAppleScript")
open class NSAppleScript: NSObject {
    @ObjCMethod("initWithSource:")
    func initialize(source: String?) -> NSAppleScript {
        ScriptSources.set(objcObject, source)
        return self
    }

    @ObjCMethod("initWithContentsOfURL:error:")
    func initialize(contentsOf url: UnsafeMutableRawPointer?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSAppleScript {
        error?.pointee = nil
        return self
    }

    @ObjCMethod("source") func sourceString() -> String? { ScriptSources.get(objcObject) }
    @ObjCMethod("isCompiled") func isCompiled() -> Bool { false }
    @ObjCMethod("compileAndReturnError:")
    func compile(error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        error?.pointee = nil
        return true
    }

    /// Reports the script and returns nil, as a failed execution does; the
    /// error dictionary is left nil, which callers take as "no result".
    @ObjCMethod("executeAndReturnError:")
    func execute(error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        ScriptInspection.report(ScriptSources.get(objcObject))
        error?.pointee = nil
        return nil
    }

    @ObjCMethod("executeAppleEvent:error:")
    func execute(appleEvent: UnsafeMutableRawPointer?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        ScriptInspection.report(ScriptSources.get(objcObject))
        error?.pointee = nil
        return nil
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        ScriptSources.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSAppleScript.objCClass.pointer)
    }
}

// MARK: - User notifications

@ObjCClass("NSUserNotification")
open class NSUserNotification: NSObject {
    var values: [String: id] = [:]

    deinit { for value in values.values { ObjC.release(value) } }

    private func get(_ key: String) -> UnsafeMutableRawPointer? { values[key] }
    private func set(_ key: String, _ value: UnsafeMutableRawPointer?) {
        if let old = values[key] { ObjC.release(old) }
        values[key] = value.flatMap { ObjC.send($0, ObjC.selector("copy")) }
    }

    @ObjCMethod("title") func title() -> UnsafeMutableRawPointer? { get("title") }
    @ObjCMethod("setTitle:") func setTitle(_ value: UnsafeMutableRawPointer?) { set("title", value) }
    @ObjCMethod("subtitle") func subtitle() -> UnsafeMutableRawPointer? { get("subtitle") }
    @ObjCMethod("setSubtitle:") func setSubtitle(_ value: UnsafeMutableRawPointer?) { set("subtitle", value) }
    @ObjCMethod("informativeText") func informativeText() -> UnsafeMutableRawPointer? { get("informativeText") }
    @ObjCMethod("setInformativeText:") func setInformativeText(_ value: UnsafeMutableRawPointer?) { set("informativeText", value) }
    @ObjCMethod("identifier") func identifier() -> UnsafeMutableRawPointer? { get("identifier") }
    @ObjCMethod("setIdentifier:") func setIdentifier(_ value: UnsafeMutableRawPointer?) { set("identifier", value) }
    @ObjCMethod("userInfo") func userInfo() -> UnsafeMutableRawPointer? { get("userInfo") }
    @ObjCMethod("setUserInfo:") func setUserInfo(_ value: UnsafeMutableRawPointer?) { set("userInfo", value) }
    @ObjCMethod("soundName") func soundName() -> UnsafeMutableRawPointer? { get("soundName") }
    @ObjCMethod("setSoundName:") func setSoundName(_ value: UnsafeMutableRawPointer?) { set("soundName", value) }
    @ObjCMethod("hasActionButton") func hasActionButton() -> Bool { false }
    @ObjCMethod("setHasActionButton:") func setHasActionButton(_ value: Bool) {}
    @ObjCMethod("actionButtonTitle") func actionButtonTitle() -> UnsafeMutableRawPointer? { get("actionButtonTitle") }
    @ObjCMethod("setActionButtonTitle:") func setActionButtonTitle(_ value: UnsafeMutableRawPointer?) { set("actionButtonTitle", value) }
    @ObjCMethod("otherButtonTitle") func otherButtonTitle() -> UnsafeMutableRawPointer? { get("otherButtonTitle") }
    @ObjCMethod("setOtherButtonTitle:") func setOtherButtonTitle(_ value: UnsafeMutableRawPointer?) { set("otherButtonTitle", value) }
    @ObjCMethod("isPresented") func isPresented() -> Bool { false }
}

/// Notifications are delivered at once and shown nowhere; the delegate is
/// told they were.
@ObjCClass("NSUserNotificationCenter")
public final class NSUserNotificationCenter: NSObject {
    nonisolated(unsafe) static var shared: id?
    /// Not retained.
    var delegate: id?
    var delivered: [id] = []

    @ObjCClassMethod("defaultUserNotificationCenter")
    static func defaultCenter(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        if shared == nil { shared = ObjC.retain(makeInstance(cls)) }
        return shared
    }

    @ObjCMethod("delegate") func delegateValue() -> UnsafeMutableRawPointer? { delegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: UnsafeMutableRawPointer?) { delegate = value }

    @ObjCMethod("deliverNotification:")
    func deliver(_ notification: UnsafeMutableRawPointer?) {
        guard let notification else { return }
        delivered.append(ObjC.retain(notification)!)
        let selector = ObjC.selector("userNotificationCenter:didDeliverNotification:")
        if let delegate, ObjC.sendBool(delegate, ObjC.selector("respondsToSelector:"), UnsafeMutableRawPointer(mutating: selector)) {
            _ = ObjC.send(delegate, selector, objcObject, notification)
        }
    }

    @ObjCMethod("scheduleNotification:") func schedule(_ notification: UnsafeMutableRawPointer?) { deliver(notification) }

    @ObjCMethod("removeDeliveredNotification:")
    func removeDelivered(_ notification: UnsafeMutableRawPointer?) {
        delivered.removeAll { candidate in
            guard candidate == notification else { return false }
            ObjC.release(candidate)
            return true
        }
    }

    @ObjCMethod("removeAllDeliveredNotifications")
    func removeAllDelivered() {
        for notification in delivered { ObjC.release(notification) }
        delivered.removeAll()
    }

    @ObjCMethod("deliveredNotifications") func deliveredNotifications() -> UnsafeMutableRawPointer? { Arrays.autoreleased(delivered) }
    @ObjCMethod("scheduledNotifications") func scheduledNotifications() -> UnsafeMutableRawPointer? { Arrays.autoreleased([]) }
}

// MARK: - The system

/// This computer, by its host name.
@ObjCClass("NSHost")
public final class NSHost: NSObject {
    var hostName = ""

    @ObjCClassMethod("currentHost")
    static func currentHost(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        let host = makeInstance(cls)
        var buffer = [CChar](repeating: 0, count: 256)
        gethostname(&buffer, buffer.count - 1)
        if let host { NSObject(objCReturnValue: host).as(NSHost.self)?.hostName = String(cString: buffer) }
        return host
    }

    @ObjCMethod("name") func name() -> String { hostName }
    @ObjCMethod("localizedName") func localizedName() -> String { hostName }
    @ObjCMethod("names") func names() -> UnsafeMutableRawPointer? { Arrays.autoreleased([Strings.autoreleased(hostName)]) }
    @ObjCMethod("address") func address() -> String { "127.0.0.1" }
    @ObjCMethod("addresses") func addresses() -> UnsafeMutableRawPointer? { Arrays.autoreleased([Strings.autoreleased("127.0.0.1")]) }
}

/// What NSAssert and NSParameterAssert call when they fail: an
/// NSInternalInconsistencyException.
@ObjCClass("NSAssertionHandler")
public final class NSAssertionHandler: NSObject {
    nonisolated(unsafe) static var shared: id?

    @ObjCClassMethod("currentHandler")
    static func currentHandler(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        if shared == nil { shared = ObjC.retain(makeInstance(cls)) }
        return shared
    }

    private func fail(_ message: String) -> Never {
        if let exception = named("NSException") {
            _ = ObjC.send(exception, ObjC.selector("raise:format:"), Strings.autoreleased("NSInternalInconsistencyException"),
                          Strings.autoreleased(message.replacingOccurrences(of: "%", with: "%%")))
        }
        foundationFatal(message)
    }

    @ObjCMethod("handleFailureInMethod:object:file:lineNumber:description:", types: "v56@0:8:16@24@32q40@48")
    func handleFailure(inMethod selector: ObjCSelector?, object: UnsafeMutableRawPointer?, file: String?, lineNumber: Int,
                       description: String?) {
        fail("*** Assertion failure in \(ObjC.className(object)) \(selector?.name ?? "?"), \(file ?? "?"):\(lineNumber): \(description ?? "")")
    }

    @ObjCMethod("handleFailureInFunction:file:lineNumber:description:", types: "v48@0:8@16@24q32@40")
    func handleFailure(inFunction function: String?, file: String?, lineNumber: Int, description: String?) {
        fail("*** Assertion failure in \(function ?? "?"), \(file ?? "?"):\(lineNumber): \(description ?? "")")
    }
}

/// Work to do now and then: the block runs once the interval has passed,
/// on the main run loop, and again each interval when it repeats.
@ObjCClass("NSBackgroundActivityScheduler")
public final class NSBackgroundActivityScheduler: NSObject {
    var identifier = ""
    var interval: Double = 0
    var repeats = false
    var tolerance: Double = 0
    var qualityOfService = -1
    var block: id?

    @ObjCMethod("initWithIdentifier:")
    func initialize(identifier: String) -> Self {
        self.identifier = identifier
        return self
    }

    deinit { invalidate() }

    @ObjCMethod("identifier") func identifierValue() -> String { identifier }
    @ObjCMethod("interval") func intervalValue() -> Double { interval }
    @ObjCMethod("setInterval:") func setInterval(_ value: Double) { interval = value }
    @ObjCMethod("repeats") func repeatsValue() -> Bool { repeats }
    @ObjCMethod("setRepeats:") func setRepeats(_ value: Bool) { repeats = value }
    @ObjCMethod("tolerance") func toleranceValue() -> Double { tolerance }
    @ObjCMethod("setTolerance:") func setTolerance(_ value: Double) { tolerance = value }
    @ObjCMethod("qualityOfService") func qualityOfServiceValue() -> Int { qualityOfService }
    @ObjCMethod("setQualityOfService:") func setQualityOfService(_ value: Int) { qualityOfService = value }
    @ObjCMethod("shouldDefer") func shouldDefer() -> Bool { false }

    /// The block runs each interval, with a completion handler that needs
    /// no call back here: the next run is scheduled already.
    @ObjCMethod("scheduleWithBlock:")
    func schedule(block: UnsafeMutableRawPointer?) {
        invalidate()
        guard let block else { return }
        self.block = ObjC.retainBlock(block)
        scheduleNext()
    }

    private func scheduleNext() {
        perform(ObjCSelector("_perryRunActivity"), with: nil, afterDelay: max(interval, 1))
    }

    @ObjCMethod("_perryRunActivity")
    func runActivity() {
        guard let block else { return }
        typealias Invoke = @convention(c) (id, id?) -> Void
        Blocks.invoke(block, as: Invoke.self)(block, IgnoredBlock.block)
        if repeats { scheduleNext() }
    }

    @ObjCMethod("invalidate")
    func invalidate() {
        guard let block else { return }
        ObjC.release(block)
        self.block = nil
    }
}

/// Distributed objects, which have no other process to talk to here.
@ObjCClass("NSConnection")
public final class NSConnection: NSObject {
    @ObjCClassMethod("defaultConnection") static func defaultConnection(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { makeInstance(cls) }
    @ObjCClassMethod("connectionWithRegisteredName:host:")
    static func connection(registeredName: String?, host: String?) -> UnsafeMutableRawPointer? { nil }
    @ObjCClassMethod("rootProxyForConnectionWithRegisteredName:host:")
    static func rootProxy(registeredName: String?, host: String?) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("registerName:") func registerName(_ name: String?) -> Bool { true }
    @ObjCMethod("setRootObject:") func setRootObject(_ object: UnsafeMutableRawPointer?) {}
    @ObjCMethod("rootProxy") func rootProxy() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("invalidate") func invalidate() {}
    @ObjCMethod("isValid") func isValid() -> Bool { true }
    // Its setup: kept by none, as no request ever comes.
    @ObjCMethod("addRequestMode:") func addRequestMode(_ mode: String?) {}
    @ObjCMethod("removeRequestMode:") func removeRequestMode(_ mode: String?) {}
    @ObjCMethod("requestModes") func requestModes() -> UnsafeMutableRawPointer? { Arrays.autoreleased([]) }
    @ObjCMethod("addRunLoop:") func addRunLoop(_ runLoop: UnsafeMutableRawPointer?) {}
    @ObjCMethod("removeRunLoop:") func removeRunLoop(_ runLoop: UnsafeMutableRawPointer?) {}
    @ObjCMethod("runInNewThread") func runInNewThread() {}
    @ObjCMethod("enableMultipleThreads") func enableMultipleThreads() {}
    @ObjCMethod("setIndependentConversationQueueing:") func setIndependentConversationQueueing(_ value: Bool) {}
    @ObjCMethod("setRequestTimeout:") func setRequestTimeout(_ seconds: Double) {}
    @ObjCMethod("setReplyTimeout:") func setReplyTimeout(_ seconds: Double) {}
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: UnsafeMutableRawPointer?) {}
    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("rootObject") func rootObject() -> UnsafeMutableRawPointer? { nil }
}

// MARK: - Byte counts

/// Byte counts as people read them: "12 bytes", "1.2 MB", "3 GB", in
/// powers of 1000 (file and decimal styles) or 1024 (memory and binary).
/// The unit is the largest allowed that there is one of, once rounded to
/// three digits; adaptive formatting writes kilobytes whole, megabytes
/// with one fraction digit and larger units with two, rounding half up, as
/// on Darwin. The units' names are English.
final class ByteCountFormatterStorage {
    var countStyle = 0
    var allowedUnits: UInt = 0
    var allowsNonnumeric = true
    var includesUnit = true
    var includesCount = true
    var includesActualByteCount = false
    var adaptive = true
    var zeroPadsFractionDigits = false
    var formattingContext = 0
}

@ObjCClass("NSByteCountFormatter")
public final class NSByteCountFormatter: NSFormatter {
    nonisolated(unsafe) static var formatterClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        formatterClass = cls.storage
    }

    /// The settings, kept with the object: the formatter isn't a Swift
    /// peer, so stored properties wouldn't last from one message to the next.
    var settings: ByteCountFormatterStorage {
        if let settings = Storage.get(objcObject, as: ByteCountFormatterStorage.self) { return settings }
        let settings = ByteCountFormatterStorage()
        Storage.set(objcObject, settings)
        return settings
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = settings
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSByteCountFormatter.formatterClass)
    }

    @ObjCClassMethod("stringFromByteCount:countStyle:")
    static func string(fromByteCount count: Int64, countStyle: Int) -> String { format(count, style: countStyle) }

    /// NSByteCountFormatterUnits' units, smallest first; the last,
    /// yottabytes, stands for all from it up.
    private static let unitNames = ["bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]

    static func format(_ count: Int64, style: Int, allowedUnits: UInt = 0, includesUnit: Bool = true, includesCount: Bool = true,
                       allowsNonnumeric: Bool = true, includesActualByteCount: Bool = false, adaptive: Bool = true,
                       zeroPads: Bool = false) -> String {
        if count == 0 && allowsNonnumeric && includesCount && includesUnit {
            // Bytes when they're among a choice of units, else kilobytes.
            return allowedUnits & 1 != 0 && allowedUnits != 0xFFFF ? "Zero bytes" : "Zero KB"
        }
        let allowed = allowedUnits == 0 ? 0xFFFF : allowedUnits
        var units = (0..<unitNames.count).filter { $0 == 8 ? allowed & 0xFF00 != 0 : allowed & (1 << UInt($0)) != 0 }
        if units.isEmpty { units = [0] }
        let base: Double = style == 1 || style == 3 ? 1024 : 1000
        let magnitude = Double(count.magnitude)
        var unit = units[0]
        for candidate in units where magnitude / pow(base, Double(candidate)) >= 0.9995 { unit = candidate }
        let name = unit == 0 && count.magnitude == 1 ? "byte" : unitNames[unit]
        let number: String
        if unit == 0 {
            number = NumberFormatterStorage.roundingHalfUp(fractionDigits: (0, 0)).string(from: Numbers.make(nil, .signed(count))!) ?? "\(count)"
        } else {
            let value = Double(count) / pow(base, Double(unit))
            let formatter: NumberFormatterStorage
            if adaptive {
                let digits = unit == 1 ? 0 : unit == 2 ? 1 : 2
                formatter = .roundingHalfUp(fractionDigits: (zeroPads ? digits : 0, digits))
            } else {
                formatter = .roundingHalfUp(significantDigits: (zeroPads ? 3 : 1, 3))
            }
            number = formatter.string(fromDouble: value)
        }
        var text: String
        switch (includesCount, includesUnit) {
        case (true, true): text = number + " " + name
        case (true, false): text = number
        case (false, _): text = name
        }
        if includesActualByteCount && unit != 0 {
            let exact = NumberFormatterStorage.roundingHalfUp(fractionDigits: (0, 0)).string(from: Numbers.make(nil, .signed(count))!) ?? "\(count)"
            text += " (" + exact + (count.magnitude == 1 ? " byte)" : " bytes)")
        }
        return text
    }

    @ObjCMethod("stringFromByteCount:")
    func string(fromByteCount count: Int64) -> String {
        let current = settings
        return NSByteCountFormatter.format(count, style: current.countStyle, allowedUnits: current.allowedUnits,
                                           includesUnit: current.includesUnit, includesCount: current.includesCount,
                                           allowsNonnumeric: current.allowsNonnumeric,
                                           includesActualByteCount: current.includesActualByteCount, adaptive: current.adaptive,
                                           zeroPads: current.zeroPadsFractionDigits)
    }

    /// An information storage measurement's whole bytes.
    private static func byteCount(of measurement: id) -> Int64 {
        let data = Units.measurement(measurement)
        let bytes = data.unit.map { Units.baseValue(data.value, of: $0) } ?? data.value
        guard bytes.isFinite else { return 0 }
        return Int64(max(min(bytes, 9.2e18), -9.2e18).rounded(.towardZero))
    }

    @ObjCClassMethod("stringFromMeasurement:countStyle:")
    static func string(fromMeasurement measurement: ObjCObject, countStyle: Int) -> String {
        format(byteCount(of: measurement.objcObject), style: countStyle)
    }

    @ObjCMethod("stringFromMeasurement:")
    func string(fromMeasurement measurement: ObjCObject) -> String {
        string(fromByteCount: NSByteCountFormatter.byteCount(of: measurement.objcObject))
    }

    /// Numbers as byte counts, and information storage measurements; nil
    /// for anything else.
    @ObjCMethod("stringForObjectValue:")
    override func formatterString(forObjectValue value: ObjCObject?) -> String? {
        guard let value else { return nil }
        if let measurement = Units.measurementClass, ObjC.isKind(value.id, of: measurement) {
            return string(fromMeasurement: value)
        }
        guard ObjC.isKind(value.id, of: Numbers.numberClass) else { return nil }
        typealias Fn = @convention(c) (id?, SEL) -> Int64
        return string(fromByteCount: unsafeBitCast(ObjC.msgSend, to: Fn.self)(value.id, ObjC.selector("longLongValue")))
    }

    @ObjCMethod("countStyle") func countStyleValue() -> Int { settings.countStyle }
    @ObjCMethod("setCountStyle:") func setCountStyle(_ value: Int) { settings.countStyle = value }
    @ObjCMethod("allowsNonnumericFormatting") func allowsNonnumericFormatting() -> Bool { settings.allowsNonnumeric }
    @ObjCMethod("setAllowsNonnumericFormatting:") func setAllowsNonnumericFormatting(_ value: Bool) { settings.allowsNonnumeric = value }
    @ObjCMethod("includesUnit") func includesUnitValue() -> Bool { settings.includesUnit }
    @ObjCMethod("setIncludesUnit:") func setIncludesUnit(_ value: Bool) { settings.includesUnit = value }
    @ObjCMethod("includesCount") func includesCountValue() -> Bool { settings.includesCount }
    @ObjCMethod("setIncludesCount:") func setIncludesCount(_ value: Bool) { settings.includesCount = value }
    /// Whether a count in a larger unit adds its bytes: "1.2 MB (1,234,567 bytes)".
    @ObjCMethod("includesActualByteCount") func includesActualByteCountValue() -> Bool { settings.includesActualByteCount }
    @ObjCMethod("setIncludesActualByteCount:")
    func setIncludesActualByteCount(_ value: Bool) { settings.includesActualByteCount = value }
    /// Whether the fraction digits depend on the unit; otherwise three
    /// significant digits.
    @ObjCMethod("isAdaptive") func isAdaptive() -> Bool { settings.adaptive }
    @ObjCMethod("setAdaptive:") func setAdaptive(_ value: Bool) { settings.adaptive = value }
    /// Whether trailing zeros stay: "1.0 MB".
    @ObjCMethod("zeroPadsFractionDigits") func zeroPadsFractionDigitsValue() -> Bool { settings.zeroPadsFractionDigits }
    @ObjCMethod("setZeroPadsFractionDigits:") func setZeroPadsFractionDigits(_ value: Bool) { settings.zeroPadsFractionDigits = value }
    /// NSByteCountFormatterUnits; 0 for any.
    @ObjCMethod("allowedUnits") func allowedUnits() -> UInt { settings.allowedUnits }
    @ObjCMethod("setAllowedUnits:") func setAllowedUnits(_ value: UInt) { settings.allowedUnits = value }
    /// Kept: English unit names don't change with it.
    @ObjCMethod("formattingContext") func formattingContextValue() -> Int { settings.formattingContext }
    @ObjCMethod("setFormattingContext:") func setFormattingContext(_ value: Int) { settings.formattingContext = value }

    /// Byte counts aren't parsed, on Darwin either.
    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func getObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String?,
                        errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        value?.pointee = nil
        return false
    }
}
