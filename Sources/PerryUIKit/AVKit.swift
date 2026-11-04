import CPerryGeometry
import PerryObjCInterop

// AVKit's AVPlayerViewController: a black view showing its player's video,
// fitted by its video gravity. AVFoundation's player decodes the frames;
// while the controller's view is in a window it shows each new one. There
// are no playback controls.

final class PlayerViewControllerState: ObjectState {
    var player: NSObject?
    var showsPlaybackControls = true
    var videoGravity = "AVLayerVideoGravityResizeAspect"
    var videoView: UIView?
    /// The number of the frame showing.
    var frameNumber: UInt = 0
}

@ObjCClass("AVPlayerViewController")
open class AVPlayerViewController: UIViewController {
    static let playerStates = StateTable<PlayerViewControllerState>()
    var playerState: PlayerViewControllerState { AVPlayerViewController.playerStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        PlayerViews.stop(objcObject)
        AVPlayerViewController.playerStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("player") func player() -> NSObject? { playerState.player }
    @ObjCMethod("setPlayer:")
    func setPlayer(_ player: NSObject?) {
        playerState.player = player
        playerState.frameNumber = 0
    }

    @ObjCMethod("showsPlaybackControls") func showsPlaybackControls() -> Bool { playerState.showsPlaybackControls }
    @ObjCMethod("setShowsPlaybackControls:") func setShowsPlaybackControls(_ shows: Bool) { playerState.showsPlaybackControls = shows }
    @ObjCMethod("videoGravity") func videoGravity() -> String { playerState.videoGravity }
    @ObjCMethod("setVideoGravity:")
    func setVideoGravity(_ gravity: String) {
        playerState.videoGravity = gravity
        playerState.videoView?.state.layer.setContentsGravity(AVPlayerViewController.contentsGravity(gravity))
    }

    @ObjCMethod("entersFullScreenWhenPlaybackBegins") func entersFullScreenWhenPlaybackBegins() -> Bool { false }
    @ObjCMethod("setEntersFullScreenWhenPlaybackBegins:") func setEntersFullScreenWhenPlaybackBegins(_ enters: Bool) {}
    @ObjCMethod("exitsFullScreenWhenPlaybackEnds") func exitsFullScreenWhenPlaybackEnds() -> Bool { false }
    @ObjCMethod("setExitsFullScreenWhenPlaybackEnds:") func setExitsFullScreenWhenPlaybackEnds(_ exits: Bool) {}
    @ObjCMethod("allowsPictureInPicturePlayback") func allowsPictureInPicturePlayback() -> Bool { false }
    @ObjCMethod("setAllowsPictureInPicturePlayback:") func setAllowsPictureInPicturePlayback(_ allows: Bool) {}
    @ObjCMethod("updatesNowPlayingInfoCenter") func updatesNowPlayingInfoCenter() -> Bool { false }
    @ObjCMethod("setUpdatesNowPlayingInfoCenter:") func setUpdatesNowPlayingInfoCenter(_ updates: Bool) {}
    @ObjCMethod("delegate") func delegate() -> NSObject? { nil }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) {}
    @ObjCMethod("isReadyForDisplay") func isReadyForDisplay() -> Bool { playerState.frameNumber > 0 }
    @ObjCMethod("videoBounds") func videoBounds() -> CGRect { playerState.videoView?.state.bounds ?? .zero }
    @ObjCMethod("contentOverlayView") func contentOverlayView() -> UIView? { _ = loadedView; return playerState.videoView }

    /// A black view, and the video in a view filling it.
    @ObjCMethod("loadView")
    override func loadView() {
        let view = UIView.objCClass.object.allocated().initializeView(frame: Screen.bounds).unsafeCast(to: UIView.self)
        view.setAutoresizingMask(18)
        view.setBackgroundColor(UIColor.gray(0))
        let video = UIView.objCClass.object.allocated().initializeView(frame: view.state.bounds).unsafeCast(to: UIView.self)
        video.setAutoresizingMask(18)
        video.setUserInteractionEnabled(false)
        video.state.layer.setContentsGravity(AVPlayerViewController.contentsGravity(playerState.videoGravity))
        view.addSubview(video)
        playerState.videoView = video
        setView(view)
        // In case a subclass's -viewDidAppear: doesn't call this one's.
        PlayerViews.start(objcObject)
    }

    @ObjCMethod("viewDidAppear:")
    override func viewDidAppear(_ animated: Bool) {
        PlayerViews.start(objcObject)
    }

    @ObjCMethod("viewDidDisappear:")
    override func viewDidDisappear(_ animated: Bool) {
        PlayerViews.stop(objcObject)
    }

    static func contentsGravity(_ videoGravity: String) -> String {
        switch videoGravity {
        case "AVLayerVideoGravityResizeAspectFill": "resizeAspectFill"
        case "AVLayerVideoGravityResize": "resize"
        default: "resizeAspect"
        }
    }

    /// Shows the player's frame, if it has a new one.
    func showFrame() {
        let state = playerState
        guard let player = state.player, let video = state.videoView else { return }
        let number = player.sendVideoFrameNumber()
        guard number != state.frameNumber else { return }
        let width = player.sendVideoFrameWidth(), height = player.sendVideoFrameHeight()
        guard width > 0, height > 0, let bytes = player.sendVideoFrameBytes(),
              let image = AVPlayerViewController.image(bytes, width: width, height: height) else { return }
        state.frameNumber = number
        video.state.layer.setContents(NSObject(image.object))
        Display.markDirty()
    }

    /// RGBA pixels, top row first, as an image.
    static func image(_ bytes: UnsafeRawPointer, width: Int, height: Int) -> Owned? {
        guard let space = CG.colorSpaceCreateDeviceRGB() else { return nil }
        defer { CG.release(space) }
        let rowBytes = width * 4
        // Premultiplied RGBA, first byte red; video is opaque.
        guard let context = CG.bitmapContextCreate(nil, width, height, 8, rowBytes, space, 1 | 0x4000) else { return nil }
        defer { CG.release(context) }
        guard let data = CG.bitmapContextGetData(context) else { return nil }
        data.copyMemory(from: bytes, byteCount: rowBytes * height)
        return CG.bitmapContextCreateImage(context).map(Owned.init)
    }
}

/// The player controllers in windows, shown a new frame when there is one.
enum PlayerViews {
    nonisolated(unsafe) private static var showing: [UnsafeMutableRawPointer] = []
    nonisolated(unsafe) private static var scheduled = false

    static func start(_ controller: UnsafeMutableRawPointer) {
        if !showing.contains(controller) { showing.append(controller) }
        schedule()
    }

    static func stop(_ controller: UnsafeMutableRawPointer) { showing.removeAll { $0 == controller } }

    private static func schedule() {
        guard !scheduled, let after = Display.dispatchAfter, let time = Display.dispatchTime else { return }
        scheduled = true
        after(time(0, 16_666_667), Updates.mainQueue, nil) { _ in
            PlayerViews.scheduled = false
            for object in PlayerViews.showing {
                AVPlayerViewController(objcObject: object, ownership: .retain).showFrame()
            }
            if !PlayerViews.showing.isEmpty { PlayerViews.schedule() }
        }
    }
}

/// AVFoundation's player's frames.
extension NSObject {
    @ObjCMethod("_perryVideoFrameNumber") func sendVideoFrameNumber() -> UInt
    @ObjCMethod("_perryVideoFrameWidth") func sendVideoFrameWidth() -> Int
    @ObjCMethod("_perryVideoFrameHeight") func sendVideoFrameHeight() -> Int
    @ObjCMethod("_perryVideoFrameBytes") func sendVideoFrameBytes() -> UnsafeRawPointer?
}
