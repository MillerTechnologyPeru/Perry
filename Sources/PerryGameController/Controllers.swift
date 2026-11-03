import PerryObjCInterop

// GCController with no controllers connected: the list is empty, discovery
// finds none, and the connect and disconnect notifications never come.

@ObjCClass("GCController")
open class GCController: NSObject {
    @ObjCClassMethod("controllers")
    static func controllers() -> NSObject { NSObject(NSMutableArray.objCClass.pointer).newInstance() }

    @ObjCClassMethod("startWirelessControllerDiscoveryWithCompletionHandler:")
    static func startWirelessControllerDiscovery(completionHandler: ObjCBlock?) {
        // Discovery ends at once, having found nothing.
        guard let completionHandler else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
        completionHandler.function(as: Invoke.self)(completionHandler.object)
    }

    @ObjCClassMethod("stopWirelessControllerDiscovery") static func stopWirelessControllerDiscovery() {}
    @ObjCClassMethod("current") static func current() -> NSObject? { nil }
    @ObjCClassMethod("shouldMonitorBackgroundEvents") static func shouldMonitorBackgroundEvents() -> Bool { false }
    @ObjCClassMethod("setShouldMonitorBackgroundEvents:") static func setShouldMonitorBackgroundEvents(_ monitor: Bool) {}
}

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSObject {}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

/// The notifications, which are never posted.
@ObjCConstants
enum ControllerConstants {
    static let GCControllerDidConnectNotification = "GCControllerDidConnectNotification"
    static let GCControllerDidDisconnectNotification = "GCControllerDidDisconnectNotification"
    static let GCControllerDidBecomeCurrentNotification = "GCControllerDidBecomeCurrentNotification"
    static let GCControllerDidStopBeingCurrentNotification = "GCControllerDidStopBeingCurrentNotification"
}
