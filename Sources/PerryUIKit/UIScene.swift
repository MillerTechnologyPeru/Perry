import PerryObjCInterop

// Scenes: the session that describes one, the configuration that names its
// classes, and the scene itself.

/// UISceneActivationState.
enum SceneActivationState: Int {
    case unattached = -1
    case foregroundActive = 0
    case foregroundInactive = 1
    case background = 2
}

// MARK: - UISceneConfiguration

final class SceneConfigurationState: ObjectState {
    var name: String?
    var role = ""
    var delegateClass: ObjCClass?
    var sceneClass: ObjCClass?
}

/// The classes a scene of one role is made from.
@ObjCClass("UISceneConfiguration")
open class UISceneConfiguration: NSObject {
    static let states = StateTable<SceneConfigurationState>()
    var state: SceneConfigurationState { Self.states[objcObject] }

    /// A new configuration, +1.
    static func make(name: String?, role: String) -> UISceneConfiguration {
        let configuration = UISceneConfiguration.objCClass.object.newInstance().unsafeCast(to: UISceneConfiguration.self)
        configuration.state.name = name
        configuration.state.role = role
        return configuration
    }

    @ObjCClassMethod("configurationWithName:sessionRole:")
    static func configuration(name: String?, sessionRole role: String) -> UISceneConfiguration {
        make(name: name, role: role)
    }

    @ObjCMethod("initWithName:sessionRole:")
    func initialize(name: String?, sessionRole role: String) -> Self {
        state.name = name
        state.role = role
        return self
    }

    @ObjCMethod("name") func name() -> String? { state.name }
    @ObjCMethod("role") func role() -> String { state.role }
    @ObjCMethod("delegateClass") func delegateClass() -> ObjCClass? { state.delegateClass }
    @ObjCMethod("setDelegateClass:") func setDelegateClass(_ cls: ObjCClass?) { state.delegateClass = cls }
    @ObjCMethod("sceneClass") func sceneClass() -> ObjCClass? { state.sceneClass }
    @ObjCMethod("setSceneClass:") func setSceneClass(_ cls: ObjCClass?) { state.sceneClass = cls }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UISceneConfiguration {
        let copy = UISceneConfiguration.make(name: state.name, role: state.role)
        copy.state.delegateClass = state.delegateClass
        copy.state.sceneClass = state.sceneClass
        return copy
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Self.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UISceneConfiguration.objCClass.pointer)
    }
}

// MARK: - UISceneSession

final class SceneSessionState: ObjectState {
    var role = ""
    var identifier = ""
    var configuration: UISceneConfiguration?
    /// The scene, which holds the session; not retained.
    var scene: UnsafeMutableRawPointer?
}

/// A scene's session: its role, configuration and identity.
@ObjCClass("UISceneSession")
open class UISceneSession: NSObject {
    static let states = StateTable<SceneSessionState>()
    var state: SceneSessionState { Self.states[objcObject] }

    /// A new session for `configuration`, +1.
    static func make(role: String, configuration: UISceneConfiguration) -> UISceneSession {
        let session = UISceneSession.objCClass.object.newInstance().unsafeCast(to: UISceneSession.self)
        session.state.role = role
        session.state.identifier = NSUUID.make().uuidString()
        session.state.configuration = configuration.copied().unsafeCast(to: UISceneConfiguration.self)
        return session
    }

    @ObjCMethod("role") func role() -> String { state.role }
    @ObjCMethod("persistentIdentifier") func persistentIdentifier() -> String { state.identifier }
    @ObjCMethod("configuration") func configuration() -> UISceneConfiguration? { state.configuration }
    @ObjCMethod("scene") func scene() -> NSObject? { state.scene.map(NSObject.init) }
    @ObjCMethod("userInfo") func userInfo() -> NSObject? { nil }

    @ObjCMethod("dealloc")
    func dealloc() {
        Self.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UISceneSession.objCClass.pointer)
    }
}

// MARK: - UISceneConnectionOptions

/// Why a scene connected: URLs, activities and the like. Empty for a launch.
@ObjCClass("UISceneConnectionOptions")
open class UISceneConnectionOptions: NSObject {
    @ObjCMethod("URLContexts") func urlContexts() -> NSObject { NSMutableSet.empty() }
    @ObjCMethod("sourceApplication") func sourceApplication() -> String? { nil }
    @ObjCMethod("userActivities") func userActivities() -> NSObject { NSMutableSet.empty() }
}

// MARK: - UIScene

final class SceneState: ObjectState {
    var session: UISceneSession?
    var delegate: NSObject?
    var activationState = SceneActivationState.unattached
    var title = ""
}

/// UIScene: one instance of the app's UI.
@ObjCClass("UIScene")
open class UIScene: UIResponder {
    static let states = StateTable<SceneState>()
    var state: SceneState { Self.states[objcObject] }

    @ObjCMethod("initWithSession:connectionOptions:")
    func initialize(session: UISceneSession, connectionOptions options: UISceneConnectionOptions) -> Self {
        state.session = session
        return self
    }

    @ObjCMethod("session") func session() -> UISceneSession? { state.session }
    @ObjCMethod("delegate") func delegate() -> NSObject? { state.delegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { state.delegate = delegate }
    @ObjCMethod("activationState") func activationState() -> Int { state.activationState.rawValue }
    @ObjCMethod("title") func title() -> String { state.title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { state.title = title ?? "" }

    /// The application.
    @ObjCMethod("nextResponder")
    override func nextResponder() -> NSObject? { Application.shared }

    @ObjCMethod("dealloc")
    func dealloc() {
        Self.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIScene.objCClass.pointer)
    }
}

final class WindowSceneState: ObjectState {
    /// The scene's windows, in the order made; not retained.
    var windows: [UnsafeMutableRawPointer] = []
}

/// A scene with windows: the kind the application role uses.
@ObjCClass("UIWindowScene")
open class UIWindowScene: UIScene {
    static let windowSceneStates = StateTable<WindowSceneState>()
    var windowSceneState: WindowSceneState { UIWindowScene.windowSceneStates[objcObject] }

    static func remove(window: UnsafeMutableRawPointer, from scene: UnsafeMutableRawPointer) {
        windowSceneStates[scene].windows.removeAll { $0 == window }
    }

    @ObjCMethod("windows")
    func windows() -> NSObject { NSMutableArray.of(windowSceneState.windows.map(NSObject.init)) }

    @ObjCMethod("keyWindow")
    func keyWindow() -> NSObject? {
        guard let key = Windows.key, windowSceneState.windows.contains(key) else { return nil }
        return NSObject(key)
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIWindowScene.windowSceneStates.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIWindowScene.objCClass.pointer)
    }
}

/// UISceneDelegate's messages, and UIScene's initializer as a message, so a
/// subclass's runs.
extension NSObject {
    @ObjCMethod("initWithSession:connectionOptions:")
    func initializeScene(session: UISceneSession, options: UISceneConnectionOptions) -> NSObject

    @ObjCMethod("scene:willConnectToSession:options:")
    func sceneWillConnect(_ scene: UIScene, to session: UISceneSession, options: UISceneConnectionOptions)

    @ObjCMethod("sceneWillEnterForeground:")
    func sceneWillEnterForeground(_ scene: UIScene)

    @ObjCMethod("sceneDidBecomeActive:")
    func sceneDidBecomeActive(_ scene: UIScene)
}
