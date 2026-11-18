import Glibc
import PerryObjCInterop

// MXMetricManager, and the payload classes an app names. No payload is
// ever delivered.

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

/// An empty NSArray.
private func emptyArray() -> NSObject { NSObject(ObjCClass(named: "NSArray").pointer).newInstance() }

@ObjCClass("MXMetricManager")
open class MXMetricManager: NSObject {
    nonisolated(unsafe) static var shared = MXMetricManager()
    var subscribers: [NSObject] = []

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("sharedManager") static func sharedManager() -> MXMetricManager { shared }
    @ObjCClassMethod("makeLogHandleWithCategory:") static func makeLogHandle(category: String?) -> NSObject? { nil }

    @ObjCMethod("addSubscriber:") func add(subscriber: NSObject?) { if let subscriber { subscribers.append(subscriber) } }
    @ObjCMethod("removeSubscriber:")
    func remove(subscriber: NSObject?) { subscribers.removeAll { $0.objcObject == subscriber?.objcObject } }
    @ObjCMethod("pastPayloads") func pastPayloads() -> NSObject { emptyArray() }
    @ObjCMethod("pastDiagnosticPayloads") func pastDiagnosticPayloads() -> NSObject { emptyArray() }

    @ObjCClassMethod("extendLaunchMeasurementForTaskID:error:")
    static func extendLaunchMeasurement(taskID: String?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        error?.pointee = nil
        return true
    }

    @ObjCClassMethod("finishExtendedLaunchMeasurementForTaskID:error:")
    static func finishExtendedLaunchMeasurement(taskID: String?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        error?.pointee = nil
        return true
    }
}

@ObjCClass("MXMetricPayload") open class MXMetricPayload: NSObject {}
@ObjCClass("MXDiagnosticPayload") open class MXDiagnosticPayload: NSObject {}
@ObjCClass("MXDiagnostic") open class MXDiagnostic: NSObject {}
@ObjCClass("MXCrashDiagnostic") open class MXCrashDiagnostic: MXDiagnostic {}
@ObjCClass("MXHangDiagnostic") open class MXHangDiagnostic: MXDiagnostic {}
@ObjCClass("MXCPUExceptionDiagnostic") open class MXCPUExceptionDiagnostic: MXDiagnostic {}
@ObjCClass("MXDiskWriteExceptionDiagnostic") open class MXDiskWriteExceptionDiagnostic: MXDiagnostic {}
@ObjCClass("MXUnitAveragePixelLuminance") open class MXUnitAveragePixelLuminance: NSObject {}
