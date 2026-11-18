import CPerryGeometry
import FoundationEssentials
import Glibc
import PerryObjCInterop

// UIKit's deferred work, done once the current event or timer callback
// returns, as Darwin does when Core Animation commits its transaction:
// navigation and presentation transitions, then the ends of appearance
// transitions begun since, then layout of the visible windows. Work is
// queued on the main dispatch queue, which the main run loop drains.

enum Updates {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias DispatchAsync = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    nonisolated(unsafe) static var dispatchAsync: DispatchAsync!
    nonisolated(unsafe) static var mainQueue: UnsafeMutableRawPointer?

    nonisolated(unsafe) private static var scheduled = false
    /// Transitions to run, in the order they were asked for.
    nonisolated(unsafe) private static var transitions: [() -> Void] = []
    /// View controllers whose appearance transitions end in the pass.
    nonisolated(unsafe) private static var appearanceEnds: [UIViewController] = []
    /// Work for once the pass is over.
    nonisolated(unsafe) private static var afterwards: [() -> Void] = []

    static func load(_ lookup: (String, String) -> UnsafeMutableRawPointer?) -> Bool {
        let library = "/usr/lib/system/libdispatch.dylib"
        guard let async = lookup(library, "_dispatch_async_f"), let main = lookup(library, "__dispatch_main_q") else { return false }
        dispatchAsync = unsafeBitCast(async, to: DispatchAsync.self)
        mainQueue = main
        return true
    }

    /// Runs the pass soon, once.
    static func schedule() {
        guard !scheduled else { return }
        scheduled = true
        dispatchAsync(mainQueue, nil) { _ in Updates.run() }
    }

    /// Adds a transition to the next pass.
    static func transition(_ body: @escaping () -> Void) {
        transitions.append(body)
        schedule()
    }

    /// Ends `controller`'s appearance transition in the next pass.
    static func endAppearance(of controller: UIViewController) {
        appearanceEnds.append(controller)
        schedule()
    }

    /// Runs `body` once the next pass is over.
    static func afterPass(_ body: @escaping () -> Void) {
        afterwards.append(body)
        schedule()
    }

    /// Whether `controller` waits for its appearance transition to end.
    static func isPendingEnd(_ controller: UIViewController) -> Bool {
        appearanceEnds.contains { $0.objcObject == controller.objcObject }
    }

    static func run() {
        FrameWork.passes += 1
        let start = Clock.now
        defer { FrameWork.passTime += Clock.now - start }
        scheduled = false
        ObjCRuntime.autoreleasepool {
            while !transitions.isEmpty || !appearanceEnds.isEmpty {
                if !transitions.isEmpty {
                    let transition = transitions.removeFirst()
                    transition()
                    continue
                }
                let controller = appearanceEnds.removeFirst()
                controller.finishAppearance()
            }
            for window in Windows.visible { window.layoutIfNeeded() }
        }
        let after = afterwards
        afterwards = []
        for body in after { ObjCRuntime.autoreleasepool { body() } }
        Snapshot.requestWrite()
        Display.markDirty()
    }
}

/// With PERRY_UIKIT_SNAPSHOT set to a path, the visible windows are
/// written there as a PNG at the screen's scale after update passes and
/// changes to layers, to look at what an app shows without a display;
/// with PERRY_UIKIT_SNAPSHOT_STEPS as well, only after the tap script's
/// steps.
enum Snapshot {
    nonisolated(unsafe) static let path: String? = getenv("PERRY_UIKIT_SNAPSHOT").map { String(cString: $0) }

    static func writeIfRequested() {
        guard let path else { return }
        write(to: path)
    }

    /// PERRY_UIKIT_SNAPSHOT_STEPS: only the numbered snapshots of the tap
    /// script's steps are written. One a second, each encoded on the main
    /// thread, stalls a game that draws every frame.
    private static let stepsOnly = getenv("PERRY_UIKIT_SNAPSHOT_STEPS") != nil

    nonisolated(unsafe) private static var requested = false

    /// Writes the snapshot a second after an update pass or a change to
    /// layers, at most once a second: encoding it is slow. The numbered
    /// snapshots are written when they are due.
    static func requestWrite() {
        guard path != nil, !requested, !stepsOnly else { return }
        requested = true
        Deferred.run(after: 1) {
            Snapshot.requested = false
            ObjCRuntime.autoreleasepool { Snapshot.writeIfRequested() }
        }
    }

    /// The image beside the latest, numbered: "shot.png" and 3 make
    /// "shot-3.png".
    static func writeNumbered(_ number: Int) {
        guard let path else { return }
        let stem = path.hasSuffix(".png") ? String(path.dropLast(4)) : path
        write(to: "\(stem)-\(number).png")
    }

    static func write(to path: String) {
        guard !Windows.visible.isEmpty,
              let context = CG.makeContext(size: Screen.bounds.size, scale: Screen.scale, opaque: true) else { return }
        defer { CG.release(context) }
        let black = UIColor.black()
        withExtendedLifetime(black) {
            CG.setFillColorWithColor(context, black.state.makeCGColor())
            CG.fillRect(context, Screen.bounds)
        }
        for window in Windows.visible {
            window.layoutIfNeeded()
            CG.saveGState(context)
            CG.concatCTM(context, window.state.geometry.toSuperlayer)
            window.state.layer.render(in: context)
            CG.restoreGState(context)
        }
        guard let image = CG.bitmapContextCreateImage(context) else { return }
        defer { CG.release(image) }
        UIImage.encode(image, type: "public.png")?.sendWrite(toFile: path, atomically: true)
        writeView(beside: path)
        var tree = ""
        for window in Windows.visible { describe(window, depth: 0, into: &tree) }
        FileManager.default.createFile(atPath: path + ".txt", contents: Data(tree.utf8))
    }

    /// PERRY_UIKIT_SNAPSHOT_VIEW, a class name or part of one: the first
    /// such view in the windows is also written alone, with its subviews,
    /// on gray, as "shot-view.png", to see what it draws apart from what
    /// is around and over it.
    private static let viewName = getenv("PERRY_UIKIT_SNAPSHOT_VIEW").map { String(cString: $0) }

    private static func writeView(beside path: String) {
        guard let viewName else { return }
        func find(_ view: UIView) -> UIView? {
            let name = ObjCRuntime.objectClass(view.objcObject).flatMap { NSObject($0).describedByObject() } ?? ""
            if name.contains(viewName) { return view }
            for subview in view.state.subviews { if let found = find(subview) { return found } }
            return nil
        }
        guard let view = Windows.visible.lazy.compactMap({ find($0) }).first else { return }
        let bounds = view.state.bounds
        guard bounds.width > 0, bounds.height > 0,
              let context = CG.makeContext(size: bounds.size, scale: Screen.scale, opaque: true) else { return }
        defer { CG.release(context) }
        let gray = UIColor.gray(0.5)
        withExtendedLifetime(gray) {
            CG.setFillColorWithColor(context, gray.state.makeCGColor())
            CG.fillRect(context, CGRect(origin: .zero, size: bounds.size))
        }
        CG.translateCTM(context, -bounds.minX, -bounds.minY)
        view.state.layer.render(in: context)
        guard let image = CG.bitmapContextCreateImage(context) else { return }
        defer { CG.release(image) }
        let stem = path.hasSuffix(".png") ? String(path.dropLast(4)) : path
        UIImage.encode(image, type: "public.png")?.sendWrite(toFile: stem + "-view.png", atomically: true)
    }

    /// The view tree beside the image: each view's class, frame, bounds
    /// origin when scrolled, how its layer clips, its alpha when below 1, a
    /// transform, its layer's z position, frame where that differs and class
    /// where it has one of its own, an image view's image and whether it
    /// is hidden.
    /// An object's class by its description, or by the runtime's name for
    /// it when the description gives none (a generic Swift class's).
    static func className(_ object: UnsafeMutableRawPointer) -> String {
        guard let cls = ObjCRuntime.objectClass(object) else { return "?" }
        if let name = NSObject(cls).describedByObject() { return name }
        typealias GetName = @convention(c) (UnsafeMutableRawPointer) -> UnsafePointer<CChar>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: 0), "_class_getName") ?? dlsym(UnsafeMutableRawPointer(bitPattern: 0), "class_getName"),
              let name = unsafeBitCast(symbol, to: GetName.self)(cls) else { return "?" }
        return String(cString: name)
    }

    private static func describe(_ view: UIView, depth: Int, into tree: inout String) {
        let name = className(view.objcObject)
        let frame = view.state.frame
        tree += String(repeating: "  ", count: depth) + "\(name) (\(frame.minX), \(frame.minY), \(frame.width), \(frame.height))"
        let origin = view.state.bounds.origin
        if origin != .zero { tree += " bounds origin (\(origin.x), \(origin.y))" }
        if let geometry = view.state.geometry {
            if geometry.opacity < 1 { tree += " alpha \(geometry.opacity)" }
            if geometry.masksToBounds { tree += " clips" }
            if geometry.cornerRadius > 0 { tree += " radius \(geometry.cornerRadius)" }
            if geometry.layer.mask() != nil { tree += " masked" }
            if let presented = geometry.layer.presentationLayer() {
                let model = geometry.layer
                if presented.frame() != model.frame() { tree += " presented \(presented.frame())" }
                if presented.bounds() != model.bounds() { tree += " presented bounds \(presented.bounds())" }
                if presented.opacity() != model.opacity() { tree += " presented alpha \(presented.opacity())" }
                if presented.masksToBounds() != model.masksToBounds() { tree += " presented clips \(presented.masksToBounds())" }
            }
        }
        if let t = view.state.geometry?.transform, (t.a, t.b, t.c, t.d, t.tx, t.ty) != (1, 0, 0, 1, 0, 0) {
            tree += " transform [\(t.a) \(t.b) \(t.c) \(t.d) \(t.tx) \(t.ty)]"
        }
        if let layer = view.state.layer {
            if layer.zPosition() != 0 { tree += " z \(layer.zPosition())" }
            let actual = layer.frame()
            if abs(actual.minX - frame.minX) + abs(actual.minY - frame.minY) + abs(actual.width - frame.width)
                + abs(actual.height - frame.height) > 0.01 {
                tree += " layer at (\(actual.minX), \(actual.minY), \(actual.width), \(actual.height))"
            }
        }
        if let layer = view.state.layer, ObjCRuntime.objectClass(layer.objcObject) != CALayer.objCClass.pointer {
            tree += " layer " + (ObjCRuntime.objectClass(layer.objcObject).flatMap { NSObject($0).describedByObject() } ?? "?")
        }
        if let imageView = view.as(UIImageView.self) {
            let size = imageView.imageState.image?.state.size
            tree += size.map { " image \($0.width)x\($0.height)" } ?? " no image"
            if let image = imageView.imageState.image {
                if image.state.cgImage == nil { tree += " without pixels" }
                if image.state.renderingMode == 2 { tree += " template" }
                if imageView.imageState.highlighted { tree += " highlighted" }
            }
            if view.state.geometry?.contents == nil { tree += " no contents" }
        }
        if let label = view.as(UILabel.self), let text = label.label.text {
            tree += " \"\(text.prefix(40))\"" + (label.label.attributedText != nil ? " attributed" : "")
            // Kept until its components are read: an attributed text's color may live only as long as this.
            let color = label.textColor()
            if let c = withExtendedLifetime(color, { SKRenderer.components(color.objcObject) }) {
                tree += " color (\((c.0 * 100).rounded() / 100), \((c.1 * 100).rounded() / 100), \((c.2 * 100).rounded() / 100), \((c.3 * 100).rounded() / 100))"
            }
            tree += " font \(label.font.state.name) \(label.font.state.pointSize)"
        }
        if constraintsToo {
            // Whether constraints place the view, whether it is a stack view, and whether it awaits layout.
            if view.state.translatesAutoresizingMaskIntoConstraints { tree += " by frame" }
            if let stack = view.as(UIStackView.self) { tree += " stack of \(stack.arranged.count)" }
            if view.state.needsLayout { tree += " needs layout" }
        }
        tree += view.state.hidden ? " hidden\n" : "\n"
        if constraintsToo {
            for constraint in view.state.constraints.compactMap({ $0.as(NSLayoutConstraint.self) }) {
                tree += String(repeating: "  ", count: depth + 1) + "| " + describe(constraint, heldBy: view) + "\n"
            }
        }
        for subview in view.state.subviews { describe(subview, depth: depth + 1, into: &tree) }
        // Sublayers of no subview, which SwiftUI draws some content in.
        if let layer = view.state.layer {
            let viewLayers = Set(view.state.subviews.compactMap { $0.state.layer?.objcObject })
            describe(layer: layer, skipping: viewLayers, depth: depth + 1, into: &tree)
        }
    }

    /// PERRY_UIKIT_SNAPSHOT_CONSTRAINTS: the tree lists the constraints
    /// each view holds under it.
    private static let constraintsToo = getenv("PERRY_UIKIT_SNAPSHOT_CONSTRAINTS") != nil

    /// A constraint as "Class.attribute = Class.attribute * multiplier +
    /// constant @priority", with "self" for the view that holds it.
    private static func describe(_ constraint: NSLayoutConstraint, heldBy holder: UIView) -> String {
        let names = ["none", "left", "right", "top", "bottom", "leading", "trailing", "width", "height", "centerX", "centerY",
                     "lastBaseline", "firstBaseline", "leftMargin", "rightMargin", "topMargin", "bottomMargin", "leadingMargin",
                     "trailingMargin", "centerXWithinMargins", "centerYWithinMargins"]
        func side(_ item: UnsafeMutableRawPointer?, _ attribute: Int) -> String {
            guard let item else { return "" }
            let name = item == holder.objcObject ? "self"
                : ObjCRuntime.objectClass(item).flatMap { NSObject($0).describedByObject() } ?? "?"
            return name + "." + (names.indices.contains(attribute) ? names[attribute] : "\(attribute)")
        }
        let state = constraint.state
        var text = side(state.firstItem, state.firstAttribute) + (state.relation < 0 ? " <= " : state.relation > 0 ? " >= " : " = ")
        let second = state.secondAttribute == 0 ? "" : side(state.secondItem, state.secondAttribute)
        if !second.isEmpty {
            text += second
            if state.multiplier != 1 { text += " * \(state.multiplier)" }
            if state.constant != 0 { text += " + \(state.constant)" }
        } else {
            text += "\(state.constant)"
        }
        if state.priority != 1000 { text += " @\(state.priority)" }
        if !state.active { text += " inactive" }
        return text
    }

    private static func describe(layer: CALayer, skipping: Set<UnsafeMutableRawPointer>, depth: Int, into tree: inout String) {
        for sublayer in (layer.sublayers()?.elements ?? []).map({ $0.unsafeCast(to: CALayer.self) }) where !skipping.contains(sublayer.objcObject) {
            let name = ObjCRuntime.objectClass(sublayer.objcObject).flatMap { NSObject($0).describedByObject() } ?? "?"
            let frame = sublayer.frame()
            tree += String(repeating: "  ", count: depth) + "layer \(name) (\(frame.minX), \(frame.minY), \(frame.width), \(frame.height))"
            if sublayer.masksToBounds() { tree += " clips" }
            tree += sublayer.perryDebugDetails() ?? ""
            tree += sublayer.isHidden() ? " hidden\n" : "\n"
            if let mask = sublayer.mask()?.as(CALayer.self) {
                tree += String(repeating: "  ", count: depth + 1) + "mask \(mask.frame()):\(mask.perryDebugDetails() ?? "")\n"
                describe(layer: mask, skipping: [], depth: depth + 2, into: &tree)
            }
            describe(layer: sublayer, skipping: [], depth: depth + 1, into: &tree)
        }
    }
}

extension NSObject {
    @ObjCMethod("writeToFile:atomically:") @discardableResult func sendWrite(toFile path: String, atomically: Bool) -> Bool
}
