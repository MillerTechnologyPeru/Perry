import Foundation
import CoreMedia

// The asynchronously loaded properties of assets, tracks and metadata
// items: a key that AVAsynchronousKeyValueLoading loads (the Objective-C
// property's name, playable for isPlayable) and a getter that reads the
// loaded value, as AVAsyncProperty values.

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVMetadataItem {
    public static var extraAttributes: AVAsyncProperty<Root, [AVMetadataExtraAttributeKey : Any]?> {
        AVAsyncProperty(key: "extraAttributes") { $0.extraAttributes }
    }

    public static var value: AVAsyncProperty<Root, (any NSCopying & NSObjectProtocol)?> {
        AVAsyncProperty(key: "value") { $0.value }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVMetadataItem {
    public static var stringValue: AVAsyncProperty<Root, String?> {
        AVAsyncProperty(key: "stringValue") { $0.stringValue }
    }

    public static var numberValue: AVAsyncProperty<Root, NSNumber?> {
        AVAsyncProperty(key: "numberValue") { $0.numberValue }
    }

    public static var dateValue: AVAsyncProperty<Root, Date?> {
        AVAsyncProperty(key: "dateValue") { $0.dateValue }
    }

    public static var dataValue: AVAsyncProperty<Root, Data?> {
        AVAsyncProperty(key: "dataValue") { $0.dataValue }
    }
}

@available(macOS 12, iOS 15, watchOS 8, visionOS 1, *)
@available(tvOS, unavailable)
extension AVPartialAsyncProperty where Root: AVMutableMovie {
    public static var tracks: AVAsyncProperty<Root, [AVMutableMovieTrack]> {
        AVAsyncProperty(key: "tracks") { $0.tracks }
    }
}

@available(macOS 12, iOS 15, watchOS 8, visionOS 1, *)
@available(tvOS, unavailable)
extension AVPartialAsyncProperty where Root: AVFragmentedMovie {
    public static var tracks: AVAsyncProperty<Root, [AVFragmentedMovieTrack]> {
        AVAsyncProperty(key: "tracks") { $0.tracks }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVComposition {
    public static var tracks: AVAsyncProperty<Root, [AVCompositionTrack]> {
        AVAsyncProperty(key: "tracks") { $0.tracks }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAsset {
    public static var duration: AVAsyncProperty<Root, CMTime> {
        AVAsyncProperty(key: "duration") { $0.duration }
    }

    public static var preferredRate: AVAsyncProperty<Root, Float> {
        AVAsyncProperty(key: "preferredRate") { $0.preferredRate }
    }

    public static var preferredVolume: AVAsyncProperty<Root, Float> {
        AVAsyncProperty(key: "preferredVolume") { $0.preferredVolume }
    }

    public static var preferredTransform: AVAsyncProperty<Root, CGAffineTransform> {
        AVAsyncProperty(key: "preferredTransform") { $0.preferredTransform }
    }

    public static var minimumTimeOffsetFromLive: AVAsyncProperty<Root, CMTime> {
        AVAsyncProperty(key: "minimumTimeOffsetFromLive") { $0.minimumTimeOffsetFromLive }
    }

    public static var providesPreciseDurationAndTiming: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "providesPreciseDurationAndTiming") { $0.providesPreciseDurationAndTiming }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAsset {
    public static var tracks: AVAsyncProperty<Root, [AVAssetTrack]> {
        AVAsyncProperty(key: "tracks") { $0.tracks }
    }

    public static var trackGroups: AVAsyncProperty<Root, [AVAssetTrackGroup]> {
        AVAsyncProperty(key: "trackGroups") { $0.trackGroups }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAsset {
    public static var creationDate: AVAsyncProperty<Root, AVMetadataItem?> {
        AVAsyncProperty(key: "creationDate") { $0.creationDate }
    }

    public static var lyrics: AVAsyncProperty<Root, String?> {
        AVAsyncProperty(key: "lyrics") { $0.lyrics }
    }

    public static var commonMetadata: AVAsyncProperty<Root, [AVMetadataItem]> {
        AVAsyncProperty(key: "commonMetadata") { $0.commonMetadata }
    }

    public static var metadata: AVAsyncProperty<Root, [AVMetadataItem]> {
        AVAsyncProperty(key: "metadata") { $0.metadata }
    }

    public static var availableMetadataFormats: AVAsyncProperty<Root, [AVMetadataFormat]> {
        AVAsyncProperty(key: "availableMetadataFormats") { $0.availableMetadataFormats }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAsset {
    public static var availableChapterLocales: AVAsyncProperty<Root, [Locale]> {
        AVAsyncProperty(key: "availableChapterLocales") { $0.availableChapterLocales }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVURLAsset {
    public static var variants: AVAsyncProperty<Root, [AVAssetVariant]> {
        AVAsyncProperty(key: "variants") { $0.variants }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAsset {
    public static var availableMediaCharacteristicsWithMediaSelectionOptions: AVAsyncProperty<Root, [AVMediaCharacteristic]> {
        AVAsyncProperty(key: "availableMediaCharacteristicsWithMediaSelectionOptions") { $0.availableMediaCharacteristicsWithMediaSelectionOptions }
    }

    public static var preferredMediaSelection: AVAsyncProperty<Root, AVMediaSelection> {
        AVAsyncProperty(key: "preferredMediaSelection") { $0.preferredMediaSelection }
    }

    public static var allMediaSelections: AVAsyncProperty<Root, [AVMediaSelection]> {
        AVAsyncProperty(key: "allMediaSelections") { $0.allMediaSelections }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAsset {
    @available(macOS 12, iOS 15, tvOS 15, visionOS 1, *)
    @available(watchOS, unavailable)
    public static var hasProtectedContent: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "hasProtectedContent") { $0.hasProtectedContent }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAsset {
    @available(macOS 12, iOS 15, tvOS 15, visionOS 1, *)
    @available(watchOS, unavailable)
    public static var canContainFragments: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "canContainFragments") { $0.canContainFragments }
    }

    @available(macOS 12, iOS 15, tvOS 15, visionOS 1, *)
    @available(watchOS, unavailable)
    public static var containsFragments: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "containsFragments") { $0.containsFragments }
    }

    public static var overallDurationHint: AVAsyncProperty<Root, CMTime> {
        AVAsyncProperty(key: "overallDurationHint") { $0.overallDurationHint }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAsset {
    public static var isPlayable: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "playable") { $0.isPlayable }
    }

    @available(macOS 12, iOS 15, tvOS 15, visionOS 1, *)
    @available(watchOS, unavailable)
    public static var isExportable: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "exportable") { $0.isExportable }
    }

    @available(macOS 12, iOS 15, tvOS 15, visionOS 1, *)
    @available(watchOS, unavailable)
    public static var isReadable: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "readable") { $0.isReadable }
    }

    public static var isComposable: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "composable") { $0.isComposable }
    }

    @available(iOS 15, tvOS 15, visionOS 1, *)
    @available(macOS, unavailable)
    @available(watchOS, unavailable)
    public static var isCompatibleWithSavedPhotosAlbum: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "compatibleWithSavedPhotosAlbum") { $0.isCompatibleWithSavedPhotosAlbum }
    }

    @available(macOS 12, iOS 15, tvOS 15, visionOS 1, *)
    @available(watchOS, unavailable)
    public static var isCompatibleWithAirPlayVideo: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "compatibleWithAirPlayVideo") { $0.isCompatibleWithAirPlayVideo }
    }
}

@available(macOS 27.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension AVPartialAsyncProperty where Root: AVAsset {
    public static var constituentFileURLs: AVAsyncProperty<Root, [URL]> {
        AVAsyncProperty(key: "constituentFileURLs") { $0.value(forKey: "constituentFileURLs") as? [URL] ?? [] }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVMutableComposition {
    public static var tracks: AVAsyncProperty<Root, [AVMutableCompositionTrack]> {
        AVAsyncProperty(key: "tracks") { $0.tracks }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAssetTrack {
    public static var formatDescriptions: AVAsyncProperty<Root, [CMFormatDescription]> {
        AVAsyncProperty(key: "formatDescriptions") { $0.formatDescriptions as! [CMFormatDescription] }
    }

    public static var isPlayable: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "playable") { $0.isPlayable }
    }

    public static var isDecodable: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "decodable") { $0.isDecodable }
    }

    public static var isEnabled: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "enabled") { $0.isEnabled }
    }

    public static var isSelfContained: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "selfContained") { $0.isSelfContained }
    }

    public static var totalSampleDataLength: AVAsyncProperty<Root, Int64> {
        AVAsyncProperty(key: "totalSampleDataLength") { $0.totalSampleDataLength }
    }

    public static var mediaCharacteristics: AVAsyncProperty<Root, [AVMediaCharacteristic]> {
        AVAsyncProperty(key: "mediaCharacteristics") { trackMediaCharacteristics(of: $0) }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAssetTrack {
    public static var timeRange: AVAsyncProperty<Root, CMTimeRange> {
        AVAsyncProperty(key: "timeRange") { $0.timeRange }
    }

    public static var naturalTimeScale: AVAsyncProperty<Root, CMTimeScale> {
        AVAsyncProperty(key: "naturalTimeScale") { $0.naturalTimeScale }
    }

    public static var estimatedDataRate: AVAsyncProperty<Root, Float> {
        AVAsyncProperty(key: "estimatedDataRate") { $0.estimatedDataRate }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAssetTrack {
    public static var languageCode: AVAsyncProperty<Root, String?> {
        AVAsyncProperty(key: "languageCode") { $0.languageCode }
    }

    public static var extendedLanguageTag: AVAsyncProperty<Root, String?> {
        AVAsyncProperty(key: "extendedLanguageTag") { $0.extendedLanguageTag }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAssetTrack {
    public static var naturalSize: AVAsyncProperty<Root, CGSize> {
        AVAsyncProperty(key: "naturalSize") { $0.naturalSize }
    }

    public static var preferredTransform: AVAsyncProperty<Root, CGAffineTransform> {
        AVAsyncProperty(key: "preferredTransform") { $0.preferredTransform }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAssetTrack {
    public static var preferredVolume: AVAsyncProperty<Root, Float> {
        AVAsyncProperty(key: "preferredVolume") { $0.preferredVolume }
    }

    public static var hasAudioSampleDependencies: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "hasAudioSampleDependencies") { $0.hasAudioSampleDependencies }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAssetTrack {
    public static var nominalFrameRate: AVAsyncProperty<Root, Float> {
        AVAsyncProperty(key: "nominalFrameRate") { $0.nominalFrameRate }
    }

    public static var minFrameDuration: AVAsyncProperty<Root, CMTime> {
        AVAsyncProperty(key: "minFrameDuration") { $0.minFrameDuration }
    }

    public static var requiresFrameReordering: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "requiresFrameReordering") { $0.requiresFrameReordering }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAssetTrack {
    public static var segments: AVAsyncProperty<Root, [AVAssetTrackSegment]> {
        AVAsyncProperty(key: "segments") { $0.segments }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAssetTrack {
    public static var commonMetadata: AVAsyncProperty<Root, [AVMetadataItem]> {
        AVAsyncProperty(key: "commonMetadata") { $0.commonMetadata }
    }

    public static var metadata: AVAsyncProperty<Root, [AVMetadataItem]> {
        AVAsyncProperty(key: "metadata") { $0.metadata }
    }

    public static var availableMetadataFormats: AVAsyncProperty<Root, [AVMetadataFormat]> {
        AVAsyncProperty(key: "availableMetadataFormats") { $0.availableMetadataFormats }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAssetTrack {
    public static var availableTrackAssociationTypes: AVAsyncProperty<Root, [AVAssetTrack.AssociationType]> {
        AVAsyncProperty(key: "availableTrackAssociationTypes") { $0.availableTrackAssociationTypes }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVAssetTrack {
    // The property is macOS's alone in the headers, and only this one
    // elsewhere: it is read by its key.
    @available(macOS 12, iOS 16, tvOS 16, watchOS 9, visionOS 1, *)
    public static var canProvideSampleCursors: AVAsyncProperty<Root, Bool> {
        AVAsyncProperty(key: "canProvideSampleCursors") { ($0.value(forKey: "canProvideSampleCursors") as? Bool) ?? false }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVFragmentedAsset {
    public static var tracks: AVAsyncProperty<Root, [AVFragmentedAssetTrack]> {
        AVAsyncProperty(key: "tracks") { $0.tracks }
    }
}

@available(macOS 12, iOS 15, watchOS 8, visionOS 1, *)
@available(tvOS, unavailable)
extension AVPartialAsyncProperty where Root: AVMovie {
    public static var tracks: AVAsyncProperty<Root, [AVMovieTrack]> {
        AVAsyncProperty(key: "tracks") { $0.tracks }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPartialAsyncProperty where Root: AVURLAsset {
    public static var tracks: AVAsyncProperty<Root, [AVAssetTrack]> {
        AVAsyncProperty(key: "tracks") { $0.tracks }
    }
}

@available(macOS 26.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension AVPartialAsyncProperty where Root: AVURLAsset {
    public static var sidecarURL: AVAsyncProperty<Root, URL?> {
        AVAsyncProperty(key: "sidecarURL") { $0.value(forKey: "sidecarURL") as? URL }
    }
}

/// The media characteristics a track has: its own list where it keeps
/// one, else those of AVFoundation's it answers it has.
private func trackMediaCharacteristics(of track: AVAssetTrack) -> [AVMediaCharacteristic] {
    if track.responds(to: NSSelectorFromString("mediaCharacteristics")),
       let list = track.value(forKey: "mediaCharacteristics") as? [String] {
        return list.map(AVMediaCharacteristic.init(rawValue:))
    }
    let known: [AVMediaCharacteristic] = [
        .visual, .audible, .legible, .frameBased, .usesWideGamutColorSpace,
        .isMainProgramContent, .isAuxiliaryContent, .containsOnlyForcedSubtitles,
        .transcribesSpokenDialogForAccessibility, .describesMusicAndSoundForAccessibility,
        .easyToRead, .describesVideoForAccessibility, .languageTranslation,
        .dubbedTranslation, .voiceOverTranslation, .containsHDRVideo, .containsAlphaChannel,
    ]
    return known.filter { track.hasMediaCharacteristic($0) }
}
