import CPerryGeometry
import PerryObjCInterop

// MPContentItem, an item a media app offers to CarPlay and other places that
// browse its content: an identifier, a title and subtitle, artwork, and what
// kind of item it is. Nothing here browses, so an item keeps what it is
// given, as apps subclass it for the items of their own models.

@ObjCClass("MPContentItem")
open class MPContentItem: NSObject {
    var itemIdentifier: String = ""
    var itemTitle: String?
    var itemSubtitle: String?
    var itemArtwork: NSObject?
    var streaming = false
    var explicit = false
    var container = false
    var playable = false
    var progress: Float = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithIdentifier:")
    public required init(identifier: String) {
        super.init()
        itemIdentifier = identifier
    }

    @ObjCMethod("identifier") func identifier() -> String { itemIdentifier }
    @ObjCMethod("title") func title() -> String? { itemTitle }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { itemTitle = title }
    @ObjCMethod("subtitle") func subtitle() -> String? { itemSubtitle }
    @ObjCMethod("setSubtitle:") func setSubtitle(_ subtitle: String?) { itemSubtitle = subtitle }
    @ObjCMethod("artwork") func artwork() -> NSObject? { itemArtwork }
    @ObjCMethod("setArtwork:") func setArtwork(_ artwork: NSObject?) { itemArtwork = artwork }
    @ObjCMethod("isStreamingContent") func isStreamingContent() -> Bool { streaming }
    @ObjCMethod("setStreamingContent:") func setStreamingContent(_ streaming: Bool) { self.streaming = streaming }
    @ObjCMethod("isExplicitContent") func isExplicitContent() -> Bool { explicit }
    @ObjCMethod("setExplicitContent:") func setExplicitContent(_ explicit: Bool) { self.explicit = explicit }
    @ObjCMethod("isContainer") func isContainer() -> Bool { container }
    @ObjCMethod("setContainer:") func setContainer(_ container: Bool) { self.container = container }
    @ObjCMethod("isPlayable") func isPlayable() -> Bool { playable }
    @ObjCMethod("setPlayable:") func setPlayable(_ playable: Bool) { self.playable = playable }
    @ObjCMethod("playbackProgress") func playbackProgress() -> Float { progress }
    @ObjCMethod("setPlaybackProgress:") func setPlaybackProgress(_ progress: Float) { self.progress = progress }
}
