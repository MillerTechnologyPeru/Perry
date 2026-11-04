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
/// changes to layers, to look at what an app shows without a display.
enum Snapshot {
    nonisolated(unsafe) static let path: String? = getenv("PERRY_UIKIT_SNAPSHOT").map { String(cString: $0) }

    static func writeIfRequested() {
        guard let path else { return }
        write(to: path)
    }

    nonisolated(unsafe) private static var requested = false

    /// Writes the snapshot a second after an update pass or a change to
    /// layers, at most once a second: encoding it is slow. The numbered
    /// snapshots are written when they are due.
    static func requestWrite() {
        guard path != nil, !requested else { return }
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
        var tree = ""
        for window in Windows.visible { describe(window, depth: 0, into: &tree) }
        FileManager.default.createFile(atPath: path + ".txt", contents: Data(tree.utf8))
    }

    /// The view tree beside the image: each view's class, frame, bounds
    /// origin when scrolled, how its layer clips, and whether it is hidden.
    private static func describe(_ view: UIView, depth: Int, into tree: inout String) {
        let name = ObjCRuntime.objectClass(view.objcObject).flatMap { NSObject($0).describedByObject() } ?? "?"
        let frame = view.state.frame
        tree += String(repeating: "  ", count: depth) + "\(name) (\(frame.minX), \(frame.minY), \(frame.width), \(frame.height))"
        let origin = view.state.bounds.origin
        if origin != .zero { tree += " bounds origin (\(origin.x), \(origin.y))" }
        if let geometry = view.state.geometry {
            if geometry.masksToBounds { tree += " clips" }
            if geometry.cornerRadius > 0 { tree += " radius \(geometry.cornerRadius)" }
            if geometry.layer.mask() != nil { tree += " masked" }
            if let presented = geometry.layer.presentationLayer() {
                let model = geometry.layer
                if presented.frame() != model.frame() { tree += " presented \(presented.frame())" }
                if presented.bounds() != model.bounds() { tree += " presented bounds \(presented.bounds())" }
                if presented.masksToBounds() != model.masksToBounds() { tree += " presented clips \(presented.masksToBounds())" }
            }
        }
        tree += view.state.hidden ? " hidden\n" : "\n"
        for subview in view.state.subviews { describe(subview, depth: depth + 1, into: &tree) }
        // Sublayers of no subview, which SwiftUI draws some content in.
        if let layer = view.state.layer {
            let viewLayers = Set(view.state.subviews.compactMap { $0.state.layer?.objcObject })
            describe(layer: layer, skipping: viewLayers, depth: depth + 1, into: &tree)
        }
    }

    private static func describe(layer: CALayer, skipping: Set<UnsafeMutableRawPointer>, depth: Int, into tree: inout String) {
        for sublayer in (layer.sublayers()?.elements ?? []).map({ $0.unsafeCast(to: CALayer.self) }) where !skipping.contains(sublayer.objcObject) {
            let name = ObjCRuntime.objectClass(sublayer.objcObject).flatMap { NSObject($0).describedByObject() } ?? "?"
            let frame = sublayer.frame()
            tree += String(repeating: "  ", count: depth) + "layer \(name) (\(frame.minX), \(frame.minY), \(frame.width), \(frame.height))"
            if sublayer.masksToBounds() { tree += " clips" }
            tree += sublayer.isHidden() ? " hidden\n" : "\n"
            describe(layer: sublayer, skipping: [], depth: depth + 1, into: &tree)
        }
    }
}

extension NSObject {
    @ObjCMethod("writeToFile:atomically:") @discardableResult func sendWrite(toFile path: String, atomically: Bool) -> Bool
}
