import CPerryGeometry
import Glibc
import PerryObjCInterop

// UIScrollView's scroll indicators: a thin rounded bar along the right
// edge for vertical scrolling and along the bottom for horizontal, its
// length the part of the content that shows, shrinking as the content is
// pulled past an edge. They show while the user scrolls, zooms or the
// content coasts, and fade out half a second after it stops;
// -flashScrollIndicators shows them a moment. They are layers of the
// scroll view's layer, not subviews, above its content, placed in its
// bounds (the content's coordinates) inside the indicator insets, which
// take in the safe area when the scroll view adjusts them.

final class ScrollIndicatorState: ObjectState {
    var vertical: CALayer?
    var horizontal: CALayer?
    /// The colors the bars are drawn in, kept while they are.
    var color: UIColor?
    var colorStyle = -1
    var shown = false
    /// When the content last moved, and how long the bars stay after.
    var lastMove = 0.0
    var delay = 0.5
    /// Whether a fade is waiting to run.
    var fadePending = false
}

/// The bars' layers' delegate: no implicit animations, so they keep up with
/// the content.
@ObjCClass("_PerryScrollIndicatorActions")
open class ScrollIndicatorActions: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCMethod("actionForLayer:forKey:") func action(for layer: NSObject, forKey key: String) -> NSObject? { NSNull.null() }

    nonisolated(unsafe) static let shared = ScrollIndicatorActions()
}

extension UIScrollView {
    static let indicatorStates = StateTable<ScrollIndicatorState>()
    var indicators: ScrollIndicatorState { UIScrollView.indicatorStates[objcObject] }

    static var indicatorThickness: CGFloat { 3 }
    /// Between a bar and the scroll view's edges.
    static var indicatorMargin: CGFloat { 3 }
    static var indicatorMinimumLength: CGFloat { 36 }

    /// Shows the bars where the content is, and fades them out once it
    /// has stopped moving for `delay` seconds.
    func showIndicators(fadeAfter delay: Double = 0.5) {
        let indicators = indicators
        let appearing = !indicators.shown
        indicators.shown = true
        (indicators.lastMove, indicators.delay) = (Clock.now, delay)
        layOutIndicators()
        if appearing { for layer in [indicators.vertical, indicators.horizontal].compactMap({ $0 }) { layer.setOpacity(1) } }
        if !indicators.fadePending {
            indicators.fadePending = true
            scheduleIndicatorFade(after: delay)
        }
    }

    /// Fades the bars once the content has rested long enough; looks again
    /// later while it moves.
    private func scheduleIndicatorFade(after delay: Double) {
        let object = objcObject
        Deferred.run(after: delay) {
            guard let states = UIScrollView.indicatorStates.existing(object), states.shown else { return }
            let view = UIScrollView(objcObject: object, ownership: .retain)
            let rested = Clock.now - states.lastMove
            if view.scroll.tracking || view.scroll.dragging || view.scroll.decelerating || view.scroll.zooming || rested < states.delay {
                return view.scheduleIndicatorFade(after: max(states.delay - rested, 0.1))
            }
            states.fadePending = false
            states.shown = false
            let layers = [states.vertical, states.horizontal].compactMap { $0 }
            Animations.run(duration: 0.3, { progress in
                // Shown again meanwhile: stay.
                guard !states.shown else { return }
                for layer in layers { layer.setOpacity(Float(1 - progress)) }
            }, completion: {})
        }
    }

    /// Puts the bars along the visible part of the content, or hides each
    /// whose axis does not scroll or that is turned off.
    func layOutIndicators() {
        let indicators = indicators
        guard indicators.shown else { return }
        let scroll = scroll, bounds = state.bounds, size = scroll.contentSize, inset = adjustedContentInset()
        var barInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        if scroll.automaticallyAdjustsScrollIndicatorInsets {
            let safe = safeAreaInsets()
            barInsets = UIEdgeInsets(top: safe.top, left: safe.left, bottom: safe.bottom, right: safe.right)
        }
        let thickness = Self.indicatorThickness, margin = Self.indicatorMargin
        let showsVertical = scroll.showsVerticalIndicator && size.height + inset.top + inset.bottom > bounds.height + 0.5
        let showsHorizontal = scroll.showsHorizontalIndicator && size.width + inset.left + inset.right > bounds.width + 0.5
        let color = indicatorColor()

        /// One bar's position and length along its track: from `low` to
        /// `high` in the view, the content `offset` scrolled in a range from
        /// `minimum` to `maximum`, `visible` of `total` showing.
        func bar(offset: CGFloat, minimum: CGFloat, maximum: CGFloat, visible: CGFloat, total: CGFloat, low: CGFloat, high: CGFloat)
            -> (start: CGFloat, length: CGFloat) {
            let track = max(high - low, 0)
            var length = max(track * min(visible / max(total, 1), 1), min(Self.indicatorMinimumLength, track))
            // Pulled past an edge, the bar shrinks by the overshoot.
            let over = offset < minimum ? minimum - offset : offset > maximum ? offset - maximum : 0
            length = max(length - over, thickness * 2)
            let progress = maximum > minimum ? min(max((offset - minimum) / (maximum - minimum), 0), 1) : 0
            return (low + (track - length) * progress, length)
        }

        if showsVertical {
            let layer = indicatorLayer(\.vertical, color: color)
            let top = bounds.minY + scroll.verticalIndicatorInsets.top + barInsets.top + margin
            var bottom = bounds.maxY - scroll.verticalIndicatorInsets.bottom - barInsets.bottom - margin
            if showsHorizontal { bottom -= thickness + margin }
            let placed = bar(offset: bounds.minY, minimum: -inset.top, maximum: max(-inset.top, size.height + inset.bottom - bounds.height),
                             visible: bounds.height - inset.top - inset.bottom, total: size.height, low: top, high: bottom)
            let x = bounds.maxX - scroll.verticalIndicatorInsets.right - barInsets.right - margin - thickness
            layer.setFrame(CGRect(x: x, y: placed.start, width: thickness, height: placed.length))
            layer.setHidden(false)
        } else {
            indicators.vertical?.setHidden(true)
        }
        if showsHorizontal {
            let layer = indicatorLayer(\.horizontal, color: color)
            let left = bounds.minX + scroll.horizontalIndicatorInsets.left + barInsets.left + margin
            var right = bounds.maxX - scroll.horizontalIndicatorInsets.right - barInsets.right - margin
            if showsVertical { right -= thickness + margin }
            let placed = bar(offset: bounds.minX, minimum: -inset.left, maximum: max(-inset.left, size.width + inset.right - bounds.width),
                             visible: bounds.width - inset.left - inset.right, total: size.width, low: left, high: right)
            let y = bounds.maxY - scroll.horizontalIndicatorInsets.bottom - barInsets.bottom - margin - thickness
            layer.setFrame(CGRect(x: placed.start, y: y, width: placed.length, height: thickness))
            layer.setHidden(false)
        } else {
            indicators.horizontal?.setHidden(true)
        }
    }

    /// UIScrollViewIndicatorStyle: default 0 (dark, as on a light
    /// background), black 1, white 2.
    private func indicatorColor() -> UIColor {
        let indicators = indicators, style = scroll.indicatorStyle
        if let color = indicators.color, indicators.colorStyle == style { return color }
        let color = style == 2 ? UIColor.gray(1, 0.5) : UIColor.gray(0, style == 1 ? 0.5 : 0.35)
        (indicators.color, indicators.colorStyle) = (color, style)
        for layer in [indicators.vertical, indicators.horizontal].compactMap({ $0 }) { layer.setBackgroundColor(color.state.makeCGColor()) }
        return color
    }

    /// A bar's layer, made the first time it shows, above the content.
    private func indicatorLayer(_ key: ReferenceWritableKeyPath<ScrollIndicatorState, CALayer?>, color: UIColor) -> CALayer {
        let indicators = indicators
        if let layer = indicators[keyPath: key] { return layer }
        let layer = CALayer.make()
        layer.setDelegate(ScrollIndicatorActions.shared)
        layer.setBackgroundColor(color.state.makeCGColor())
        layer.setCornerRadius(Self.indicatorThickness / 2)
        layer.setZPosition(10_000)
        layer.setContentsScale(Screen.scale)
        state.layer.addSublayer(layer)
        indicators[keyPath: key] = layer
        return layer
    }

    /// The bars' layers go with the scroll view.
    func removeIndicators() {
        guard let indicators = UIScrollView.indicatorStates.existing(objcObject) else { return }
        indicators.vertical?.removeFromSuperlayer()
        indicators.horizontal?.removeFromSuperlayer()
        UIScrollView.indicatorStates.remove(objcObject)
    }
}
