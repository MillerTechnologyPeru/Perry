import CPerryGeometry
import Glibc
import PerryObjCInterop

// SpriteKit's scene graph, drawn by QuartzCore's layers. A scene's nodes
// are kept as nodes (position, rotation, scale, alpha, z position, and for
// sprites and shapes what they show); a view presenting a scene runs its
// frames — the scene's -update:, then the evaluate, simulate and finish
// steps — and then gives each visible sprite and shape a layer, flat under
// the view's own, placed by the node's transform through the scene's scale
// mode and ordered by z position. There are no actions, physics, effects,
// text, video or particles.

// MARK: - Messages

@ObjCWrapper("CAShapeLayer")
class CAShapeLayer: CALayer {
    @ObjCClassMethod("layer") static func makeShape() -> CAShapeLayer
    @ObjCMethod("setPath:") func setPath(_ path: UnsafeMutableRawPointer?)
    @ObjCMethod("setFillColor:") func setFillColor(_ color: UnsafeMutableRawPointer?)
    @ObjCMethod("setStrokeColor:") func setStrokeColor(_ color: UnsafeMutableRawPointer?)
    @ObjCMethod("setLineWidth:") func setLineWidth(_ width: CGFloat)
}

extension NSObject {
    // The layers, as SpriteKit sets them.
    @ObjCMethod("setAnchorPoint:") func skSetAnchorPoint(_ point: CGPoint)
    @ObjCMethod("setContentsRect:") func skSetContentsRect(_ rect: CGRect)
    @ObjCMethod("setMagnificationFilter:") func skSetMagnificationFilter(_ filter: String)
    @ObjCMethod("setMinificationFilter:") func skSetMinificationFilter(_ filter: String)
    @ObjCMethod("setContentsMultiplyColor:") func skSetContentsMultiplyColor(_ color: UnsafeMutableRawPointer?)
    @ObjCMethod("CGColor") func skCGColor() -> UnsafeMutableRawPointer?
    @ObjCMethod("CGImage") func skCGImage() -> UnsafeMutableRawPointer?
    @ObjCMethod("imageNamed:") func skImageNamed(_ name: String) -> NSObject?

    // The scene's and the view's, sent so overrides run.
    @ObjCMethod("update:") func skSendUpdate(_ time: Double)
    @ObjCMethod("didEvaluateActions") func skSendDidEvaluateActions()
    @ObjCMethod("didSimulatePhysics") func skSendDidSimulatePhysics()
    @ObjCMethod("didFinishUpdate") func skSendDidFinishUpdate()
    @ObjCMethod("didMoveToView:") func skSendDidMove(to view: SKView)
    @ObjCMethod("willMoveFromView:") func skSendWillMove(from view: SKView)
    @ObjCMethod("didChangeSize:") func skSendDidChangeSize(_ oldSize: CGSize)
}

// MARK: - Colors and the clock

enum SKSupport {
    nonisolated(unsafe) static var white: CGRef?
    nonisolated(unsafe) static var clear: CGRef?
    nonisolated(unsafe) static var black: CGRef?
    nonisolated(unsafe) static var gray: CGRef?

    /// The CGColor of a UIColor-like object, white without one.
    static func cgColor(_ color: UnsafeMutableRawPointer?) -> CGRef? {
        if let color { return NSObject(color).skCGColor() }
        if white == nil { white = CG.colorCreateSRGB(1, 1, 1, 1) }
        return white
    }

    static var clearColor: CGRef? {
        if clear == nil { clear = CG.colorCreateSRGB(0, 0, 0, 0) }
        return clear
    }

    /// A scene's background when it has none.
    static var grayColor: CGRef? {
        if gray == nil { gray = CG.colorCreateSRGB(0.15, 0.15, 0.15, 1) }
        return gray
    }

    static var blackColor: CGRef? {
        if black == nil { black = CG.colorCreateSRGB(0, 0, 0, 1) }
        return black
    }

    /// Takes a reference to `object` in `slot`, giving up the one it had.
    static func replace(_ slot: inout UnsafeMutableRawPointer?, with object: UnsafeMutableRawPointer?) {
        let kept = object.flatMap { ObjCRuntime.retain($0) }
        let old = slot
        slot = kept
        ObjCRuntime.release(old)
    }

    static func union(_ a: CGRect, _ b: CGRect) -> CGRect {
        let minX = min(a.minX, b.minX), minY = min(a.minY, b.minY)
        return CGRect(x: minX, y: minY, width: max(a.maxX, b.maxX) - minX, height: max(a.maxY, b.maxY) - minY)
    }

    static func now() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }

    /// The scene's coordinates for a node's, and back: from a node to its
    /// scene, without the scene's own anchor shift.
    static func rotationScale(_ node: SKNodeState) -> CGAffineTransform {
        let cosine = CGFloat(cos(Double(node.zRotation))), sine = CGFloat(sin(Double(node.zRotation)))
        return CGAffineTransform(a: cosine * node.xScale, b: sine * node.xScale, c: -sine * node.yScale, d: cosine * node.yScale,
                                 tx: node.position.x, ty: node.position.y)
    }
}

// MARK: - SKTexture

final class SKTextureState: ObjectState {
    /// The picture, retained, and the part of it this is: the unit rectangle
    /// by default, with its origin at the bottom left as SpriteKit's is.
    var image: CGRef?
    var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var filtering = 1   // SKTextureFilteringMode: nearest 0, linear 1
    deinit { if let image { CG.release(image) } }

    var size: CGSize {
        guard let image else { return .zero }
        return CGSize(width: CGFloat(CG.imageGetWidth(image)) * rect.width, height: CGFloat(CG.imageGetHeight(image)) * rect.height)
    }
}

@ObjCClass("SKTexture")
open class SKTexture: NSObject {
    static let states = StateTable<SKTextureState>()
    var state: SKTextureState { SKTexture.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SKTexture.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SKTexture.objCClass.pointer)
    }

    static func make(_ cls: ObjCClass, image: CGRef?) -> SKTexture {
        let texture = cls.object.allocated().unsafeCast(to: SKTexture.self)
        texture.state.image = image.flatMap { ObjCRuntime.retain($0) }
        return texture
    }

    @ObjCClassMethod("textureWithImage:")
    static func texture(_ cls: ObjCClass, image: UIImage?) -> SKTexture { make(cls, image: image?.state.cgImage) }

    @ObjCClassMethod("textureWithCGImage:")
    static func texture(_ cls: ObjCClass, cgImage: UnsafeMutableRawPointer?) -> SKTexture { make(cls, image: cgImage) }

    @ObjCClassMethod("textureWithImageNamed:")
    static func texture(_ cls: ObjCClass, imageNamed name: String) -> SKTexture {
        make(cls, image: ObjCClass(named: "UIImage").object.skImageNamed(name)?.skCGImage())
    }

    @ObjCClassMethod("textureWithRect:inTexture:")
    static func texture(_ cls: ObjCClass, rect: CGRect, in base: SKTexture) -> SKTexture {
        let texture = make(cls, image: base.state.image)
        // The rectangle is in the base's own unit square, which may itself be
        // a part of the picture.
        let outer = base.state.rect
        texture.state.rect = CGRect(x: outer.minX + rect.minX * outer.width, y: outer.minY + rect.minY * outer.height,
                                    width: rect.width * outer.width, height: rect.height * outer.height)
        texture.state.filtering = base.state.filtering
        return texture
    }

    @ObjCMethod("initWithImage:")
    func initialize(image: UIImage?) -> Self {
        state.image = image?.state.cgImage.flatMap { ObjCRuntime.retain($0) }
        return self
    }

    @ObjCMethod("initWithCGImage:")
    func initialize(cgImage: UnsafeMutableRawPointer?) -> Self {
        state.image = cgImage.flatMap { ObjCRuntime.retain($0) }
        return self
    }

    @ObjCMethod("size") func size() -> CGSize { state.size }
    @ObjCMethod("textureRect") func textureRect() -> CGRect { state.rect }
    @ObjCMethod("CGImage") func cgImage() -> UnsafeMutableRawPointer? { state.image }
    @ObjCMethod("filteringMode") func filteringMode() -> Int { state.filtering }
    @ObjCMethod("setFilteringMode:") func setFilteringMode(_ mode: Int) { state.filtering = mode }
    @ObjCMethod("usesMipmaps") func usesMipmaps() -> Bool { false }
    @ObjCMethod("setUsesMipmaps:") func setUsesMipmaps(_ uses: Bool) {}
    @ObjCMethod("preloadWithCompletionHandler:") func preload(completionHandler: ObjCBlock?) {}
    @ObjCClassMethod("preloadTextures:withCompletionHandler:")
    static func preload(_ cls: ObjCClass, textures: NSObject?, completionHandler: ObjCBlock?) {}
}

// MARK: - SKNode

final class SKNodeState: ObjectState {
    var position = CGPoint.zero
    var zPosition: CGFloat = 0
    var zRotation: CGFloat = 0
    var xScale: CGFloat = 1
    var yScale: CGFloat = 1
    var alpha: CGFloat = 1
    var hidden = false
    var paused = false
    var speed: CGFloat = 1
    var userInteractionEnabled = false
    var name: String?
    /// The parent, which retains this node; not retained.
    var parent: UnsafeMutableRawPointer?
    var children: [NSObject] = []

    // A sprite's.
    var texture: SKTexture?
    var size = CGSize.zero
    var anchor = CGPoint(x: 0.5, y: 0.5)
    var color: UnsafeMutableRawPointer?
    var colorBlendFactor: CGFloat = 0
    var blendMode = 0

    // A shape's.
    var path: CGRef?
    var fillColor: UnsafeMutableRawPointer?
    var strokeColor: UnsafeMutableRawPointer?
    var lineWidth: CGFloat = 1
    var glowWidth: CGFloat = 0

    // A scene's.
    var sceneSize = CGSize.zero
    var scaleMode = 0   // SKSceneScaleMode: fill 0, aspectFill 1, aspectFit 2, resizeFill 3
    var sceneAnchor = CGPoint.zero
    var backgroundColor: UnsafeMutableRawPointer?
    var view: UnsafeMutableRawPointer?

    deinit {
        ObjCRuntime.release(color)
        ObjCRuntime.release(fillColor)
        ObjCRuntime.release(strokeColor)
        ObjCRuntime.release(backgroundColor)
        if let path { CG.release(path) }
    }
}

@ObjCClass("SKNode")
open class SKNode: UIResponder {
    static let nodeStates = StateTable<SKNodeState>()
    var node: SKNodeState { SKNode.nodeStates[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        for child in node.children { SKNode.nodeStates.existing(child.objcObject)?.parent = nil }
        SKNode.nodeStates.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SKNode.objCClass.pointer)
    }

    @ObjCClassMethod("node") static func make(_ cls: ObjCClass) -> SKNode { cls.object.allocated().unsafeCast(to: SKNode.self) }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("initWithCoder:") func initialize(coder: NSObject) -> Self { self }

    @ObjCMethod("position") func position() -> CGPoint { node.position }
    @ObjCMethod("setPosition:") func setPosition(_ position: CGPoint) { node.position = position }
    @ObjCMethod("zPosition") func zPosition() -> CGFloat { node.zPosition }
    @ObjCMethod("setZPosition:") func setZPosition(_ z: CGFloat) { node.zPosition = z }
    @ObjCMethod("zRotation") func zRotation() -> CGFloat { node.zRotation }
    @ObjCMethod("setZRotation:") func setZRotation(_ rotation: CGFloat) { node.zRotation = rotation }
    @ObjCMethod("xScale") func xScale() -> CGFloat { node.xScale }
    @ObjCMethod("setXScale:") func setXScale(_ scale: CGFloat) { node.xScale = scale }
    @ObjCMethod("yScale") func yScale() -> CGFloat { node.yScale }
    @ObjCMethod("setYScale:") func setYScale(_ scale: CGFloat) { node.yScale = scale }
    @ObjCMethod("setScale:") func setScale(_ scale: CGFloat) { node.xScale = scale; node.yScale = scale }
    @ObjCMethod("alpha") func alpha() -> CGFloat { node.alpha }
    @ObjCMethod("setAlpha:") func setAlpha(_ alpha: CGFloat) { node.alpha = alpha }
    @ObjCMethod("isHidden") func isHidden() -> Bool { node.hidden }
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool) { node.hidden = hidden }
    @ObjCMethod("isPaused") func isPaused() -> Bool { node.paused }
    @ObjCMethod("setPaused:") func setPaused(_ paused: Bool) { node.paused = paused }
    @ObjCMethod("speed") func speed() -> CGFloat { node.speed }
    @ObjCMethod("setSpeed:") func setSpeed(_ speed: CGFloat) { node.speed = speed }
    @ObjCMethod("isUserInteractionEnabled") func isUserInteractionEnabled() -> Bool { node.userInteractionEnabled }
    @ObjCMethod("setUserInteractionEnabled:") func setUserInteractionEnabled(_ enabled: Bool) { node.userInteractionEnabled = enabled }
    @ObjCMethod("name") func name() -> String? { node.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { node.name = name }
    @ObjCMethod("userData") func userData() -> NSObject? { nil }
    @ObjCMethod("setUserData:") func setUserData(_ data: NSObject?) {}

    @ObjCMethod("parent") func parent() -> SKNode? { node.parent.map { SKNode(objcObject: $0, ownership: .retain) } }
    @ObjCMethod("children") func children() -> NSObject { NSMutableArray.of(node.children) }

    @ObjCMethod("scene")
    func scene() -> SKScene? {
        var current = objcObject
        while let parent = SKNode.nodeStates.existing(current)?.parent { current = parent }
        let top = SKNode(objcObject: current, ownership: .retain)
        return top.as(SKScene.self)
    }

    @ObjCMethod("addChild:")
    func addChild(_ child: SKNode) {
        guard child.objcObject != objcObject, child.node.parent == nil else { return }
        child.node.parent = objcObject
        node.children.append(child)
    }

    @ObjCMethod("insertChild:atIndex:")
    func insertChild(_ child: SKNode, at index: Int) {
        guard child.objcObject != objcObject, child.node.parent == nil else { return }
        child.node.parent = objcObject
        node.children.insert(child, at: min(max(index, 0), node.children.count))
    }

    @ObjCMethod("removeFromParent")
    func removeFromParent() {
        guard let parent = node.parent, let state = SKNode.nodeStates.existing(parent) else { return }
        // The child may be released with the last reference; hold it while it goes.
        let held = SKNode(objcObject: objcObject, ownership: .retain)
        state.children.removeAll { $0.objcObject == held.objcObject }
        node.parent = nil
    }

    @ObjCMethod("removeAllChildren")
    func removeAllChildren() {
        let children = node.children
        node.children = []
        for child in children { SKNode.nodeStates.existing(child.objcObject)?.parent = nil }
    }

    @ObjCMethod("removeChildrenInArray:")
    func removeChildren(in array: NSArray?) {
        for child in array?.elements ?? [] where SKNode.nodeStates.existing(child.objcObject)?.parent == objcObject {
            child.unsafeCast(to: SKNode.self).removeFromParent()
        }
    }

    @ObjCMethod("childNodeWithName:")
    func childNode(withName name: String) -> SKNode? {
        node.children.first { SKNode.nodeStates.existing($0.objcObject)?.name == name }?.unsafeCast(to: SKNode.self)
    }

    @ObjCMethod("inParentHierarchy:")
    func inParentHierarchy(_ ancestor: SKNode) -> Bool {
        var current: UnsafeMutableRawPointer? = objcObject
        while let node = current {
            if node == ancestor.objcObject { return true }
            current = SKNode.nodeStates.existing(node)?.parent
        }
        return false
    }

    // Actions are not run: nothing is ever running, so nodes report none.
    @ObjCMethod("runAction:") func runAction(_ action: NSObject?) {}
    @ObjCMethod("runAction:withKey:") func runAction(_ action: NSObject?, withKey key: String?) {}
    @ObjCMethod("runAction:completion:") func runAction(_ action: NSObject?, completion: ObjCBlock?) {}
    @ObjCMethod("removeAllActions") func removeAllActions() {}
    @ObjCMethod("removeActionForKey:") func removeAction(forKey key: String) {}
    @ObjCMethod("hasActions") func hasActions() -> Bool { false }
    @ObjCMethod("actionForKey:") func action(forKey key: String) -> NSObject? { nil }

    // MARK: Coordinates

    /// From this node's coordinates to its scene's (or its topmost
    /// ancestor's).
    func toScene() -> CGAffineTransform {
        var matrix = CGAffineTransform.identity
        var current: UnsafeMutableRawPointer? = objcObject
        while let object = current, let state = SKNode.nodeStates.existing(object) {
            if state.parent != nil || !(SKNode(objcObject: object, ownership: .retain).is(SKScene.self)) {
                matrix = matrix.concatenating(SKSupport.rotationScale(state))
            }
            current = state.parent
        }
        return matrix
    }

    @ObjCMethod("convertPoint:fromNode:")
    func convertPoint(_ point: CGPoint, from other: SKNode) -> CGPoint {
        toScene().inverted.apply(other.toScene().apply(point))
    }

    @ObjCMethod("convertPoint:toNode:")
    func convertPoint(_ point: CGPoint, to other: SKNode) -> CGPoint {
        other.toScene().inverted.apply(toScene().apply(point))
    }

    @ObjCMethod("containsPoint:")
    func contains(_ point: CGPoint) -> Bool { calculateAccumulatedFrame().contains(point) }

    /// The frame of the node's own picture or path in its parent's
    /// coordinates, with its children's.
    @ObjCMethod("calculateAccumulatedFrame")
    func calculateAccumulatedFrame() -> CGRect {
        var frame = ownFrame()
        for child in node.children {
            let childFrame = child.unsafeCast(to: SKNode.self).calculateAccumulatedFrame()
            guard childFrame.width > 0 || childFrame.height > 0 else { continue }
            frame = frame.width > 0 || frame.height > 0 ? SKSupport.union(frame, childFrame) : childFrame
        }
        return frame
    }

    @ObjCMethod("frame") func frame() -> CGRect { ownFrame() }

    func ownFrame() -> CGRect {
        let state = node
        let local: CGRect
        if state.texture != nil || state.size != .zero {
            local = CGRect(x: -state.anchor.x * state.size.width, y: -state.anchor.y * state.size.height,
                           width: state.size.width, height: state.size.height)
        } else if let path = state.path {
            local = CG.pathGetBoundingBox(path)
        } else {
            return CGRect(origin: state.position, size: .zero)
        }
        return SKSupport.rotationScale(state).apply(local)
    }
}

// MARK: - SKSpriteNode

@ObjCClass("SKSpriteNode")
open class SKSpriteNode: SKNode {
    private func configure(texture: SKTexture?, size: CGSize, color: UnsafeMutableRawPointer? = nil) {
        node.texture = texture
        node.size = size
        if let color { SKSupport.replace(&node.color, with: color); node.colorBlendFactor = 0 }
    }

    private static func make(_ cls: ObjCClass, texture: SKTexture?, size: CGSize?, color: UnsafeMutableRawPointer? = nil) -> SKSpriteNode {
        let sprite = cls.object.allocated().unsafeCast(to: SKSpriteNode.self)
        sprite.configure(texture: texture, size: size ?? texture?.state.size ?? .zero, color: color)
        return sprite
    }

    @ObjCClassMethod("spriteNodeWithTexture:")
    static func sprite(_ cls: ObjCClass, texture: SKTexture?) -> SKSpriteNode { make(cls, texture: texture, size: nil) }
    @ObjCClassMethod("spriteNodeWithTexture:size:")
    static func sprite(_ cls: ObjCClass, texture: SKTexture?, size: CGSize) -> SKSpriteNode { make(cls, texture: texture, size: size) }
    @ObjCClassMethod("spriteNodeWithImageNamed:")
    static func sprite(_ cls: ObjCClass, imageNamed name: String) -> SKSpriteNode {
        make(cls, texture: SKTexture.texture(SKTexture.objCClass, imageNamed: name), size: nil)
    }
    @ObjCClassMethod("spriteNodeWithColor:size:")
    static func sprite(_ cls: ObjCClass, color: NSObject?, size: CGSize) -> SKSpriteNode {
        make(cls, texture: nil, size: size, color: color?.objcObject)
    }

    @ObjCMethod("initWithTexture:") func initialize(texture: SKTexture?) -> Self {
        configure(texture: texture, size: texture?.state.size ?? .zero)
        return self
    }
    @ObjCMethod("initWithTexture:size:") func initialize(texture: SKTexture?, size: CGSize) -> Self {
        configure(texture: texture, size: size)
        return self
    }
    @ObjCMethod("initWithTexture:color:size:") func initialize(texture: SKTexture?, color: NSObject?, size: CGSize) -> Self {
        configure(texture: texture, size: size, color: color?.objcObject)
        return self
    }
    @ObjCMethod("initWithImageNamed:") func initialize(imageNamed name: String) -> Self {
        let texture = SKTexture.texture(SKTexture.objCClass, imageNamed: name)
        configure(texture: texture, size: texture.state.size)
        return self
    }
    @ObjCMethod("initWithColor:size:") func initialize(color: NSObject?, size: CGSize) -> Self {
        configure(texture: nil, size: size, color: color?.objcObject)
        return self
    }

    @ObjCMethod("texture") func texture() -> SKTexture? { node.texture }
    @ObjCMethod("setTexture:") func setTexture(_ texture: SKTexture?) { node.texture = texture }
    @ObjCMethod("size") func size() -> CGSize { node.size }
    @ObjCMethod("setSize:") func setSize(_ size: CGSize) { node.size = size }
    @ObjCMethod("anchorPoint") func anchorPoint() -> CGPoint { node.anchor }
    @ObjCMethod("setAnchorPoint:") func setAnchorPoint(_ point: CGPoint) { node.anchor = point }
    @ObjCMethod("color") func color() -> NSObject? { node.color.map { NSObject($0) } }
    @ObjCMethod("setColor:") func setColor(_ color: NSObject?) { SKSupport.replace(&node.color, with: color?.objcObject) }
    @ObjCMethod("colorBlendFactor") func colorBlendFactor() -> CGFloat { node.colorBlendFactor }
    @ObjCMethod("setColorBlendFactor:") func setColorBlendFactor(_ factor: CGFloat) { node.colorBlendFactor = factor }
    @ObjCMethod("blendMode") func blendMode() -> Int { node.blendMode }
    @ObjCMethod("setBlendMode:") func setBlendMode(_ mode: Int) { node.blendMode = mode }
}

// MARK: - SKShapeNode

@ObjCClass("SKShapeNode")
open class SKShapeNode: SKNode {
    private static func make(_ cls: ObjCClass, path: CGRef?) -> SKShapeNode {
        let shape = cls.object.allocated().unsafeCast(to: SKShapeNode.self)
        shape.setPath(path)
        return shape
    }

    private static func rectPath(_ rect: CGRect) -> CGRef? {
        let path = CG.pathCreateMutable()
        CG.pathAddRect(path, nil, rect)
        return path
    }

    private static func ellipsePath(_ rect: CGRect) -> CGRef? {
        let path = CG.pathCreateMutable()
        CG.pathAddEllipseInRect(path, nil, rect)
        return path
    }

    @ObjCClassMethod("shapeNodeWithPath:")
    static func shape(_ cls: ObjCClass, path: UnsafeMutableRawPointer?) -> SKShapeNode { make(cls, path: path) }
    @ObjCClassMethod("shapeNodeWithRect:")
    static func shape(_ cls: ObjCClass, rect: CGRect) -> SKShapeNode { make(cls, path: rectPath(rect)) }
    @ObjCClassMethod("shapeNodeWithRectOfSize:")
    static func shape(_ cls: ObjCClass, rectOfSize size: CGSize) -> SKShapeNode {
        make(cls, path: rectPath(CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)))
    }
    @ObjCClassMethod("shapeNodeWithCircleOfRadius:")
    static func shape(_ cls: ObjCClass, circleOfRadius radius: CGFloat) -> SKShapeNode {
        make(cls, path: ellipsePath(CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)))
    }
    @ObjCClassMethod("shapeNodeWithEllipseInRect:")
    static func shape(_ cls: ObjCClass, ellipseIn rect: CGRect) -> SKShapeNode { make(cls, path: ellipsePath(rect)) }
    @ObjCClassMethod("shapeNodeWithEllipseOfSize:")
    static func shape(_ cls: ObjCClass, ellipseOfSize size: CGSize) -> SKShapeNode {
        make(cls, path: ellipsePath(CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)))
    }

    @ObjCMethod("path") func path() -> UnsafeMutableRawPointer? { node.path }

    @ObjCMethod("setPath:")
    func setPath(_ path: UnsafeMutableRawPointer?) {
        let kept = path.flatMap { ObjCRuntime.retain($0) }
        if let old = node.path { CG.release(old) }
        node.path = kept
    }

    @ObjCMethod("fillColor") func fillColor() -> NSObject? { node.fillColor.map { NSObject($0) } }
    @ObjCMethod("setFillColor:") func setFillColor(_ color: NSObject?) { SKSupport.replace(&node.fillColor, with: color?.objcObject) }
    @ObjCMethod("strokeColor") func strokeColor() -> NSObject? { node.strokeColor.map { NSObject($0) } }
    @ObjCMethod("setStrokeColor:") func setStrokeColor(_ color: NSObject?) { SKSupport.replace(&node.strokeColor, with: color?.objcObject) }
    @ObjCMethod("lineWidth") func lineWidth() -> CGFloat { node.lineWidth }
    @ObjCMethod("setLineWidth:") func setLineWidth(_ width: CGFloat) { node.lineWidth = width }
    @ObjCMethod("glowWidth") func glowWidth() -> CGFloat { node.glowWidth }
    @ObjCMethod("setGlowWidth:") func setGlowWidth(_ width: CGFloat) { node.glowWidth = width }
    @ObjCMethod("isAntialiased") func isAntialiased() -> Bool { true }
    @ObjCMethod("setAntialiased:") func setAntialiased(_ antialiased: Bool) {}
}

// MARK: - SKScene

@ObjCClass("SKScene")
open class SKScene: SKNode {
    @ObjCClassMethod("sceneWithSize:")
    static func scene(_ cls: ObjCClass, size: CGSize) -> SKScene {
        let scene = cls.object.allocated().unsafeCast(to: SKScene.self)
        scene.node.sceneSize = size
        return scene
    }

    @ObjCMethod("initWithSize:")
    func initialize(size: CGSize) -> Self {
        node.sceneSize = size
        return self
    }

    @ObjCMethod("size") func size() -> CGSize { node.sceneSize }

    @ObjCMethod("setSize:")
    func setSize(_ size: CGSize) {
        let old = node.sceneSize
        guard old != size else { return }
        node.sceneSize = size
        skSendDidChangeSize(old)
    }

    @ObjCMethod("scaleMode") func scaleMode() -> Int { node.scaleMode }
    @ObjCMethod("setScaleMode:") func setScaleMode(_ mode: Int) { node.scaleMode = mode }
    @ObjCMethod("anchorPoint") func anchorPoint() -> CGPoint { node.sceneAnchor }
    @ObjCMethod("setAnchorPoint:") func setAnchorPoint(_ point: CGPoint) { node.sceneAnchor = point }
    @ObjCMethod("backgroundColor") func backgroundColor() -> NSObject? { node.backgroundColor.map { NSObject($0) } }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSObject?) {
        SKSupport.replace(&node.backgroundColor, with: color?.objcObject)
    }
    @ObjCMethod("view") func view() -> SKView? {
        node.view.map { UIView.wrap($0).unsafeCast(to: SKView.self) }
    }
    // The steps of a frame, empty for a scene to override.
    @ObjCMethod("update:") func update(_ time: Double) {}
    @ObjCMethod("didEvaluateActions") func didEvaluateActions() {}
    @ObjCMethod("didSimulatePhysics") func didSimulatePhysics() {}
    @ObjCMethod("didFinishUpdate") func didFinishUpdate() {}
    @ObjCMethod("didMoveToView:") func didMove(to view: SKView) {}
    @ObjCMethod("willMoveFromView:") func willMove(from view: SKView) {}
    @ObjCMethod("didChangeSize:") func didChangeSize(_ oldSize: CGSize) {}
    @ObjCMethod("camera") func camera() -> NSObject? { nil }
    @ObjCMethod("delegate") func delegate() -> NSObject? { nil }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) {}

    /// From the scene's coordinates to the view's, under the scale mode.
    func sceneToView(bounds: CGSize) -> CGAffineTransform {
        let size = node.sceneSize
        guard size.width > 0, size.height > 0 else { return .identity }
        var sx = bounds.width / size.width, sy = bounds.height / size.height
        switch node.scaleMode {
        case 1: sx = max(sx, sy); sy = sx
        case 2: sx = min(sx, sy); sy = sx
        case 3: sx = 1; sy = 1
        default: break
        }
        let ox = (bounds.width - size.width * sx) / 2, oy = (bounds.height - size.height * sy) / 2
        let anchor = node.sceneAnchor
        return CGAffineTransform(a: sx, b: 0, c: 0, d: -sy, tx: ox + sx * anchor.x * size.width,
                                 ty: oy + sy * (size.height - anchor.y * size.height))
    }

    @ObjCMethod("convertPointFromView:")
    func convertPoint(fromView point: CGPoint) -> CGPoint {
        guard let view = node.view.map({ UIView.wrap($0).unsafeCast(to: SKView.self) }) else { return point }
        return sceneToView(bounds: view.state.bounds.size).inverted.apply(point)
    }

    @ObjCMethod("convertPointToView:")
    func convertPoint(toView point: CGPoint) -> CGPoint {
        guard let view = node.view.map({ UIView.wrap($0).unsafeCast(to: SKView.self) }) else { return point }
        return sceneToView(bounds: view.state.bounds.size).apply(point)
    }
}

// MARK: - SKView

final class SKViewState: ObjectState {
    var scene: SKScene?
    var ignoresSiblingOrder = false
    var paused = false
    var framesPerSecond = 60
    var running = false
    var showsFPS = false, showsNodeCount = false, showsDrawCount = false, showsPhysics = false
    var allowsTransparency = false
    /// The background, drawn over the scene's rectangle, and the layer of
    /// each node shown last frame.
    var background: CALayer?
    var layers: [UnsafeMutableRawPointer: (layer: CALayer, shape: Bool)] = [:]
}

@ObjCClass("SKView")
open class SKView: UIView {
    static let skStates = StateTable<SKViewState>()
    var sk: SKViewState { SKView.skStates[objcObject] }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        state.geometry.masksToBounds = true
        state.geometry.backgroundColor = SKSupport.blackColor
        return self
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        state.geometry.masksToBounds = true
        state.geometry.backgroundColor = SKSupport.blackColor
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        Frames.remove(sk)
        SKView.skStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("scene") func scene() -> SKScene? { sk.scene }
    @ObjCMethod("ignoresSiblingOrder") func ignoresSiblingOrder() -> Bool { sk.ignoresSiblingOrder }
    @ObjCMethod("setIgnoresSiblingOrder:") func setIgnoresSiblingOrder(_ ignores: Bool) { sk.ignoresSiblingOrder = ignores }
    @ObjCMethod("showsFPS") func showsFPS() -> Bool { sk.showsFPS }
    @ObjCMethod("setShowsFPS:") func setShowsFPS(_ shows: Bool) { sk.showsFPS = shows }
    @ObjCMethod("showsNodeCount") func showsNodeCount() -> Bool { sk.showsNodeCount }
    @ObjCMethod("setShowsNodeCount:") func setShowsNodeCount(_ shows: Bool) { sk.showsNodeCount = shows }
    @ObjCMethod("showsDrawCount") func showsDrawCount() -> Bool { sk.showsDrawCount }
    @ObjCMethod("setShowsDrawCount:") func setShowsDrawCount(_ shows: Bool) { sk.showsDrawCount = shows }
    @ObjCMethod("showsPhysics") func showsPhysics() -> Bool { sk.showsPhysics }
    @ObjCMethod("setShowsPhysics:") func setShowsPhysics(_ shows: Bool) { sk.showsPhysics = shows }
    @ObjCMethod("showsFields") func showsFields() -> Bool { false }
    @ObjCMethod("setShowsFields:") func setShowsFields(_ shows: Bool) {}
    @ObjCMethod("allowsTransparency") func allowsTransparency() -> Bool { sk.allowsTransparency }
    @ObjCMethod("setAllowsTransparency:") func setAllowsTransparency(_ allows: Bool) { sk.allowsTransparency = allows }
    @ObjCMethod("shouldCullNonVisibleNodes") func shouldCullNonVisibleNodes() -> Bool { true }
    @ObjCMethod("setShouldCullNonVisibleNodes:") func setShouldCullNonVisibleNodes(_ cull: Bool) {}
    @ObjCMethod("isAsynchronous") func isAsynchronous() -> Bool { true }
    @ObjCMethod("setAsynchronous:") func setAsynchronous(_ asynchronous: Bool) {}
    @ObjCMethod("disableDepthStencilBuffer") func disableDepthStencilBuffer() -> Bool { true }
    @ObjCMethod("setDisableDepthStencilBuffer:") func setDisableDepthStencilBuffer(_ disable: Bool) {}
    @ObjCMethod("isPaused") func isPaused() -> Bool { sk.paused }
    @ObjCMethod("setPaused:") func setPaused(_ paused: Bool) { sk.paused = paused }
    @ObjCMethod("frameInterval") func frameInterval() -> Int { max(60 / sk.framesPerSecond, 1) }
    @ObjCMethod("setFrameInterval:") func setFrameInterval(_ interval: Int) { sk.framesPerSecond = 60 / max(interval, 1); restartFrames() }
    @ObjCMethod("preferredFramesPerSecond") func preferredFramesPerSecond() -> Int { sk.framesPerSecond }
    @ObjCMethod("setPreferredFramesPerSecond:") func setPreferredFramesPerSecond(_ rate: Int) {
        sk.framesPerSecond = min(max(rate, 1), 60)
        restartFrames()
    }

    @ObjCMethod("presentScene:")
    func presentScene(_ scene: SKScene?) {
        if let old = sk.scene {
            old.skSendWillMove(from: self)
            old.node.view = nil
        }
        removeLayers()
        sk.scene = scene
        guard let scene else {
            stopFrames()
            return
        }
        scene.node.view = objcObject
        if scene.node.scaleMode == 3 { scene.setSize(state.bounds.size) }
        scene.skSendDidMove(to: self)
        restartFrames()
    }

    @ObjCMethod("presentScene:transition:")
    func presentScene(_ scene: SKScene?, transition: NSObject?) { presentScene(scene) }

    @ObjCMethod("convertPoint:toScene:")
    func convertPoint(_ point: CGPoint, to scene: SKScene) -> CGPoint { scene.convertPoint(fromView: point) }

    @ObjCMethod("convertPoint:fromScene:")
    func convertPoint(_ point: CGPoint, from scene: SKScene) -> CGPoint { scene.convertPoint(toView: point) }

    @ObjCMethod("textureFromNode:") func texture(from node: SKNode) -> SKTexture? { nil }

    // MARK: Touches

    @ObjCMethod("touchesBegan:withEvent:")
    func touchesBeganInScene(_ touches: NSObject, with event: NSObject?) { sk.scene?.sendTouchesBegan(touches, with: event) }
    @ObjCMethod("touchesMoved:withEvent:")
    func touchesMovedInScene(_ touches: NSObject, with event: NSObject?) { sk.scene?.sendTouchesMoved(touches, with: event) }
    @ObjCMethod("touchesEnded:withEvent:")
    func touchesEndedInScene(_ touches: NSObject, with event: NSObject?) { sk.scene?.sendTouchesEnded(touches, with: event) }
    @ObjCMethod("touchesCancelled:withEvent:")
    func touchesCancelledInScene(_ touches: NSObject, with event: NSObject?) { sk.scene?.sendTouchesCancelled(touches, with: event) }

    // MARK: Frames

    private func restartFrames() {
        stopFrames()
        guard sk.scene != nil else { return }
        sk.running = true
        let object = objcObject
        Frames.add(sk, framesPerSecond: sk.framesPerSecond) { _ in
            UIView.wrap(object).unsafeCast(to: SKView.self).runFrame()
        }
    }

    private func stopFrames() {
        guard sk.running else { return }
        sk.running = false
        Frames.remove(sk)
    }

    /// One frame: the scene's steps, then the layers.
    func runFrame() {
        guard let scene = sk.scene, !sk.paused, !scene.node.paused else { return }
        if scene.node.scaleMode == 3 { scene.setSize(state.bounds.size) }
        scene.skSendUpdate(SKSupport.now())
        scene.skSendDidEvaluateActions()
        scene.skSendDidSimulatePhysics()
        scene.skSendDidFinishUpdate()
        render(scene)
    }

    // MARK: Layers

    private func removeLayers() {
        for entry in sk.layers.values { entry.layer.removeFromSuperlayer() }
        sk.layers = [:]
        sk.background?.removeFromSuperlayer()
        sk.background = nil
    }

    private struct Visible {
        let node: SKNode
        let matrix: CGAffineTransform
        let alpha: CGFloat
        let z: CGFloat
    }

    private func collect(_ node: SKNode, parent: CGAffineTransform, alpha: CGFloat, z: CGFloat, into list: inout [Visible], isScene: Bool) {
        let state = node.node
        guard !state.hidden, state.alpha > 0 else { return }
        let matrix = isScene ? parent : SKSupport.rotationScale(state).concatenating(parent)
        let alpha = alpha * (isScene ? 1 : state.alpha)
        let z = z + (isScene ? 0 : state.zPosition)
        if node.is(SKSpriteNode.self) || node.is(SKShapeNode.self) { list.append(Visible(node: node, matrix: matrix, alpha: alpha, z: z)) }
        for child in state.children { collect(child.unsafeCast(to: SKNode.self), parent: matrix, alpha: alpha, z: z, into: &list, isScene: false) }
    }

    private func render(_ scene: SKScene) {
        let viewTransform = scene.sceneToView(bounds: state.bounds.size)
        var visible: [Visible] = []
        collect(scene, parent: viewTransform, alpha: 1, z: 0, into: &visible, isScene: true)
        // Back to front; nodes at the same depth keep the tree's order.
        let ordered = visible.enumerated().sorted { ($0.element.z, $0.offset) < ($1.element.z, $1.offset) }.map(\.element)

        updateBackground(scene, viewTransform)
        var seen = Set<UnsafeMutableRawPointer>()
        for (index, item) in ordered.enumerated() {
            let object = item.node.objcObject
            let shape = item.node.is(SKShapeNode.self)
            seen.insert(object)
            var entry = sk.layers[object]
            if entry == nil || entry!.shape != shape {
                entry?.layer.removeFromSuperlayer()
                let layer: CALayer = shape ? CAShapeLayer.makeShape() : CALayer.make()
                if shape { layer.skSetAnchorPoint(.zero) }
                state.layer.addSublayer(layer)
                entry = (layer, shape)
                sk.layers[object] = entry
            }
            let layer = entry!.layer
            layer.setZPosition(CGFloat(index + 1))
            layer.setOpacity(Float(item.alpha))
            if shape {
                update(shape: item.node.node, layer: layer.unsafeCast(to: CAShapeLayer.self), matrix: item.matrix)
            } else {
                update(sprite: item.node.node, layer: layer, matrix: item.matrix)
            }
        }
        for (object, entry) in sk.layers where !seen.contains(object) {
            entry.layer.removeFromSuperlayer()
            sk.layers[object] = nil
        }
    }

    private func updateBackground(_ scene: SKScene, _ viewTransform: CGAffineTransform) {
        if sk.background == nil {
            let layer = CALayer.make()
            layer.setZPosition(0)
            state.layer.addSublayer(layer)
            sk.background = layer
        }
        let size = scene.node.sceneSize, anchor = scene.node.sceneAnchor
        let rect = viewTransform.apply(CGRect(x: -anchor.x * size.width, y: -anchor.y * size.height, width: size.width, height: size.height))
        let layer = sk.background!
        layer.setBounds(CGRect(origin: .zero, size: rect.size))
        layer.setPosition(CGPoint(x: rect.midX, y: rect.midY))
        // A scene with no background color is gray, as SpriteKit's is.
        layer.setBackgroundColor(scene.node.backgroundColor.map { SKSupport.cgColor($0) } ?? SKSupport.grayColor)
    }

    /// A sprite: its layer is as big as the sprite and centered on its
    /// middle, turned and scaled by the node's matrix with the vertical flip
    /// between SpriteKit's up and the layer's down.
    private func update(sprite node: SKNodeState, layer: CALayer, matrix: CGAffineTransform) {
        let size = node.size
        let center = matrix.apply(CGPoint(x: (0.5 - node.anchor.x) * size.width, y: (0.5 - node.anchor.y) * size.height))
        layer.setBounds(CGRect(origin: .zero, size: size))
        layer.setPosition(center)
        let linear = CGAffineTransform(a: matrix.a, b: matrix.b, c: matrix.c, d: matrix.d, tx: 0, ty: 0)
        layer.setAffineTransform(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0).concatenating(linear))
        if let texture = node.texture, let image = texture.state.image {
            let rect = texture.state.rect
            layer.setContents(NSObject(image))
            // The texture's rectangle starts at the bottom left; the layer's at the top left.
            layer.skSetContentsRect(CGRect(x: rect.minX, y: 1 - rect.minY - rect.height, width: rect.width, height: rect.height))
            let filter = texture.state.filtering == 0 ? "nearest" : "linear"
            layer.skSetMagnificationFilter(filter)
            layer.skSetMinificationFilter(filter)
            layer.setBackgroundColor(nil)
            layer.skSetContentsMultiplyColor(node.colorBlendFactor > 0 ? SKSupport.cgColor(node.color) : nil)
        } else {
            layer.setContents(nil)
            layer.skSetContentsMultiplyColor(nil)
            layer.setBackgroundColor(SKSupport.cgColor(node.color))
        }
    }

    /// A shape: the path is in the node's own Y-up coordinates and the layer
    /// is at the node's origin, turned and scaled by the matrix.
    private func update(shape node: SKNodeState, layer: CAShapeLayer, matrix: CGAffineTransform) {
        layer.setBounds(CGRect(x: 0, y: 0, width: 1, height: 1))
        layer.setPosition(matrix.apply(.zero))
        // The path is already in the node's up-pointing coordinates, which the matrix takes down.
        layer.setAffineTransform(CGAffineTransform(a: matrix.a, b: matrix.b, c: matrix.c, d: matrix.d, tx: 0, ty: 0))
        layer.setPath(node.path)
        layer.setFillColor(node.fillColor.map { SKSupport.cgColor($0) } ?? SKSupport.clearColor)
        layer.setStrokeColor(node.strokeColor.map { SKSupport.cgColor($0) } ?? SKSupport.cgColor(nil))
        layer.setLineWidth(node.lineWidth)
    }
}

// MARK: - Touches in nodes

@ObjCCategory("SKNodeTouchLocation")
extension UITouch {
    @ObjCMethod("locationInNode:")
    func location(in node: SKNode) -> CGPoint { sceneLocation(state.location, in: node) }

    @ObjCMethod("previousLocationInNode:")
    func previousLocation(in node: SKNode) -> CGPoint { sceneLocation(state.previous, in: node) }

    /// A window point as the node's: through the view's scene.
    private func sceneLocation(_ window: CGPoint, in node: SKNode) -> CGPoint {
        guard let scene = node.scene(), let view = scene.view() else { return window }
        let inView = view.convert(window, from: state.window)
        let inScene = scene.convertPoint(fromView: inView)
        return node.objcObject == scene.objcObject ? inScene : node.convertPoint(inScene, from: scene)
    }
}
