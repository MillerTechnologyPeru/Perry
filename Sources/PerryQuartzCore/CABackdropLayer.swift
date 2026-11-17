import CPerryGeometry
import PerryObjCInterop

// CAFilter and CABackdropLayer, which Core Animation keeps private and
// SwiftUI's materials and UIKit's visual effect views are made of. A filter
// is a name and its inputs, set by key. A backdrop layer shows what is
// behind it, through its filters: the compositor blurs the frame so far
// where the layer is, by a gaussian blur filter's radius, and takes the
// saturation of a color saturate filter, as materials do.

@ObjCClass("CAFilter")
open class CAFilter: NSObject {
    var filterName = ""
    var inputs: [String: NSObject] = [:]
    var enabled = true

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCClassMethod("filterWithType:")
    static func filter(_ cls: ObjCClass, type: String) -> NSObject {
        let filter = cls.object.allocated().initialized().unsafeCast(to: CAFilter.self)
        filter.filterName = type
        return filter
    }

    @ObjCClassMethod("filterWithName:")
    static func filter(_ cls: ObjCClass, name: String) -> NSObject { filter(cls, type: name) }

    @ObjCClassMethod("filterTypes") static func filterTypes(_ cls: ObjCClass) -> NSObject { NSMutableArray.empty() }

    @ObjCMethod("type") func type() -> String { filterName }
    @ObjCMethod("name") func name() -> String { filterName }
    @ObjCMethod("setName:") func setName(_ name: String) { filterName = name }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { self.enabled = enabled }

    @ObjCMethod("valueForKey:") func value(forKey key: String) -> NSObject? { inputs[key] }
    @ObjCMethod("setValue:forKey:")
    func setValue(_ value: NSObject?, forKey key: String) {
        inputs[key] = value.map { NSObject(ObjCRuntime.retain($0.objcObject)!) }
    }
    @ObjCMethod("setDefaults") func setDefaults() {}

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let copy = NSObject(ObjCRuntime.objectClass(objcObject)!).allocated().initialized().unsafeCast(to: CAFilter.self)
        (copy.filterName, copy.inputs, copy.enabled) = (filterName, inputs, enabled)
        return ObjCRuntime.retain(copy.objcObject)
    }

    func number(_ key: String) -> Double? { inputs[key]?.sendDoubleValue() }
}

@ObjCClass("CABackdropLayer")
open class CABackdropLayer: CALayer {
    var scaleValue: CGFloat = 1
    var inPlaceFiltering = false
    var group: String?
    var windowServerAwareValue = true

    @ObjCMethod("scale") func scale() -> CGFloat { scaleValue }
    @ObjCMethod("setScale:") func setScale(_ scale: CGFloat) { scaleValue = scale }
    @ObjCMethod("allowsInPlaceFiltering") func allowsInPlaceFiltering() -> Bool { inPlaceFiltering }
    @ObjCMethod("setAllowsInPlaceFiltering:") func setAllowsInPlaceFiltering(_ allows: Bool) { inPlaceFiltering = allows }
    @ObjCMethod("groupName") func groupName() -> String? { group }
    @ObjCMethod("setGroupName:") func setGroupName(_ name: String?) { group = name }
    @ObjCMethod("windowServerAware") func windowServerAware() -> Bool { windowServerAwareValue }
    @ObjCMethod("setWindowServerAware:") func setWindowServerAware(_ aware: Bool) { windowServerAwareValue = aware }

    /// The blur radius, in points, and the saturation the filters ask for;
    /// the radius is 0 without a blur.
    var backdropEffect: (radius: CGFloat, saturation: CGFloat) {
        var radius: CGFloat = 0, saturation: CGFloat = 1
        for filter in state.filters?.as(NSArray.self)?.elements ?? [] {
            guard let filter = filter.as(CAFilter.self), filter.enabled else { continue }
            switch filter.filterName {
            case "gaussianBlur", "variableBlur": radius = max(radius, CGFloat(filter.number("inputRadius") ?? 0))
            case "colorSaturate": saturation *= CGFloat(filter.number("inputAmount") ?? 1)
            default: break
            }
        }
        return (radius, saturation)
    }

    /// For UIKit's visual effect views, which cannot reach the filters'
    /// class: the blur and saturation as one setting.
    @ObjCMethod("_perrySetBlurRadius:saturation:")
    func setBlur(radius: CGFloat, saturation: CGFloat) {
        let blur = CAFilter.filter(CAFilter.objCClass, type: "gaussianBlur").unsafeCast(to: CAFilter.self)
        blur.setValue(NSNumber.make(double: Double(radius)), forKey: "inputRadius")
        let saturate = CAFilter.filter(CAFilter.objCClass, type: "colorSaturate").unsafeCast(to: CAFilter.self)
        saturate.setValue(NSNumber.make(double: Double(saturation)), forKey: "inputAmount")
        setFilters(NSMutableArray.of([blur, saturate]))
    }
}
