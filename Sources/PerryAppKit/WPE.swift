import Glibc

// WPE WebKit, WebKit's port for embedding, loaded when a web view first
// needs it: AppKit's copy of UIKit's engine, with script message handlers,
// user scripts and pointer input, which Mac apps' web views use. Each web view has a WebKitWebView of its own over a view backend
// from WPEBackend-fdo, which hands every frame the web process draws to the
// view in shared memory; the view shows it as its layer's contents. The
// pages run in WPE's web and network processes, which are Linux programs;
// their replies come through GLib's main context, which runs on the main
// queue while there are pages. Without WPE web views load nothing.

final class WPE: @unchecked Sendable {
    typealias Pointer = UnsafeMutableRawPointer

    // libwpe and WPEBackend-fdo.
    let viewBackendAddActivityState: @convention(c) (Pointer, UInt32) -> Void
    let viewBackendDispatchSetSize: @convention(c) (Pointer, UInt32, UInt32) -> Void
    let viewBackendDispatchSetDeviceScaleFactor: @convention(c) (Pointer, Float) -> Void
    let exportableCreate: @convention(c) (UnsafeRawPointer, Pointer?, UInt32, UInt32) -> Pointer?
    let exportableDestroy: @convention(c) (Pointer) -> Void
    let exportableGetViewBackend: @convention(c) (Pointer) -> Pointer?
    let exportableFrameComplete: @convention(c) (Pointer) -> Void
    let exportableReleaseShmBuffer: @convention(c) (Pointer, Pointer) -> Void
    let shmExportedBufferGetShmBuffer: @convention(c) (Pointer) -> Pointer?
    // libwayland-server's shared-memory buffers.
    let shmBufferGetData: @convention(c) (Pointer) -> Pointer?
    let shmBufferGetWidth: @convention(c) (Pointer) -> Int32
    let shmBufferGetHeight: @convention(c) (Pointer) -> Int32
    let shmBufferGetStride: @convention(c) (Pointer) -> Int32
    let shmBufferBeginAccess: @convention(c) (Pointer) -> Void
    let shmBufferEndAccess: @convention(c) (Pointer) -> Void
    // WPE WebKit's API, and its JavaScriptCore's values.
    let webViewBackendNew: @convention(c) (Pointer, Pointer?, Pointer?) -> Pointer?
    let webViewNew: @convention(c) (Pointer) -> Pointer?
    let webViewLoadHTML: @convention(c) (Pointer, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> Void
    let webViewLoadURI: @convention(c) (Pointer, UnsafePointer<CChar>) -> Void
    let webViewGetTitle: @convention(c) (Pointer) -> UnsafePointer<CChar>?
    let webViewGetURI: @convention(c) (Pointer) -> UnsafePointer<CChar>?
    let webViewIsLoading: @convention(c) (Pointer) -> Int32
    let webViewGetEstimatedLoadProgress: @convention(c) (Pointer) -> Double
    let webViewCanGoBack: @convention(c) (Pointer) -> Int32
    let webViewCanGoForward: @convention(c) (Pointer) -> Int32
    let webViewGoBack: @convention(c) (Pointer) -> Void
    let webViewGoForward: @convention(c) (Pointer) -> Void
    let webViewReload: @convention(c) (Pointer) -> Void
    let webViewStopLoading: @convention(c) (Pointer) -> Void
    let webViewGetSettings: @convention(c) (Pointer) -> Pointer?
    let settingsSetUserAgent: @convention(c) (Pointer, UnsafePointer<CChar>?) -> Void
    let webViewEvaluateJavaScript: @convention(c) (Pointer, UnsafePointer<CChar>, Int, UnsafePointer<CChar>?,
                                                   UnsafePointer<CChar>?, Pointer?, Pointer?, Pointer?) -> Void
    let webViewCallAsyncJavaScriptFunction: @convention(c) (Pointer, UnsafePointer<CChar>, Int, Pointer?, UnsafePointer<CChar>?,
                                                            UnsafePointer<CChar>?, Pointer?, Pointer?, Pointer?) -> Void
    let webViewEvaluateJavaScriptFinish: @convention(c) (Pointer, Pointer, UnsafeMutablePointer<Pointer?>) -> Pointer?
    let webViewCallAsyncJavaScriptFunctionFinish: @convention(c) (Pointer, Pointer, UnsafeMutablePointer<Pointer?>) -> Pointer?
    let valueIsUndefined: @convention(c) (Pointer) -> Int32
    let valueIsString: @convention(c) (Pointer) -> Int32
    let valueIsNumber: @convention(c) (Pointer) -> Int32
    let valueIsBoolean: @convention(c) (Pointer) -> Int32
    let valueToString: @convention(c) (Pointer) -> UnsafeMutablePointer<CChar>?
    // Policy decisions on navigations.
    let navigationPolicyDecisionGetNavigationAction: @convention(c) (Pointer) -> Pointer?
    let navigationActionGetRequest: @convention(c) (Pointer) -> Pointer?
    let navigationActionGetNavigationType: @convention(c) (Pointer) -> Int32
    let uriRequestGetURI: @convention(c) (Pointer) -> UnsafePointer<CChar>?
    let policyDecisionUse: @convention(c) (Pointer) -> Void
    let policyDecisionIgnore: @convention(c) (Pointer) -> Void
    let valueToJSON: @convention(c) (Pointer, UInt32) -> UnsafeMutablePointer<CChar>?
    // Script message handlers and user scripts.
    let webViewGetUserContentManager: @convention(c) (Pointer) -> Pointer?
    let registerScriptMessageHandler: @convention(c) (Pointer, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> Int32
    let unregisterScriptMessageHandler: @convention(c) (Pointer, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> Void
    let userScriptNew: @convention(c) (UnsafePointer<CChar>, Int32, Int32, UnsafeRawPointer?, UnsafeRawPointer?) -> Pointer?
    let userScriptUnref: @convention(c) (Pointer) -> Void
    let userContentManagerAddScript: @convention(c) (Pointer, Pointer) -> Void
    let userContentManagerRemoveAllScripts: @convention(c) (Pointer) -> Void
    // Input.
    let viewBackendDispatchPointerEvent: @convention(c) (Pointer, UnsafeRawPointer) -> Void
    let viewBackendDispatchAxisEvent: @convention(c) (Pointer, UnsafeRawPointer) -> Void
    let viewBackendDispatchKeyboardEvent: @convention(c) (Pointer, UnsafeRawPointer) -> Void
    // GLib and GObject.
    let mainContextIteration: @convention(c) (Pointer?, Int32) -> Int32
    let signalConnectData: @convention(c) (Pointer, UnsafePointer<CChar>, UnsafeRawPointer, Pointer?, Pointer?, Int32) -> UInt
    let signalHandlerDisconnect: @convention(c) (Pointer, UInt) -> Void
    let objectUnref: @convention(c) (Pointer) -> Void
    let free: @convention(c) (Pointer?) -> Void
    let errorFree: @convention(c) (Pointer) -> Void
    let quarkToString: @convention(c) (UInt32) -> UnsafePointer<CChar>?
    let paramSpecGetName: @convention(c) (Pointer) -> UnsafePointer<CChar>?

    // WebKitLoadEvent.
    static let loadStarted: Int32 = 0, loadCommitted: Int32 = 2, loadFinished: Int32 = 3
    /// wpe_view_activity_state: visible, focused, in a window.
    static let activityShown: UInt32 = 1 | 2 | 4

    /// WPE, initialized; nil when it isn't installed.
    static let shared: WPE? = WPE()

    private init?() {
        let names = ["libwpe-1.0.so.1", "libWPEBackend-fdo-1.0.so.1", "libwayland-server.so.0", "libWPEWebKit-2.0.so.1",
                     "libglib-2.0.so.0", "libgobject-2.0.so.0"]
        // Local, so WPE's JavaScriptCore never stands in for the one
        // JavaScriptCore.framework is over.
        let libraries = names.map { dlopen($0, RTLD_NOW | RTLD_LOCAL) }
        guard let wpe = libraries[0], let fdo = libraries[1], let wayland = libraries[2], let webkit = libraries[3],
              let glib = libraries[4], let gobject = libraries[5] else {
            WPE.log("WPE WebKit is not installed; web views load nothing")
            return nil
        }
        var missing: [String] = []
        func bind<T>(_ library: Pointer, _ name: String, _: T.Type) -> T {
            guard let symbol = dlsym(library, name) else {
                missing.append(name)
                return unsafeBitCast(WPE.missingFunction, to: T.self)
            }
            return unsafeBitCast(symbol, to: T.self)
        }
        let loaderInit = bind(wpe, "wpe_loader_init", (@convention(c) (UnsafePointer<CChar>) -> Int32).self)
        let initializeShm = bind(fdo, "wpe_fdo_initialize_shm", (@convention(c) () -> Int32).self)
        viewBackendAddActivityState = bind(wpe, "wpe_view_backend_add_activity_state", (@convention(c) (Pointer, UInt32) -> Void).self)
        viewBackendDispatchSetSize = bind(wpe, "wpe_view_backend_dispatch_set_size", (@convention(c) (Pointer, UInt32, UInt32) -> Void).self)
        viewBackendDispatchSetDeviceScaleFactor = bind(wpe, "wpe_view_backend_dispatch_set_device_scale_factor",
                                                       (@convention(c) (Pointer, Float) -> Void).self)
        exportableCreate = bind(fdo, "wpe_view_backend_exportable_fdo_create",
                                (@convention(c) (UnsafeRawPointer, Pointer?, UInt32, UInt32) -> Pointer?).self)
        exportableDestroy = bind(fdo, "wpe_view_backend_exportable_fdo_destroy", (@convention(c) (Pointer) -> Void).self)
        exportableGetViewBackend = bind(fdo, "wpe_view_backend_exportable_fdo_get_view_backend", (@convention(c) (Pointer) -> Pointer?).self)
        exportableFrameComplete = bind(fdo, "wpe_view_backend_exportable_fdo_dispatch_frame_complete", (@convention(c) (Pointer) -> Void).self)
        exportableReleaseShmBuffer = bind(fdo, "wpe_view_backend_exportable_fdo_dispatch_release_shm_exported_buffer",
                                          (@convention(c) (Pointer, Pointer) -> Void).self)
        shmExportedBufferGetShmBuffer = bind(fdo, "wpe_fdo_shm_exported_buffer_get_shm_buffer", (@convention(c) (Pointer) -> Pointer?).self)
        shmBufferGetData = bind(wayland, "wl_shm_buffer_get_data", (@convention(c) (Pointer) -> Pointer?).self)
        shmBufferGetWidth = bind(wayland, "wl_shm_buffer_get_width", (@convention(c) (Pointer) -> Int32).self)
        shmBufferGetHeight = bind(wayland, "wl_shm_buffer_get_height", (@convention(c) (Pointer) -> Int32).self)
        shmBufferGetStride = bind(wayland, "wl_shm_buffer_get_stride", (@convention(c) (Pointer) -> Int32).self)
        shmBufferBeginAccess = bind(wayland, "wl_shm_buffer_begin_access", (@convention(c) (Pointer) -> Void).self)
        shmBufferEndAccess = bind(wayland, "wl_shm_buffer_end_access", (@convention(c) (Pointer) -> Void).self)
        webViewBackendNew = bind(webkit, "webkit_web_view_backend_new", (@convention(c) (Pointer, Pointer?, Pointer?) -> Pointer?).self)
        webViewNew = bind(webkit, "webkit_web_view_new", (@convention(c) (Pointer) -> Pointer?).self)
        webViewLoadHTML = bind(webkit, "webkit_web_view_load_html",
                               (@convention(c) (Pointer, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> Void).self)
        webViewLoadURI = bind(webkit, "webkit_web_view_load_uri", (@convention(c) (Pointer, UnsafePointer<CChar>) -> Void).self)
        webViewGetTitle = bind(webkit, "webkit_web_view_get_title", (@convention(c) (Pointer) -> UnsafePointer<CChar>?).self)
        webViewGetURI = bind(webkit, "webkit_web_view_get_uri", (@convention(c) (Pointer) -> UnsafePointer<CChar>?).self)
        webViewIsLoading = bind(webkit, "webkit_web_view_is_loading", (@convention(c) (Pointer) -> Int32).self)
        webViewGetEstimatedLoadProgress = bind(webkit, "webkit_web_view_get_estimated_load_progress", (@convention(c) (Pointer) -> Double).self)
        webViewCanGoBack = bind(webkit, "webkit_web_view_can_go_back", (@convention(c) (Pointer) -> Int32).self)
        webViewCanGoForward = bind(webkit, "webkit_web_view_can_go_forward", (@convention(c) (Pointer) -> Int32).self)
        webViewGoBack = bind(webkit, "webkit_web_view_go_back", (@convention(c) (Pointer) -> Void).self)
        webViewGoForward = bind(webkit, "webkit_web_view_go_forward", (@convention(c) (Pointer) -> Void).self)
        webViewReload = bind(webkit, "webkit_web_view_reload", (@convention(c) (Pointer) -> Void).self)
        webViewStopLoading = bind(webkit, "webkit_web_view_stop_loading", (@convention(c) (Pointer) -> Void).self)
        webViewGetSettings = bind(webkit, "webkit_web_view_get_settings", (@convention(c) (Pointer) -> Pointer?).self)
        settingsSetUserAgent = bind(webkit, "webkit_settings_set_user_agent", (@convention(c) (Pointer, UnsafePointer<CChar>?) -> Void).self)
        webViewEvaluateJavaScript = bind(webkit, "webkit_web_view_evaluate_javascript",
                                         (@convention(c) (Pointer, UnsafePointer<CChar>, Int, UnsafePointer<CChar>?,
                                                          UnsafePointer<CChar>?, Pointer?, Pointer?, Pointer?) -> Void).self)
        webViewCallAsyncJavaScriptFunction = bind(webkit, "webkit_web_view_call_async_javascript_function",
                                                  (@convention(c) (Pointer, UnsafePointer<CChar>, Int, Pointer?, UnsafePointer<CChar>?,
                                                                   UnsafePointer<CChar>?, Pointer?, Pointer?, Pointer?) -> Void).self)
        webViewEvaluateJavaScriptFinish = bind(webkit, "webkit_web_view_evaluate_javascript_finish",
                                               (@convention(c) (Pointer, Pointer, UnsafeMutablePointer<Pointer?>) -> Pointer?).self)
        webViewCallAsyncJavaScriptFunctionFinish = bind(webkit, "webkit_web_view_call_async_javascript_function_finish",
                                                        (@convention(c) (Pointer, Pointer, UnsafeMutablePointer<Pointer?>) -> Pointer?).self)
        valueIsUndefined = bind(webkit, "jsc_value_is_undefined", (@convention(c) (Pointer) -> Int32).self)
        valueIsString = bind(webkit, "jsc_value_is_string", (@convention(c) (Pointer) -> Int32).self)
        valueIsNumber = bind(webkit, "jsc_value_is_number", (@convention(c) (Pointer) -> Int32).self)
        valueIsBoolean = bind(webkit, "jsc_value_is_boolean", (@convention(c) (Pointer) -> Int32).self)
        valueToString = bind(webkit, "jsc_value_to_string", (@convention(c) (Pointer) -> UnsafeMutablePointer<CChar>?).self)
        navigationPolicyDecisionGetNavigationAction = bind(webkit, "webkit_navigation_policy_decision_get_navigation_action",
                                                           (@convention(c) (Pointer) -> Pointer?).self)
        navigationActionGetRequest = bind(webkit, "webkit_navigation_action_get_request", (@convention(c) (Pointer) -> Pointer?).self)
        navigationActionGetNavigationType = bind(webkit, "webkit_navigation_action_get_navigation_type",
                                                 (@convention(c) (Pointer) -> Int32).self)
        uriRequestGetURI = bind(webkit, "webkit_uri_request_get_uri", (@convention(c) (Pointer) -> UnsafePointer<CChar>?).self)
        policyDecisionUse = bind(webkit, "webkit_policy_decision_use", (@convention(c) (Pointer) -> Void).self)
        policyDecisionIgnore = bind(webkit, "webkit_policy_decision_ignore", (@convention(c) (Pointer) -> Void).self)
        valueToJSON = bind(webkit, "jsc_value_to_json", (@convention(c) (Pointer, UInt32) -> UnsafeMutablePointer<CChar>?).self)
        webViewGetUserContentManager = bind(webkit, "webkit_web_view_get_user_content_manager", (@convention(c) (Pointer) -> Pointer?).self)
        registerScriptMessageHandler = bind(webkit, "webkit_user_content_manager_register_script_message_handler",
                                            (@convention(c) (Pointer, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> Int32).self)
        unregisterScriptMessageHandler = bind(webkit, "webkit_user_content_manager_unregister_script_message_handler",
                                              (@convention(c) (Pointer, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> Void).self)
        userScriptNew = bind(webkit, "webkit_user_script_new",
                             (@convention(c) (UnsafePointer<CChar>, Int32, Int32, UnsafeRawPointer?, UnsafeRawPointer?) -> Pointer?).self)
        userScriptUnref = bind(webkit, "webkit_user_script_unref", (@convention(c) (Pointer) -> Void).self)
        userContentManagerAddScript = bind(webkit, "webkit_user_content_manager_add_script", (@convention(c) (Pointer, Pointer) -> Void).self)
        userContentManagerRemoveAllScripts = bind(webkit, "webkit_user_content_manager_remove_all_scripts",
                                                  (@convention(c) (Pointer) -> Void).self)
        viewBackendDispatchPointerEvent = bind(wpe, "wpe_view_backend_dispatch_pointer_event",
                                               (@convention(c) (Pointer, UnsafeRawPointer) -> Void).self)
        viewBackendDispatchAxisEvent = bind(wpe, "wpe_view_backend_dispatch_axis_event", (@convention(c) (Pointer, UnsafeRawPointer) -> Void).self)
        viewBackendDispatchKeyboardEvent = bind(wpe, "wpe_view_backend_dispatch_keyboard_event",
                                                (@convention(c) (Pointer, UnsafeRawPointer) -> Void).self)
        mainContextIteration = bind(glib, "g_main_context_iteration", (@convention(c) (Pointer?, Int32) -> Int32).self)
        signalConnectData = bind(gobject, "g_signal_connect_data",
                                 (@convention(c) (Pointer, UnsafePointer<CChar>, UnsafeRawPointer, Pointer?, Pointer?, Int32) -> UInt).self)
        signalHandlerDisconnect = bind(gobject, "g_signal_handler_disconnect", (@convention(c) (Pointer, UInt) -> Void).self)
        objectUnref = bind(gobject, "g_object_unref", (@convention(c) (Pointer) -> Void).self)
        free = bind(glib, "g_free", (@convention(c) (Pointer?) -> Void).self)
        errorFree = bind(glib, "g_error_free", (@convention(c) (Pointer) -> Void).self)
        quarkToString = bind(glib, "g_quark_to_string", (@convention(c) (UInt32) -> UnsafePointer<CChar>?).self)
        paramSpecGetName = bind(gobject, "g_param_spec_get_name", (@convention(c) (Pointer) -> UnsafePointer<CChar>?).self)
        guard missing.isEmpty else {
            WPE.log("WPE WebKit is incomplete (no \(missing.joined(separator: ", "))); web views load nothing")
            return nil
        }
        guard loaderInit("libWPEBackend-fdo-1.0.so.1") != 0, initializeShm() != 0 else {
            WPE.log("WPEBackend-fdo did not initialize; web views load nothing")
            return nil
        }
    }

    private static let missingFunction: @convention(c) () -> Void = {}

    /// Runs what GLib's main context has ready: WPE's replies, signals and
    /// frames.
    func dispatch() {
        var budget = 1000
        while budget > 0, mainContextIteration(nil, 0) != 0 { budget -= 1 }
    }

    /// A GError's domain, code and message.
    func error(_ error: Pointer) -> (domain: String, code: Int, message: String) {
        let domain = quarkToString(error.load(as: UInt32.self)).map { String(cString: $0) } ?? ""
        let code = Int(error.load(fromByteOffset: 4, as: Int32.self))
        let message = error.load(fromByteOffset: 8, as: UnsafePointer<CChar>?.self).map { String(cString: $0) } ?? ""
        return (domain, code, message)
    }

    static func log(_ message: String) {
        let line = "perry: WebKit: \(message)\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }
}

/// One web view's page: a WebKitWebView drawing into frames of the view's
/// size, which `frame` shows.
final class WebPage {
    typealias Pointer = UnsafeMutableRawPointer

    let wpe: WPE
    private let exportable: Pointer
    private let backend: Pointer
    /// The exportable's client data: this page, until it goes.
    private let slot: UnsafeMutablePointer<Pointer?>
    let view: Pointer
    private var handlers: [UInt] = []
    private(set) var size: (width: UInt32, height: UInt32)
    private(set) var scale: Float

    /// A frame: BGRA pixels, premultiplied, top row first, with the width,
    /// height and bytes per row. They are good only during the call.
    var frame: ((UnsafeRawPointer, Int, Int, Int) -> Void)?
    /// WebKitLoadEvent: started, committed, finished.
    var loadChanged: ((Int32) -> Void)?
    /// A load failed: whether it had committed, then GError's domain, code
    /// and message.
    var loadFailed: ((Bool, String, Int, String) -> Void)?
    /// A property of the page's changed, by WebKit's name: title, uri,
    /// is-loading, estimated-load-progress.
    var propertyChanged: ((String) -> Void)?
    /// Whether a navigation to a URI goes ahead, with its
    /// WebKitNavigationType (UIWebViewNavigationType's values); nil lets
    /// every navigation go ahead.
    var decideNavigation: ((String, Int32) -> Bool)?

    /// The pages there are, which the main queue runs GLib's context for.
    nonisolated(unsafe) static var count = 0
    nonisolated(unsafe) private static var scheduled = false

    init?(width: UInt32, height: UInt32, scale: Float) {
        guard let wpe = WPE.shared else { return nil }
        let size = (max(width, 1), max(height, 1))
        let slot = UnsafeMutablePointer<Pointer?>.allocate(capacity: 1)
        slot.initialize(to: nil)
        // WebKit destroys the exportable when it is done with the backend.
        guard let exportable = wpe.exportableCreate(WebPage.client, slot, size.0, size.1),
              let backend = wpe.exportableGetViewBackend(exportable),
              let webBackend = wpe.webViewBackendNew(backend, unsafeBitCast(WebPage.onBackendDestroyed, to: Pointer.self), exportable),
              let view = wpe.webViewNew(webBackend) else {
            WPE.log("can't make a web view")
            return nil
        }
        (self.wpe, self.exportable, self.backend, self.view, self.slot) = (wpe, exportable, backend, view, slot)
        (self.size, self.scale) = (size, scale)
        slot.pointee = Unmanaged.passUnretained(self).toOpaque()
        wpe.viewBackendDispatchSetDeviceScaleFactor(backend, scale)
        wpe.viewBackendAddActivityState(backend, WPE.activityShown)
        let data = Unmanaged.passUnretained(self).toOpaque()
        handlers.append(wpe.signalConnectData(view, "load-changed", unsafeBitCast(WebPage.onLoadChanged, to: UnsafeRawPointer.self), data, nil, 0))
        handlers.append(wpe.signalConnectData(view, "load-failed", unsafeBitCast(WebPage.onLoadFailed, to: UnsafeRawPointer.self), data, nil, 0))
        handlers.append(wpe.signalConnectData(view, "decide-policy", unsafeBitCast(WebPage.onDecidePolicy, to: UnsafeRawPointer.self), data, nil, 0))
        for property in ["title", "uri", "is-loading", "estimated-load-progress"] {
            handlers.append(wpe.signalConnectData(view, "notify::\(property)", unsafeBitCast(WebPage.onNotify, to: UnsafeRawPointer.self),
                                                  data, nil, 0))
        }
        WebPage.count += 1
        WebPage.schedule()
    }

    // MARK: Script messages, user scripts and input

    /// A script message: the handler's name and the message's body as
    /// JSON (nil for undefined).
    var scriptMessage: ((String, String?) -> Void)?
    private var messageHandlers: [String: UInt] = [:]

    private var contentManager: Pointer? { wpe.webViewGetUserContentManager(view) }

    /// Makes window.webkit.messageHandlers[name] post to `scriptMessage`.
    func addMessageHandler(_ name: String) {
        guard messageHandlers[name] == nil, let manager = contentManager, wpe.registerScriptMessageHandler(manager, name, nil) != 0 else { return }
        let box = Unmanaged.passRetained(MessageSource(page: self, name: name)).toOpaque()
        messageHandlers[name] = wpe.signalConnectData(manager, "script-message-received::\(name)",
                                                      unsafeBitCast(WebPage.onScriptMessage, to: UnsafeRawPointer.self), box,
                                                      unsafeBitCast(WebPage.onMessageSourceDestroyed, to: Pointer.self), 0)
    }

    func removeMessageHandler(_ name: String) {
        guard let handler = messageHandlers.removeValue(forKey: name), let manager = contentManager else { return }
        wpe.signalHandlerDisconnect(manager, handler)
        wpe.unregisterScriptMessageHandler(manager, name, nil)
    }

    /// A script the page runs on each load, at its start or end.
    func addUserScript(_ source: String, atStart: Bool, mainFrameOnly: Bool) {
        guard let manager = contentManager,
              let script = wpe.userScriptNew(source, mainFrameOnly ? 1 : 0, atStart ? 0 : 1, nil, nil) else { return }
        wpe.userContentManagerAddScript(manager, script)
        wpe.userScriptUnref(script)
    }

    func removeAllUserScripts() {
        if let manager = contentManager { wpe.userContentManagerRemoveAllScripts(manager) }
    }

    private final class MessageSource {
        unowned let page: WebPage
        let name: String
        init(page: WebPage, name: String) { (self.page, self.name) = (page, name) }
    }

    /// script-message-received: the content manager, the message's
    /// JSCValue and the source.
    private static let onScriptMessage: @convention(c) (Pointer?, Pointer?, Pointer?) -> Void = { _, value, data in
        guard let data else { return }
        let source = Unmanaged<MessageSource>.fromOpaque(data).takeUnretainedValue()
        let wpe = source.page.wpe
        var json: String?
        if let value, wpe.valueIsUndefined(value) == 0, let text = wpe.valueToJSON(value, 0) {
            json = String(cString: text)
            wpe.free(text)
        }
        source.page.scriptMessage?(source.name, json)
    }

    private static let onMessageSourceDestroyed: @convention(c) (Pointer?, Pointer?) -> Void = { data, _ in
        if let data { Unmanaged<MessageSource>.fromOpaque(data).release() }
    }

    /// wpe_input_pointer_event: motion (1) or a button (2), in the view's
    /// points, top left first; buttons 1 left, 2 right, 3 middle.
    func pointer(motion: Bool, x: Int32, y: Int32, button: UInt32, pressed: Bool, modifiers: UInt32) {
        var event: (UInt32, UInt32, Int32, Int32, UInt32, UInt32, UInt32) =
            (motion ? 1 : 2, WebPage.milliseconds, x, y, button, pressed ? 1 : 0, modifiers)
        withUnsafeBytes(of: &event) { wpe.viewBackendDispatchPointerEvent(backend, $0.baseAddress!) }
    }

    /// wpe_input_axis_event: a wheel's motion (1) along the vertical (0) or
    /// horizontal (1) axis.
    func axis(x: Int32, y: Int32, horizontal: Bool, value: Int32, modifiers: UInt32) {
        var event: (UInt32, UInt32, Int32, Int32, UInt32, Int32, UInt32) =
            (1, WebPage.milliseconds, x, y, horizontal ? 1 : 0, value, modifiers)
        withUnsafeBytes(of: &event) { wpe.viewBackendDispatchAxisEvent(backend, $0.baseAddress!) }
    }

    /// wpe_input_keyboard_event: an XKB key symbol, pressed or released.
    func key(symbol: UInt32, hardwareCode: UInt32, pressed: Bool, modifiers: UInt32) {
        var event: (UInt32, UInt32, UInt32, Bool, UInt32) = (WebPage.milliseconds, symbol, hardwareCode, pressed, modifiers)
        withUnsafeBytes(of: &event) { wpe.viewBackendDispatchKeyboardEvent(backend, $0.baseAddress!) }
    }

    private static var milliseconds: UInt32 {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return UInt32(truncatingIfNeeded: Int(time.tv_sec) * 1000 + Int(time.tv_nsec) / 1_000_000)
    }

    deinit {
        if let manager = contentManager {
            for (name, handler) in messageHandlers {
                wpe.signalHandlerDisconnect(manager, handler)
                wpe.unregisterScriptMessageHandler(manager, name, nil)
            }
        }
        for handler in handlers { wpe.signalHandlerDisconnect(view, handler) }
        // The slot stays, empty, for any frame still on its way.
        slot.pointee = nil
        wpe.objectUnref(view)
        WebPage.count -= 1
    }

    /// Drops the callbacks into the page's view, which has gone, while
    /// something else keeps the page: its frames and events go nowhere.
    func detach() {
        (frame, loadChanged, loadFailed, propertyChanged, decideNavigation, scriptMessage) = (nil, nil, nil, nil, nil, nil)
    }

    func loadHTML(_ html: String, baseURI: String?) {
        if let baseURI { wpe.webViewLoadHTML(view, html, baseURI) } else { wpe.webViewLoadHTML(view, html, nil) }
    }

    func loadURI(_ uri: String) { wpe.webViewLoadURI(view, uri) }

    var title: String? { wpe.webViewGetTitle(view).map { String(cString: $0) } }
    var uri: String? { wpe.webViewGetURI(view).map { String(cString: $0) } }
    var isLoading: Bool { wpe.webViewIsLoading(view) != 0 }
    var progress: Double { wpe.webViewGetEstimatedLoadProgress(view) }
    var canGoBack: Bool { wpe.webViewCanGoBack(view) != 0 }
    var canGoForward: Bool { wpe.webViewCanGoForward(view) != 0 }
    func goBack() { wpe.webViewGoBack(view) }
    func goForward() { wpe.webViewGoForward(view) }
    func reload() { wpe.webViewReload(view) }
    func stopLoading() { wpe.webViewStopLoading(view) }

    func setUserAgent(_ agent: String?) {
        guard let settings = wpe.webViewGetSettings(view) else { return }
        if let agent { wpe.settingsSetUserAgent(settings, agent) } else { wpe.settingsSetUserAgent(settings, nil) }
    }

    /// The view's size in points and its scale, which the next frames have.
    func resize(width: UInt32, height: UInt32, scale: Float) {
        let size = (max(width, 1), max(height, 1))
        if scale != self.scale {
            self.scale = scale
            wpe.viewBackendDispatchSetDeviceScaleFactor(backend, scale)
        }
        guard size != self.size else { return }
        self.size = size
        wpe.viewBackendDispatchSetSize(backend, size.0, size.1)
    }

    /// Runs `script` in the page; `completion` hears its value as JSON (nil
    /// for undefined) or a GError's domain, code and message.
    func evaluate(_ script: String, completion: @escaping (Result<String?, EvaluationError>) -> Void) {
        let box = Unmanaged.passRetained(Evaluation(page: self, completion: completion)).toOpaque()
        wpe.webViewEvaluateJavaScript(view, script, -1, nil, nil, nil, unsafeBitCast(WebPage.onEvaluated, to: Pointer.self), box)
    }

    /// Calls `body` once the page has drawn what it has now: after two of
    /// its animation frames, and a frame's time for that frame to arrive.
    func afterRendering(_ body: @escaping () -> Void) {
        let box = Unmanaged.passRetained(Rendering(body)).toOpaque()
        wpe.webViewCallAsyncJavaScriptFunction(view, "await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))",
                                               -1, nil, nil, nil, nil, unsafeBitCast(WebPage.onRendered, to: Pointer.self), box)
    }

    private final class Rendering {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    /// The function's result is not needed; the frame drawn after it is.
    private static let onRendered: @convention(c) (Pointer?, Pointer?, Pointer?) -> Void = { source, result, data in
        guard let data else { return }
        let rendering = Unmanaged<Rendering>.fromOpaque(data).takeRetainedValue()
        if let wpe = WPE.shared, let source, let result {
            var error: Pointer?
            if let value = wpe.webViewCallAsyncJavaScriptFunctionFinish(source, result, &error) { wpe.objectUnref(value) }
            if let error { wpe.errorFree(error) }
        }
        Dispatch.after(nanoseconds: 50_000_000) { rendering.body() }
    }

    /// Runs `script` in the page and waits for it, running GLib's context
    /// meanwhile: a string, number or Boolean value as a string, as
    /// JavaScript's String() makes it; nil for other values and exceptions.
    func evaluateString(_ script: String) -> String? {
        var outcome: String??
        let box = Unmanaged.passRetained(StringEvaluation(page: self) { outcome = $0 }).toOpaque()
        wpe.webViewEvaluateJavaScript(view, script, -1, nil, nil, nil, unsafeBitCast(WebPage.onEvaluatedString, to: Pointer.self), box)
        while outcome == nil { _ = wpe.mainContextIteration(nil, 1) }
        return outcome ?? nil
    }

    private final class StringEvaluation {
        let page: WebPage
        let completion: (String?) -> Void
        init(page: WebPage, completion: @escaping (String?) -> Void) { (self.page, self.completion) = (page, completion) }
    }

    private static let onEvaluatedString: @convention(c) (Pointer?, Pointer?, Pointer?) -> Void = { source, result, data in
        guard let data else { return }
        let evaluation = Unmanaged<StringEvaluation>.fromOpaque(data).takeRetainedValue()
        let wpe = evaluation.page.wpe
        var error: Pointer?
        guard let source, let result, let value = wpe.webViewEvaluateJavaScriptFinish(source, result, &error) else {
            if let error { wpe.errorFree(error) }
            return evaluation.completion(nil)
        }
        defer { wpe.objectUnref(value) }
        guard wpe.valueIsString(value) != 0 || wpe.valueIsNumber(value) != 0 || wpe.valueIsBoolean(value) != 0 else {
            return evaluation.completion(nil)
        }
        let string = wpe.valueToString(value)
        defer { wpe.free(string) }
        evaluation.completion(string.map { String(cString: $0) } ?? "")
    }

    /// decide-policy: navigations ask `decideNavigation`; the rest, and
    /// navigations without it, take WebKit's default.
    private static let onDecidePolicy: @convention(c) (Pointer?, Pointer?, Int32, Pointer?) -> Int32 = { _, decision, type, data in
        guard let data, let decision, type == 0 else { return 0 }    // WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION
        let page = Unmanaged<WebPage>.fromOpaque(data).takeUnretainedValue()
        let wpe = page.wpe
        guard let decide = page.decideNavigation, let action = wpe.navigationPolicyDecisionGetNavigationAction(decision) else { return 0 }
        let uri = wpe.navigationActionGetRequest(action).flatMap(wpe.uriRequestGetURI).map { String(cString: $0) } ?? ""
        if decide(uri, wpe.navigationActionGetNavigationType(action)) {
            wpe.policyDecisionUse(decision)
        } else {
            wpe.policyDecisionIgnore(decision)
        }
        return 1
    }

    /// Runs `body` as an async function's body, awaiting what it returns;
    /// `completion` hears its value as `evaluate`'s does.
    func callAsync(_ body: String, completion: @escaping (Result<String?, EvaluationError>) -> Void) {
        let box = Unmanaged.passRetained(Evaluation(page: self, completion: completion)).toOpaque()
        wpe.webViewCallAsyncJavaScriptFunction(view, body, -1, nil, nil, nil, nil, unsafeBitCast(WebPage.onCalled, to: Pointer.self), box)
    }

    struct EvaluationError: Error {
        let domain: String, code: Int, message: String
    }

    private final class Evaluation {
        let page: WebPage
        let completion: (Result<String?, EvaluationError>) -> Void
        init(page: WebPage, completion: @escaping (Result<String?, EvaluationError>) -> Void) {
            (self.page, self.completion) = (page, completion)
        }
    }

    // MARK: Callbacks from C

    /// wpe_view_backend_exportable_fdo_client: frames in shared memory only.
    nonisolated(unsafe) private static let client: UnsafeRawPointer = {
        let client = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 5)
        client.initialize(repeating: nil, count: 5)
        client[2] = unsafeBitCast(WebPage.onShmBuffer, to: UnsafeRawPointer.self)
        return UnsafeRawPointer(client)
    }()

    /// A frame, to the page in the exportable's slot.
    private static let onShmBuffer: @convention(c) (Pointer?, Pointer?) -> Void = { data, buffer in
        guard let buffer, let page = data?.assumingMemoryBound(to: Pointer?.self).pointee else { return }
        Unmanaged<WebPage>.fromOpaque(page).takeUnretainedValue().receive(buffer)
    }

    private static let onBackendDestroyed: @convention(c) (Pointer?) -> Void = { exportable in
        if let exportable { WPE.shared?.exportableDestroy(exportable) }
    }

    private func receive(_ buffer: Pointer) {
        defer {
            wpe.exportableReleaseShmBuffer(exportable, buffer)
            wpe.exportableFrameComplete(exportable)
        }
        guard let shm = wpe.shmExportedBufferGetShmBuffer(buffer) else { return }
        wpe.shmBufferBeginAccess(shm)
        defer { wpe.shmBufferEndAccess(shm) }
        let width = Int(wpe.shmBufferGetWidth(shm)), height = Int(wpe.shmBufferGetHeight(shm))
        let stride = Int(wpe.shmBufferGetStride(shm))
        guard width > 0, height > 0, let data = wpe.shmBufferGetData(shm) else { return }
        frame?(data, width, height, stride)
    }

    private static let onLoadChanged: @convention(c) (Pointer?, Int32, Pointer?) -> Void = { _, event, data in
        guard let data else { return }
        Unmanaged<WebPage>.fromOpaque(data).takeUnretainedValue().loadChanged?(event)
    }

    /// load-failed: the view, the WebKitLoadEvent it failed at, the URI and
    /// the GError; true, as handled.
    private static let onLoadFailed: @convention(c) (Pointer?, Int32, UnsafePointer<CChar>?, Pointer?, Pointer?) -> Int32 = {
        _, event, _, error, data in
        guard let data else { return 1 }
        let page = Unmanaged<WebPage>.fromOpaque(data).takeUnretainedValue()
        let described = error.map(page.wpe.error) ?? (domain: "", code: 0, message: "")
        page.loadFailed?(event >= WPE.loadCommitted, described.domain, described.code, described.message)
        return 1
    }

    private static let onNotify: @convention(c) (Pointer?, Pointer?, Pointer?) -> Void = { _, spec, data in
        guard let data, let spec else { return }
        let page = Unmanaged<WebPage>.fromOpaque(data).takeUnretainedValue()
        guard let name = page.wpe.paramSpecGetName(spec) else { return }
        page.propertyChanged?(String(cString: name))
    }

    private static let onEvaluated: @convention(c) (Pointer?, Pointer?, Pointer?) -> Void = { source, result, data in
        finish(source, result, data) { WPE.shared!.webViewEvaluateJavaScriptFinish($0, $1, $2) }
    }

    private static let onCalled: @convention(c) (Pointer?, Pointer?, Pointer?) -> Void = { source, result, data in
        finish(source, result, data) { WPE.shared!.webViewCallAsyncJavaScriptFunctionFinish($0, $1, $2) }
    }

    /// A script's value as JSON (nil for undefined), or its error.
    private static func finish(_ source: Pointer?, _ result: Pointer?, _ data: Pointer?,
                               _ finish: (Pointer, Pointer, UnsafeMutablePointer<Pointer?>) -> Pointer?) {
        guard let data else { return }
        let evaluation = Unmanaged<Evaluation>.fromOpaque(data).takeRetainedValue()
        let wpe = evaluation.page.wpe
        var error: Pointer?
        guard let source, let result, let value = finish(source, result, &error) else {
            let described = error.map(wpe.error) ?? (domain: "", code: 0, message: "")
            if let error { wpe.errorFree(error) }
            evaluation.completion(.failure(EvaluationError(domain: described.domain, code: described.code, message: described.message)))
            return
        }
        defer { wpe.objectUnref(value) }
        if wpe.valueIsUndefined(value) != 0 {
            evaluation.completion(.success(nil))
            return
        }
        let json = wpe.valueToJSON(value, 0)
        defer { wpe.free(json) }
        evaluation.completion(.success(json.map { String(cString: $0) }))
    }

    /// Runs GLib's context on the main queue, a frame's time apart, while
    /// there are pages.
    private static func schedule() {
        guard !scheduled else { return }
        scheduled = true
        Dispatch.after(nanoseconds: 8_000_000) {
            WebPage.scheduled = false
            WPE.shared?.dispatch()
            WebPage.tick?()
            if WebPage.count > 0 { WebPage.schedule() }
        }
    }

    /// Run after each pass of GLib's context: web views follow their sizes.
    nonisolated(unsafe) static var tick: (() -> Void)?
}
