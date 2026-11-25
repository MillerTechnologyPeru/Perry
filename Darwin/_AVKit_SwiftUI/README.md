# _AVKit_SwiftUI

Perry's `_AVKit_SwiftUI.framework`: AVKit's SwiftUI API, the framework Apple's
`VideoPlayer` is in (AVKit's cross-import overlay with SwiftUI). `VideoPlayer`
shows its player through Perry's `AVPlayerViewController`, with the overlay
the app gives over it. `Scripts/build-avkit-swiftui.sh` builds it on a Mac,
after `Scripts/build-swiftui.sh`, against Perry's SwiftUI; it is installed as
`_AVKit_SwiftUI.framework/_AVKit_SwiftUI` in the Swift runtime's directory.
