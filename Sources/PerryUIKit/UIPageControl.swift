import CPerryGeometry
import PerryObjCInterop

// UIPageControl, drawn as iOS draws it: a 7-point dot for each page, 9
// points apart, the current one in the current page tint (white unless
// set) and the others in the page tint (white at 30%), on a capsule when
// the background style is prominent. A tap on either side of the current
// dot moves a page that way and sends value changed. New page controls take
// their tints from UIPageControl's appearance proxy, as on iOS.

final class PageControlState: ObjectState {
    var numberOfPages = 0
    var currentPage = 0
    var hidesForSinglePage = false
    var pageIndicatorTintColor: UIColor?
    var currentPageIndicatorTintColor: UIColor?
    /// UIPageControlBackgroundStyle: automatic 0, prominent 1, minimal 2.
    var backgroundStyle = 0
}

@ObjCClass("UIPageControl")
open class UIPageControl: UIControl {
    static let pageStates = StateTable<PageControlState>()
    var pageState: PageControlState { UIPageControl.pageStates[objcObject] }

    static let dot: CGFloat = 7
    static let spacing: CGFloat = 9
    static let height: CGFloat = 26

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIPageControl.pageStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        let s = pageState
        s.pageIndicatorTintColor = AppearanceProxies.style("pageIndicatorTintColor", of: objCClassPointer)?.as(UIColor.self)
        s.currentPageIndicatorTintColor = AppearanceProxies.style("currentPageIndicatorTintColor", of: objCClassPointer)?
            .as(UIColor.self)
        return self
    }

    /// The class the object is an instance of, whose appearance it takes.
    private var objCClassPointer: UnsafeMutableRawPointer? { ObjCRuntime.objectClass(objcObject) }

    @ObjCMethod("numberOfPages") func numberOfPages() -> Int { pageState.numberOfPages }
    @ObjCMethod("setNumberOfPages:")
    func setNumberOfPages(_ count: Int) {
        let s = pageState
        s.numberOfPages = max(count, 0)
        s.currentPage = min(s.currentPage, max(s.numberOfPages - 1, 0))
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    @ObjCMethod("currentPage") func currentPage() -> Int { pageState.currentPage }
    @ObjCMethod("setCurrentPage:")
    func setCurrentPage(_ page: Int) {
        pageState.currentPage = min(max(page, 0), max(pageState.numberOfPages - 1, 0))
        setNeedsDisplay()
    }

    @ObjCMethod("hidesForSinglePage") func hidesForSinglePage() -> Bool { pageState.hidesForSinglePage }
    @ObjCMethod("setHidesForSinglePage:")
    func setHidesForSinglePage(_ hides: Bool) { pageState.hidesForSinglePage = hides; setNeedsDisplay() }

    @ObjCMethod("pageIndicatorTintColor") func pageIndicatorTintColor() -> UIColor? { pageState.pageIndicatorTintColor }
    @ObjCMethod("setPageIndicatorTintColor:")
    func setPageIndicatorTintColor(_ color: UIColor?) { pageState.pageIndicatorTintColor = color; setNeedsDisplay() }
    @ObjCMethod("currentPageIndicatorTintColor") func currentPageIndicatorTintColor() -> UIColor? {
        pageState.currentPageIndicatorTintColor
    }
    @ObjCMethod("setCurrentPageIndicatorTintColor:")
    func setCurrentPageIndicatorTintColor(_ color: UIColor?) { pageState.currentPageIndicatorTintColor = color; setNeedsDisplay() }

    @ObjCMethod("backgroundStyle") func backgroundStyle() -> Int { pageState.backgroundStyle }
    @ObjCMethod("setBackgroundStyle:")
    func setBackgroundStyle(_ style: Int) { pageState.backgroundStyle = style; setNeedsDisplay() }

    /// Page indicator images aren't drawn; the dots stand in for them.
    @ObjCMethod("setPreferredIndicatorImage:") func setPreferredIndicatorImage(_ image: UIImage?) {}
    @ObjCMethod("preferredIndicatorImage") func preferredIndicatorImage() -> UIImage? { nil }
    @ObjCMethod("setIndicatorImage:forPage:") func setIndicatorImage(_ image: UIImage?, forPage page: Int) {}
    @ObjCMethod("indicatorImageForPage:") func indicatorImage(forPage page: Int) -> UIImage? { nil }

    @ObjCMethod("sizeForNumberOfPages:")
    func size(forNumberOfPages count: Int) -> CGSize {
        let dots = CGFloat(max(count, 0))
        let width = dots * UIPageControl.dot + max(dots - 1, 0) * UIPageControl.spacing
        return CGSize(width: count > 0 ? width + 24 : 0, height: UIPageControl.height)
    }

    @ObjCMethod("intrinsicContentSize")
    override func intrinsicContentSizeOfView() -> CGSize { size(forNumberOfPages: pageState.numberOfPages) }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize { self.size(forNumberOfPages: pageState.numberOfPages) }

    /// Where the dots are: centered in the bounds.
    private func dotFrames() -> [CGRect] {
        let s = pageState, bounds = state.bounds
        let width = size(forNumberOfPages: s.numberOfPages).width - 24
        var x = bounds.midX - width / 2
        return (0..<s.numberOfPages).map { _ in
            defer { x += UIPageControl.dot + UIPageControl.spacing }
            return CGRect(x: x, y: bounds.midY - UIPageControl.dot / 2, width: UIPageControl.dot, height: UIPageControl.dot)
        }
    }

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let s = pageState
        guard s.numberOfPages > 0, !(s.hidesForSinglePage && s.numberOfPages == 1) else { return }
        let frames = dotFrames()
        if s.backgroundStyle == 1, let first = frames.first, let last = frames.last {
            let capsule = CGRect(x: first.minX - 12, y: state.bounds.midY - 13, width: last.maxX - first.minX + 24, height: 26)
            fill(roundedRectPath(capsule, radius: 13, corners: 0xf), with: UIColor.gray(0, 0.25), in: context)
        }
        let current = s.currentPageIndicatorTintColor ?? UIColor.gray(1)
        let other = s.pageIndicatorTintColor ?? UIColor.gray(1, 0.3)
        for (page, frame) in frames.enumerated() {
            fill(roundedRectPath(frame, radius: UIPageControl.dot / 2, corners: 0xf), with: page == s.currentPage ? current : other,
                 in: context)
        }
    }

    private func fill(_ path: Owned?, with color: UIColor, in context: CGRef) {
        guard let path else { return }
        withExtendedLifetime(color) {
            CG.setFillColorWithColor(context, color.state.makeCGColor())
            CG.addPath(context, path.object)
            CG.fillPath(context)
        }
    }

    @ObjCMethod("touchesEnded:withEvent:")
    override func touchesEnded(_ touches: NSObject, with event: NSObject?) {
        guard control.tracking else { return }
        control.tracking = false
        let s = pageState
        guard let touch = touches.as(NSSet.self)?.anyObject()?.as(UITouch.self), s.numberOfPages > 1,
              let current = dotFrames().indices.contains(s.currentPage) ? dotFrames()[s.currentPage] : nil else { return }
        let next = touch.location(in: self).x < current.midX ? s.currentPage - 1 : s.currentPage + 1
        guard next >= 0, next < s.numberOfPages else { return }
        s.currentPage = next
        setNeedsDisplay()
        sendActions(for: 1 << 12)
    }

    @ObjCMethod("touchesCancelled:withEvent:")
    override func touchesCancelled(_ touches: NSObject, with event: NSObject?) { control.tracking = false }
}
