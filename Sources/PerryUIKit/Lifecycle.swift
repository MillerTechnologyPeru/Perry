import Glibc
import PerryObjCInterop

// The app's lifecycle after launch, as iOS runs it: active, inactive,
// background and back, and termination. A scene app's scenes hear of each
// step through their delegates (which is also how SwiftUI's scenePhase
// changes) and the scene notifications; an app without scenes hears through
// its app delegate. Both get the UIApplication notifications, and the app
// delegate is told of termination last.
//
// The window losing focus makes the app inactive, and gaining it active;
// the window minimized or hidden sends it to the background, and shown or
// restored brings it back. Closing the window, SIGTERM, SIGINT or SIGHUP
// (as a handheld's menu sends when it closes a port) and UIKit's
// -_perryTerminate end it, going through the background first so apps
// save as they do when iOS suspends them. A second signal while ending
// exits at once.

enum Lifecycle {
    /// The scenes connected, in the order they were.
    nonisolated(unsafe) static var scenes: [UIScene] = []
    /// The scene an app without a scene manifest or scene configuration
    /// has, as UIKit gives the windows it makes: foreground active from the
    /// start, with no delegate. SwiftUI updates a hosting view's display
    /// only while its scene is active.
    nonisolated(unsafe) static var implicitScene: UIScene?
    nonisolated(unsafe) private static var terminating = false
    /// Whether launch is over, the app first active: the window's focus and
    /// visibility count from then.
    nonisolated(unsafe) static var launched = false

    /// The window's focus or visibility changed: SDL's window events.
    static func window(focused: Bool) {
        guard launched else { return }
        if focused { becomeActive() } else { resignActive() }
    }

    static func window(visible: Bool) {
        guard launched else { return }
        if visible { becomeActive() } else { enterBackground() }
    }

    private static var application: UIApplication? { Application.shared }
    private static var delegate: AnyUIApplicationDelegate? { Application.delegate?.unsafeCast(to: AnyUIApplicationDelegate.self) }

    private static func sceneDelegate(_ scene: UIScene) -> AnyUISceneDelegate? {
        scene.state.delegate?.unsafeCast(to: AnyUISceneDelegate.self)
    }

    static func resignActive() {
        guard Application.state == .active, let application else { return }
        Application.state = .inactive
        if scenes.isEmpty {
            delegate?.applicationWillResignActive(application)
        }
        for scene in scenes where scene.state.activationState == .foregroundActive {
            scene.state.activationState = .foregroundInactive
            sceneDelegate(scene)?.sceneWillResignActive(scene)
            Application.post(Notifications.UISceneWillDeactivateNotification, object: scene)
        }
        Application.post(Notifications.UIApplicationWillResignActiveNotification, object: application)
    }

    static func enterBackground() {
        resignActive()
        guard Application.state != .background, let application else { return }
        Application.state = .background
        if scenes.isEmpty {
            delegate?.applicationDidEnterBackground(application)
        }
        for scene in scenes where scene.state.activationState != .background {
            scene.state.activationState = .background
            sceneDelegate(scene)?.sceneDidEnterBackground(scene)
            Application.post(Notifications.UISceneDidEnterBackgroundNotification, object: scene)
        }
        Application.post(Notifications.UIApplicationDidEnterBackgroundNotification, object: application)
    }

    static func enterForeground() {
        guard Application.state == .background, !terminating, let application else { return }
        Application.state = .inactive
        if scenes.isEmpty {
            delegate?.applicationWillEnterForeground(application)
        }
        for scene in scenes where scene.state.activationState == .background {
            scene.state.activationState = .foregroundInactive
            sceneDelegate(scene)?.sceneWillEnterForeground(scene)
            Application.post(Notifications.UISceneWillEnterForegroundNotification, object: scene)
        }
        Application.post(Notifications.UIApplicationWillEnterForegroundNotification, object: application)
    }

    static func becomeActive() {
        enterForeground()
        guard Application.state == .inactive, !terminating, let application else { return }
        Application.state = .active
        if scenes.isEmpty {
            delegate?.applicationDidBecomeActive(application)
        }
        for scene in scenes where scene.state.activationState == .foregroundInactive {
            scene.state.activationState = .foregroundActive
            sceneDelegate(scene)?.sceneDidBecomeActive(scene)
            Application.post(Notifications.UISceneDidActivateNotification, object: scene)
        }
        Application.post(Notifications.UIApplicationDidBecomeActiveNotification, object: application)
    }

    /// Ends the app: to the background, then terminating, then the scenes
    /// disconnect; the defaults are written and the process exits.
    static func terminate() -> Never {
        if !terminating, let application {
            ObjCRuntime.autoreleasepool {
                enterBackground()
                terminating = true
                delegate?.applicationWillTerminate(application)
                Application.post(Notifications.UIApplicationWillTerminateNotification, object: application)
                for scene in scenes {
                    scene.state.activationState = .unattached
                    sceneDelegate(scene)?.sceneDidDisconnect(scene)
                    Application.post(Notifications.UISceneDidDisconnectNotification, object: scene)
                }
                NSUserDefaults.standardUserDefaults()?.synchronize()
            }
        }
        exit(0)
    }

    // MARK: Signals

    /// Set from a signal handler, which may do nothing else; the main
    /// queue's tick ends the app.
    nonisolated(unsafe) private static var signalled: sig_atomic_t = 0

    static func installSignalHandlers() {
        for signal in [SIGTERM, SIGINT, SIGHUP] {
            var action = sigaction()
            action.__sigaction_handler.sa_handler = { _ in
                // A second signal while ending: out at once.
                if Lifecycle.signalled != 0 { _exit(0) }
                Lifecycle.signalled = 1
            }
            sigemptyset(&action.sa_mask)
            _ = sigaction(signal, &action, nil)
        }
        scheduleSignalCheck()
    }

    /// Ten times a second, whether or not the app shows anything.
    private static func scheduleSignalCheck() {
        guard let dispatchAfter = Display.dispatchAfter, let dispatchTime = Display.dispatchTime else { return }
        dispatchAfter(dispatchTime(0, 100_000_000), Updates.mainQueue, nil) { _ in
            if Lifecycle.signalled != 0 { Lifecycle.terminate() }
            Lifecycle.scheduleSignalCheck()
        }
    }
}

@ObjCWrapper("NSUserDefaults")
class NSUserDefaults: NSObject {
    @ObjCClassMethod("standardUserDefaults") static func standardUserDefaults() -> NSUserDefaults?
    @ObjCMethod("synchronize") @discardableResult func synchronize() -> Bool
}
