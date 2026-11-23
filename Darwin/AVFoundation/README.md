# AVFoundation

Perry's Swift overlay of AVFoundation, written for Perry from the API in
the macOS SDK's `AVFoundation.swiftinterface`: the asynchronously loaded
properties (`AVAsyncProperty`, `load(_:)` of every arity and its status),
Core Media's times bridged to `NSValue`, `AVError`'s userInfo, the Swift
API over the members AVFoundation's API notes make private to Swift
(NSNumber, NSValue and dictionary arrays of capture formats, photo
outputs, variants, captions, sliders, metrics events), video compositions
made from configurations, writer receivers and reader providers of ready
sample buffers, the integrated timeline's and image generator's async
sequences, export states, sample buffer outputs, metrics streams, the
sample buffer renderers' receivers and planned, resumable writing. It
replaces the Swift 5.0 overlay Xcode ships as a file, which a runtime
directory made for an x86_64 Mac app used to take.

It is compiled as the module `AVFoundation` over the SDK's Objective-C
headers, as Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh AVFoundation <runtime directory>

`swiftc-flags` gives it the `_swift_FORCE_LOAD_$_swiftAVFoundation` symbol
programs built against the overlay reference, and aliases the protocol
requirements base descriptor of `AVAssetReaderOutput.SupportedPayload` to
its protocol descriptor: the protocol has no requirements, so nothing is
reached through the base, but Apple's compiler exported it and today's
doesn't.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftAVFoundation.tbd`. What it still lacks (44):

- the initializing entry points (`fc`) of the convenience initializers on
  Objective-C classes (`AVPlayerItem(asset:automaticallyLoadedAssetKeys:)`,
  `AVCaptureSlider`'s three, `AVVideoComposition(configuration:)` and
  `(applyingFiltersTo:applier:)`, the instructions', layer instructions'
  and animation tool's `init(configuration:)`, `AVTimedMetadataGroup`,
  `AVPlayerItemVideoOutput`, `AVPlayerInterstitialEvent`'s two,
  `AVVideoOutputSpecification`, `AVAssetWritingPlanner`,
  `AVAssetVideoTrackPlan`), which Swift doesn't emit for them; the
  allocating ones programs call are there;
- `AVAnnotation`, `AVAnnotationSerializedData` and
  `AVAnnotationPathRepresentation`, `AVPlayerItem.speedRamp` and
  `AVPlayer`'s `interstitialPlayerDidChangeNotification`,
  `backgroundPIPAuthorizationTokenDidChangeNotification` and
  `audiovisualBackgroundPlaybackPolicyDidChangeNotification`: private to
  Apple, with no declaration in the SDK's interface or headers to go by.

Where the behaviour is Perry's own rather than a thin wrapper:

- an async property's key is the Objective-C property's name (`playable`
  for `.isPlayable`) and its getter reads the loaded property;
  `.mediaCharacteristics` of a track reads the track's characteristics, or
  asks it for each of AVFoundation's when it keeps no list;
- receivers wait for `isReadyForMoreMediaData` by polling every 2 ms rather
  than through a media-data-ready callback, which would take over the
  input's or renderer's own; `renderingEventsAfterFinishedEnqueuing`
  reports the renderers' notifications from when it's first read, and an
  enqueue result reports the decode failures and suggested flushes
  notified since the previous enqueue;
- a reader provider reads the next payload on a detached task, as the
  Objective-C read blocks;
- `AVAssetExportSession.states(updateInterval:)` polls the session's status
  and progress (every 0.1 s for an infinite interval);
- `AVPlayerItemSampleBufferOutput` sets its own delegate the first time a
  sample buffer is asked for, to wake `nextSampleBuffer()` and report
  restarted sequences;
- `AVSampleBufferVideoRenderer.presentationTimeExpectation` keeps the last
  value set, which the renderer can't report (the getter is unavailable in
  the SDK too);
- a layer instruction configuration's value set at a time is a ramp from
  the value to itself held from that time on; its ramp at a time is the last
  one starting at or before it;
- `[CMTag].monoscopicForVideoOutput()` is the video media type tag, and
  `stereoscopicForVideoOutput()` adds a stereo view of both eyes.
