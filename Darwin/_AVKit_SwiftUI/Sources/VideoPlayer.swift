// SwiftUI's video player: AVKit's player view controller, with the app's
// overlay above the video. The camera capture event modifiers are not here.
//
// AVKit isn't imported: its Swift overlay imports Apple's SwiftUI, whose
// default arguments then clash with Perry's in the compiler. The player view
// controller is made by its class name and given the player by key, and
// AVPlayer comes from AVFoundation.

public import AVFoundation
public import OpenSwiftUI
import UIKit

/// A view that shows a player's video, with playback controls, and an
/// overlay over the video.
@available(iOS 14.0, *)
@MainActor @preconcurrency
public struct VideoPlayer<VideoOverlay>: View where VideoOverlay: View {
    var player: AVPlayer?
    var videoOverlay: VideoOverlay

    @MainActor @preconcurrency
    public init(player: AVPlayer?, @ViewBuilder videoOverlay: () -> VideoOverlay) {
        self.player = player
        self.videoOverlay = videoOverlay()
    }

    @MainActor @preconcurrency
    public var body: some View {
        PlayerViewController(player: player).overlay(videoOverlay, alignment: .center)
    }
}

@available(iOS 14.0, *)
extension VideoPlayer where VideoOverlay == EmptyView {
    /// A video player with no overlay.
    @MainActor @preconcurrency
    public init(player: AVPlayer?) {
        self.init(player: player) { EmptyView() }
    }
}

@available(iOS 14.0, *)
extension VideoPlayer: Sendable {}

/// AVKit's player view controller, given the player each update.
@available(iOS 14.0, *)
struct PlayerViewController: UIViewControllerRepresentable {
    var player: AVPlayer?

    func makeUIViewController(context: Context) -> UIViewController {
        let type = NSClassFromString("AVPlayerViewController") as? UIViewController.Type ?? UIViewController.self
        let controller = type.init()
        controller.setValue(player, forKey: "player")
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        if controller.value(forKey: "player") as AnyObject? !== player { controller.setValue(player, forKey: "player") }
    }
}
