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

/// Media characteristics, the common metadata identifiers and the other names
/// players, subtitle selection and streaming code compare against. Apps read
/// them as they load (Hulu puts AVMediaCharacteristicLegible in an array),
/// so each is a string, never the callable stub an unresolved import gets.
@ObjCConstants
enum MediaCharacteristics {
    static let AVMediaCharacteristicVisual = "public.visual"
    static let AVMediaCharacteristicAudible = "public.audible"
    static let AVMediaCharacteristicLegible = "public.legible"
    static let AVMediaCharacteristicFrameBased = "public.frame-based"
    static let AVMediaCharacteristicContainsOnlyForcedSubtitles = "public.subtitles.forced-only"
    static let AVMediaCharacteristicDescribesVideoForAccessibility = "public.accessibility.describes-video"
    static let AVMediaCharacteristicTranscribesSpokenDialogForAccessibility = "public.accessibility.transcribes-spoken-dialog"
    static let AVMediaCharacteristicDescribesMusicAndSoundForAccessibility = "public.accessibility.describes-music-and-sound"
    static let AVMediaCharacteristicEasyToRead = "public.easy-to-read"
    static let AVMediaCharacteristicIsAuxiliaryContent = "public.auxiliary-content"
    static let AVMediaCharacteristicIsOriginalContent = "public.main-program-content"
    static let AVMediaTypeClosedCaption = "clcp"
    static let AVMediaTypeSubtitle = "sbtl"
    static let AVMediaTypeTimecode = "tmcd"
    static let AVMediaTypeMetadata = "meta"
    static let AVMetadataCommonIdentifierTitle = "common/title"
    static let AVMetadataCommonIdentifierArtwork = "common/artwork"
    static let AVMetadataCommonIdentifierDescription = "common/description"
    static let AVMetadataCommonIdentifierArtist = "common/artist"
    static let AVMetadataCommonIdentifierCreator = "common/creator"
    static let AVMetadataCommonIdentifierSubject = "common/subject"
    static let AVMetadataCommonIdentifierPublisher = "common/publisher"
    static let AVMetadataCommonIdentifierAlbumName = "common/albumName"
    static let AVMetadataCommonIdentifierLanguage = "common/language"
    static let AVMetadataCommonIdentifierCopyrights = "common/copyrights"
    static let AVMetadataCommonIdentifierCreationDate = "common/creationDate"
    static let AVMetadataCommonIdentifierType = "common/type"
    static let AVMetadataIdentifieriTunesMetadataContentRating = "itsk/rtng"
    static let AVPlayerWaitingToMinimizeStallsReason = "AVPlayerWaitingToMinimizeStallsReason"
    static let AVPlayerWaitingWhileEvaluatingBufferingRateReason = "AVPlayerWaitingWhileEvaluatingBufferingRateReason"
    static let AVPlayerWaitingWithNoItemToPlayReason = "AVPlayerWaitingWithNoItemToPlayReason"
    static let AVPlayerWaitingForCoordinatedPlaybackReason = "AVPlayerWaitingForCoordinatedPlaybackReason"
    static let AVCoordinatedPlaybackSuspensionReasonPlayingInterstitial = "AVCoordinatedPlaybackSuspensionReasonPlayingInterstitial"
    static let AVContentKeySystemFairPlayStreaming = "FairPlayStreaming"
    static let AVStreamingKeyDeliveryContentKeyType = "com.apple.streamingkeydelivery.contentkey"
}

/// Metadata object types, which a capture output would recognize.
@ObjCConstants
enum MetadataObjectTypes {
    static let AVMetadataObjectTypeQRCode = "org.iso.QRCode"
    static let AVMetadataObjectTypeEAN13Code = "org.gs1.EAN-13"
    static let AVMetadataObjectTypeEAN8Code = "org.gs1.EAN-8"
    static let AVMetadataObjectTypeCode128Code = "com.intermec.Code128"
    static let AVMetadataObjectTypeFace = "face"
}
