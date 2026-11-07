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
}

// MARK: - Byte counts

/// Byte counts as people read them: "12 bytes", "1.2 MB", "3 GB", in
/// powers of 1000 (file and decimal styles) or 1024 (memory and binary).
@ObjCClass("NSByteCountFormatter")
public final class NSByteCountFormatter: NSFormatter {
    var countStyle = 0
    var allowsNonnumeric = true
    var includesUnit = true
    var includesCount = true
    var adaptive = true

    @ObjCClassMethod("stringFromByteCount:countStyle:")
    static func string(fromByteCount count: Int64, countStyle: Int) -> String { format(count, style: countStyle) }

    static func format(_ count: Int64, style: Int, includesUnit: Bool = true, includesCount: Bool = true,
                       allowsNonnumeric: Bool = true) -> String {
        if count == 0 && allowsNonnumeric && includesCount { return includesUnit ? "Zero KB" : "Zero" }
        let base: Double = style == 2 || style == 3 ? 1024 : 1000
        let units = ["bytes", "KB", "MB", "GB", "TB", "PB", "EB"]
        var value = Double(count.magnitude)
        var unit = 0
        while value >= base && unit < units.count - 1 {
            value /= base
            unit += 1
        }
        let sign = count < 0 ? "-" : ""
        let number: String
        if unit == 0 {
            number = "\(count)"
        } else {
            let digits = unit == 1 ? 0 : value < 10 ? 1 : 0
            let rounded = (value * pow(10, Double(digits))).rounded() / pow(10, Double(digits))
            number = sign + (digits == 0 ? "\(Int(rounded))" : "\(rounded)")
        }
        let name = unit == 0 && count.magnitude == 1 ? "byte" : units[unit]
        switch (includesCount, includesUnit) {
        case (true, true): return number + " " + name
        case (true, false): return number
        case (false, _): return name
        }
    }

    @ObjCMethod("stringFromByteCount:")
    func string(fromByteCount count: Int64) -> String {
        NSByteCountFormatter.format(count, style: countStyle, includesUnit: includesUnit, includesCount: includesCount,
                                    allowsNonnumeric: allowsNonnumeric)
    }

    @ObjCMethod("stringForObjectValue:")
    override func formatterString(forObjectValue value: ObjCObject?) -> String? {
        guard let value else { return nil }
        typealias Fn = @convention(c) (id?, SEL) -> Int64
        return string(fromByteCount: unsafeBitCast(ObjC.msgSend, to: Fn.self)(value.id, ObjC.selector("longLongValue")))
    }

    @ObjCMethod("countStyle") func countStyleValue() -> Int { countStyle }
    @ObjCMethod("setCountStyle:") func setCountStyle(_ value: Int) { countStyle = value }
    @ObjCMethod("allowsNonnumericFormatting") func allowsNonnumericFormatting() -> Bool { allowsNonnumeric }
    @ObjCMethod("setAllowsNonnumericFormatting:") func setAllowsNonnumericFormatting(_ value: Bool) { allowsNonnumeric = value }
    @ObjCMethod("includesUnit") func includesUnitValue() -> Bool { includesUnit }
    @ObjCMethod("setIncludesUnit:") func setIncludesUnit(_ value: Bool) { includesUnit = value }
    @ObjCMethod("includesCount") func includesCountValue() -> Bool { includesCount }
    @ObjCMethod("setIncludesCount:") func setIncludesCount(_ value: Bool) { includesCount = value }
    @ObjCMethod("isAdaptive") func isAdaptive() -> Bool { adaptive }
    @ObjCMethod("setAdaptive:") func setAdaptive(_ value: Bool) { adaptive = value }
    @ObjCMethod("allowedUnits") func allowedUnits() -> UInt { 0 }
    @ObjCMethod("setAllowedUnits:") func setAllowedUnits(_ value: UInt) {}
}
