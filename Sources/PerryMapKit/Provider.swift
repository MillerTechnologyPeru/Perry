import CPerryGeometry
import Glibc
import PerryInterface
import PerryMapKitShared
import PerryObjCInterop

// libPerryMapKit: the provider for MapKit. PerryProviderPlugin generates its
// entry points from the module's Objective-C declarations; this file binds
// libobjc and libdispatch first, and holds the UIKit and CoreLocation calls
// the framework makes. Its views are UIKit's, so the loader starts it after
// UIKit. What its map views do on either platform is PerryMapKitShared's.
//
// A Mac app's map views are PerryMapKitAppKit's NSViews, whose provider
// re-exports this one for the rest of MapKit: in a Mac app this provider's
// views go by names of their own, leaving theirs to AppKit's.

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    MapKitShared.load { library, name in library.withCString { library in name.withCString { lookup(library, $0) } } }
    if MapKitShared.isMacApp(info.main_header) {
        for name in ["MKMapView", "MKAnnotationView", "MKPinAnnotationView", "MKMarkerAnnotationView"] {
            ObjCRuntime.privateClassNames[name] = "PerryMapKitUIKit" + name
        }
    }
    return true
}

/// The views' superclass: UIView, or NSObject in a Mac app that has no
/// UIKit, where they go unused.
enum UIKitViews {
    static var superclassName: String { ObjCRuntime.registeredClassPair("UIView") != nil ? "UIView" : "NSObject" }
}

/// MapKit's structure constants, which the loader asks for while binding
/// images.
func providerSymbol(_ name: String) -> UnsafeMutableRawPointer? { StructureConstants.values[name] }

enum StructureConstants {
    nonisolated(unsafe) static let values: [String: UnsafeMutableRawPointer] = {
        func value<T>(_ value: T) -> UnsafeMutableRawPointer {
            let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
            storage.initialize(to: value)
            return UnsafeMutableRawPointer(storage)
        }
        return [
            "_MKMapSizeWorld": value(MapGeometry.worldSize),
            "_MKMapRectWorld": value(MKMapRect(origin: MKMapPoint(x: 0, y: 0), size: MapGeometry.worldSize)),
            "_MKMapRectNull": value(MapGeometry.nullRect),
            "_MKCoordinateRegionInvalid": value(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -180, longitude: -180),
                                                                   span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0))),
        ]
    }()
}

// MARK: - UIKit and CoreLocation, as this provider calls them

@ObjCWrapper("UIView")
class UIView: NSObject {
    @ObjCMethod("bounds") func bounds() -> CGRect
    @ObjCMethod("frame") func frame() -> CGRect
    @ObjCMethod("setFrame:") func setFrame(_ frame: CGRect)
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: UIColor?)
    @ObjCMethod("setNeedsDisplay") func setNeedsDisplay()
    @ObjCMethod("setMultipleTouchEnabled:") func setMultipleTouchEnabled(_ enabled: Bool)
    @ObjCMethod("contentScaleFactor") func contentScaleFactor() -> CGFloat
    @ObjCMethod("convertPoint:toView:") func convert(_ point: CGPoint, to view: UIView?) -> CGPoint
    @ObjCMethod("convertPoint:fromView:") func convert(_ point: CGPoint, from view: UIView?) -> CGPoint
    @ObjCMethod("convertRect:toView:") func convert(_ rect: CGRect, to view: UIView?) -> CGRect
    @ObjCMethod("convertRect:fromView:") func convert(_ rect: CGRect, from view: UIView?) -> CGRect
}

@ObjCWrapper("UIColor")
class UIColor: NSObject {
    @ObjCClassMethod("colorWithRed:green:blue:alpha:") static func make(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> UIColor
}

@ObjCWrapper("CLLocation")
class CLLocation: NSObject {
    @ObjCMethod("initWithLatitude:longitude:") func initialize(latitude: Double, longitude: Double) -> CLLocation
    @ObjCMethod("coordinate") func coordinate() -> CLLocationCoordinate2D

    static func make(_ coordinate: CLLocationCoordinate2D) -> CLLocation {
        objCClass.object.allocated().unsafeCast(to: CLLocation.self).initialize(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

@ObjCWrapper("CLPlacemark")
class CLPlacemark: NSObject {
    @ObjCMethod("initWithLocation:addressDictionary:region:areasOfInterest:")
    func initializePlacemark(location: CLLocation?, addressDictionary: NSObject?, region: NSObject?, areasOfInterest: NSObject?) -> NSObject
    @ObjCMethod("location") func location() -> CLLocation?
    @ObjCMethod("name") func name() -> String?
    @ObjCMethod("ISOcountryCode") func isoCountryCode() -> String?
}
