import CPerryGeometry
import Glibc
import PerryObjCInterop

// What a web view's configuration holds that its page uses: the script
// message handlers and user scripts, which window.webkit.messageHandlers and
// the page's scripts are, and the URL scheme handlers, which serve a
// scheme's loads: a hybrid app (Capacitor's, Cordova's) loads its pages
// from "capacitor://localhost", answered by a handler of its own.

/// A message from a page's script: its handler's name, body and web view.
@ObjCClass("WKScriptMessage")
open class WKScriptMessage: NSObject {
    var body: NSObject?
    var name = ""
    /// Not retained.
    var webViewObject: UnsafeMutableRawPointer?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("body") func messageBody() -> NSObject? { body }
    @ObjCMethod("name") func messageName() -> String { name }
    @ObjCMethod("webView") func messageWebView() -> NSObject? { webViewObject.map { NSObject($0) } }
    @ObjCMethod("frameInfo") func frameInfo() -> NSObject? { nil }
    @ObjCMethod("world") func world() -> NSObject? { nil }
}

extension WKWebViewConfiguration {
    /// The user content controller, made when first asked for.
    func contentController() -> WKUserContentController {
        if let controller = userContentController?.as(WKUserContentController.self) { return controller }
        let controller = WKUserContentController()
        userContentController = controller
        return controller
    }
}

extension NSObject {
    @ObjCMethod("source") func sendScriptSource() -> String?
    @ObjCMethod("injectionTime") func sendInjectionTime() -> Int
    @ObjCMethod("isForMainFrameOnly") func sendIsForMainFrameOnly() -> Bool
    @ObjCMethod("userContentController:didReceiveScriptMessage:")
    func sendDidReceiveScriptMessage(_ controller: NSObject, _ scriptMessage: NSObject)
    @ObjCMethod("webView:startURLSchemeTask:") func sendStartURLSchemeTask(_ view: NSObject, _ task: NSObject)
    @ObjCMethod("MIMEType") func sendMIMEType() -> String?
    @ObjCMethod("statusCode") func sendStatusCode() -> Int
    @ObjCMethod("allHeaderFields") func sendAllHeaderFields() -> NSObject?
    @ObjCMethod("objectForKey:") func sendObjectForKey(_ key: String) -> NSObject?
}

extension WKWebView {
    /// Gives a new page what its configuration holds: the message handlers
    /// and scripts, and the schemes' handlers.
    func attachContent(_ page: WebPage, _ web: WebViewState) {
        guard let configuration = web.configuration?.as(WKWebViewConfiguration.self) else { return }
        let object = objcObject
        let controller = configuration.contentController()
        page.scriptMessage = { name, json in
            let view = WKWebView(objcObject: object, ownership: .retain)
            guard let configuration = view.web.configuration?.as(WKWebViewConfiguration.self),
                  let handler = configuration.contentController().handlers[name] else { return }
            let message = WKScriptMessage()
            message.name = name
            message.body = json.flatMap(WebViews.object(json:))
            message.webViewObject = object
            handler.sendDidReceiveScriptMessage(configuration.contentController(), message)
        }
        WebPage.trace("content: handlers \(controller.handlers.keys.sorted()), \(controller.userScripts.count) scripts, schemes \(configuration.schemeHandlers.keys.sorted())")
        for script in controller.userScripts {
            WebPage.trace("script at \(script.sendInjectionTime() == 0 ? "start" : "end"), main frame \(script.sendIsForMainFrameOnly()), \((script.sendScriptSource() ?? "").utf8.count) bytes: \((script.sendScriptSource() ?? "").prefix(90))")
        }
        for name in controller.handlers.keys { page.addMessageHandler(name) }
        for script in controller.userScripts {
            guard let source = script.sendScriptSource() else { continue }
            page.addUserScript(source, atStart: script.sendInjectionTime() == 0, mainFrameOnly: script.sendIsForMainFrameOnly())
        }
        // PERRY_UIKIT_WEB_SCRIPT, a file: a script every page runs at its end, to look into it with
        // (with PERRY_UIKIT_WEB_CONSOLE, what it logs is printed).
        if let path = getenv("PERRY_UIKIT_WEB_SCRIPT"), let file = fopen(path, "r") {
            var text = [UInt8]()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = fread(&buffer, 1, buffer.count, file)
                if count <= 0 { break }
                text.append(contentsOf: buffer[0..<count])
            }
            fclose(file)
            page.addUserScript(String(decoding: text, as: UTF8.self), atStart: false, mainFrameOnly: true)
        }
        for (scheme, handler) in configuration.schemeHandlers { URLSchemes.register(scheme, handler: handler, view: object) }
    }
}

// MARK: - Scheme tasks

final class SchemeTaskState: ObjectState {
    let lock = Lock()
    required init() {}
    /// The WebKitURISchemeRequest, referenced until the task is answered.
    var request: UnsafeMutableRawPointer?
    var url = ""
    var method = "GET"
    var status = 200
    var contentType: String?
    var data: [UInt8] = []
    var finished = false
}

/// A request for a scheme's URL, which the scheme's handler answers with a
/// response, data and then its finish.
@ObjCClass("WKURLSchemeTaskImpl")
open class WKURLSchemeTaskImpl: NSObject {
    static let states = StateTable<SchemeTaskState>()
    var task: SchemeTaskState { WKURLSchemeTaskImpl.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        WKURLSchemeTaskImpl.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: WKURLSchemeTaskImpl.objCClass.pointer)
    }

    @ObjCMethod("request")
    func request() -> NSObject? {
        guard let url = NSURLObject.make(string: task.url) else { return nil }
        return NSURLRequestFactory.make(url: url)
    }

    /// The status and type of a response: an HTTP one's, else its MIME type.
    @ObjCMethod("didReceiveResponse:")
    func didReceive(response: NSObject) {
        let state = task
        var status = 200, type = response.sendMIMEType()
        if response.responds(to: "statusCode") { status = response.sendStatusCode() }
        if response.responds(to: "allHeaderFields"), let headers = response.sendAllHeaderFields() {
            if let header = headers.sendObjectForKey("Content-Type")?.stringValue ?? headers.sendObjectForKey("content-type")?.stringValue {
                type = header
            }
        }
        state.lock.withLock { (state.status, state.contentType) = (status, type) }
    }

    @ObjCMethod("didReceiveData:")
    func didReceive(data: NSObject) {
        guard let bytes = data.sendBytes() else { return }
        let count = Int(data.sendLength())
        task.lock.withLock { task.data.append(contentsOf: UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: count)) }
    }

    @ObjCMethod("didFinish") func didFinish() { URLSchemes.answer(objcObject, failing: false) }
    @ObjCMethod("didFailWithError:") func didFail(error: NSObject?) { URLSchemes.answer(objcObject, failing: true) }
    @ObjCMethod("didPerformRedirection:newRequest:") func didPerformRedirection(response: NSObject?, newRequest: NSObject?) {}
}

// MARK: - Schemes

enum URLSchemes {
    /// The handler of each scheme and the web view it was given for, which
    /// is not retained.
    nonisolated(unsafe) static var handlers: [String: (handler: NSObject, view: UnsafeMutableRawPointer)] = [:]
    nonisolated(unsafe) private static var registered: Set<String> = []

    /// Has WPE's context hand `scheme`'s requests here, once; the handler is
    /// the latest to be given.
    static func register(_ scheme: String, handler: NSObject, view: UnsafeMutableRawPointer) {
        handlers[scheme] = (handler, view)
        guard let wpe = WPE.shared, !registered.contains(scheme), let context = wpe.contextGetDefault() else { return }
        registered.insert(scheme)
        if let manager = wpe.contextGetSecurityManager(context) {
            wpe.securityManagerRegisterSecure(manager, scheme)
            wpe.securityManagerRegisterCORSEnabled(manager, scheme)
        }
        wpe.contextRegisterURIScheme(context, scheme, unsafeBitCast(onRequest, to: UnsafeRawPointer.self), nil, nil)
    }

    /// WebKitURISchemeRequestCallback: a request, which is the task's until
    /// it is answered.
    private static let onRequest: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { request, _ in
        guard let request, let wpe = WPE.shared, let uri = wpe.uriSchemeRequestGetURI(request).map({ String(cString: $0) }) else { return }
        let scheme = String(uri.prefix { $0 != ":" })
        guard let (handler, view) = handlers[scheme], handler.responds(to: "webView:startURLSchemeTask:") else {
            fail(request, "No handler for \(scheme)")
            return
        }
        let task = NSObject(WKURLSchemeTaskImpl.objCClass.pointer).newInstance()
        let state = WKURLSchemeTaskImpl.states[task.objcObject]
        state.request = wpe.objectRef(request)
        state.url = uri
        state.method = wpe.uriSchemeRequestGetHTTPMethod(request).map { String(cString: $0) } ?? "GET"
        // The task is kept until it is answered.
        _ = ObjCRuntime.retain(task.objcObject)
        handler.sendStartURLSchemeTask(NSObject(view), task)
    }

    private static func fail(_ request: UnsafeMutableRawPointer, _ message: String) {
        guard let wpe = WPE.shared, let error = wpe.errorNewLiteral(wpe.quarkFromString("perry-uri-scheme"), 1, message) else { return }
        wpe.uriSchemeRequestFinishError(request, error)
        wpe.errorFree(error)
    }

    /// The task answered, from any thread: the response is given to WebKit
    /// on the main queue, where GLib's context runs.
    static func answer(_ task: UnsafeMutableRawPointer, failing: Bool) {
        guard let state = WKURLSchemeTaskImpl.states.existing(task) else { return }
        let first = state.lock.withLock { () -> Bool in
            defer { state.finished = true }
            return !state.finished
        }
        guard first else { return }
        let box = Unmanaged.passRetained(Answer(task: task, failing: failing)).toOpaque()
        _ = WPE.shared?.idleAdd(unsafeBitCast(onIdle, to: UnsafeRawPointer.self), box)
    }

    private final class Answer {
        let task: UnsafeMutableRawPointer
        let failing: Bool
        init(task: UnsafeMutableRawPointer, failing: Bool) { (self.task, self.failing) = (task, failing) }
    }

    /// GSourceFunc: false, to run once.
    private static let onIdle: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = { data in
        guard let data else { return 0 }
        let answer = Unmanaged<Answer>.fromOpaque(data).takeRetainedValue()
        defer { ObjCRuntime.release(answer.task) }
        guard let wpe = WPE.shared, let state = WKURLSchemeTaskImpl.states.existing(answer.task),
              let request = state.request else { return 0 }
        state.request = nil
        defer { wpe.objectUnref(request) }
        if answer.failing {
            fail(request, "The handler failed")
            return 0
        }
        let (status, type, body) = state.lock.withLock { (state.status, state.contentType, state.data) }
        guard let bytes = body.withUnsafeBytes({ wpe.bytesNew($0.baseAddress, body.count) }) else {
            fail(request, "Out of memory")
            return 0
        }
        defer { wpe.bytesUnref(bytes) }
        guard let stream = wpe.memoryInputStreamNewFromBytes(bytes), let response = wpe.uriSchemeResponseNew(stream, Int64(body.count)) else {
            fail(request, "No response")
            return 0
        }
        wpe.uriSchemeResponseSetStatus(response, UInt32(status), nil)
        if let type { type.withCString { wpe.uriSchemeResponseSetContentType(response, $0) } }
        wpe.uriSchemeRequestFinishWithResponse(request, response)
        wpe.objectUnref(response)
        wpe.objectUnref(stream)
        return 0
    }
}
