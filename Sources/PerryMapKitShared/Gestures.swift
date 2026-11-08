import CPerryGeometry
import Glibc
import PerryObjCInterop

// MKMapView's gestures on a touchscreen, as MapKit's: one finger pans the
// map, the point under it staying under it; two fingers pinch, zooming about
// their midpoint, and pan with it; a double tap zooms in two levels on the
// point tapped. The view follows its touches itself (it is multiple-touch
// enabled, so each finger's touches come to it), honoring isScrollEnabled
// and isZoomEnabled. The delegate hears that the region will change as a
// gesture starts, that the visible region changed with each move, and that
// the region did change when the fingers lift.
//
// UIKit's map view installs the MapViewGestures category and is sent
// touches; AppKit's gets none of these messages (see MouseGestures).

final class GestureState: ObjectState {
    /// Each finger down, by its UITouch, where it is in the view.
    var touches: [UnsafeMutableRawPointer: CGPoint] = [:]
    /// The fingers in the order they went down.
    var order: [UnsafeMutableRawPointer] = []
    /// Whether the fingers have moved the map since the first went down.
    var moved = false
    /// Whether the fingers have moved far enough not to be a tap.
    var travelled: CGFloat = 0
    /// The last tap: when, and where.
    var lastTap: (time: Double, point: CGPoint)?
    /// Where the mouse is, while it is down.
    var mouse: CGPoint?
}

extension MapViews {
    /// Forgets a map view's fingers, as it goes.
    public static func removeGestures(_ view: UnsafeMutableRawPointer) { MapGestures.states.remove(view) }
}

enum MapGestures {
    static let states = StateTable<GestureState>()

    /// Seconds, on the monotonic clock.
    static var now: Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }

    /// The closest zoom: MapLibre's level 20, the world 512 · 2^20 points
    /// across.
    static let closest = MapGeometry.worldSize.width / (512 * pow(2, 20))
}

@ObjCCategory("MapViewGestures", addedAtStartup: false)
public extension MapViewObject {
    @ObjCMethod("touchesBegan:withEvent:")
    func mapTouchesBegan(_ touches: NSObject?, with event: NSObject?) {
        let gesture = MapGestures.states[objcObject]
        if gesture.touches.isEmpty {
            gesture.moved = false
            gesture.travelled = 0
        }
        for touch in touchList(touches) {
            gesture.touches[touch.objcObject] = touch.location(in: self)
            gesture.order.append(touch.objcObject)
        }
    }

    @ObjCMethod("touchesMoved:withEvent:")
    func mapTouchesMoved(_ touches: NSObject?, with event: NSObject?) {
        let gesture = MapGestures.states[objcObject]
        let before = gesture.touches
        for touch in touchList(touches) where gesture.touches[touch.objcObject] != nil {
            gesture.touches[touch.objcObject] = touch.location(in: self)
        }
        let fingers = gesture.order.prefix(2)
        guard let first = fingers.first, let from = before[first], let to = gesture.touches[first] else { return }
        if fingers.count == 2, let second = fingers.last, let otherFrom = before[second], let otherTo = gesture.touches[second] {
            let fromMid = CGPoint(x: (from.x + otherFrom.x) / 2, y: (from.y + otherFrom.y) / 2)
            let toMid = CGPoint(x: (to.x + otherTo.x) / 2, y: (to.y + otherTo.y) / 2)
            let fromDistance = hypot(otherFrom.x - from.x, otherFrom.y - from.y)
            let toDistance = hypot(otherTo.x - to.x, otherTo.y - to.y)
            gesture.travelled += hypot(toMid.x - fromMid.x, toMid.y - fromMid.y) + abs(toDistance - fromDistance)
            let scale = fromDistance > 1 && toDistance > 1 && map.zoomEnabled ? toDistance / fromDistance : 1
            moveMap(holding: fromMid, at: map.scrollEnabled ? toMid : fromMid, scale: scale)
        } else {
            gesture.travelled += hypot(to.x - from.x, to.y - from.y)
            guard map.scrollEnabled, gesture.travelled >= 10 || gesture.moved else { return }
            moveMap(holding: from, at: to, scale: 1)
        }
    }

    @ObjCMethod("touchesEnded:withEvent:")
    func mapTouchesEnded(_ touches: NSObject?, with event: NSObject?) { lift(touches, tapping: true) }

    @ObjCMethod("touchesCancelled:withEvent:")
    func mapTouchesCancelled(_ touches: NSObject?, with event: NSObject?) { lift(touches, tapping: false) }

    /// Removes the lifted fingers; with none left, ends the gesture: the
    /// region did change, or a second tap close to the first zooms in.
    private func lift(_ touches: NSObject?, tapping: Bool) {
        let gesture = MapGestures.states[objcObject]
        var point: CGPoint?
        let single = gesture.order.count == 1
        for touch in touchList(touches) {
            point = gesture.touches.removeValue(forKey: touch.objcObject) ?? point
            gesture.order.removeAll { $0 == touch.objcObject }
        }
        guard gesture.touches.isEmpty else { return }
        if gesture.moved {
            gesture.lastTap = nil
            MapLibre.trace("gesture ended at \(map.region.center.latitude), \(map.region.center.longitude)")
            regionDidChange(animated: false)
            return
        }
        guard tapping, single, gesture.travelled < 10, let point else { return }
        let now = MapGestures.now
        if let last = gesture.lastTap, now - last.time < 0.35, hypot(point.x - last.point.x, point.y - last.point.y) < 40 {
            gesture.lastTap = nil
            guard map.zoomEnabled else { return }
            // Two levels in, the tapped point staying put.
            moveMap(holding: point, at: point, scale: 4)
            regionDidChange(animated: true)
        } else {
            gesture.lastTap = (now, point)
        }
    }

    /// Moves the map so the map point that was under `held` is under
    /// `point`, zoomed in by `scale`: the visible map rect, in map points,
    /// kept within the world's height and between the whole world's width
    /// and the closest zoom.
    func moveMap(holding held: CGPoint, at point: CGPoint, scale: CGFloat) {
        let size = map.size
        guard size.width >= 1, size.height >= 1, scale > 0 else { return }
        let gesture = MapGestures.states[objcObject]
        if !gesture.moved {
            gesture.moved = true
            if let delegate = delegate(), delegate.responds(to: "mapView:regionWillChangeAnimated:") {
                delegate.sendMapView(self, regionWillChangeAnimated: false)
            }
        }
        let world = MapGeometry.worldSize
        let rect = MapGeometry.rect(map.shownRegion)
        let perPoint = rect.size.width / Double(size.width)
        let farthest = world.width / Double(size.width)
        let newPerPoint = min(max(perPoint / Double(scale), MapGestures.closest), farthest)
        let anchor = (x: rect.origin.x + Double(held.x) * perPoint, y: rect.origin.y + Double(held.y) * perPoint)
        let width = Double(size.width) * newPerPoint, height = Double(size.height) * newPerPoint
        var x = anchor.x - Double(point.x) * newPerPoint
        var y = anchor.y - Double(point.y) * newPerPoint
        y = height >= world.height ? (world.height - height) / 2 : min(max(y, 0), world.height - height)
        // East and west wrap around.
        x = (x + width / 2).truncatingRemainder(dividingBy: world.width)
        if x < 0 { x += world.width }
        x -= width / 2
        var region = MapGeometry.region(MKMapRect(origin: MKMapPoint(x: x, y: y), size: MKMapSize(width: width, height: height)))
        if region.center.longitude > 180 { region.center.longitude -= 360 }
        if region.center.longitude < -180 { region.center.longitude += 360 }
        map.region = region
        map.tiles?.show(region)
        if let delegate = delegate(), delegate.responds(to: "mapViewDidChangeVisibleRegion:") {
            delegate.sendMapViewDidChangeVisibleRegion(self)
        }
    }

    /// The touches in a set of them.
    func touchList(_ touches: NSObject?) -> [NSObject] {
        guard let touches else { return [] }
        return touches.allObjects().elements
    }
}

/// UITouch's and NSSet's messages, as the gestures send them.
extension NSObject {
    @ObjCMethod("locationInView:") func location(in view: NSObject?) -> CGPoint
    @ObjCMethod("allObjects") func allObjects() -> NSArray
}
