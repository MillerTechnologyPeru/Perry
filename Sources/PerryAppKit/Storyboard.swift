import CPerryGeometry
import Glibc
import PerryObjCInterop

// Storyboards and view controllers. A compiled storyboard is a directory
// of nibs and an Info.plist naming its entry point, its main menu and the
// nib of each controller identifier. Instantiating a controller loads its
// nib with the storyboard passed in; a window controller's nib holds its
// window (as a template) and its content view controller, whose own view
// is in another nib, loaded with the controller as File's Owner when its
// view is first asked for. NSApplicationMain loads the main storyboard's
// menu, then shows its initial controller, as AppKit does.

@ObjCClass("NSStoryboard")
open class NSStoryboard: NSObject {
    var directory = ""
    var name = ""
    var info: [String: NSObject] = [:]
    var nibNames: [String: String] = [:]
    var bundle: NSObject?

    nonisolated(unsafe) static var main: NSStoryboard?

    @ObjCMethod("init")
    public required override init() { super.init() }

    /// The storyboard `name`.storyboardc in a bundle's resources.
    static func load(named name: String, bundle: NSObject?) -> NSStoryboard? {
        for directory in Nibs.directories(bundle) {
            let path = "\(directory)/\(name).storyboardc"
            guard let dictionary = Send.object(Classes.named("NSDictionary")?.pointer, "dictionaryWithContentsOfFile:",
                                               (path + "/Info.plist").objCArgument()) else { continue }
            let storyboard = NSStoryboard()
            storyboard.directory = path
            storyboard.name = name
            storyboard.bundle = bundle
            storyboard.info = Nibs.strings(NSObject(dictionary))
            storyboard.nibNames = Nibs.strings(storyboard.info["NSViewControllerIdentifiersToNibNames"]).mapValues { $0.stringValue }
            return storyboard
        }
        return nil
    }

    @ObjCClassMethod("storyboardWithName:bundle:")
    static func storyboard(name: String?, bundle: NSObject?) -> NSStoryboard? {
        guard let name else { return nil }
        if let main, main.name == name { return main }
        guard let storyboard = load(named: name, bundle: bundle) else {
            appKitWarning("NSStoryboard: no storyboard \(name)")
            return nil
        }
        return storyboard
    }

    @ObjCClassMethod("mainStoryboard") static func mainStoryboard() -> NSStoryboard? { main }

    @ObjCMethod("instantiateInitialController")
    func instantiateInitialController() -> NSObject? {
        guard let identifier = info["NSStoryboardDesignatedEntryPointIdentifier"]?.stringValue else { return nil }
        return instantiateController(withIdentifier: identifier)
    }

    @ObjCMethod("instantiateInitialControllerWithCreator:")
    func instantiateInitialController(creator: ObjCBlock?) -> NSObject? { instantiateInitialController() }

    @ObjCMethod("instantiateControllerWithIdentifier:")
    func instantiateController(withIdentifier identifier: String?) -> NSObject? {
        guard let identifier, let nibName = nibNames[identifier] ?? (nibNames.values.contains(identifier) ? identifier : nil) else {
            appKitWarning("NSStoryboard \(name): no controller \(identifier ?? "")")
            return nil
        }
        return instantiate(nib: nibName)
    }

    @ObjCMethod("instantiateControllerWithIdentifier:creator:")
    func instantiateController(withIdentifier identifier: String?, creator: ObjCBlock?) -> NSObject? { instantiateController(withIdentifier: identifier) }

    /// A scene's nib: its controller is File's Owner's "sceneController".
    func instantiate(nib name: String, external: [String: NSObject] = [:]) -> NSObject? {
        guard let archive = Nibs.load(named: name, in: directory) else {
            appKitWarning("NSStoryboard \(self.name): no nib \(name)")
            return nil
        }
        let scene = StoryboardScene()
        var placeholders = external
        placeholders["NSStoryboardPlaceholder"] = self
        let objects = Nibs.instantiate(archive, owner: scene, external: placeholders, bundlePath: directory)
        guard let controller = scene.sceneController ?? objects.first else { return nil }
        if let windowController = controller.as(NSWindowController.self) {
            windowController.storyboard = self
            Send.void(windowController.objcObject, "windowDidLoad")
        }
        controller.as(NSViewController.self)?.storyboard = self
        return controller
    }

    /// The main menu, with the application as File's Owner.
    func loadMainMenu(owner: NSObject) {
        guard let name = info["NSStoryboardMainMenu"]?.stringValue, let archive = Nibs.load(named: name, in: directory) else { return }
        Nibs.kept += Nibs.instantiate(archive, owner: owner, external: ["NSStoryboardPlaceholder": self], bundlePath: directory)
    }
}

/// File's Owner of a storyboard scene's nib.
@ObjCClass("_PerryStoryboardScene")
open class StoryboardScene: NSObject {
    var sceneController: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("setSceneController:") func setSceneController(_ value: NSObject?) { sceneController = value }
    @ObjCMethod("sceneController") func controller() -> NSObject? { sceneController }
}

/// NSStoryboardSegue: performed by showing or presenting its destination.
@ObjCClass("NSStoryboardSegue")
open class NSStoryboardSegue: NSObject {
    var identifier: String?
    var source: NSObject?
    var destination: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithIdentifier:source:destination:")
    public required init(identifier: String?, source: NSObject?, destination: NSObject?) {
        super.init()
        (self.identifier, self.source, self.destination) = (identifier, source, destination)
    }

    @ObjCMethod("identifier") func segueIdentifier() -> String? { identifier }
    @ObjCMethod("sourceController") func sourceController() -> NSObject? { source }
    @ObjCMethod("destinationController") func destinationController() -> NSObject? { destination }
    @ObjCMethod("perform")
    func perform() {
        if let windowController = destination?.as(NSWindowController.self) { windowController.showWindow(nil) }
        else if let controller = destination?.as(NSViewController.self) { controller.presentInWindow() }
    }
}

@ObjCClass("NSViewController")
open class NSViewController: NSResponder {
    var viewObject: NSView?
    var nibName: String?
    var nibBundle: NSObject?
    var title: String?
    var representedObject: NSObject?
    var storyboard: NSStoryboard?
    var identifier: String?
    var external: [String: NSObject] = [:]
    var children: [NSViewController] = []
    /// Not retained.
    var parentObject: UnsafeMutableRawPointer?
    var presentingObject: UnsafeMutableRawPointer?
    var presented: [NSViewController] = []
    var preferredContentSize = CGSize.zero
    var loading = false
    var presentationWindow: NSWindow?

    public required init() { super.init() }

    /// -init is -initWithNibName:bundle: with neither, sent so a
    /// subclass's initializer (a Swift class's property defaults) runs.
    @ObjCMethod("init")
    func initialize() -> NSObject { initializeViewController(nibName: nil, bundle: nil) }

    @ObjCMethod("initWithNibName:bundle:")
    public required init(nibName: String?, bundle: NSObject?) {
        super.init()
        self.nibName = nibName
        nibBundle = bundle
    }

    /// A storyboard's view controller: the nib its view is in, and the
    /// objects that nib's placeholders stand for.
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        nibName = decoded.string("NSNibName")
        title = decoded.string("NSTitle")
        identifier = decoded.string("NSUserInterfaceItemIdentifier")
        external = decoded.dictionary("NSExternalObjectsTableForViewLoading")
        if decoded.has("NSView") { viewObject = decoded.object("NSView")?.as(NSView.self) }
        if let directory = decoded.nib?.bundlePath, directory.hasSuffix(".storyboardc") { storyboardDirectory = directory }
    }

    var storyboardDirectory: String?

    var parent: NSViewController? { parentObject.map { NSViewController.objCInstance($0, ownership: .retain) } }

    // MARK: The view

    @ObjCMethod("view")
    func view() -> NSView? {
        if viewObject == nil, !loading {
            loading = true
            Send.void(objcObject, "loadView")
            loading = false
            if viewObject != nil { Send.void(objcObject, "viewDidLoad") }
        }
        return viewObject
    }

    @ObjCMethod("setView:")
    func setView(_ view: NSView?) {
        viewObject = view
        view?.nextResponderObject = objcObject
    }

    @ObjCMethod("isViewLoaded") func isViewLoaded() -> Bool { viewObject != nil }
    @ObjCMethod("viewIfLoaded") func viewIfLoaded() -> NSView? { viewObject }
    @ObjCMethod("loadViewIfNeeded") func loadViewIfNeeded() { _ = view() }

    /// Loads the view's nib, with the controller as File's Owner: the
    /// storyboard's, or the nib named for it in its bundle.
    @ObjCMethod("loadView")
    func loadView() {
        let name = nibName ?? defaultNibName
        var placeholders = external
        if let storyboard { placeholders["NSStoryboardPlaceholder"] = storyboard }
        if let directory = storyboardDirectory ?? storyboard?.directory, let archive = Nibs.load(named: name, in: directory) {
            Nibs.instantiate(archive, owner: self, external: placeholders, bundlePath: directory)
        } else if let found = Nibs.find(name, bundle: nibBundle) {
            Nibs.instantiate(found.archive, owner: self, external: placeholders, bundlePath: found.directory)
        } else if nibName != nil {
            appKitWarning("NSViewController: no nib \(name)")
        }
        if viewObject == nil, nibName == nil { setView(NSView(frame: CGRect(x: 0, y: 0, width: 480, height: 270))) }
    }

    /// The class's name without its module, as AppKit looks for a nib.
    private var defaultNibName: String {
        guard let cls = ObjCRuntime.objectClass(objcObject), let described = Send.object(cls, "description") else { return "" }
        let name = String(objCArgument: described)
        if name.hasPrefix("_TtC") {
            // _TtC<length><module><length><name>
            var rest = Substring(name.dropFirst(4))
            var parts: [String] = []
            while let digits = rest.prefix(while: \.isNumber).nilIfEmpty, let length = Int(digits) {
                rest = rest.dropFirst(digits.count)
                parts.append(String(rest.prefix(length)))
                rest = rest.dropFirst(length)
            }
            return parts.last ?? name
        }
        return name
    }

    @ObjCMethod("viewDidLoad") func viewDidLoad() {}
    @ObjCMethod("viewWillAppear") func viewWillAppear() {}
    @ObjCMethod("viewDidAppear") func viewDidAppear() {}
    @ObjCMethod("viewWillDisappear") func viewWillDisappear() {}
    @ObjCMethod("viewDidDisappear") func viewDidDisappear() {}
    @ObjCMethod("viewWillLayout") func viewWillLayout() {}
    @ObjCMethod("viewDidLayout") func viewDidLayout() {}
    @ObjCMethod("updateViewConstraints") func updateViewConstraints() {}
    @ObjCMethod("viewWillTransitionToSize:") func viewWillTransition(to size: CGSize) {}

    // MARK: Values

    @ObjCMethod("nibName") func controllerNibName() -> String? { nibName }
    @ObjCMethod("nibBundle") func controllerNibBundle() -> NSObject? { nibBundle }
    @ObjCMethod("title") func controllerTitle() -> String? { title }
    @ObjCMethod("setTitle:") func setTitle(_ value: String?) { title = value }
    @ObjCMethod("representedObject") func controllerRepresentedObject() -> NSObject? { representedObject }
    @ObjCMethod("setRepresentedObject:") func setRepresentedObject(_ value: NSObject?) { representedObject = value }
    @ObjCMethod("storyboard") func controllerStoryboard() -> NSStoryboard? { storyboard }
    @ObjCMethod("setStoryboard:") func setStoryboard(_ value: NSStoryboard?) { storyboard = value }
    @ObjCMethod("identifier") func controllerIdentifier() -> String? { identifier }
    @ObjCMethod("setIdentifier:") func setIdentifier(_ value: String?) { identifier = value }
    @ObjCMethod("preferredContentSize") func controllerPreferredContentSize() -> CGSize { preferredContentSize }
    @ObjCMethod("setPreferredContentSize:") func setPreferredContentSize(_ value: CGSize) { preferredContentSize = value }
    @ObjCMethod("preferredMinimumSize") func preferredMinimumSize() -> CGSize { .zero }
    @ObjCMethod("preferredMaximumSize") func preferredMaximumSize() -> CGSize { CGSize(width: 100_000, height: 100_000) }
    @ObjCMethod("commitEditing") func commitEditing() -> Bool { true }
    @ObjCMethod("discardEditing") func discardEditing() {}
    @ObjCMethod("extensionContext") func extensionContext() -> NSObject? { nil }
    @ObjCMethod("sourceItemView") func sourceItemView() -> NSObject? { nil }

    // MARK: Children and presentation

    @ObjCMethod("childViewControllers") func childViewControllers() -> NSObject { NSMutableArray.of(children) }
    @ObjCMethod("children") func controllerChildren() -> NSObject { NSMutableArray.of(children) }
    @ObjCMethod("setChildViewControllers:")
    func setChildViewControllers(_ value: NSObject?) {
        children = value?.as(NSArray.self)?.elements.compactMap { $0.as(NSViewController.self) } ?? []
        for child in children { child.parentObject = objcObject }
    }
    @ObjCMethod("setChildren:") func setChildren(_ value: NSObject?) { setChildViewControllers(value) }
    @ObjCMethod("addChildViewController:") func addChild(_ child: NSViewController?) { insertChild(child, at: children.count) }
    @ObjCMethod("insertChildViewController:atIndex:")
    func insertChild(_ child: NSViewController?, at index: Int) {
        guard let child else { return }
        child.removeFromParent()
        children.insert(child, at: max(0, min(index, children.count)))
        child.parentObject = objcObject
    }
    @ObjCMethod("removeChildViewControllerAtIndex:")
    func removeChild(at index: Int) {
        guard children.indices.contains(index) else { return }
        children.remove(at: index).parentObject = nil
    }
    @ObjCMethod("removeFromParentViewController")
    func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        parentObject = nil
    }
    @ObjCMethod("parentViewController") func parentViewController() -> NSViewController? { parent }
    @ObjCMethod("presentingViewController") func presentingViewController() -> NSViewController? {
        presentingObject.map { NSViewController.objCInstance($0, ownership: .retain) }
    }
    @ObjCMethod("presentedViewControllers") func presentedViewControllers() -> NSObject { NSMutableArray.of(presented) }

    /// Shows the controller's view in a window of its own.
    func presentInWindow() {
        guard let view = view() else { return }
        let size = preferredContentSize != .zero ? preferredContentSize : view.frame.size
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: StyleMask.titled | StyleMask.closable, backing: 2, defer: false)
        window.setTitle(title)
        window.setContentViewController(self)
        window.center()
        presentationWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func present(_ controller: NSViewController?) {
        guard let controller else { return }
        controller.presentingObject = objcObject
        presented.append(controller)
        controller.presentInWindow()
    }

    @ObjCMethod("presentViewControllerAsSheet:") func presentAsSheet(_ controller: NSViewController?) { present(controller) }
    @ObjCMethod("presentViewControllerAsModalWindow:") func presentAsModalWindow(_ controller: NSViewController?) { present(controller) }
    @ObjCMethod("presentViewController:asPopoverRelativeToRect:ofView:preferredEdge:behavior:")
    func presentAsPopover(_ controller: NSViewController?, relativeTo rect: CGRect, of view: NSView?, preferredEdge: UInt, behavior: Int) { present(controller) }
    @ObjCMethod("presentViewController:animator:") func present(_ controller: NSViewController?, animator: NSObject?) { present(controller) }
    @ObjCMethod("dismissViewController:")
    func dismiss(_ controller: NSViewController?) {
        guard let controller else { return }
        controller.presentationWindow?.close()
        controller.presentationWindow = nil
        presented.removeAll { $0 === controller }
        controller.presentingObject = nil
    }
    @ObjCMethod("dismissController:")
    func dismissController(_ sender: NSObject?) {
        if let presenting = presentingViewController() { presenting.dismiss(self) } else { viewObject?.window?.close() }
    }
    @ObjCMethod("performSegueWithIdentifier:sender:")
    func performSegue(withIdentifier identifier: String?, sender: NSObject?) {
        appKitWarning("NSViewController: segue \(identifier ?? "") isn't performed")
    }
    @ObjCMethod("shouldPerformSegueWithIdentifier:sender:") func shouldPerformSegue(withIdentifier identifier: String?, sender: NSObject?) -> Bool { true }
    @ObjCMethod("prepareForSegue:sender:") func prepare(for segue: NSObject?, sender: NSObject?) {}
}

extension Substring {
    var nilIfEmpty: Substring? { isEmpty ? nil : self }
}

// MARK: - Windows from nibs and their controllers

extension NSWindow {
    /// A window from a nib's NSWindowTemplate: its class, content
    /// rectangle, style, title, content view and size limits.
    static func instantiate(template decoded: Coder, unarchiving: NibUnarchiving) -> NSObject? {
        let className = decoded.string("NSWindowClass") ?? "NSWindow"
        guard let cls = Classes.named(className) ?? Classes.named("NSWindow"), let allocated = Send.object(cls.pointer, "alloc") else { return nil }
        let rect = decoded.rect("NSWindowRect")
        let style = UInt(bitPattern: decoded.integer("NSWindowStyleMask"))
        let backing = UInt(bitPattern: decoded.integer("NSWindowBacking"))
        typealias Init = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGRect, UInt, UInt, Bool) -> UnsafeMutableRawPointer?
        guard let made = unsafeBitCast(ObjCRuntime.msgSend, to: Init.self)(allocated, ObjCRuntime.selector("initWithContentRect:styleMask:backing:defer:"),
                                                                           rect, style, backing, true) else { return nil }
        let window = NSWindow.objCInstance(made, ownership: .adopt)
        if let index = unarchiving.stack.last { unarchiving.decoded[index] = window }
        if let title = decoded.string("NSWindowTitle") { window.setTitle(title) }
        if let view = decoded.object("NSWindowView")?.as(NSView.self) { Send.void(window.objcObject, "setContentView:", view.objcObject) }
        let minimum = decoded.has("NSWindowContentMinSize") ? decoded.size("NSWindowContentMinSize") : decoded.size("NSMinSize")
        if minimum != .zero { window.minSize = minimum }
        if decoded.has("NSWindowContentMaxSize") || decoded.has("NSMaxSize") {
            let maximum = decoded.has("NSWindowContentMaxSize") ? decoded.size("NSWindowContentMaxSize") : decoded.size("NSMaxSize")
            if maximum.width > 0, maximum.height > 0 { window.maxSize = CGSize(width: min(maximum.width, 100_000), height: min(maximum.height, 100_000)) }
        }
        if let name = decoded.string("NSFrameAutosaveName"), !name.isEmpty { window.frameAutosaveName = name }
        // NSWTFlags: hides on deactivate 0x80000000... the window isn't
        // released when closed, as nib windows usually aren't freed.
        window.releasedWhenClosed = false
        unarchiving.made.append(window)
        return window
    }
}

extension NSWindowController {
    /// The window from the controller's nib, loaded once.
    func loadWindowIfNeeded() {
        guard window == nil, !loadingWindow, let name = windowNibName else { return }
        loadingWindow = true
        defer { loadingWindow = false }
        Send.void(objcObject, "windowWillLoad")
        Send.void(objcObject, "loadWindow")
        if let window { window.windowControllerObject = objcObject }
        Send.void(objcObject, "windowDidLoad")
        if window == nil { appKitWarning("NSWindowController: nib \(name) has no window outlet") }
    }

    func loadWindowNib() {
        guard let name = windowNibName else { return }
        guard let found = Nibs.find(name, bundle: nil) else {
            appKitWarning("NSWindowController: no nib \(name)")
            return
        }
        let owner = windowNibOwner.map(NSObject.init) ?? self
        Nibs.kept += Nibs.instantiate(found.archive, owner: owner, bundlePath: found.directory)
    }
}

/// NSViewController's messages, sent so subclasses' overrides run.
extension NSObject {
    @ObjCMethod("initWithNibName:bundle:")
    func initializeViewController(nibName: String?, bundle: NSObject?) -> NSObject
}
