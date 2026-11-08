import CPerryGeometry
import Glibc
import PerryObjCInterop

// MKMapView's gestures on a Mac, as MapKit's: dragging with the mouse pans
// the map, the point under the pointer staying under it; a double click
// zooms in on the point clicked; a trackpad's two-finger scroll pans; a mouse
// wheel zooms about the pointer. They
// honor isScrollEnabled and isZoomEnabled, and tell the delegate as the
// touch gestures do: the region will change as one starts, and did change
// as it ends.
//
// AppKit's map view installs the MapViewMouse category; UIKit's gets none of
// these messages.

@ObjCCategory("MapViewMouse", addedAtStartup: false)
public extension MapViewObject {
    @ObjCMethod("mouseDown:")
    func mapMouseDown(_ event: NSObject?) {
        guard let event else { return }
        let gesture = MapGestures.states[objcObject]
        gesture.moved = false
        gesture.travelled = 0
        let point = location(of: event)
        gesture.mouse = point
        if event.clickCount() == 2, map.zoomEnabled {
            moveMap(holding: point, at: point, scale: 2)
            finishGesture(gesture)
        }
    }

    @ObjCMethod("mouseDragged:")
    func mapMouseDragged(_ event: NSObject?) {
        guard let event else { return }
        let gesture = MapGestures.states[objcObject]
        guard let from = gesture.mouse else { return }
        let to = location(of: event)
        gesture.mouse = to
        gesture.travelled += hypot(to.x - from.x, to.y - from.y)
        guard map.scrollEnabled, gesture.travelled >= 3 || gesture.moved else { return }
        moveMap(holding: from, at: to, scale: 1)
    }

    @ObjCMethod("mouseUp:")
    func mapMouseUp(_ event: NSObject?) {
        let gesture = MapGestures.states[objcObject]
        gesture.mouse = nil
        finishGesture(gesture)
    }

    /// A trackpad's two fingers pan; a wheel zooms.
    @ObjCMethod("scrollWheel:")
    func mapScrollWheel(_ event: NSObject?) {
        guard let event else { return }
        let gesture = MapGestures.states[objcObject]
        let point = location(of: event)
        if event.hasPreciseScrollingDeltas() {
            if map.scrollEnabled {
                moveMap(holding: point, at: CGPoint(x: point.x + event.scrollingDeltaX(), y: point.y + event.scrollingDeltaY()), scale: 1)
            }
        } else if map.zoomEnabled {
            moveMap(holding: point, at: point, scale: pow(1.25, event.scrollingDeltaY()))
        }
        // NSEventPhaseEnded, NSEventPhaseCancelled, or no phase: a wheel's
        // notch is a gesture of its own.
        let phase = event.phase()
        if phase == 0 || phase & (8 | 16) != 0 { finishGesture(gesture) }
    }

    /// Where an event is in the view.
    private func location(of event: NSObject) -> CGPoint { convert(event.locationInWindow(), from: nil) }

    /// The region did change, when the gesture has moved it.
    private func finishGesture(_ gesture: GestureState) {
        guard gesture.moved else { return }
        gesture.moved = false
        regionDidChange(animated: false)
    }
}

/// NSEvent's messages, as the gestures send them.
extension NSObject {
    @ObjCMethod("locationInWindow") func locationInWindow() -> CGPoint
    @ObjCMethod("clickCount") func clickCount() -> Int
    @ObjCMethod("hasPreciseScrollingDeltas") func hasPreciseScrollingDeltas() -> Bool
    @ObjCMethod("scrollingDeltaX") func scrollingDeltaX() -> CGFloat
    @ObjCMethod("scrollingDeltaY") func scrollingDeltaY() -> CGFloat
    @ObjCMethod("phase") func phase() -> UInt
}
