# CoreLocation

Perry's Swift overlay of Core Location, written for Perry from the API in
the macOS SDK's `CoreLocation.swiftinterface`: `CLLocationCoordinate2D`
bridged to `NSValue`, `CLMonitor` (an actor monitoring circular and
beacon conditions, its events an async sequence) over the Objective-C
`CLMonitor`, `CLLocationUpdate.liveUpdates(_:)` over
`CLLocationUpdater`, the beacon constraint's numbers and `CLError`'s
alternate region. It replaces the Swift 5.0 overlay Xcode ships as a file,
which a runtime directory made for an x86_64 Mac app used to take.

It is compiled as the module `CoreLocation` over the SDK's Objective-C
headers, as Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh CoreLocation <runtime directory>

`swiftc-flags` gives it the `_swift_FORCE_LOAD_$_swiftCoreLocation`
symbol programs built against the overlay reference.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftCoreLocation.tbd`. What it still lacks (135) is
private to Apple, with no declaration in the SDK's interface or headers to
go by:

- `CLLivePlaceContext` and `CLHistoricalPlaceContext` (their places and
  properties);
- `CLLocationManager`'s `liveUpdates(_:)`, `serviceSession()`,
  `backgroundActivitySession()` and `historicalUpdates`, and
  `CLLocationUpdate.historicalUpdates`;
- `CLServiceSession`'s `Requirement`, `VisitHistoryRequirement` and
  `LearnedRoutesRequirement`, its `init(requirement:)` and
  `init(requirement:locationManager:)`, `_locationIntelligenceDiagnostics`,
  and the diagnostic properties beyond the interface's (`accuracyLimited`,
  visit history and learned routes);
- `CLMonitor.CircularGeographicCondition`'s `requiresWirelessClientInfo`
  and `CLLocationUpdate.LiveConfiguration.wirelessClientInfo`.

Where the behaviour is Perry's own rather than a thin wrapper:

- `CLServiceSession` and `CLBackgroundActivitySession` are unavailable on
  macOS, as in the SDK (their Objective-C classes are too): they're here
  for the symbols the SDK's stub lists for the library it shares with Mac
  Catalyst, and their initializers trap;
- a monitor's events are delivered on a queue of its own into the async
  sequence `events`, which one iteration consumes;
- `add(_:identifier:)` monitors circular and beacon conditions, the kinds
  Core Location has; it ignores a condition of a kind of the program's own.
  A record or event's condition of a kind the overlay doesn't know is kept
  as the Objective-C object's keyed archive, so it can be handed back;
- the conditions' `Codable` form is Perry's own (latitude, longitude and
  radius; UUID, major and minor), not Apple's;
- each iteration of `liveUpdates(_:)` has its own `CLLocationUpdater`,
  invalidated when the iteration ends.
