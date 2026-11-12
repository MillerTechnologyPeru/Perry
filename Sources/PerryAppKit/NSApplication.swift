import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSApplication: the one application, its delegate, and the event loop.
// -run finishes launching and then takes events with
// -nextEventMatchingMask:untilDate:inMode:dequeue: and sends them with
// -sendEvent:, as AppKit's does, so an app that overrides either, or runs
// its own loop with them, works the same. Waiting for an event runs the
// main run loop (timers, the main queue, performs) and draws the windows.

@ObjCClass("NSApplication")
open class NSApplication: NSResponder {
    /// Not retained, as AppKit's.
    var delegateObject: UnsafeMutableRawPointer?
    var running = false
    var launched = false
    var activationPending = false
    var active = false
    var hidden = false
    var activationPolicy = 0
    var presentationOptions: UInt = 0
    var mainMenu: NSObject?
    var windowsMenu: NSObject?
    var servicesMenu: NSObject?
    var helpMenu: NSObject?
    var applicationIconImage: NSObject?
    var appearance: NSObject?
    var currentEvent: NSEvent?
    /// Events taken from SDL and posted, waiting to be asked for.
    var queue: [NSEvent] = []
    var modalWindow: NSWindow?
    var modalResponse = 0

    /// AppKit's -init sets NSApp, so a subclass's own -init makes the one
    /// application too.
    @ObjCMethod("init")
    public required init() {
        super.init()
        if App.shared == nil { App.shared = self }
    }

    static func wrap(_ object: UnsafeMutableRawPointer) -> NSApplication { NSApplication.objCInstance(object, ownership: .retain) }

    /// The application, made from the class asked the first time.
    @ObjCClassMethod("sharedApplication")
    static func sharedApplication(_ cls: ObjCClass) -> NSApplication? {
        if let shared = App.shared { return shared }
        let made = cls.object.allocated().initialized()
        guard App.shared?.objcObject == made.objcObject else {
            App.shared = made.as(NSApplication.self)
            return App.shared
        }
        return App.shared
    }

    // MARK: Delegate

    @ObjCMethod("delegate") func appDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { delegateObject = delegate?.objcObject }

    /// Tells the delegate, then posts the notification.
    func notify(_ selector: String, _ name: String, userInfo: NSObject? = nil) {
        let notification = NSNotification.make(name: name, object: self, userInfo: userInfo)
        if Send.responds(delegateObject, selector) { Send.void(delegateObject, selector, notification.objcObject) }
        NSNotificationCenter.defaultCenter().post(notification)
    }

    // MARK: Launching and running

    @ObjCMethod("finishLaunching")
    func finishLaunching() {
        guard !launched else { return }
        launched = true
        Signals.install()
        notify("applicationWillFinishLaunching:", Constants.NSApplicationWillFinishLaunchingNotification)
        let info = NSMutableDictionary.empty()
        info.set(NSNumber.make(bool: true), forKey: Constants.NSApplicationLaunchIsDefaultLaunchKey)
        notify("applicationDidFinishLaunching:", Constants.NSApplicationDidFinishLaunchingNotification, userInfo: info)
        NSDocumentController.openAtLaunch(delegate: delegateObject)
        // Activation is an event, delivered when the program next asks for
        // one: a game with its own loop finishes launching, then sets up.
        activationPending = true
    }

    /// With PERRY_APPKIT_TYPE set, its text is typed into the key window
    /// four seconds after launch, a key at a time ("\\n" is Return), to try
    /// an app's text input without a keyboard.
    @ObjCMethod("_perryTypeScriptedText")
    func typeScriptedText() {
        guard let text = getenv("PERRY_APPKIT_TYPE").map({ String(cString: $0) }) else { return }
        let window = Windows.key ?? Windows.all.last { $0.visible }
        for character in text.replacingEscapes() {
            let (keyCode, characters): (UInt16, String) = character == "\n" ? (0x24, "\r") : character == "\t" ? (0x30, "\t") : (0, String(character))
            guard let event = NSEvent.keyEvent(type: EventType.keyDown.rawValue, location: .zero, modifierFlags: 0, timestamp: Clock.now,
                                               windowNumber: window?.windowNumber ?? 0, context: nil, characters: characters,
                                               charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else { continue }
            Send.void(objcObject, "sendEvent:", event.objcObject)
        }
    }

    /// With PERRY_APPKIT_CLICKS set to "x,y;x,y…", clicks at those points
    /// of the first window shown (from its top left), two seconds apart
    /// starting six seconds after launch, go to the window on top there:
    /// to try menus and controls without a mouse.
    /// An entry "s:x,y,dy" scrolls there instead, dy wheel lines (up
    /// positive), as a mouse wheel's notches.
    nonisolated(unsafe) private static var scriptedClicks: [(point: CGPoint, scroll: CGFloat?)]? = getenv("PERRY_APPKIT_CLICKS").map { value in
        String(cString: value).split(separator: ";").compactMap { entry in
            let scrolls = entry.hasPrefix("s:")
            let numbers = entry.dropFirst(scrolls ? 2 : 0).split(separator: ",").compactMap { Double($0.filter { $0 != " " }).map { CGFloat($0) } }
            if scrolls { return numbers.count == 3 ? (CGPoint(x: numbers[0], y: numbers[1]), CGFloat(numbers[2])) : nil }
            return numbers.count == 2 ? (CGPoint(x: numbers[0], y: numbers[1]), nil) : nil
        }
    }
    nonisolated(unsafe) private static var clickWindow: NSWindow?

    @ObjCMethod("_perryScriptedClick")
    func scriptedClick() {
        guard var clicks = NSApplication.scriptedClicks, !clicks.isEmpty else { return }
        let (point, scroll) = clicks.removeFirst()
        NSApplication.scriptedClicks = clicks
        if NSApplication.clickWindow == nil { NSApplication.clickWindow = Windows.all.first { $0.visible } }
        if let base = NSApplication.clickWindow {
            let screen = CGPoint(x: base.frame.minX + point.x, y: base.frame.maxY - point.y)
            let target = Windows.all.last { $0.visible && $0.frame.contains(screen) } ?? base
            let local = CGPoint(x: screen.x - target.frame.minX, y: screen.y - target.frame.minY)
            if let scroll {
                Trace.log("scripted scroll of \(scroll) at \(point) in window \(target.windowNumber)")
                let event = NSEvent(.scrollWheel, window: target, location: local)
                (event.deltaY, event.scrollingDeltaY) = (scroll, scroll)
                queue.append(event)
                return
            }
            Trace.log("scripted click at \(point) in window \(target.windowNumber)")
            for type in [EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent(type, window: target, location: local)
                event.clickCount = 1
                queue.append(event)
            }
        }
    }

    private func scheduleScriptedClick(after delay: Double) {
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?, Double) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(objcObject, ObjCRuntime.selector("performSelector:withObject:afterDelay:"),
                                                       ObjCRuntime.selector("_perryScriptedClick"), nil, delay)
    }

    @ObjCMethod("run")
    func run() {
        Send.void(objcObject, "finishLaunching")
        for index in NSApplication.scriptedClicks?.indices ?? 0..<0 { scheduleScriptedClick(after: 6 + 2 * Double(index)) }
        if getenv("PERRY_APPKIT_TYPE") != nil {
            typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?, Double) -> Void
            unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(objcObject, ObjCRuntime.selector("performSelector:withObject:afterDelay:"),
                                                           ObjCRuntime.selector("_perryTypeScriptedText"), nil, 4)
        }
        running = true
        let mode = "kCFRunLoopDefaultMode".objCArgument()
        let future = NSDate.distantFuture()
        while running {
            ObjCRuntime.autoreleasepool {
                if let event = Send.nextEvent(objcObject, mask: UInt64.max, until: future.objcObject, mode: mode, dequeue: true) {
                    Send.void(objcObject, "sendEvent:", event)
                }
                Send.void(objcObject, "updateWindows")
            }
        }
    }

    @ObjCMethod("isRunning") func isRunning() -> Bool { running }

    /// Stops -run after the event being handled, as AppKit's does: an
    /// event is posted so a loop waiting for one wakes.
    @ObjCMethod("stop:")
    func stop(_ sender: NSObject?) {
        running = false
        queue.append(NSEvent(.applicationDefined, window: nil, location: .zero))
    }

    /// The delegate may cancel or delay; then the app ends.
    @ObjCMethod("terminate:")
    func terminate(_ sender: NSObject?) {
        // NSTerminateCancel 0, NSTerminateNow 1, NSTerminateLater 2.
        if let reply = Send.reply(delegateObject, "applicationShouldTerminate:", objcObject), reply != 1 {
            if reply == 2 { Trace.log("termination delayed by the delegate") }
            return
        }
        end()
    }

    @ObjCMethod("replyToApplicationShouldTerminate:")
    func reply(toApplicationShouldTerminate shouldTerminate: Bool) {
        if shouldTerminate { end() }
    }

    func end() -> Never {
        notify("applicationWillTerminate:", Constants.NSApplicationWillTerminateNotification)
        exit(0)
    }

    // MARK: Events

    /// The next event matching `mask`, from those posted and SDL's, waiting
    /// until `date` (nil: not at all) while running the run loop and
    /// drawing the windows.
    @ObjCMethod("nextEventMatchingMask:untilDate:inMode:dequeue:")
    func nextEvent(matching wordMask: UInt, until date: NSObject?, inMode mode: NSObject?, dequeue: Bool) -> NSEvent? {
        let mask = NSEvent.mask(fromWord: wordMask)
        let deadline = date.map { $0.sendTimeIntervalSinceReferenceDate() } ?? -Double.infinity
        if activationPending {
            activationPending = false
            activate(true)
        }
        var ranLoop = false
        while true {
            Events.pump()
            while let index = queue.firstIndex(where: { $0.type.mask & mask != 0 }) {
                let event = queue[index]
                if !dequeue { return event }
                queue.remove(at: index)
                currentEvent = event
                // Local monitors may change the event, or take it.
                guard let filtered = Monitors.filter(event) else { continue }
                return filtered == event.objcObject ? event : NSEvent.objCInstance(filtered, ownership: .retain)
            }
            Windows.drawIfNeeded()
            let remaining = deadline - Clock.absolute
            guard remaining > 0 else {
                // A date already past (programs that poll pass distantPast)
                // still has the run loop run once without waiting, as it is
                // on a Mac: timers due, sources ready and blocks queued are
                // handled, then events looked for again.
                if ranLoop { return nil }
                ranLoop = true
                RunLoop.run(for: 0)
                continue
            }
            ranLoop = true
            // Timers and the main queue, for a little while; a run loop with
            // nothing to run returns at once, so the wait is a short sleep.
            let start = Clock.now
            RunLoop.run(for: min(remaining, 0.004))
            if Clock.now - start < 0.001 { usleep(UInt32(min(remaining, 0.002) * 1_000_000)) }
        }
    }

    @ObjCMethod("discardEventsMatchingMask:beforeEvent:")
    func discardEvents(matching wordMask: UInt, before event: NSEvent?) {
        let mask = NSEvent.mask(fromWord: wordMask)
        Events.pump()
        let limit = event?.eventNumber ?? Int.max
        queue.removeAll { $0.type.mask & mask != 0 && $0.eventNumber < limit }
    }

    @ObjCMethod("postEvent:atStart:")
    func postEvent(_ event: NSEvent?, atStart: Bool) {
        guard let event else { return }
        if atStart { queue.insert(event, at: 0) } else { queue.append(event) }
    }

    /// Sends an event to its window, or key events to the key window.
    @ObjCMethod("sendEvent:")
    func sendEvent(_ eventObject: NSObject?) {
        guard let event = eventObject?.as(NSEvent.self) else { return }
        currentEvent = event
        let window = event.type.isKey ? (Windows.key ?? event.window) : (event.window ?? Windows.key)
        guard let window else { return }
        Send.void(window.objcObject, "sendEvent:", event.objcObject)
    }

    @ObjCMethod("currentEvent") func appCurrentEvent() -> NSEvent? { currentEvent }
    @ObjCMethod("updateWindows") func updateWindows() {}
    @ObjCMethod("setWindowsNeedUpdate:") func setWindowsNeedUpdate(_ value: Bool) {}

    @ObjCMethod("sendAction:to:from:")
    func sendAction(_ action: ObjCSelector?, to target: NSObject?, from sender: NSObject?) -> Bool {
        guard let action else { return false }
        let name = action.name
        if let target {
            guard Send.responds(target.objcObject, name) else { return false }
            Send.void(target.objcObject, name, sender?.objcObject)
            return true
        }
        guard let receiver = self.receiver(forAction: name) else { return false }
        Send.void(receiver, name, sender?.objcObject)
        return true
    }

    /// What an action with no target goes to, as AppKit finds it: along the
    /// key window's responder chain from its first responder, then the key
    /// window's delegate, then the same for the main window, then the
    /// application and its delegate.
    func receiver(forAction name: String) -> UnsafeMutableRawPointer? {
        var candidates: [UnsafeMutableRawPointer?] = []
        for window in [Windows.key, Windows.main].compactMap({ $0 }) {
            var responder: UnsafeMutableRawPointer? = window.firstResponderObject ?? window.objcObject
            var seen = 0
            while let current = responder, seen < 64 {
                candidates.append(current)
                responder = Send.object(current, "nextResponder")
                seen += 1
            }
            candidates.append(window.objcObject)
            candidates.append(window.delegateObject)
        }
        candidates.append(objcObject)
        candidates.append(delegateObject)
        return candidates.lazy.compactMap { $0 }.first { Send.responds($0, name) }
    }

    @ObjCMethod("targetForAction:")
    func target(forAction action: ObjCSelector?) -> NSObject? {
        action.flatMap { receiver(forAction: $0.name) }.map(NSObject.init)
    }
    @ObjCMethod("targetForAction:to:from:")
    func target(forAction action: ObjCSelector?, to target: NSObject?, from sender: NSObject?) -> NSObject? {
        if let target { return target }
        return action.flatMap { receiver(forAction: $0.name) }.map(NSObject.init)
    }

    // MARK: Activation

    /// Becoming active or not, as the window gains or loses focus.
    func activate(_ on: Bool) {
        guard active != on, launched else { return }
        if on {
            notify("applicationWillBecomeActive:", Constants.NSApplicationWillBecomeActiveNotification)
            active = true
            notify("applicationDidBecomeActive:", Constants.NSApplicationDidBecomeActiveNotification)
        } else {
            notify("applicationWillResignActive:", Constants.NSApplicationWillResignActiveNotification)
            active = false
            notify("applicationDidResignActive:", Constants.NSApplicationDidResignActiveNotification)
        }
    }

    @ObjCMethod("isActive") func isActive() -> Bool { active }
    @ObjCMethod("activateIgnoringOtherApps:") func activate(ignoringOtherApps flag: Bool) { activate(true) }
    @ObjCMethod("activate") func activateApp() { activate(true) }
    @ObjCMethod("deactivate") func deactivate() { activate(false) }
    @ObjCMethod("yieldActivationToApplication:") func yieldActivation(to application: NSObject?) {}
    @ObjCMethod("hide:")
    func hide(_ sender: NSObject?) {
        guard !hidden else { return }
        notify("applicationWillHide:", "NSApplicationWillHideNotification")
        hidden = true
        for window in Windows.all where window.visible { window.miniaturize(nil) }
        notify("applicationDidHide:", Constants.NSApplicationDidHideNotification)
    }
    @ObjCMethod("unhide:")
    func unhide(_ sender: NSObject?) {
        guard hidden else { return }
        hidden = false
        notify("applicationDidUnhide:", Constants.NSApplicationDidUnhideNotification)
    }
    @ObjCMethod("unhideWithoutActivation") func unhideWithoutActivation() { unhide(nil) }
    @ObjCMethod("isHidden") func isHidden() -> Bool { hidden }
    @ObjCMethod("hideOtherApplications:") func hideOtherApplications(_ sender: NSObject?) {}
    @ObjCMethod("unhideAllApplications:") func unhideAllApplications(_ sender: NSObject?) {}

    /// NSApplicationActivationPolicy: regular 0, accessory 1, prohibited 2.
    @ObjCMethod("activationPolicy") func appActivationPolicy() -> Int { activationPolicy }
    @ObjCMethod("setActivationPolicy:")
    func setActivationPolicy(_ policy: Int) -> Bool {
        activationPolicy = policy
        return true
    }
    @ObjCMethod("presentationOptions") func appPresentationOptions() -> UInt { presentationOptions }
    @ObjCMethod("setPresentationOptions:") func setPresentationOptions(_ options: UInt) { presentationOptions = options }
    @ObjCMethod("currentSystemPresentationOptions") func currentSystemPresentationOptions() -> UInt { presentationOptions }
    /// NSApplicationOcclusionState: visible 2.
    @ObjCMethod("occlusionState") func occlusionState() -> UInt { hidden ? 0 : 2 }
    @ObjCMethod("requestUserAttention:") func requestUserAttention(_ type: UInt) -> Int { 0 }
    @ObjCMethod("cancelUserAttentionRequest:") func cancelUserAttentionRequest(_ request: Int) {}

    // MARK: Windows

    @ObjCMethod("windows") func windows() -> NSObject { NSMutableArray.of(Windows.all) }
    @ObjCMethod("keyWindow") func keyWindow() -> NSWindow? { Windows.key }
    @ObjCMethod("mainWindow") func mainWindow() -> NSWindow? { Windows.main }
    @ObjCMethod("windowWithWindowNumber:") func window(withWindowNumber number: Int) -> NSWindow? { Windows.numbered(number) }
    @ObjCMethod("orderedWindows") func orderedWindows() -> NSObject { NSMutableArray.of(Windows.all.reversed()) }
    @ObjCMethod("makeWindowsPerform:inOrder:")
    func makeWindowsPerform(_ selector: ObjCSelector?, inOrder: Bool) -> NSWindow? {
        guard let selector else { return nil }
        for window in Windows.all.reversed() where Send.bool(window.objcObject, selector.name) { return window }
        return nil
    }
    @ObjCMethod("miniaturizeAll:") func miniaturizeAll(_ sender: NSObject?) { Windows.all.forEach { $0.miniaturize(nil) } }
    @ObjCMethod("arrangeInFront:") func arrangeInFront(_ sender: NSObject?) {}

    // MARK: Modal windows

    /// A modal window runs until -stopModal: the event loop goes on, with
    /// the window in front.
    @ObjCMethod("runModalForWindow:")
    func runModal(for window: NSWindow?) -> Int {
        guard let window else { return -1001 }
        modalWindow = window
        modalResponse = -1001     // NSModalResponseAbort until stopped
        Send.void(window.objcObject, "makeKeyAndOrderFront:", nil)
        let mode = Constants.NSModalPanelRunLoopMode.objCArgument()
        let future = NSDate.distantFuture()
        while modalWindow === window {
            ObjCRuntime.autoreleasepool {
                if let event = Send.nextEvent(objcObject, mask: UInt64.max, until: future.objcObject, mode: mode, dequeue: true) {
                    Send.void(objcObject, "sendEvent:", event)
                }
            }
        }
        return modalResponse
    }

    @ObjCMethod("stopModal") func stopModal() { stopModal(withCode: -1000) }
    @ObjCMethod("stopModalWithCode:")
    func stopModal(withCode code: Int) {
        modalResponse = code
        modalWindow = nil
    }
    @ObjCMethod("abortModal") func abortModal() { stopModal(withCode: -1001) }
    @ObjCMethod("modalWindow") func appModalWindow() -> NSWindow? { modalWindow }
    @ObjCMethod("beginModalSessionForWindow:")
    func beginModalSession(for window: NSWindow?) -> UnsafeMutableRawPointer? {
        guard let window else { return nil }
        modalWindow = window
        Send.void(window.objcObject, "makeKeyAndOrderFront:", nil)
        return window.objcObject
    }
    /// NSModalResponseContinue (-1002) while the window is modal.
    @ObjCMethod("runModalSession:")
    func runModalSession(_ session: UnsafeMutableRawPointer?) -> Int {
        let now = NSDate.make(timeIntervalSinceReferenceDate: Clock.absolute)
        if let event = Send.nextEvent(objcObject, mask: UInt64.max, until: now.objcObject, mode: nil, dequeue: true) {
            Send.void(objcObject, "sendEvent:", event)
        }
        return modalWindow == nil ? modalResponse : -1002
    }
    @ObjCMethod("endModalSession:") func endModalSession(_ session: UnsafeMutableRawPointer?) { modalWindow = nil }

    // MARK: Menus, icon and appearance

    @ObjCMethod("mainMenu") func appMainMenu() -> NSObject? { mainMenu }
    @ObjCMethod("setMainMenu:") func setMainMenu(_ menu: NSObject?) {
        mainMenu = menu
        for window in Windows.all where window.visible { window.chromeChanged() }
    }
    @ObjCMethod("windowsMenu") func appWindowsMenu() -> NSObject? { windowsMenu }
    @ObjCMethod("setWindowsMenu:") func setWindowsMenu(_ menu: NSObject?) { windowsMenu = menu }
    @ObjCMethod("servicesMenu") func appServicesMenu() -> NSObject? { servicesMenu }
    @ObjCMethod("setServicesMenu:") func setServicesMenu(_ menu: NSObject?) { servicesMenu = menu }
    @ObjCMethod("helpMenu") func appHelpMenu() -> NSObject? { helpMenu }
    @ObjCMethod("setHelpMenu:") func setHelpMenu(_ menu: NSObject?) { helpMenu = menu }
    @ObjCMethod("setAppleMenu:") func setAppleMenu(_ menu: NSObject?) {}
    @ObjCMethod("applicationIconImage") func appApplicationIconImage() -> NSObject? { applicationIconImage }
    @ObjCMethod("setApplicationIconImage:") func setApplicationIconImage(_ image: NSObject?) { applicationIconImage = image }
    @ObjCMethod("dockTile") func dockTile() -> NSObject? { nil }
    @ObjCMethod("appearance") func appAppearance() -> NSObject? { appearance }
    @ObjCMethod("setAppearance:") func setAppearance(_ appearance: NSObject?) { self.appearance = appearance }
    /// The app's appearance, or the desktop's.
    @ObjCMethod("effectiveAppearance") func effectiveAppearance() -> NSObject? { appearance ?? NSAppearance.system }
    @ObjCMethod("userInterfaceLayoutDirection") func userInterfaceLayoutDirection() -> Int { 0 }
    @ObjCMethod("isFullKeyboardAccessEnabled") func isFullKeyboardAccessEnabled() -> Bool { false }
    @ObjCMethod("orderFrontStandardAboutPanel:") func orderFrontStandardAboutPanel(_ sender: NSObject?) {}
    @ObjCMethod("orderFrontStandardAboutPanelWithOptions:") func orderFrontStandardAboutPanel(options: NSObject?) {}
    @ObjCMethod("setAutomaticCustomizeTouchBarMenuItemEnabled:") func setAutomaticCustomizeTouchBarMenuItemEnabled(_ value: Bool) {}
    @ObjCMethod("registerForRemoteNotifications") func registerForRemoteNotifications() {}
    @ObjCMethod("unregisterForRemoteNotifications") func unregisterForRemoteNotifications() {}
    @ObjCMethod("isRegisteredForRemoteNotifications") func isRegisteredForRemoteNotifications() -> Bool { false }
    @ObjCMethod("registerForRemoteNotificationTypes:") func registerForRemoteNotificationTypes(_ types: UInt) {}
    @ObjCMethod("enabledRemoteNotificationTypes") func enabledRemoteNotificationTypes() -> UInt { 0 }
    @ObjCMethod("registerServicesMenuSendTypes:returnTypes:") func registerServicesMenuSendTypes(_ send: NSObject?, returnTypes: NSObject?) {}
    @ObjCMethod("enumerateWindowsWithOptions:usingBlock:")
    func enumerateWindows(options: Int, using block: ObjCBlock) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafeMutablePointer<Bool>) -> Void
        var stop = false
        for window in Windows.all.reversed() {
            block.function(as: Invoke.self)(block.object, window.objcObject, &stop)
            if stop { break }
        }
    }
}

/// BOOL NSApplicationLoad(void): AppKit made ready for a program that
/// runs its own event loop (Carbon's): the shared application, made.
@c(_NSApplicationLoad)
public func NSApplicationLoad() -> Bool {
    if let cls = Classes.named("NSApplication") { _ = Send.object(cls.pointer, "sharedApplication") }
    return true
}

/// int NSApplicationMain(int argc, const char *argv[]): the principal
/// class's shared application, with the main nib loaded, run.
@c(_NSApplicationMain)
public func NSApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32 {
    ObjCRuntime.autoreleasepool {
        let info = NSBundle.main()
        let principal = info.infoObject(forKey: "NSPrincipalClass")?.stringValue ?? "NSApplication"
        guard let cls = Classes.named(principal) ?? Classes.named("NSApplication") else {
            appKitFatal("Unable to find class: \(principal), exiting")
        }
        let application = Send.object(cls.pointer, "sharedApplication")
        if let nib = info.infoObject(forKey: "NSMainNibFile")?.stringValue, let application {
            NibLoader.loadMainNib(named: nib, owner: NSObject(application))
        }
        // The main storyboard: its menu, then its initial controller shown.
        if let name = info.infoObject(forKey: "NSMainStoryboardFile")?.stringValue, let application {
            if let storyboard = NSStoryboard.load(named: name, bundle: nil) {
                NSStoryboard.main = storyboard
                storyboard.loadMainMenu(owner: NSObject(application))
                if let controller = storyboard.instantiateInitialController() {
                    Nibs.kept.append(controller)
                    if let windowController = controller.as(NSWindowController.self) {
                        Send.void(windowController.objcObject, "showWindow:", nil)
                    } else if let viewController = controller.as(NSViewController.self) {
                        viewController.presentInWindow()
                    }
                }
            } else {
                appKitWarning("no main storyboard \(name)")
            }
        }
        Send.void(application, "run")
    }
    return 0
}

/// NSBeep: nothing to hear.
@c(_NSBeep)
public func NSBeep() {}

/// NSDisableScreenUpdates and NSEnableScreenUpdates: windows draw to the
/// screen as each frame is done, so there are no updates to hold back.
@c(_NSDisableScreenUpdates)
public func NSDisableScreenUpdates() {}

@c(_NSEnableScreenUpdates)
public func NSEnableScreenUpdates() {}

/// SIGTERM, SIGINT and SIGHUP end the app through -terminate:, as quitting
/// does, on the main queue; a second one exits at once.
enum Signals {
    nonisolated(unsafe) static var installed = false
    nonisolated(unsafe) static var ending = false

    static func install() {
        guard !installed else { return }
        installed = true
        for signal in [SIGTERM, SIGINT, SIGHUP] {
            Glibc.signal(signal) { _ in
                if Signals.ending { _exit(0) }
                Signals.ending = true
                Dispatch.onMain { if let app = App.shared { Send.void(app.objcObject, "terminate:", nil) } else { exit(0) } }
            }
        }
    }
}

private extension String {
    /// "\\n" and "\\t" as the characters they stand for.
    func replacingEscapes() -> String {
        var result = ""
        var escaped = false
        for character in self {
            if escaped {
                result.append(character == "n" ? "\n" : character == "t" ? "\t" : character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}
