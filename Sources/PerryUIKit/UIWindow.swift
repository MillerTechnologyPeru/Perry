import CPerryGeometry
import PerryObjCInterop

// UIWindow: the root of a view hierarchy, in a window scene. Its root view
// controller's view is installed when the window becomes visible.

final class WindowState: ObjectState {
    /// The window's scene, which lists the window; not retained.
    var scene: UnsafeMutableRawPointer?
    var rootViewController: UIViewController?
    /// The view between the window and the root view, once installed.
    var transitionView: UIView?
}

enum Windows {
    /// The application's key window; not retained.
    nonisolated(unsafe) static var key: UnsafeMutableRawPointer?
    /// Every window, in the order made; not retained.
    nonisolated(unsafe) static var all: [UnsafeMutableRawPointer] = []

    /// The windows that are not hidden, back to front.
    static var visible: [UIWindow] {
        all.map { UIWindow(objcObject: $0, ownership: .retain) }.filter { !$0.state.hidden }
    }
}

@ObjCClass("UIWindow")
open class UIWindow: UIView {
    static let windowStates = StateTable<WindowState>()
    var windowState: WindowState { UIWindow.windowStates[objcObject] }

    /// Windows start hidden.
    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        state.hidden = true
        if !Windows.all.contains(objcObject) { Windows.all.append(objcObject) }
        return self
    }

    /// From a nib, as a main nib's window: hidden until shown, and the
    /// size of the screen when it resizes to fill it, as nib windows do.
    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        state.hidden = true
        if Coder(coder: coder).bool("UIResizesToFullScreen") { sendSetFrame(Screen.bounds) }
        if !Windows.all.contains(objcObject) { Windows.all.append(objcObject) }
        return self
    }

    /// A window in `scene`, the size of the screen.
    @ObjCMethod("initWithWindowScene:")
    func initialize(windowScene scene: UIWindowScene) -> NSObject {
        let window = initializeView(frame: Screen.bounds).unsafeCast(to: UIWindow.self)
        window.setWindowScene(scene)
        return window
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        if Windows.key == objcObject { Windows.key = nil }
        Windows.all.removeAll { $0 == objcObject }
        if let scene = windowState.scene { UIWindowScene.remove(window: objcObject, from: scene) }
        UIWindow.windowStates.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIWindow.objCClass.pointer)
    }

    @ObjCMethod("windowScene")
    func windowScene() -> UIWindowScene? { windowState.scene.map { UIWindowScene(objcObject: $0, ownership: .retain) } }

    @ObjCMethod("setWindowScene:")
    func setWindowScene(_ scene: UIWindowScene?) {
        if let old = windowState.scene { UIWindowScene.remove(window: objcObject, from: old) }
        windowState.scene = scene?.objcObject
        scene?.windowSceneState.windows.append(objcObject)
    }

    // MARK: The root view controller

    @ObjCMethod("rootViewController")
    func rootViewController() -> UIViewController? { windowState.rootViewController }

    @ObjCMethod("setRootViewController:")
    func setRootViewController(_ controller: UIViewController?) {
        windowState.transitionView?.removeFromSuperview()
        windowState.transitionView = nil
        windowState.rootViewController = controller
        if !state.hidden { installRootView() }
    }

    /// Puts the root view controller's view in the window, inside the
    /// transition and drop shadow views UIKit uses, loading it if needed.
    private func installRootView() {
        guard windowState.transitionView == nil, let controller = windowState.rootViewController else { return }
        let bounds = state.bounds
        let transition = UITransitionView.objCClass.object.allocated().initializeView(frame: bounds)
            .unsafeCast(to: UIView.self)
        let shadow = UIDropShadowView.objCClass.object.allocated().initializeView(frame: bounds)
            .unsafeCast(to: UIView.self)
        let root = controller.sendView()
        root.sendSetFrame(bounds)
        // All three follow the window's size, as the screen's can change.
        for view in [transition, shadow, root] { view.setAutoresizingMask(18) }
        shadow.addSubview(root)
        transition.addSubview(shadow)
        windowState.transitionView = transition
        addSubview(transition)
    }

    // MARK: Visibility and the key window

    @ObjCMethod("setHidden:")
    override func setHidden(_ hidden: Bool) {
        state.hidden = hidden
        if !hidden {
            installRootView()
            Display.startIfWanted()
            TapScript.startIfRequested()
        }
        Updates.schedule()
    }

    /// The one screen.
    @ObjCMethod("screen") func screen() -> UIScreen { UIScreen.mainScreen() }
    @ObjCMethod("setScreen:") func setScreen(_ screen: UIScreen?) {}

    @ObjCMethod("makeKeyAndVisible")
    func makeKeyAndVisible() {
        sendSetHidden(false)
        makeKeyWindow()
    }

    @ObjCMethod("makeKeyWindow")
    func makeKeyWindow() {
        guard Windows.key != objcObject else { return }
        if let previous = Windows.key { NSObject(previous).sendResignKeyWindow() }
        Windows.key = objcObject
        sendBecomeKeyWindow()
    }

    @ObjCMethod("isKeyWindow") func isKeyWindow() -> Bool { Windows.key == objcObject }
    @ObjCMethod("becomeKeyWindow") func becomeKeyWindow() {}
    @ObjCMethod("resignKeyWindow") func resignKeyWindow() {}

    /// The window's scene, or the application.
    @ObjCMethod("nextResponder")
    override func nextResponder() -> NSObject? {
        if let scene = windowState.scene { return NSObject(scene) }
        return Application.shared
    }
}

/// UIWindow's messages, sent so subclasses' overrides run.
extension NSObject {
    @ObjCMethod("setFrame:") func sendSetFrame(_ frame: CGRect)
    @ObjCMethod("setHidden:") func sendSetHidden(_ hidden: Bool)
    @ObjCMethod("becomeKeyWindow") func sendBecomeKeyWindow()
    @ObjCMethod("resignKeyWindow") func sendResignKeyWindow()
}
