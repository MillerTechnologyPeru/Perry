import Glibc
import PerryDesktopNotifications
import PerryObjCInterop

// Delivered notifications shown on the desktop, through its notification
// server, as Cacao's menu bar runs one: the title, with the subtitle and
// body below it, and the buttons of the notification's category. Clicking
// the notification, or one of its buttons, tells the delegate with
// -userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:
// on the main queue, as on a Mac. Removing delivered notifications takes
// them off the desktop too.
//
// PERRY_USER_NOTIFICATIONS_DESKTOP=0 shows nothing.

enum Desktop {
    static var enabled: Bool { getenv("PERRY_USER_NOTIFICATIONS_DESKTOP").map { String(cString: $0) != "0" } ?? true }

    /// UNNotificationDefaultActionIdentifier.
    static let defaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"

    nonisolated(unsafe) private static var client: DesktopNotifications?

    /// The app's name, as its bundle gives it.
    static let appName: String = {
        let bundle = UNBundle.main()
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = bundle.infoObject(forKey: key) {
                return String(objCArgument: name.objcObject)
            }
        }
        return ""
    }()

    private static var started: DesktopNotifications? {
        guard enabled else { return nil }
        if let client { return client }
        client = DesktopNotifications { identifier, action in
            Dispatch.onMain { respond(identifier, action) }
        }
        return client
    }

    /// Shows a delivered notification.
    static func show(_ notification: NSObject) {
        guard let client = started,
              let request = UNNotification.states[notification.objcObject]?.request,
              let state = request.unsafeCast(to: UNNotificationRequest.self).request,
              let content = Contents.state(state.content)
        else { return }
        let lines = [content.subtitle, content.body].compactMap { $0 }.filter { !$0.isEmpty }
        client.post(DesktopNotifications.Notification(
            identifier: state.identifier,
            appName: appName,
            summary: content.title ?? appName,
            body: lines.joined(separator: "\n"),
            actions: actions(forCategory: content.categoryIdentifier)
        ))
    }

    /// Takes delivered notifications off the desktop.
    static func remove(_ identifiers: [String]) {
        guard let client else { return }
        for identifier in identifiers {
            client.close(identifier: identifier)
        }
    }

    /// The buttons of the category with an identifier, as the app set them.
    private static func actions(forCategory identifier: String) -> [DesktopNotifications.Notification.Action] {
        guard !identifier.isEmpty else { return [] }
        let categories = Center.state.lock.withLock { Center.state.categories }
        for category in categories.unsafeCast(to: NSSet.self).allObjects().elements {
            guard let state = UNNotificationCategory.states[category.objcObject], state.identifier == identifier else { continue }
            return state.actions.arrayElements.compactMap { action in
                UNNotificationAction.states[action.objcObject].map { .init(key: $0.identifier, label: $0.title) }
            }
        }
        return []
    }

    /// The user clicked a notification or one of its buttons: the
    /// delegate hears it, as on a Mac.
    private static func respond(_ identifier: String, _ action: String) {
        let delivered = Center.state.lock.withLock { Center.state.delivered.first { $0.identifier == identifier }?.notification }
        guard let notification = delivered,
              let delegate = Center.state.lock.withLock({ Center.state.delegate }),
              let center = Center.shared
        else { return }
        let selector = ObjCSelector("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:")
        guard NSObject(delegate).responds(toSelector: selector) else { return }
        let response = UNNotificationResponse.objCClass.autoreleasedInstance()
        UNNotificationResponse.states.set(response.objcObject, ResponseState(
            notification: notification,
            actionIdentifier: action == DesktopNotifications.defaultAction ? defaultActionIdentifier : action,
            userText: nil
        ))
        typealias Object = UnsafeMutableRawPointer?
        unsafeBitCast(ObjCRuntime.msgSend, to: (@convention(c) (Object, UnsafeRawPointer, Object, Object, Object) -> Void).self)(
            delegate, selector.pointer, center.objcObject, response.objcObject, IgnoredBlock.block)
    }
}

@ObjCWrapper("NSBundle")
class UNBundle: NSObject {
    @ObjCClassMethod("mainBundle") static func main() -> UNBundle
    @ObjCMethod("objectForInfoDictionaryKey:") func infoObject(forKey key: String) -> NSObject?
}
