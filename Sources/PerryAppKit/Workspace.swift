import CPerryGeometry
import Glibc
import PerryObjCInterop

// The system around the app: the pasteboard (SDL's clipboard, for text),
// sounds (silent), the running application, and the workspace, which
// opens nothing here and says so.

@ObjCClass("NSPasteboard")
open class NSPasteboard: NSObject {
    var changeCount = 0
    var name = "Apple CFPasteboard general"

    nonisolated(unsafe) static var general: NSPasteboard?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("generalPasteboard")
    static func generalPasteboard() -> NSPasteboard {
        if let general { return general }
        let board = NSPasteboard()
        general = board
        return board
    }

    @ObjCClassMethod("pasteboardWithName:")
    static func pasteboard(name: String?) -> NSPasteboard { generalPasteboard() }

    @ObjCMethod("name") func boardName() -> String { name }
    @ObjCMethod("changeCount") func boardChangeCount() -> Int { changeCount }

    @ObjCMethod("clearContents")
    func clearContents() -> Int {
        changeCount += 1
        if SDL.start() { _ = "".withCString { SDL.setClipboardText($0) } }
        return changeCount
    }

    @ObjCMethod("declareTypes:owner:")
    func declareTypes(_ types: NSObject?, owner: NSObject?) -> Int { clearContents() }
    @ObjCMethod("addTypes:owner:") func addTypes(_ types: NSObject?, owner: NSObject?) -> Int { changeCount }

    @ObjCMethod("setString:forType:")
    func setString(_ string: String?, forType type: String?) -> Bool {
        guard SDL.start() else { return false }
        changeCount += 1
        return (string ?? "").withCString { SDL.setClipboardText($0) }
    }

    @ObjCMethod("stringForType:")
    func string(forType type: String?) -> String? {
        guard SDL.start(), let text = SDL.getClipboardText() else { return nil }
        defer { SDL.free(text) }
        let string = String(cString: text)
        return string.isEmpty ? nil : string
    }

    @ObjCMethod("types")
    func types() -> NSObject {
        let types = NSMutableArray.empty()
        if string(forType: nil) != nil { types.add(NSObject(Constants.NSPasteboardTypeStringObject)) }
        return types
    }

    @ObjCMethod("availableTypeFromArray:")
    func availableType(from types: NSObject?) -> String? {
        guard string(forType: nil) != nil,
              types?.as(NSArray.self)?.elements.contains(where: { $0.stringValue == Constants.NSPasteboardTypeString }) == true else { return nil }
        return Constants.NSPasteboardTypeString
    }

    @ObjCMethod("dataForType:") func data(forType type: String?) -> NSObject? { nil }
    @ObjCMethod("setData:forType:") func setData(_ data: NSObject?, forType type: String?) -> Bool { false }
    /// Strings, and pasteboard items' strings, go on the clipboard.
    @ObjCMethod("writeObjects:")
    func writeObjects(_ objects: NSObject?) -> Bool {
        guard let first = objects?.as(NSArray.self)?.elements.first else { return false }
        if let item = first.as(NSPasteboardItem.self) {
            guard let text = item.strings[Constants.NSPasteboardTypeString] ?? item.strings.values.first else { return false }
            return setString(text, forType: Constants.NSPasteboardTypeString)
        }
        guard ObjCRuntime.isKind(first.objcObject, of: ObjCRuntime.classObject("NSString")) else { return false }
        return setString(first.stringValue, forType: Constants.NSPasteboardTypeString)
    }
    @ObjCMethod("readObjectsForClasses:options:")
    func readObjects(forClasses classes: NSObject?, options: NSObject?) -> NSObject? {
        guard let text = string(forType: nil) else { return NSMutableArray.empty() }
        let array = NSMutableArray.empty()
        if let object = text.objCArgument() { array.add(NSObject(object)) }
        return array
    }
    @ObjCMethod("canReadObjectForClasses:options:")
    func canReadObject(forClasses classes: NSObject?, options: NSObject?) -> Bool { string(forType: nil) != nil }
    @ObjCMethod("pasteboardItems") func pasteboardItems() -> NSObject { NSMutableArray.empty() }
}

/// NSPasteboardItem: an item's data, by type; strings are what the
/// clipboard takes.
@ObjCClass("NSPasteboardItem")
open class NSPasteboardItem: NSObject {
    var strings: [String: String] = [:]
    var data: [String: NSObject] = [:]

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("types")
    func types() -> NSObject { NSMutableArray.of((Array(strings.keys) + Array(data.keys)).compactMap { $0.objCArgument().map(NSObject.init) }) }
    @ObjCMethod("setString:forType:")
    func setString(_ string: String?, forType type: String?) -> Bool {
        guard let type else { return false }
        strings[type] = string
        return true
    }
    @ObjCMethod("stringForType:") func string(forType type: String?) -> String? { type.flatMap { strings[$0] } }
    @ObjCMethod("setData:forType:")
    func setData(_ value: NSObject?, forType type: String?) -> Bool {
        guard let type else { return false }
        data[type] = value
        return true
    }
    @ObjCMethod("dataForType:") func data(forType type: String?) -> NSObject? { type.flatMap { data[$0] } }
    @ObjCMethod("setPropertyList:forType:") func setPropertyList(_ value: NSObject?, forType type: String?) -> Bool { setData(value, forType: type) }
    @ObjCMethod("propertyListForType:") func propertyList(forType type: String?) -> NSObject? { data(forType: type) }
    @ObjCMethod("availableTypeFromArray:")
    func availableType(from types: NSObject?) -> String? {
        types?.as(NSArray.self)?.elements.map(\.stringValue).first { strings[$0] != nil || data[$0] != nil }
    }
    @ObjCMethod("setDataProvider:forTypes:") func setDataProvider(_ provider: NSObject?, forTypes types: NSObject?) -> Bool { false }
    @ObjCMethod("pasteboardPropertyListForType:") func pasteboardPropertyList(forType type: String?) -> NSObject? { data(forType: type) }
    @ObjCMethod("writableTypesForPasteboard:") func writableTypes(for pasteboard: NSObject?) -> NSObject { types() }
}

@ObjCClass("NSSound")
open class NSSound: NSObject {
    var name: String?
    var volume: Float = 1

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithContentsOfFile:byReference:")
    public required init(contentsOfFile path: String?, byReference: Bool) { super.init() }

    @ObjCMethod("initWithContentsOfURL:byReference:")
    public required init(contentsOf url: NSObject?, byReference: Bool) { super.init() }

    @ObjCClassMethod("soundNamed:")
    static func sound(named name: String?) -> NSSound? {
        let sound = NSSound()
        sound.name = name
        return sound
    }

    @ObjCMethod("play") func play() -> Bool { false }
    @ObjCMethod("stop") func stop() -> Bool { true }
    @ObjCMethod("pause") func pause() -> Bool { true }
    @ObjCMethod("resume") func resume() -> Bool { true }
    @ObjCMethod("isPlaying") func isPlaying() -> Bool { false }
    @ObjCMethod("volume") func soundVolume() -> Float { volume }
    @ObjCMethod("setVolume:") func setVolume(_ volume: Float) { self.volume = volume }
    @ObjCMethod("setLoops:") func setLoops(_ value: Bool) {}
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) {}
    @ObjCMethod("name") func soundName() -> String? { name }
    @ObjCMethod("duration") func duration() -> Double { 0 }
}

@ObjCClass("NSRunningApplication")
open class NSRunningApplication: NSObject {
    nonisolated(unsafe) static var current: NSRunningApplication?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("currentApplication")
    static func currentApplication() -> NSRunningApplication {
        if let current { return current }
        let app = NSRunningApplication()
        current = app
        return app
    }

    /// Only this one runs: none other matches a bundle identifier.
    @ObjCClassMethod("runningApplicationsWithBundleIdentifier:")
    static func runningApplications(withBundleIdentifier identifier: String?) -> NSObject {
        identifier == NSBundle.main().bundleIdentifier() ? NSMutableArray.of([currentApplication()]) : NSMutableArray.empty()
    }

    @ObjCClassMethod("runningApplicationWithProcessIdentifier:")
    static func runningApplication(withProcessIdentifier pid: Int32) -> NSRunningApplication? { pid == getpid() ? currentApplication() : nil }

    @ObjCClassMethod("terminateAutomaticallyTerminableApplications") static func terminateAutomaticallyTerminableApplications() {}

    @ObjCMethod("processIdentifier") func processIdentifier() -> Int32 { getpid() }
    @ObjCMethod("bundleIdentifier") func bundleIdentifier() -> String? { NSBundle.main().bundleIdentifier() }
    @ObjCMethod("localizedName")
    func localizedName() -> String? {
        let bundle = NSBundle.main()
        return (bundle.infoObject(forKey: "CFBundleDisplayName") ?? bundle.infoObject(forKey: "CFBundleName"))?.stringValue
    }
    @ObjCMethod("bundleURL") func bundleURL() -> NSObject? { NSURL.make(fileURLWithPath: NSBundle.main().bundlePath()) }
    @ObjCMethod("executableURL") func executableURL() -> NSObject? { nil }
    @ObjCMethod("launchDate") func launchDate() -> NSObject? { nil }
    @ObjCMethod("icon") func icon() -> NSObject? { App.shared?.applicationIconImage }
    @ObjCMethod("isActive") func isActive() -> Bool { App.shared?.active ?? false }
    @ObjCMethod("isHidden") func isHidden() -> Bool { App.shared?.hidden ?? false }
    @ObjCMethod("isFinishedLaunching") func isFinishedLaunching() -> Bool { App.shared?.launched ?? false }
    @ObjCMethod("isTerminated") func isTerminated() -> Bool { false }
    @ObjCMethod("ownsMenuBar") func ownsMenuBar() -> Bool { true }
    @ObjCMethod("activationPolicy") func activationPolicy() -> Int { App.shared?.activationPolicy ?? 0 }
    /// NSBundleExecutableArchitectureARM64.
    @ObjCMethod("executableArchitecture") func executableArchitecture() -> Int { 0x0100000c }
    @ObjCMethod("activateWithOptions:")
    func activate(options: UInt) -> Bool {
        App.shared?.activate(true)
        return true
    }
    @ObjCMethod("activateFromApplication:options:") func activate(from application: NSObject?, options: UInt) -> Bool { activate(options: options) }
    @ObjCMethod("hide") func hide() -> Bool { App.shared?.hide(nil); return true }
    @ObjCMethod("unhide") func unhide() -> Bool { App.shared?.unhide(nil); return true }
    @ObjCMethod("terminate") func terminate() -> Bool { App.shared.map { Send.void($0.objcObject, "terminate:", nil) }; return true }
    @ObjCMethod("forceTerminate") func forceTerminate() -> Bool { exit(0) }
}

@ObjCClass("NSWorkspace")
open class NSWorkspace: NSObject {
    var notificationCenter: NSObject?

    nonisolated(unsafe) static var shared: NSWorkspace?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("sharedWorkspace")
    static func sharedWorkspace() -> NSWorkspace {
        if let shared { return shared }
        let workspace = NSWorkspace()
        shared = workspace
        return workspace
    }

    /// The workspace's own center, which posts nothing here.
    @ObjCMethod("notificationCenter")
    func workspaceNotificationCenter() -> NSObject? {
        if notificationCenter == nil { notificationCenter = Classes.named("NSNotificationCenter")?.object.newInstance() }
        return notificationCenter
    }

    private func cannotOpen(_ what: String) {
        appKitWarning("NSWorkspace: no app here to open \(what)")
    }

    /// Opens a URL in the desktop's app for it (the browser for web pages)
    /// through xdg-open.
    @ObjCMethod("openURL:")
    func open(_ url: NSObject?) -> Bool {
        guard let string = url?.as(NSURL.self)?.absoluteString(), !string.isEmpty else {
            cannotOpen("a URL")
            return false
        }
        Trace.log("NSWorkspace: opening \(string) with xdg-open")
        // From a shell that leaves it running and ends at once, so the
        // browser outlives no zombie of ours.
        var pid: pid_t = 0
        let arguments = ["sh", "-c", "xdg-open \"$1\" >/dev/null 2>&1 &", "sh", string]
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        guard posix_spawnp(&pid, "sh", nil, nil, &argv, environ) == 0 else {
            cannotOpen(string)
            return false
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return true
    }

    @ObjCMethod("openURL:configuration:completionHandler:")
    func open(_ url: NSObject?, configuration: NSObject?, completionHandler: ObjCBlock?) {
        _ = open(url)
        if let completionHandler { Dispatch.onMain { Blocks.call(completionHandler, nil, nil) } }
    }

    @ObjCMethod("openURLs:withApplicationAtURL:configuration:completionHandler:")
    func open(_ urls: NSObject?, withApplicationAt application: NSObject?, configuration: NSObject?, completionHandler: ObjCBlock?) {
        cannotOpen("URLs")
        if let completionHandler { Dispatch.onMain { Blocks.call(completionHandler, nil, nil) } }
    }

    @ObjCMethod("openApplicationAtURL:configuration:completionHandler:")
    func openApplication(at url: NSObject?, configuration: NSObject?, completionHandler: ObjCBlock?) {
        cannotOpen(url?.as(NSURL.self)?.absoluteString() ?? "an application")
        if let completionHandler { Dispatch.onMain { Blocks.call(completionHandler, nil, nil) } }
    }

    @ObjCMethod("openFile:") func openFile(_ path: String?) -> Bool { cannotOpen(path ?? "a file"); return false }
    @ObjCMethod("selectFile:inFileViewerRootedAtPath:")
    func selectFile(_ path: String?, inFileViewerRootedAtPath root: String?) -> Bool { cannotOpen(path ?? "a file viewer"); return false }
    @ObjCMethod("activateFileViewerSelectingURLs:") func activateFileViewer(selecting urls: NSObject?) { cannotOpen("a file viewer") }
    @ObjCMethod("URLForApplicationWithBundleIdentifier:") func urlForApplication(withBundleIdentifier identifier: String?) -> NSObject? { nil }
    @ObjCMethod("URLForApplicationToOpenURL:") func urlForApplication(toOpen url: NSObject?) -> NSObject? { nil }
    @ObjCMethod("fullPathForApplication:") func fullPath(forApplication name: String?) -> String? { nil }
    @ObjCMethod("runningApplications") func runningApplications() -> NSObject { NSMutableArray.of([NSRunningApplication.currentApplication()]) }
    @ObjCMethod("frontmostApplication") func frontmostApplication() -> NSObject? { NSRunningApplication.currentApplication() }
    @ObjCMethod("menuBarOwningApplication") func menuBarOwningApplication() -> NSObject? { NSRunningApplication.currentApplication() }
    @ObjCMethod("iconForFile:") func icon(forFile path: String?) -> NSObject? { NSImage(size: CGSize(width: 32, height: 32)) }
    @ObjCMethod("isFilePackageAtPath:") func isFilePackage(atPath path: String?) -> Bool { path?.hasSuffix(".app") ?? false }
    @ObjCMethod("accessibilityDisplayShouldReduceMotion") func reduceMotion() -> Bool { false }
    @ObjCMethod("accessibilityDisplayShouldReduceTransparency") func reduceTransparency() -> Bool { false }
    @ObjCMethod("accessibilityDisplayShouldIncreaseContrast") func increaseContrast() -> Bool { false }
    @ObjCMethod("accessibilityDisplayShouldDifferentiateWithoutColor") func differentiateWithoutColor() -> Bool { false }
    @ObjCMethod("accessibilityDisplayShouldInvertColors") func invertColors() -> Bool { false }
    @ObjCMethod("isVoiceOverEnabled") func isVoiceOverEnabled() -> Bool { false }
    @ObjCMethod("isSwitchControlEnabled") func isSwitchControlEnabled() -> Bool { false }
}

@ObjCClass("NSWorkspaceOpenConfiguration")
open class NSWorkspaceOpenConfiguration: NSObject {
    var activates = true
    var createsNewApplicationInstance = false
    var arguments: NSObject?
    var promptsUserIfNeeded = true
    /// No app claims universal links here: web pages go to the browser.
    var requiresUniversalLinks = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("configuration") static func configuration() -> NSWorkspaceOpenConfiguration { NSWorkspaceOpenConfiguration() }

    @ObjCMethod("activates") func configurationActivates() -> Bool { activates }
    @ObjCMethod("setActivates:") func setActivates(_ value: Bool) { activates = value }
    @ObjCMethod("createsNewApplicationInstance") func configurationCreatesNewApplicationInstance() -> Bool { createsNewApplicationInstance }
    @ObjCMethod("setCreatesNewApplicationInstance:") func setCreatesNewApplicationInstance(_ value: Bool) { createsNewApplicationInstance = value }
    @ObjCMethod("arguments") func configurationArguments() -> NSObject? { arguments }
    @ObjCMethod("setArguments:") func setArguments(_ arguments: NSObject?) { self.arguments = arguments }
    @ObjCMethod("promptsUserIfNeeded") func configurationPromptsUserIfNeeded() -> Bool { promptsUserIfNeeded }
    @ObjCMethod("setPromptsUserIfNeeded:") func setPromptsUserIfNeeded(_ value: Bool) { promptsUserIfNeeded = value }
    @ObjCMethod("requiresUniversalLinks") func configurationRequiresUniversalLinks() -> Bool { requiresUniversalLinks }
    @ObjCMethod("setRequiresUniversalLinks:") func setRequiresUniversalLinks(_ value: Bool) { requiresUniversalLinks = value }
    @ObjCMethod("setAddsToRecentItems:") func setAddsToRecentItems(_ value: Bool) {}
    @ObjCMethod("setHides:") func setHides(_ value: Bool) {}
    @ObjCMethod("setEnvironment:") func setEnvironment(_ environment: NSObject?) {}
}
