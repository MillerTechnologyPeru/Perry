import PerryObjCInterop

// UNUserNotificationCenter. Linux has no notification service, so the
// center does what one would for a user who allows notifications: requests
// for authorization are granted, pending requests fire when their triggers
// say, and each delivered notification goes to the delegate's
// -userNotificationCenter:willPresentNotification:withCompletionHandler:
// on the main queue, as for an app in the foreground, and is kept with the
// delivered notifications. Completion handlers run on a background queue,
// as on Darwin.

final class CenterState: @unchecked Sendable {
    let lock = Lock()
    /// UNAuthorizationStatus: not determined 0, authorized 2.
    var status = 0
    var pending: [(identifier: String, request: NSObject, generation: Int)] = []
    var delivered: [(identifier: String, notification: NSObject)] = []
    var categories: NSObject = NSMutableSet.empty()
    var badge = 0
    var generation = 0
    /// Unretained, as Darwin's is weak.
    var delegate: UnsafeMutableRawPointer?
}

enum Center {
    static let state = CenterState()
    nonisolated(unsafe) static var shared: NSObject?

    typealias Object = UnsafeMutableRawPointer?

    /// Calls a completion block with one object argument.
    static func call(_ block: ObjCBlock?, _ object: NSObject?) {
        guard let block else { return }
        Dispatch.inBackground {
            block.function(as: (@convention(c) (Object, Object) -> Void).self)(block.object, object?.objcObject)
        }
    }

    /// Schedules a pending request's next firing.
    static func schedule(_ identifier: String, _ request: NSObject, generation: Int) {
        guard let trigger = request.unsafeCast(to: UNNotificationRequest.self).request?.trigger,
              let seconds = Triggers.states[trigger.objcObject]?.secondsToNext else { return }
        Dispatch.after(seconds) { fire(identifier, generation: generation) }
    }

    /// Delivers the request, unless it was removed or replaced since.
    static func fire(_ identifier: String, generation: Int) {
        let found = state.lock.withLock { () -> NSObject? in
            guard let index = state.pending.firstIndex(where: { $0.identifier == identifier && $0.generation == generation }) else { return nil }
            let request = state.pending[index].request
            let repeats = request.unsafeCast(to: UNNotificationRequest.self).request?.trigger
                .flatMap { Triggers.states[$0.objcObject]?.repeats } ?? false
            if !repeats { state.pending.remove(at: index) }
            return request
        }
        guard let request = found else { return }
        if let trigger = request.unsafeCast(to: UNNotificationRequest.self).request?.trigger,
           Triggers.states[trigger.objcObject]?.repeats == true {
            schedule(identifier, request, generation: generation)
        }
        Dispatch.onMain {
            let notification = UNNotification.object(request: request)
            state.lock.withLock {
                state.delivered.removeAll { $0.identifier == identifier }
                state.delivered.append((identifier, notification))
            }
            present(notification)
        }
    }

    /// The delegate's willPresent, with a handler that takes the
    /// presentation options and does nothing more.
    static func present(_ notification: NSObject) {
        guard let delegate = state.lock.withLock({ state.delegate }), let center = shared else { return }
        let selector = ObjCSelector("userNotificationCenter:willPresentNotification:withCompletionHandler:")
        guard NSObject(delegate).responds(toSelector: selector) else { return }
        unsafeBitCast(ObjCRuntime.msgSend, to: (@convention(c) (Object, UnsafeRawPointer, Object, Object, Object) -> Void).self)(
            delegate, selector.pointer, center.objcObject, notification.objcObject, IgnoredBlock.block)
    }
}

/// A global block taking one integer and ignoring it: the presentation
/// options handler given to delegates.
enum IgnoredBlock {
    nonisolated(unsafe) static let block: UnsafeMutableRawPointer = {
        let invoke: @convention(c) (UnsafeMutableRawPointer?, UInt) -> Void = { _, _ in }
        let descriptor = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 8)
        descriptor.storeBytes(of: 0, as: UInt.self)
        descriptor.storeBytes(of: UInt(3 * MemoryLayout<UnsafeRawPointer>.size + 8), toByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UInt.self)
        let block = UnsafeMutableRawPointer.allocate(byteCount: 3 * MemoryLayout<UnsafeRawPointer>.size + 8, alignment: 8)
        block.storeBytes(of: Dispatch.globalBlockClass, as: UnsafeMutableRawPointer?.self)
        block.storeBytes(of: Int32(1 << 28), toByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: Int32.self)   // BLOCK_IS_GLOBAL
        block.storeBytes(of: Int32(0), toByteOffset: MemoryLayout<UnsafeRawPointer>.size + 4, as: Int32.self)
        block.storeBytes(of: unsafeBitCast(invoke, to: UnsafeRawPointer.self), toByteOffset: MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(descriptor), toByteOffset: 2 * MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer.self)
        return block
    }()
}

/// UNUserNotificationCenter.
@ObjCClass("UNUserNotificationCenter")
open class UNUserNotificationCenter: NSObject {
    typealias Object = UnsafeMutableRawPointer?

    @ObjCClassMethod("currentNotificationCenter")
    static func current() -> NSObject {
        if let shared = Center.shared { return shared }
        let center = objCClass.object.newInstance()
        Center.shared = center
        return center
    }

    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { Center.state.lock.withLock { Center.state.delegate } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: UnsafeMutableRawPointer?) { Center.state.lock.withLock { Center.state.delegate = delegate } }
    @ObjCMethod("supportsContentExtensions") func supportsContentExtensions() -> Bool { false }

    /// Granted: void (^)(BOOL granted, NSError *error).
    @ObjCMethod("requestAuthorizationWithOptions:completionHandler:")
    func requestAuthorization(options: UInt, completionHandler: ObjCBlock?) {
        Center.state.lock.withLock { Center.state.status = 2 }
        guard let completionHandler else { return }
        Dispatch.inBackground {
            completionHandler.function(as: (@convention(c) (Object, Bool, Object) -> Void).self)(completionHandler.object, true, nil)
        }
    }

    @ObjCMethod("getNotificationSettingsWithCompletionHandler:")
    func getNotificationSettings(completionHandler: ObjCBlock?) {
        Center.call(completionHandler, UNNotificationSettings.object(status: Center.state.lock.withLock { Center.state.status }))
    }

    /// Replaces a pending request with the same identifier.
    @ObjCMethod("addNotificationRequest:withCompletionHandler:")
    func add(_ request: NSObject, completionHandler: ObjCBlock?) {
        let identifier = request.unsafeCast(to: UNNotificationRequest.self).identifier()
        let generation = Center.state.lock.withLock { () -> Int in
            Center.state.generation += 1
            Center.state.pending.removeAll { $0.identifier == identifier }
            Center.state.pending.append((identifier, request, Center.state.generation))
            return Center.state.generation
        }
        if request.unsafeCast(to: UNNotificationRequest.self).request?.trigger == nil {
            Dispatch.inBackground { Center.fire(identifier, generation: generation) }
        } else {
            Center.schedule(identifier, request, generation: generation)
        }
        Center.call(completionHandler, nil)
    }

    @ObjCMethod("getPendingNotificationRequestsWithCompletionHandler:")
    func getPendingRequests(completionHandler: ObjCBlock?) {
        Center.call(completionHandler, NSMutableArray.of(Center.state.lock.withLock { Center.state.pending.map(\.request) }))
    }

    @ObjCMethod("removePendingNotificationRequestsWithIdentifiers:")
    func removePendingRequests(identifiers: NSObject) {
        let removed = Set(identifiers.arrayElements.map { String(objCArgument: $0.objcObject) })
        Center.state.lock.withLock { Center.state.pending.removeAll { removed.contains($0.identifier) } }
    }

    @ObjCMethod("removeAllPendingNotificationRequests")
    func removeAllPendingRequests() { Center.state.lock.withLock { Center.state.pending.removeAll() } }

    @ObjCMethod("getDeliveredNotificationsWithCompletionHandler:")
    func getDeliveredNotifications(completionHandler: ObjCBlock?) {
        Center.call(completionHandler, NSMutableArray.of(Center.state.lock.withLock { Center.state.delivered.map(\.notification) }))
    }

    @ObjCMethod("removeDeliveredNotificationsWithIdentifiers:")
    func removeDeliveredNotifications(identifiers: NSObject) {
        let removed = Set(identifiers.arrayElements.map { String(objCArgument: $0.objcObject) })
        Center.state.lock.withLock { Center.state.delivered.removeAll { removed.contains($0.identifier) } }
    }

    @ObjCMethod("removeAllDeliveredNotifications")
    func removeAllDeliveredNotifications() { Center.state.lock.withLock { Center.state.delivered.removeAll() } }

    @ObjCMethod("setNotificationCategories:")
    func setNotificationCategories(_ categories: NSObject) { Center.state.lock.withLock { Center.state.categories = categories.copyObject() } }

    @ObjCMethod("getNotificationCategoriesWithCompletionHandler:")
    func getNotificationCategories(completionHandler: ObjCBlock?) {
        Center.call(completionHandler, Center.state.lock.withLock { Center.state.categories })
    }

    @ObjCMethod("setBadgeCount:withCompletionHandler:")
    func setBadgeCount(_ count: Int, completionHandler: ObjCBlock?) {
        Center.state.lock.withLock { Center.state.badge = count }
        Center.call(completionHandler, nil)
    }
}
