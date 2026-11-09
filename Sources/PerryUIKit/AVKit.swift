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

    /// Player layers with a player, which show its frames wherever they are.
    nonisolated(unsafe) static var layers: [UnsafeMutableRawPointer] = []

    static func start(layer: UnsafeMutableRawPointer) {
        if !layers.contains(layer) { layers.append(layer) }
        schedule()
    }

    static func stop(layer: UnsafeMutableRawPointer) { layers.removeAll { $0 == layer } }

    private static func schedule() {
        guard !scheduled, let after = Display.dispatchAfter, let time = Display.dispatchTime else { return }
        scheduled = true
        after(time(0, 16_666_667), Updates.mainQueue, nil) { _ in
            PlayerViews.scheduled = false
            for object in PlayerViews.showing {
                AVPlayerViewController(objcObject: object, ownership: .retain).showFrame()
            }
            for object in PlayerViews.layers {
                AVPlayerLayer(objcObject: object, ownership: .retain).showFrame()
            }
            if !PlayerViews.showing.isEmpty || !PlayerViews.layers.isEmpty { PlayerViews.schedule() }
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

// AVFoundation's AVPlayerLayer: a layer showing its player's frames as its
// contents, fitted by its video gravity. It is here with the player view,
// as a layer of UIKit's; Objective-C classes bind from any provider.

final class PlayerLayerState: ObjectState {
    var player: NSObject?
    var videoGravity = "AVLayerVideoGravityResizeAspect"
    var frameNumber: UInt = 0
    var size = CGSize.zero
}

@ObjCClass("AVPlayerLayer")
class AVPlayerLayer: CALayer {
    static let states = StateTable<PlayerLayerState>()
    var layerState: PlayerLayerState { AVPlayerLayer.states[objcObject] }

    @ObjCClassMethod("playerLayerWithPlayer:")
    static func layer(_ cls: ObjCClass, player: NSObject?) -> NSObject {
        let layer = cls.object.allocated().initializeLayer().unsafeCast(to: AVPlayerLayer.self)
        layer.setPlayer(player)
        return layer
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        PlayerViews.stop(layer: objcObject)
        AVPlayerLayer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVPlayerLayer.objCClass.pointer)
    }

    @ObjCMethod("player") func player() -> NSObject? { layerState.player }
    @ObjCMethod("setPlayer:")
    func setPlayer(_ player: NSObject?) {
        let state = layerState
        state.player = player
        state.frameNumber = 0
        if player != nil { PlayerViews.start(layer: objcObject) } else { PlayerViews.stop(layer: objcObject) }
    }

    @ObjCMethod("videoGravity") func videoGravity() -> String { layerState.videoGravity }
    @ObjCMethod("setVideoGravity:")
    func setVideoGravity(_ gravity: String) {
        layerState.videoGravity = gravity
        setContentsGravity(AVPlayerViewController.contentsGravity(gravity))
    }

    @ObjCMethod("isReadyForDisplay") func isReadyForDisplay() -> Bool { layerState.frameNumber > 0 }

    /// The rectangle the video fills, by its gravity.
    @ObjCMethod("videoRect")
    func videoRect() -> CGRect {
        let bounds = self.bounds(), size = layerState.size
        guard size.width > 0, size.height > 0, layerState.videoGravity != "AVLayerVideoGravityResize" else { return bounds }
        let sx = bounds.size.width / size.width, sy = bounds.size.height / size.height
        let scale = layerState.videoGravity == "AVLayerVideoGravityResizeAspectFill" ? max(sx, sy) : min(sx, sy)
        let width = size.width * scale, height = size.height * scale
        return CGRect(origin: CGPoint(x: bounds.origin.x + (bounds.size.width - width) / 2,
                                      y: bounds.origin.y + (bounds.size.height - height) / 2),
                      size: CGSize(width: width, height: height))
    }

    @ObjCMethod("pixelBufferAttributes") func pixelBufferAttributes() -> NSObject? { nil }
    @ObjCMethod("setPixelBufferAttributes:") func setPixelBufferAttributes(_ attributes: NSObject?) {}

    /// Shows the player's frame, if it has a new one.
    func showFrame() {
        let state = layerState
        guard let player = state.player else { return }
        let number = player.sendVideoFrameNumber()
        guard number != state.frameNumber else { return }
        let width = player.sendVideoFrameWidth(), height = player.sendVideoFrameHeight()
        guard width > 0, height > 0, let bytes = player.sendVideoFrameBytes(),
              let image = AVPlayerViewController.image(bytes, width: width, height: height) else { return }
        state.frameNumber = number
        state.size = CGSize(width: CGFloat(width), height: CGFloat(height))
        setContents(NSObject(image.object))
        Display.markDirty()
    }
}

// The view MediaPlayer's movie players show their movies in, and the window
// a movie player view controller is presented in.

@ObjCClass("_PerryMovieView")
class PerryMovieView: UIView {
    @ObjCClassMethod("layerClass") static func movieLayerClass() -> ObjCClass { AVPlayerLayer.objCClass }

    @ObjCMethod("setMoviePlayer:")
    func setMoviePlayer(_ player: NSObject?) {
        setBackgroundColor(UIColor.gray(0))
        state.layer.unsafeCast(to: AVPlayerLayer.self).setPlayer(player)
    }
}

extension NSObject {
    @ObjCMethod("view") func sendMoviePlayerView() -> UIView?
}

enum MoviePresentation {
    nonisolated(unsafe) private static var shown: UIView?
    static var isShowing: Bool { shown != nil }

    /// Puts the controller's view over the key window's others, filling the
    /// screen as the display shows it: a movie is upright on a turned display
    /// however the app's own screen stands.
    static func present(_ controller: NSObject?) {
        guard let key = Windows.key, let view = controller?.sendMoviePlayerView() else { return }
        dismiss()
        let bounds = Screen.bounds
        view.setAutoresizingMask(0)
        view.setCenter(CGPoint(x: bounds.size.width / 2, y: bounds.size.height / 2))
        switch Compositor.displayRotation {
        case 90:
            view.setBounds(CGRect(origin: .zero, size: CGSize(width: bounds.size.height, height: bounds.size.width)))
            view.setTransform(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0))
        case 270:
            view.setBounds(CGRect(origin: .zero, size: CGSize(width: bounds.size.height, height: bounds.size.width)))
            view.setTransform(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0))
        default:
            view.setBounds(CGRect(origin: .zero, size: bounds.size))
        }
        UIView.wrap(key).addSubview(view)
        shown = view
        Display.markDirty()
    }

    static func dismiss() {
        shown?.removeFromSuperview()
        shown = nil
        Display.markDirty()
    }
}
