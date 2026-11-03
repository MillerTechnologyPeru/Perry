import PerryObjCInterop

// AVCaptureDevice on a machine without cameras or microphones: no devices
// of any media type, and access to them is never granted.

@ObjCClass("AVCaptureDevice")
open class AVCaptureDevice: NSObject {
    @ObjCClassMethod("devices")
    static func devices() -> NSObject { NSObject(ObjCClass(named: "NSArray").pointer).sendArray() }

    @ObjCClassMethod("devicesWithMediaType:")
    static func devices(mediaType: NSObject?) -> NSObject { NSObject(ObjCClass(named: "NSArray").pointer).sendArray() }

    @ObjCClassMethod("defaultDeviceWithMediaType:")
    static func defaultDevice(mediaType: NSObject?) -> AVCaptureDevice? { nil }

    @ObjCClassMethod("deviceWithUniqueID:")
    static func device(uniqueID: NSObject?) -> AVCaptureDevice? { nil }

    /// AVAuthorizationStatusNotDetermined: the app may ask, and is refused.
    @ObjCClassMethod("authorizationStatusForMediaType:")
    static func authorizationStatus(mediaType: NSObject?) -> Int { 0 }

    @ObjCClassMethod("requestAccessForMediaType:completionHandler:")
    static func requestAccess(mediaType: NSObject?, completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        completionHandler.function(as: (@convention(c) (UnsafeMutableRawPointer, Bool) -> Void).self)(completionHandler.object, false)
    }
}

extension NSObject {
    @ObjCMethod("array") func sendArray() -> NSObject
}

/// Media types and the names players and layers use.
@ObjCConstants
enum MediaConstants {
    static let AVMediaTypeVideo = "vide"
    static let AVMediaTypeAudio = "soun"
    static let AVMediaTypeText = "text"
    static let AVMediaTypeMuxed = "muxx"
    static let AVLayerVideoGravityResize = "AVLayerVideoGravityResize"
    static let AVLayerVideoGravityResizeAspect = "AVLayerVideoGravityResizeAspect"
    static let AVLayerVideoGravityResizeAspectFill = "AVLayerVideoGravityResizeAspectFill"
    static let AVPlayerItemDidPlayToEndTimeNotification = "AVPlayerItemDidPlayToEndTimeNotification"
    static let AVPlayerItemFailedToPlayToEndTimeNotification = "AVPlayerItemFailedToPlayToEndTimeNotification"
}
