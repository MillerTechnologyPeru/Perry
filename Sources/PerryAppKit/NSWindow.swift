import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSWindow: a window on the screen, shown as an SDL window once it is
// ordered front, whose content view's layer tree QuartzCore composites
// into the window's renderer each frame something changed. A window's
// frame is its content rectangle: the desktop draws the title bar outside
// it. Events reach views as AppKit sends them: clicks to the view under
// the mouse (and its drags and release to the same view), keys to the
// first responder, motion to tracking areas' owners and, when the window
// accepts mouse-moved events, the first responder.

/// NSWindowStyleMask.
enum StyleMask {
    static let titled: UInt = 1 << 0
    static let closable: UInt = 1 << 1
    static let miniaturizable: UInt = 1 << 2
    static let resizable: UInt = 1 << 3
    static let fullScreen: UInt = 1 << 14
}

/// The windows, and drawing them.
enum Windows {
    nonisolated(unsafe) static var all: [NSWindow] = []
    nonisolated(unsafe) static var key: NSWindow?
    nonisolated(unsafe) static var main: NSWindow?
    nonisolated(unsafe) static var lastNumber = 100
    nonisolated(unsafe) private static var dirty = true
    nonisolated(unsafe) private static var lastDraw = 0.0

    static func numbered(_ number: Int) -> NSWindow? { all.first { $0.windowNumber == number } }
    static func shown(sdl id: UInt32) -> NSWindow? { all.first { $0.sdlID == id && $0.sdlWindow != nil } }

    static func layersChanged() { dirty = true }

    /// Draws the windows when their layers changed or animate, at most a
    /// display refresh apart, and twice a second regardless.
    static func drawIfNeeded() {
        for window in all { window.touchScrolling.flush() }
        let now = Clock.now
        if QuartzCore.needsDisplay?() == true { dirty = true }
        guard dirty || now - lastDraw > 0.5, now - lastDraw >= 1 / Screens.display.refreshRate * 0.9 else { return }
        dirty = false
        lastDraw = now
        ObjCRuntime.autoreleasepool {
            for window in all where window.sdlWindow != nil && window.visible { window.draw() }
            Snapshot.windowsDrew()
        }
    }
}

@ObjCClass("NSWindow")
open class NSWindow: NSResponder {
    /// The content rectangle, in screen coordinates.
    var frame = CGRect(x: 0, y: 0, width: 640, height: 480)
    var styleMask: UInt = StyleMask.titled
    var title = ""
    var representedFilename = ""
    var representedURL: NSObject?
    var tabbingIdentifier = ""
    var tabbingMode = 0
    var titlebarAccessories: [NSViewController] = []
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var contentView: NSView?
    var visible = false
    var windowNumber = 0
    var level = 0
    /// Not retained.
    var firstResponderObject: UnsafeMutableRawPointer?
    var initialFirstResponder: NSObject?
    var flushDisabled = 0
    var acceptsMouseMovedEvents = false
    var ignoresMouseEvents = false
    var collectionBehavior: UInt = 0
    var releasedWhenClosed = true
    var minSize = CGSize.zero
    var maxSize = CGSize(width: 100_000, height: 100_000)
    var backgroundColor: NSObject?
    var alphaValue: CGFloat = 1
    var opaque = true
    var hasShadow = true
    var miniaturized = false
    var appearance: NSObject?
    /// Not retained.
    var windowControllerObject: UnsafeMutableRawPointer?
    var sdlWindow: SDL.Window?
    var sdlID: UInt32 = 0
    var renderer: UnsafeMutableRawPointer?
    var backingScale: CGFloat = 1
    /// The view that took the last mouse-down, which gets its drags and up.
    var mouseDownView: NSView?
    var excludedFromWindowsMenu = false
    var contentViewControllerObject: NSViewController?
    var frameAutosaveName = ""
    var toolbar: NSToolbar?
    var dumpedViews = false
    /// The background color the root layer has.
    var drawnBackground: NSColor?
    /// With a toolbar, the view holding it above the content view.
    var frameView: NSView?
    var toolbarView: ToolbarView?
    /// With the main menu shown in the window: the strip over the toolbar's.
    var menuBarView: MenuBarView?
    /// The height of the strips above the content view: the window is that
    /// much taller than the content view, which keeps its size.
    var appliedChrome: CGFloat = 0

    /// The view at the root of the window's views.
    var rootView: NSView? { frameView ?? contentView }
    var toolbarHeight: CGFloat { appliedChrome }

    @ObjCMethod("init")
    public required init() {
        super.init()
        setUp(contentRect: frame, styleMask: StyleMask.titled)
    }

    @ObjCMethod("initWithContentRect:styleMask:backing:defer:")
    public required init(contentRect: CGRect, styleMask: UInt, backing: UInt, defer: Bool) {
        super.init()
        setUp(contentRect: contentRect, styleMask: styleMask)
    }

    @ObjCMethod("initWithContentRect:styleMask:backing:defer:screen:")
    public required init(contentRect: CGRect, styleMask: UInt, backing: UInt, defer: Bool, screen: NSObject?) {
        super.init()
        setUp(contentRect: contentRect, styleMask: styleMask)
    }

    private func setUp(contentRect: CGRect, styleMask: UInt) {
        frame = contentRect
        self.styleMask = styleMask
        Windows.lastNumber += 1
        windowNumber = Windows.lastNumber
        backingScale = Screens.display.density
        firstResponderObject = objcObject
        let view = NSView(frame: CGRect(origin: .zero, size: contentRect.size))
        view.autoresizingMask = 2 | 16
        installContentView(view)
        Windows.all.append(self)
        Trace.log("window \(windowNumber) made, \(contentRect), style \(styleMask)")
    }

    deinit {
        destroySDLWindow()
    }

    static func wrap(_ object: UnsafeMutableRawPointer) -> NSWindow { NSWindow.objCInstance(object, ownership: .retain) }

    // MARK: Content

    @ObjCMethod("contentView") func windowContentView() -> NSView? { contentView }

    @ObjCMethod("setContentView:")
    func setContentView(_ view: NSView?) {
        if let old = contentView, old !== view {
            Send.void(old.objcObject, "viewWillMoveToWindow:", nil)
            old.layer.map { CALayer(objcObject: $0.objcObject, ownership: .retain).removeFromSuperlayer() }
            old.setWindowTree(nil)
            old.nextResponderObject = nil
            old.didMoveToWindowTree()
        }
        guard let view else {
            contentView = nil
            return
        }
        installContentView(view)
    }

    private func installContentView(_ view: NSView) {
        view.removeFromSuperview()
        if let frameView {
            // Under the toolbar, in the frame view.
            contentView = view
            frameView.addSubview(view, positioned: -1, relativeTo: nil)
            view.autoresizingMask = 2 | 16
            Send.void(view.objcObject, "setFrame:", rect: CGRect(x: 0, y: 0, width: frame.width, height: frame.height - toolbarHeight))
            view.nextResponderObject = objcObject
            Windows.layersChanged()
            return
        }
        Send.void(view.objcObject, "viewWillMoveToWindow:", objcObject)
        contentView = view
        view.nextResponderObject = objcObject
        view.setWindowTree(objcObject)
        view.ensureLayer()
        Send.void(view.objcObject, "setFrame:", rect: CGRect(origin: .zero, size: frame.size))
        view.updateLayerGeometry()
        view.didMoveToWindowTree()
        Windows.layersChanged()
    }

    // MARK: Toolbar

    @ObjCMethod("toolbar") func windowToolbar() -> NSToolbar? { toolbar }

    @ObjCMethod("setToolbar:")
    func setToolbar(_ value: NSToolbar?) {
        toolbar?.windowObject = nil
        toolbar = value
        value?.windowObject = objcObject
        toolbarChanged()
    }

    @ObjCMethod("toggleToolbarShown:")
    func toggleToolbarShown(_ sender: NSObject?) {
        guard let toolbar else { return }
        toolbar.visible.toggle()
        toolbarChanged()
    }

    @ObjCMethod("runToolbarCustomizationPalette:") func runToolbarCustomizationPalette(_ sender: NSObject?) {}
    @ObjCMethod("toolbarStyle") func toolbarStyle() -> Int { 0 }
    @ObjCMethod("setToolbarStyle:") func setToolbarStyle(_ style: Int) {}

    func toolbarChanged() { chromeChanged() }

    /// The menu bar and the toolbar show above the content view, which keeps
    /// its size: the window grows by their heights, the menu bar on top.
    func chromeChanged() {
        let wantsMenu = MenuBar.shows(in: self)
        let wantsToolbar = toolbar?.visible == true
        if (wantsMenu || wantsToolbar), frameView == nil, let content = contentView {
            let root = NSView(frame: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
            root.autoresizingMask = 2 | 16
            // The content view leaves the root for the frame view.
            content.layer.map { CALayer(objcObject: $0.objcObject, ownership: .retain).removeFromSuperlayer() }
            content.setWindowTree(nil)
            frameView = root
            root.nextResponderObject = objcObject
            root.setWindowTree(objcObject)
            root.ensureLayer()
            root.updateLayerGeometry()
            root.addSubview(content, positioned: -1, relativeTo: nil)
            content.autoresizingMask = 2 | 16
            content.setFrame(CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
            content.nextResponderObject = objcObject
            root.didMoveToWindowTree()
        }
        guard let root = frameView else { return }
        if wantsToolbar, toolbarView == nil {
            let bar = ToolbarView(frame: CGRect(x: 0, y: frame.height, width: frame.width, height: ToolbarView.height))
            bar.autoresizingMask = 2 | 8
            toolbarView = bar
            root.addSubview(bar)
        }
        if wantsMenu, menuBarView == nil {
            let bar = MenuBarView(frame: CGRect(x: 0, y: frame.height, width: frame.width, height: MenuBarView.height))
            bar.autoresizingMask = 2 | 8
            menuBarView = bar
            root.addSubview(bar)
        }
        toolbarView?.setHidden(!wantsToolbar)
        menuBarView?.setHidden(!wantsMenu)
        let toolbarStrip = wantsToolbar ? ToolbarView.height : 0
        let menuStrip = wantsMenu ? MenuBarView.height : 0
        let delta = toolbarStrip + menuStrip - appliedChrome
        if delta != 0 {
            appliedChrome += delta
            place(CGRect(x: frame.minX, y: frame.minY - delta, width: frame.width, height: frame.height + delta))
        }
        let contentHeight = frame.height - appliedChrome
        contentView?.setFrame(CGRect(x: 0, y: 0, width: frame.width, height: contentHeight))
        toolbarView?.setFrame(CGRect(x: 0, y: contentHeight, width: frame.width, height: ToolbarView.height))
        menuBarView?.setFrame(CGRect(x: 0, y: contentHeight + toolbarStrip, width: frame.width, height: MenuBarView.height))
        toolbarView?.toolbarObject = toolbar?.objcObject
        toolbarView?.arrange()
        menuBarView?.setNeedsDisplay(true)
        root.setNeedsDisplay(true)
        Windows.layersChanged()
    }

    @ObjCMethod("contentViewController") func contentViewController() -> NSViewController? { contentViewControllerObject }

    /// The controller's view becomes the content view; the window takes
    /// the view's size.
    @ObjCMethod("setContentViewController:")
    func setContentViewController(_ controller: NSViewController?) {
        contentViewControllerObject = controller
        guard let controller, let view = controller.view() else { return }
        let size = view.frame.size
        if size.width > 0, size.height > 0, size != frame.size {
            place(CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height))
        }
        Send.void(objcObject, "setContentView:", view.objcObject)
        view.nextResponderObject = controller.objcObject
        controller.nextResponderObject = objcObject
        if visible {
            Send.void(controller.objcObject, "viewWillAppear")
            Send.void(controller.objcObject, "viewDidAppear")
        }
    }
    @ObjCMethod("windowController") func windowController() -> NSObject? { windowControllerObject.map(NSObject.init) }
    @ObjCMethod("setWindowController:") func setWindowController(_ controller: NSObject?) { windowControllerObject = controller?.objcObject }

    // MARK: Geometry

    @ObjCMethod("frame") func windowFrame() -> CGRect { frame }
    @ObjCMethod("contentLayoutRect") func contentLayoutRect() -> CGRect { CGRect(origin: .zero, size: frame.size) }
    @ObjCMethod("contentRectForFrameRect:") func contentRect(forFrameRect rect: CGRect) -> CGRect { rect }
    @ObjCMethod("frameRectForContentRect:") func frameRect(forContentRect rect: CGRect) -> CGRect { rect }
    @ObjCClassMethod("contentRectForFrameRect:styleMask:")
    static func contentRect(forFrameRect rect: CGRect, styleMask: UInt) -> CGRect { rect }
    @ObjCClassMethod("frameRectForContentRect:styleMask:")
    static func frameRect(forContentRect rect: CGRect, styleMask: UInt) -> CGRect { rect }
    @ObjCClassMethod("minFrameWidthWithTitle:styleMask:")
    static func minFrameWidth(title: NSObject?, styleMask: UInt) -> CGFloat { 100 }

    @ObjCMethod("setFrame:display:") func setFrame(_ rect: CGRect, display: Bool) { place(rect) }
    @ObjCMethod("setFrame:display:animate:") func setFrame(_ rect: CGRect, display: Bool, animate: Bool) { place(rect) }
    @ObjCMethod("setFrameOrigin:") func setFrameOrigin(_ origin: CGPoint) { place(CGRect(origin: origin, size: frame.size)) }
    @ObjCMethod("setFrameTopLeftPoint:")
    func setFrameTopLeftPoint(_ point: CGPoint) { place(CGRect(x: point.x, y: point.y - frame.height, width: frame.width, height: frame.height)) }
    @ObjCMethod("setContentSize:")
    func setContentSize(_ size: CGSize) { place(CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)) }
    @ObjCMethod("cascadeTopLeftFromPoint:") func cascadeTopLeft(from point: CGPoint) -> CGPoint { point }

    /// Centered a little above the middle of the screen, as AppKit puts it.
    @ObjCMethod("center")
    func center() {
        let screen = Screens.flip(Screens.display.usable)
        place(CGRect(x: (screen.minX + (screen.width - frame.width) / 2).rounded(),
                     y: (screen.minY + (screen.height - frame.height) * 2 / 3).rounded(), width: frame.width, height: frame.height))
    }

    /// Moves and resizes the window, its SDL window and its content view.
    func place(_ rect: CGRect) {
        let old = frame
        frame = rect
        if let sdlWindow {
            if rect.size != old.size { _ = SDL.setWindowSize(sdlWindow, Int32(rect.width.rounded()), Int32(rect.height.rounded())) }
            if rect.origin != old.origin {
                let top = Screens.flip(rect)
                _ = SDL.setWindowPosition(sdlWindow, Int32(top.minX.rounded()), Int32(top.minY.rounded()))
            }
        }
        if rect.size != old.size { contentResized() }
        if rect.origin != old.origin { notify("windowDidMove:", Constants.NSWindowDidMoveNotification) }
    }

    /// The content view takes the frame's size.
    func contentResized() {
        if let root = rootView { Send.void(root.objcObject, "setFrameSize:", size: frame.size) }
        notify("windowDidResize:", Constants.NSWindowDidResizeNotification)
        Windows.layersChanged()
    }

    @ObjCMethod("minSize") func windowMinSize() -> CGSize { minSize }
    @ObjCMethod("setMinSize:") func setMinSize(_ size: CGSize) { minSize = size }
    @ObjCMethod("maxSize") func windowMaxSize() -> CGSize { maxSize }
    @ObjCMethod("setMaxSize:") func setMaxSize(_ size: CGSize) { maxSize = size }
    @ObjCMethod("setContentMinSize:") func setContentMinSize(_ size: CGSize) {
        minSize = size
        if let sdlWindow { _ = SDL.setWindowMinimumSize(sdlWindow, Int32(size.width), Int32(size.height)) }
    }
    @ObjCMethod("setContentMaxSize:") func setContentMaxSize(_ size: CGSize) { maxSize = size }
    @ObjCMethod("contentMinSize") func contentMinSize() -> CGSize { minSize }
    @ObjCMethod("contentMaxSize") func contentMaxSize() -> CGSize { maxSize }
    @ObjCMethod("setContentAspectRatio:") func setContentAspectRatio(_ ratio: CGSize) {}
    @ObjCMethod("setAspectRatio:") func setAspectRatio(_ ratio: CGSize) {}
    @ObjCMethod("setResizeIncrements:") func setResizeIncrements(_ increments: CGSize) {}

    @ObjCMethod("screen") func screen() -> NSScreen? { NSScreen.mainScreen() }
    @ObjCMethod("deepestScreen") func deepestScreen() -> NSScreen? { NSScreen.mainScreen() }
    @ObjCMethod("backingScaleFactor") func backingScaleFactor() -> CGFloat { backingScale }
    @ObjCMethod("windowNumber") func windowWindowNumber() -> Int { windowNumber }
    @ObjCMethod("deviceDescription") func deviceDescription() -> NSObject { NSScreen.mainScreen()?.deviceDescription() ?? NSMutableDictionary.empty() }

    // MARK: Conversion

    @ObjCMethod("convertPointFromScreen:")
    func convertPoint(fromScreen point: CGPoint) -> CGPoint { CGPoint(x: point.x - frame.minX, y: point.y - frame.minY) }
    @ObjCMethod("convertPointToScreen:")
    func convertPoint(toScreen point: CGPoint) -> CGPoint { CGPoint(x: point.x + frame.minX, y: point.y + frame.minY) }
    @ObjCMethod("convertRectFromScreen:")
    func convertRect(fromScreen rect: CGRect) -> CGRect { CGRect(origin: convertPoint(fromScreen: rect.origin), size: rect.size) }
    @ObjCMethod("convertRectToScreen:")
    func convertRect(toScreen rect: CGRect) -> CGRect { CGRect(origin: convertPoint(toScreen: rect.origin), size: rect.size) }
    @ObjCMethod("convertRectToBacking:") func convertRectToBacking(_ rect: CGRect) -> CGRect { Backing.scale(rect, by: backingScale) }
    @ObjCMethod("convertRectFromBacking:") func convertRectFromBacking(_ rect: CGRect) -> CGRect { Backing.scale(rect, by: 1 / backingScale) }
    @ObjCMethod("convertPointToBacking:") func convertPointToBacking(_ point: CGPoint) -> CGPoint { Backing.scale(point, by: backingScale) }
    @ObjCMethod("convertPointFromBacking:") func convertPointFromBacking(_ point: CGPoint) -> CGPoint { Backing.scale(point, by: 1 / backingScale) }
    @ObjCMethod("backingAlignedRect:options:")
    func backingAlignedRect(_ rect: CGRect, options: UInt64) -> CGRect { Backing.aligned(rect, scale: backingScale) }

    /// The mouse in the window's base coordinates.
    @ObjCMethod("mouseLocationOutsideOfEventStream")
    func mouseLocationOutsideOfEventStream() -> CGPoint { convertPoint(fromScreen: NSEvent.mouseLocation()) }

    // MARK: Appearance

    @ObjCMethod("title") func windowTitle() -> String { title }
    @ObjCMethod("setTitle:")
    func setTitle(_ title: String?) {
        self.title = title ?? ""
        if let sdlWindow { _ = self.title.withCString { SDL.setWindowTitle(sdlWindow, $0) } }
    }
    @ObjCMethod("setTitleWithRepresentedFilename:") func setTitle(representedFilename name: String?) { setTitle(name) }
    @ObjCMethod("styleMask") func windowStyleMask() -> UInt { styleMask }
    @ObjCMethod("setStyleMask:")
    func setStyleMask(_ mask: UInt) {
        styleMask = mask
        if let sdlWindow { _ = SDL.setWindowResizable(sdlWindow, mask & StyleMask.resizable != 0) }
    }
    @ObjCMethod("level") func windowLevel() -> Int { level }
    @ObjCMethod("setLevel:") func setLevel(_ level: Int) { self.level = level }
    @ObjCMethod("isOpaque") func isOpaque() -> Bool { opaque }
    @ObjCMethod("setOpaque:") func setOpaque(_ opaque: Bool) { self.opaque = opaque }
    @ObjCMethod("backgroundColor") func windowBackgroundColor() -> NSObject? { backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSObject?) { backgroundColor = color }
    @ObjCMethod("alphaValue") func windowAlphaValue() -> CGFloat { alphaValue }
    @ObjCMethod("setAlphaValue:") func setAlphaValue(_ alpha: CGFloat) { alphaValue = alpha }
    @ObjCMethod("hasShadow") func windowHasShadow() -> Bool { hasShadow }
    @ObjCMethod("setHasShadow:") func setHasShadow(_ value: Bool) { hasShadow = value }
    @ObjCMethod("appearance") func windowAppearance() -> NSObject? { appearance }
    @ObjCMethod("setAppearance:") func setAppearance(_ appearance: NSObject?) { self.appearance = appearance }
    @ObjCMethod("effectiveAppearance") func effectiveAppearance() -> NSObject? { appearance ?? App.shared?.effectiveAppearance() ?? NSAppearance.system }
    @ObjCMethod("collectionBehavior") func windowCollectionBehavior() -> UInt { collectionBehavior }
    @ObjCMethod("setCollectionBehavior:") func setCollectionBehavior(_ behavior: UInt) { collectionBehavior = behavior }
    @ObjCMethod("isReleasedWhenClosed") func isReleasedWhenClosed() -> Bool { releasedWhenClosed }
    @ObjCMethod("setReleasedWhenClosed:") func setReleasedWhenClosed(_ value: Bool) { releasedWhenClosed = value }
    @ObjCMethod("acceptsMouseMovedEvents") func windowAcceptsMouseMovedEvents() -> Bool { acceptsMouseMovedEvents }
    @ObjCMethod("setAcceptsMouseMovedEvents:") func setAcceptsMouseMovedEvents(_ value: Bool) { acceptsMouseMovedEvents = value }
    @ObjCMethod("ignoresMouseEvents") func windowIgnoresMouseEvents() -> Bool { ignoresMouseEvents }
    @ObjCMethod("setIgnoresMouseEvents:") func setIgnoresMouseEvents(_ value: Bool) { ignoresMouseEvents = value }
    @ObjCMethod("isExcludedFromWindowsMenu") func isExcludedFromWindowsMenu() -> Bool { excludedFromWindowsMenu }
    @ObjCMethod("setExcludedFromWindowsMenu:") func setExcludedFromWindowsMenu(_ value: Bool) { excludedFromWindowsMenu = value }
    @ObjCMethod("standardWindowButton:") func standardWindowButton(_ button: UInt) -> NSObject? { nil }
    /// NSWindowOcclusionState: visible 2.
    @ObjCMethod("occlusionState") func occlusionState() -> UInt { visible && !miniaturized ? 2 : 0 }
    @ObjCMethod("isOnActiveSpace") func isOnActiveSpace() -> Bool { true }
    @ObjCMethod("canHide") func canHide() -> Bool { true }
    @ObjCMethod("setCanHide:") func setCanHide(_ value: Bool) {}
    @ObjCMethod("hidesOnDeactivate") func hidesOnDeactivate() -> Bool { false }
    @ObjCMethod("setHidesOnDeactivate:") func setHidesOnDeactivate(_ value: Bool) {}
    @ObjCMethod("setMovable:") func setMovable(_ value: Bool) {}
    @ObjCMethod("setMovableByWindowBackground:") func setMovableByWindowBackground(_ value: Bool) {}
    @ObjCMethod("setRestorable:") func setRestorable(_ value: Bool) {}
    @ObjCMethod("isRestorable") func isRestorable() -> Bool { false }
    @ObjCMethod("tabbingMode") func tabbingModeValue() -> Int { tabbingMode }
    @ObjCMethod("setTabbingMode:") func setTabbingMode(_ mode: Int) { tabbingMode = mode }
    @ObjCMethod("tabbingIdentifier") func tabbingIdentifierValue() -> String { tabbingIdentifier }
    @ObjCMethod("setTabbingIdentifier:") func setTabbingIdentifier(_ value: String?) { tabbingIdentifier = value ?? "" }
    /// Windows never merge into tabs here.
    @ObjCClassMethod("allowsAutomaticWindowTabbing") static func allowsAutomaticWindowTabbing() -> Bool { false }
    @ObjCClassMethod("setAllowsAutomaticWindowTabbing:") static func setAllowsAutomaticWindowTabbing(_ value: Bool) {}
    @ObjCClassMethod("userTabbingPreference") static func userTabbingPreference() -> Int { 2 }
    @ObjCMethod("tabbedWindows") func tabbedWindows() -> NSObject? { nil }
    @ObjCMethod("tabGroup") func tabGroup() -> NSObject? { nil }

    /// The file the window shows: its name is the title.
    @ObjCMethod("representedFilename") func representedFilenameValue() -> String { representedFilename }
    @ObjCMethod("setRepresentedFilename:") func setRepresentedFilename(_ value: String?) { representedFilename = value ?? "" }
    @ObjCMethod("representedURL") func representedURLValue() -> NSObject? { representedURL }
    @ObjCMethod("setRepresentedURL:") func setRepresentedURL(_ value: NSObject?) { representedURL = value }

    /// Views a controller adds to the titlebar; they show nowhere yet.
    @ObjCMethod("titlebarAccessoryViewControllers")
    func titlebarAccessoryViewControllers() -> NSObject? {
        NSMutableArray.of(titlebarAccessories)
    }
    @ObjCMethod("addTitlebarAccessoryViewController:")
    func addTitlebarAccessoryViewController(_ controller: NSViewController?) {
        guard let controller, !titlebarAccessories.contains(where: { $0 === controller }) else { return }
        titlebarAccessories.append(controller)
    }
    @ObjCMethod("insertTitlebarAccessoryViewController:atIndex:")
    func insertTitlebarAccessoryViewController(_ controller: NSViewController?, at index: Int) {
        guard let controller else { return }
        titlebarAccessories.insert(controller, at: max(0, min(index, titlebarAccessories.count)))
    }
    @ObjCMethod("removeTitlebarAccessoryViewControllerAtIndex:")
    func removeTitlebarAccessoryViewController(at index: Int) {
        if titlebarAccessories.indices.contains(index) { titlebarAccessories.remove(at: index) }
    }
    @ObjCMethod("setFrameAutosaveName:") func setFrameAutosaveName(_ name: String?) -> Bool { frameAutosaveName = name ?? ""; return true }
    @ObjCMethod("frameAutosaveName") func windowFrameAutosaveName() -> String { frameAutosaveName }
    @ObjCMethod("setFrameUsingName:") func setFrameUsingName(_ name: NSObject?) -> Bool { false }
    @ObjCMethod("saveFrameUsingName:") func saveFrameUsingName(_ name: NSObject?) {}
    @ObjCMethod("setTitleVisibility:") func setTitleVisibility(_ visibility: Int) {}
    @ObjCMethod("setTitlebarAppearsTransparent:") func setTitlebarAppearsTransparent(_ value: Bool) {}
    @ObjCMethod("setShowsResizeIndicator:") func setShowsResizeIndicator(_ value: Bool) {}
    @ObjCMethod("setPreservesContentDuringLiveResize:") func setPreservesContentDuringLiveResize(_ value: Bool) {}
    @ObjCMethod("inLiveResize") func inLiveResize() -> Bool { false }
    @ObjCMethod("setAnimationBehavior:") func setAnimationBehavior(_ behavior: Int) {}
    @ObjCMethod("setSharingType:") func setSharingType(_ type: UInt) {}
    @ObjCMethod("setColorSpace:") func setColorSpace(_ space: NSObject?) {}
    @ObjCMethod("colorSpace") func colorSpace() -> NSObject? { nil }
    @ObjCMethod("setDocumentEdited:") func setDocumentEdited(_ value: Bool) {}
    @ObjCMethod("setDepthLimit:") func setDepthLimit(_ limit: Int32) {}
    @ObjCMethod("setDisplaysWhenScreenProfileChanges:") func setDisplaysWhenScreenProfileChanges(_ value: Bool) {}
    @ObjCMethod("invalidateCursorRectsForView:") func invalidateCursorRects(for view: NSObject?) {}
    @ObjCMethod("resetCursorRects") func resetCursorRects() {}
    @ObjCMethod("disableCursorRects") func disableCursorRects() {}
    @ObjCMethod("enableCursorRects") func enableCursorRects() {}
    @ObjCMethod("attachedSheet") func attachedSheet() -> NSObject? { nil }
    @ObjCMethod("sheets") func sheets() -> NSObject { NSMutableArray.empty() }
    @ObjCMethod("parentWindow") func parentWindow() -> NSObject? { nil }
    @ObjCMethod("childWindows") func childWindows() -> NSObject { NSMutableArray.empty() }
    @ObjCMethod("addChildWindow:ordered:") func addChildWindow(_ window: NSObject?, ordered: Int) {}
    @ObjCMethod("removeChildWindow:") func removeChildWindow(_ window: NSObject?) {}
    @ObjCMethod("graphicsContext") func graphicsContext() -> NSObject? { nil }
    @ObjCMethod("windowRef") func windowRef() -> UnsafeMutableRawPointer? { nil }

    /// A sheet is shown as a window of its own; its handler hears it ended
    /// when it does.
    @ObjCMethod("beginSheet:completionHandler:")
    func beginSheet(_ sheet: NSWindow?, completionHandler: ObjCBlock?) {
        sheet.map { Send.void($0.objcObject, "makeKeyAndOrderFront:", nil) }
    }
    @ObjCMethod("endSheet:") func endSheet(_ sheet: NSWindow?) { sheet?.orderOut(nil) }
    @ObjCMethod("endSheet:returnCode:") func endSheet(_ sheet: NSWindow?, returnCode: Int) { sheet?.orderOut(nil) }

    // MARK: Delegate and notifications

    @ObjCMethod("delegate") func windowDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { delegateObject = delegate?.objcObject }

    /// Tells the delegate, then posts the notification.
    func notify(_ selector: String, _ name: String) {
        let notification = NSNotification.make(name: name, object: self)
        if Send.responds(delegateObject, selector) { Send.void(delegateObject, selector, notification.objcObject) }
        NSNotificationCenter.defaultCenter().post(notification)
    }

    // MARK: Ordering and key status

    @ObjCMethod("isVisible") func isVisible() -> Bool { visible }
    @ObjCMethod("setIsVisible:") func setIsVisible(_ value: Bool) { value ? orderFront(nil) : orderOut(nil) }
    @ObjCMethod("isKeyWindow") func isKeyWindow() -> Bool { Windows.key === self }
    @ObjCMethod("isMainWindow") func isMainWindow() -> Bool { Windows.main === self }
    @ObjCMethod("canBecomeKeyWindow") func canBecomeKeyWindow() -> Bool { true }
    @ObjCMethod("canBecomeMainWindow") func canBecomeMainWindow() -> Bool { styleMask & StyleMask.titled != 0 || true }

    @ObjCMethod("makeKeyAndOrderFront:")
    func makeKeyAndOrderFront(_ sender: NSObject?) {
        orderFront(sender)
        Send.void(objcObject, "makeKeyWindow")
        if Send.bool(objcObject, "canBecomeMainWindow") { Send.void(objcObject, "makeMainWindow") }
    }

    @ObjCMethod("orderFront:")
    func orderFront(_ sender: NSObject?) {
        if !visible {
            let controller = contentViewControllerObject
            if let controller { Send.void(controller.objcObject, "viewWillAppear") }
            visible = true
            chromeChanged()
            show()
            if let controller { Send.void(controller.objcObject, "viewDidAppear") }
        } else if let sdlWindow {
            _ = SDL.raiseWindow(sdlWindow)
        }
        if let index = Windows.all.firstIndex(where: { $0 === self }) {
            Windows.all.remove(at: index)
            Windows.all.append(self)
        }
    }

    @ObjCMethod("orderFrontRegardless") func orderFrontRegardless() { orderFront(nil) }
    @ObjCMethod("orderBack:") func orderBack(_ sender: NSObject?) { orderFront(sender) }
    /// NSWindowOrderingMode: out 0, above 1, below -1.
    @ObjCMethod("orderWindow:relativeTo:") func order(_ place: Int, relativeTo other: Int) { place == 0 ? orderOut(nil) : orderFront(nil) }

    @ObjCMethod("orderOut:")
    func orderOut(_ sender: NSObject?) {
        guard visible else { return }
        visible = false
        if let sdlWindow { _ = SDL.hideWindow(sdlWindow) }
        if Windows.key === self { Send.void(objcObject, "resignKeyWindow") }
        if Windows.main === self { Send.void(objcObject, "resignMainWindow") }
    }

    @ObjCMethod("makeKeyWindow")
    func makeKeyWindow() {
        guard Windows.key !== self else { return }
        if let old = Windows.key { Send.void(old.objcObject, "resignKeyWindow") }
        Windows.key = self
        Send.void(objcObject, "becomeKeyWindow")
    }

    @ObjCMethod("makeMainWindow")
    func makeMainWindow() {
        guard Windows.main !== self else { return }
        if let old = Windows.main { Send.void(old.objcObject, "resignMainWindow") }
        Windows.main = self
        Send.void(objcObject, "becomeMainWindow")
    }

    @ObjCMethod("becomeKeyWindow")
    func becomeKeyWindow() {
        if firstResponderObject == objcObject {
            // With no initial responder, as AppKit's first key view: the
            // text view a window opens to edit in.
            if let responder = initialFirstResponder ?? rootView.flatMap(NSWindow.firstTextView) { _ = makeFirstResponder(responder) }
        }
        notify("windowDidBecomeKey:", Constants.NSWindowDidBecomeKeyNotification)
    }

    private static func firstTextView(in view: NSView) -> NSObject? {
        if view.as(NSTextView.self) != nil, Send.bool(view.objcObject, "acceptsFirstResponder") { return view }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }

    @ObjCMethod("disableFlushWindow") func disableFlushWindow() { flushDisabled += 1 }
    @ObjCMethod("enableFlushWindow") func enableFlushWindow() { flushDisabled = max(0, flushDisabled - 1) }
    @ObjCMethod("isFlushWindowDisabled") func isFlushWindowDisabled() -> Bool { flushDisabled > 0 }

    @ObjCMethod("resignKeyWindow")
    func resignKeyWindow() {
        if Windows.key === self { Windows.key = nil }
        notify("windowDidResignKey:", Constants.NSWindowDidResignKeyNotification)
    }

    @ObjCMethod("becomeMainWindow") func becomeMainWindow() { notify("windowDidBecomeMain:", Constants.NSWindowDidBecomeMainNotification) }

    @ObjCMethod("resignMainWindow")
    func resignMainWindow() {
        if Windows.main === self { Windows.main = nil }
        notify("windowDidResignMain:", Constants.NSWindowDidResignMainNotification)
    }

    /// Asks the delegate, then closes.
    @ObjCMethod("performClose:")
    func performClose(_ sender: NSObject?) {
        if Send.responds(delegateObject, "windowShouldClose:"), !Send.bool(delegateObject, "windowShouldClose:", objcObject) { return }
        Send.void(objcObject, "close")
    }

    @ObjCMethod("close")
    func close() {
        notify("windowWillClose:", Constants.NSWindowWillCloseNotification)
        orderOut(nil)
        destroySDLWindow()
        withExtendedLifetime(self) { Windows.all.removeAll { $0 === self } }
        // The last window closed may end the app, as its delegate asks.
        if Windows.all.allSatisfy({ !$0.visible }), let app = App.shared,
           Send.responds(app.delegateObject, "applicationShouldTerminateAfterLastWindowClosed:"),
           Send.bool(app.delegateObject, "applicationShouldTerminateAfterLastWindowClosed:", app.objcObject) {
            Dispatch.onMain { Send.void(app.objcObject, "terminate:", nil) }
        }
    }

    @ObjCMethod("miniaturize:")
    func miniaturize(_ sender: NSObject?) {
        if let sdlWindow { _ = SDL.minimizeWindow(sdlWindow) }
    }
    @ObjCMethod("deminiaturize:") func deminiaturize(_ sender: NSObject?) { orderFront(nil) }
    @ObjCMethod("isMiniaturized") func isMiniaturized() -> Bool { miniaturized }
    @ObjCMethod("zoom:") func zoom(_ sender: NSObject?) {}
    @ObjCMethod("isZoomed") func isZoomed() -> Bool { false }

    /// Full screen: the SDL window fills the display, and the delegate and
    /// observers hear of it on the way in and out, as from AppKit's
    /// animation.
    @ObjCMethod("toggleFullScreen:")
    func toggleFullScreen(_ sender: NSObject?) { setFullScreen(styleMask & StyleMask.fullScreen == 0) }

    func setFullScreen(_ on: Bool) {
        guard (styleMask & StyleMask.fullScreen != 0) != on else { return }
        if on {
            notify("windowWillEnterFullScreen:", Constants.NSWindowWillEnterFullScreenNotification)
            styleMask |= StyleMask.fullScreen
            if let sdlWindow { _ = SDL.setWindowFullscreen(sdlWindow, true) }
            else { frame = Screens.flip(Screens.display.bounds); contentResized() }
            notify("windowDidEnterFullScreen:", Constants.NSWindowDidEnterFullScreenNotification)
        } else {
            notify("windowWillExitFullScreen:", Constants.NSWindowWillExitFullScreenNotification)
            styleMask &= ~StyleMask.fullScreen
            if let sdlWindow { _ = SDL.setWindowFullscreen(sdlWindow, false) }
            notify("windowDidExitFullScreen:", Constants.NSWindowDidExitFullScreenNotification)
        }
    }

    // MARK: Display

    @ObjCMethod("display") func display() { Windows.layersChanged() }
    @ObjCMethod("displayIfNeeded") func displayIfNeeded() { Windows.drawIfNeeded() }
    @ObjCMethod("setViewsNeedDisplay:") func setViewsNeedDisplay(_ value: Bool) { if value { Windows.layersChanged() } }
    @ObjCMethod("viewsNeedDisplay") func viewsNeedDisplay() -> Bool { false }
    @ObjCMethod("update") func update() {}
    @ObjCMethod("disableScreenUpdatesUntilFlush") func disableScreenUpdatesUntilFlush() {}
    @ObjCMethod("flushWindow") func flushWindow() { Windows.layersChanged() }
    @ObjCMethod("useOptimizedDrawing:") func useOptimizedDrawing(_ value: Bool) {}

    /// The SDL window and its renderer, made when the window is first shown.
    private func show() {
        if let sdlWindow {
            _ = SDL.showWindow(sdlWindow)
            return
        }
        guard SDL.start() else { return }
        var flags = SDL.windowHighPixelDensity
        if styleMask & StyleMask.resizable != 0 { flags |= SDL.windowResizable }
        if styleMask == 0 { flags |= SDL.windowBorderless }
        if styleMask & StyleMask.fullScreen != 0 { flags |= SDL.windowFullscreen }
        let name = title.isEmpty ? (NSBundle.main().infoObject(forKey: "CFBundleName")?.stringValue ?? "") : title
        // A frame an app computed from nothing has no size SDL can make.
        if !frame.width.isFinite || !frame.height.isFinite || frame.width < 1 || frame.height < 1 {
            appKitWarning("window \(windowNumber) has no usable size (\(frame.width)×\(frame.height)); making it 640×480")
            frame.size = CGSize(width: 640, height: 480)
        }
        guard let window = name.withCString({ SDL.createWindow($0, Int32(frame.width.rounded()), Int32(frame.height.rounded()), flags) }) else {
            appKitWarning("SDL could not make a window: \(SDL.lastError)")
            return
        }
        sdlWindow = window
        sdlID = SDL.windowID(window)
        let top = Screens.flip(frame)
        _ = SDL.setWindowPosition(window, Int32(top.minX.rounded()), Int32(top.minY.rounded()))
        // Typed text for key events: SDL types only while text input is on.
        _ = SDL.startTextInput(window)
        if minSize.width > 0 || minSize.height > 0 { _ = SDL.setWindowMinimumSize(window, Int32(minSize.width), Int32(minSize.height)) }
        renderer = "opengles2".withCString { SDL.createRenderer(window, $0) } ?? SDL.createRenderer(window, nil)
        if let renderer {
            Trace.log("window \(windowNumber) shown with SDL's \(SDL.rendererName(renderer).map { String(cString: $0) } ?? "?") renderer")
        } else {
            appKitWarning("SDL could not make a renderer: \(SDL.lastError)")
        }
        updateBackingScale()
        Windows.layersChanged()
    }

    /// The SDL window's pixels per point; views and the delegate hear when
    /// it changes.
    func updateBackingScale() {
        guard let sdlWindow else { return }
        let density = CGFloat(SDL.windowPixelDensity(sdlWindow))
        guard density > 0, density != backingScale else { return }
        backingScale = density
        for view in rootView?.allViews ?? [] {
            view.layer.map { CALayer(objcObject: $0.objcObject, ownership: .retain).setContentsScale(density) }
            Send.void(view.objcObject, "viewDidChangeBackingProperties")
        }
        notify("windowDidChangeBackingProperties:", Constants.NSWindowDidChangeBackingPropertiesNotification)
    }

    private func destroySDLWindow() {
        if let renderer { SDL.destroyRenderer(renderer) }
        if let sdlWindow { SDL.destroyWindow(sdlWindow) }
        renderer = nil
        sdlWindow = nil
        sdlID = 0
    }

    /// Composites the content view's layers into the window.
    func draw() {
        guard let renderer, let contentView, let root = rootView, let layer = root.layer else { return }
        let controller = contentViewControllerObject
        Send.void(root.objcObject, "updateConstraintsForSubtreeIfNeeded")
        let laidOut = contentView.needsLayout
        if laidOut, let controller { Send.void(controller.objcObject, "viewWillLayout") }
        root.layoutSubtreeIfNeeded()
        if laidOut, let controller { Send.void(controller.objcObject, "viewDidLayout") }
        // The window's background shows behind its views.
        // Set only when it changes: a layer change asks for another frame.
        let background = backgroundColor?.as(NSColor.self) ?? NSColor.windowBackgroundColor()
        if !(drawnBackground?.isEqual(background) ?? false) {
            drawnBackground = background
            CALayer(objcObject: layer.objcObject, ownership: .retain).setBackgroundColor(background.cgColorRef)
        }
        QuartzCore.draw(CALayer(objcObject: layer.objcObject, ownership: .retain), renderer: renderer, scale: backingScale)
        if Trace.enabled, !dumpedViews {
            dumpedViews = true
            Trace.log("window \(windowNumber) views:\n" + Trace.describe(root))
        }
    }

    // MARK: SDL's window events

    /// The SDL window moved or was resized by the desktop.
    func sdlWindowChanged() {
        guard let sdlWindow else { return }
        var x: Int32 = 0, y: Int32 = 0, w: Int32 = 0, h: Int32 = 0
        guard SDL.getWindowSize(sdlWindow, &w, &h) else { return }
        _ = SDL.getWindowPosition(sdlWindow, &x, &y)
        let rect = Screens.flip(CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h)))
        let old = frame
        frame = rect
        if rect.size != old.size { contentResized() }
        if rect.origin != old.origin { notify("windowDidMove:", Constants.NSWindowDidMoveNotification) }
    }

    func sdlFocus(_ gained: Bool) {
        Trace.log("window \(windowNumber) \(gained ? "gained" : "lost") focus")
        if gained {
            makeKeyWindow()
            if Send.bool(objcObject, "canBecomeMainWindow") { makeMainWindow() }
            App.shared?.activate(true)
        } else if Windows.key === self {
            Send.void(objcObject, "resignKeyWindow")
            if Windows.all.allSatisfy({ Windows.key !== $0 }) { App.shared?.activate(false) }
        }
    }

    func sdlMinimized(_ minimized: Bool) {
        guard miniaturized != minimized else { return }
        miniaturized = minimized
        if minimized {
            notify("windowWillMiniaturize:", "NSWindowWillMiniaturizeNotification")
            notify("windowDidMiniaturize:", Constants.NSWindowDidMiniaturizeNotification)
        } else {
            notify("windowDidDeminiaturize:", Constants.NSWindowDidDeminiaturizeNotification)
        }
        notify("windowDidChangeOcclusionState:", Constants.NSWindowDidChangeOcclusionStateNotification)
    }

    // MARK: First responder and events

    @ObjCMethod("firstResponder") func firstResponder() -> NSObject? { firstResponderObject.map(NSObject.init) }
    @ObjCMethod("initialFirstResponder") func windowInitialFirstResponder() -> NSObject? { initialFirstResponder }
    @ObjCMethod("setInitialFirstResponder:") func setInitialFirstResponder(_ responder: NSObject?) { initialFirstResponder = responder }

    @ObjCMethod("makeFirstResponder:")
    func makeFirstResponder(_ responder: NSObject?) -> Bool {
        let new = responder?.objcObject ?? objcObject
        guard new != firstResponderObject else { return true }
        if let current = firstResponderObject, current != objcObject, !Send.bool(current, "resignFirstResponder") { return false }
        firstResponderObject = objcObject
        guard new != objcObject else { return true }
        if Send.bool(new, "acceptsFirstResponder"), Send.bool(new, "becomeFirstResponder") {
            firstResponderObject = new
            return true
        }
        return responder == nil
    }

    /// Touch scrolling's state for this window.
    let touchScrolling = TouchScrolling()

    /// A mouse down to the view under it, which becomes the first
    /// responder if it takes it.
    func dispatchMouseDown(_ event: NSEvent) {
        guard !ignoresMouseEvents else { return }
        let view = viewAt(event.locationInWindow)
        mouseDownView = view
        if event.type == .leftMouseDown, let view, view.objcObject != firstResponderObject,
           Send.bool(view.objcObject, "acceptsFirstResponder") {
            _ = makeFirstResponder(view)
        }
        let selector = event.type == .leftMouseDown ? "mouseDown:" : event.type == .rightMouseDown ? "rightMouseDown:" : "otherMouseDown:"
        Send.void(view?.objcObject ?? objcObject, selector, event.objcObject)
    }

    /// Dispatches an event the application sent the window.
    @ObjCMethod("sendEvent:")
    func sendEvent(_ eventObject: NSObject?) {
        guard let event = eventObject?.as(NSEvent.self) else { return }
        // A touch over a scroll view scrolls it, or waits to be a click.
        if event.subtype == 3, !ignoresMouseEvents, touchScrolling.handle(event, in: self) { return }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            dispatchMouseDown(event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let view = mouseDownView ?? viewAt(event.locationInWindow)
            if MouseButtons.pressed == 0 { mouseDownView = nil }
            let selector = event.type == .leftMouseUp ? "mouseUp:" : event.type == .rightMouseUp ? "rightMouseUp:" : "otherMouseUp:"
            Send.void(view?.objcObject ?? objcObject, selector, event.objcObject)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let view = mouseDownView ?? viewAt(event.locationInWindow)
            let selector = event.type == .leftMouseDragged ? "mouseDragged:"
                : event.type == .rightMouseDragged ? "rightMouseDragged:" : "otherMouseDragged:"
            Send.void(view?.objcObject ?? objcObject, selector, event.objcObject)
            track(event, moved: false)
        case .mouseMoved:
            track(event, moved: true)
            if acceptsMouseMovedEvents, let responder = firstResponderObject { Send.void(responder, "mouseMoved:", event.objcObject) }
        case .mouseEntered:
            if let owner = event.trackingArea?.as(NSTrackingArea.self)?.owner { Send.void(owner, "mouseEntered:", event.objcObject) }
        case .mouseExited:
            if let owner = event.trackingArea?.as(NSTrackingArea.self)?.owner { Send.void(owner, "mouseExited:", event.objcObject) }
        case .scrollWheel:
            guard !ignoresMouseEvents else { return }
            Send.void(viewAt(event.locationInWindow)?.objcObject ?? objcObject, "scrollWheel:", event.objcObject)
        case .keyDown:
            let responder = firstResponderObject ?? objcObject
            if event.modifierFlags & ModifierFlags.command != 0,
               contentView.map({ Send.bool($0.objcObject, "performKeyEquivalent:", event.objcObject) }) == true { return }
            if event.modifierFlags & (ModifierFlags.command | ModifierFlags.control) != 0, MenuBar.performKeyEquivalent(event) { return }
            Send.void(responder, "keyDown:", event.objcObject)
        case .keyUp:
            Send.void(firstResponderObject ?? objcObject, "keyUp:", event.objcObject)
        case .flagsChanged:
            Send.void(firstResponderObject ?? objcObject, "flagsChanged:", event.objcObject)
        default:
            break
        }
    }

    /// The deepest view at a point in the window's base coordinates.
    func viewAt(_ point: CGPoint) -> NSView? {
        guard let root = rootView, let hit = Send.hitTest(root.objcObject, point) else { return nil }
        return NSView.wrap(hit)
    }

    /// Tracking areas' owners hear the mouse move, enter and leave.
    func track(_ event: NSEvent, moved: Bool) {
        guard let root = rootView else { return }
        for view in root.allViews where view.windowObject == objcObject {
            for area in view.trackingAreas {
                let rect = area.options & 0x200 != 0 ? view.bounds : area.rect
                let inside = rect.contains(view.fromWindow(event.locationInWindow))
                if inside != area.inside {
                    area.inside = inside
                    if area.options & 0x01 != 0, let owner = area.owner {
                        let crossing = NSEvent(inside ? .mouseEntered : .mouseExited, window: self, location: event.locationInWindow)
                        crossing.trackingArea = area
                        Send.void(owner, inside ? "mouseEntered:" : "mouseExited:", crossing.objcObject)
                    }
                }
                if moved, inside, area.options & 0x02 != 0, let owner = area.owner, owner != firstResponderObject || !acceptsMouseMovedEvents {
                    Send.void(owner, "mouseMoved:", event.objcObject)
                }
            }
        }
    }

    /// The window's own -mouseDown: and the like end the responder chain.
    @ObjCMethod("keyDown:") override func keyDown(_ event: NSObject?) {}
}

/// NSPanel: a window for auxiliary content.
@ObjCClass("NSPanel")
open class NSPanel: NSWindow {
    @ObjCMethod("setFloatingPanel:") func setFloatingPanel(_ value: Bool) {}
    @ObjCMethod("setBecomesKeyOnlyIfNeeded:") func setBecomesKeyOnlyIfNeeded(_ value: Bool) {}
    @ObjCMethod("setWorksWhenModal:") func setWorksWhenModal(_ value: Bool) {}
}


/// NSWindowController: owns a window, loaded from its nib (or a
/// storyboard's), and shows it.
@ObjCClass("NSWindowController")
open class NSWindowController: NSResponder {
    var window: NSWindow?
    var windowNibName: String?
    /// Not retained: File's Owner of the window's nib, when it isn't the controller.
    var windowNibOwner: UnsafeMutableRawPointer?
    var document: NSObject?
    var storyboard: NSStoryboard?
    var loadingWindow = false
    var shouldCascadeWindows = true
    var windowFrameAutosaveName = ""
    var pendingContentViewController: NSViewController?

    public required init() { super.init() }

    @ObjCMethod("initWithWindow:")
    public required init(window: NSWindow?) {
        super.init()
        self.window = window
        window?.windowControllerObject = objcObject
    }

    // The other initializers send -initWithWindow:, as AppKit's do, so a
    // subclass's designated initializer (a Swift class's property
    // defaults) runs.

    @ObjCMethod("init")
    func initialize() -> NSObject { initializeWindowController(window: nil) }

    @ObjCMethod("initWithWindowNibName:")
    func initialize(windowNibName: String?) -> NSObject { initialize(windowNibName: windowNibName, owner: nil) }

    @ObjCMethod("initWithWindowNibName:owner:")
    func initialize(windowNibName: String?, owner: NSObject?) -> NSObject {
        let initialized = initializeWindowController(window: nil)
        if let controller = initialized.as(NSWindowController.self) {
            controller.windowNibName = windowNibName
            controller.windowNibOwner = owner?.objcObject
        }
        return initialized
    }

    @ObjCMethod("initWithWindowNibPath:owner:")
    func initialize(windowNibPath: String?, owner: NSObject?) -> NSObject {
        let file = windowNibPath.map { String($0.split(separator: "/").last ?? "") } ?? ""
        return initialize(windowNibName: file.hasSuffix(".nib") ? String(file.dropLast(4)) : file, owner: owner)
    }

    public convenience init(windowNibName: String?, owner: NSObject? = nil) {
        self.init(window: nil)
        self.windowNibName = windowNibName
        windowNibOwner = owner?.objcObject
    }

    /// A storyboard's window controller: its window (a template) and the
    /// window's content view controller.
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        if let window = decoded.object("IBWindowTemplate")?.as(NSWindow.self) {
            self.window = window
            window.windowControllerObject = objcObject
        }
        pendingContentViewController = decoded.object("IBWindowTemplateContentViewController")?.as(NSViewController.self)
        windowFrameAutosaveName = decoded.string("NSWindowFrameAutosaveName") ?? ""
    }

    @ObjCMethod("window")
    func controllerWindow() -> NSWindow? {
        loadWindowIfNeeded()
        return window
    }
    @ObjCMethod("setWindow:")
    func setWindow(_ window: NSWindow?) {
        self.window = window
        window?.windowControllerObject = objcObject
    }
    @ObjCMethod("windowNibName") func controllerWindowNibName() -> String? { windowNibName }
    @ObjCMethod("windowNibPath") func windowNibPath() -> String? { nil }
    @ObjCMethod("isWindowLoaded") func isWindowLoaded() -> Bool { window != nil }
    @ObjCMethod("loadWindow") func loadWindow() { loadWindowNib() }
    @ObjCMethod("windowDidLoad") func windowDidLoad() {}
    @ObjCMethod("windowWillLoad") func windowWillLoad() {}

    @ObjCMethod("showWindow:")
    func showWindow(_ sender: NSObject?) {
        guard let window = controllerWindow() else { return }
        if let pending = pendingContentViewController, window.contentViewControllerObject == nil {
            window.setContentViewController(pending)
        }
        pendingContentViewController = nil
        Send.void(window.objcObject, "makeKeyAndOrderFront:", sender?.objcObject)
    }
    @ObjCMethod("close") func close() { window.map { Send.void($0.objcObject, "close") } }
    @ObjCMethod("document") func controllerDocument() -> NSObject? { document }
    @ObjCMethod("setDocument:") func setDocument(_ document: NSObject?) { self.document = document }
    @ObjCMethod("owner") func owner() -> NSObject? { windowNibOwner.map(NSObject.init) ?? self }
    @ObjCMethod("storyboard") func controllerStoryboard() -> NSStoryboard? { storyboard }
    @ObjCMethod("setStoryboard:") func setStoryboard(_ value: NSStoryboard?) { storyboard = value }
    @ObjCMethod("contentViewController")
    func contentViewController() -> NSViewController? { window?.contentViewControllerObject ?? pendingContentViewController }
    @ObjCMethod("setContentViewController:")
    func setContentViewController(_ controller: NSViewController?) {
        if let window = controllerWindow() { window.setContentViewController(controller) } else { pendingContentViewController = controller }
    }
    @ObjCMethod("shouldCascadeWindows") func controllerShouldCascadeWindows() -> Bool { shouldCascadeWindows }
    @ObjCMethod("setShouldCascadeWindows:") func setShouldCascadeWindows(_ value: Bool) { shouldCascadeWindows = value }
    @ObjCMethod("windowFrameAutosaveName") func controllerWindowFrameAutosaveName() -> String { windowFrameAutosaveName }
    @ObjCMethod("setWindowFrameAutosaveName:") func setWindowFrameAutosaveName(_ name: String?) { windowFrameAutosaveName = name ?? "" }
    @ObjCMethod("shouldCloseDocument") func shouldCloseDocument() -> Bool { false }
    @ObjCMethod("setShouldCloseDocument:") func setShouldCloseDocument(_ value: Bool) {}
    @ObjCMethod("synchronizeWindowTitleWithDocumentName") func synchronizeWindowTitleWithDocumentName() {}
    @ObjCMethod("windowTitleForDocumentDisplayName:") func windowTitle(forDocumentDisplayName name: String?) -> String? { name }
    @ObjCMethod("dismissController:") func dismissController(_ sender: NSObject?) { close() }
}

/// NSWindowController's messages, sent so subclasses' overrides run.
extension NSObject {
    @ObjCMethod("initWithWindow:")
    func initializeWindowController(window: NSWindow?) -> NSObject
}
