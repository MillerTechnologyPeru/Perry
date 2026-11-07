import CPerryGeometry
import Glibc
import PerryInterface
import PerryMapKitShared
import PerryObjCInterop

// libPerryMapKitAppKit: a Mac app's MapKit (a versioned framework, which
// the loader maps here). Its map and annotation views are NSViews, their
// methods those PerryMapKitShared shares with PerryMapKit's UIViews; the
// rest of MapKit (annotations, placemarks, map items, its functions and
// constants) is PerryMapKit's, which the loader re-exports through this
// provider. It starts after AppKit, whose views its views subclass.

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    MapKitShared.load { library, name in library.withCString { library in name.withCString { lookup(library, $0) } } }
    return true
}

// MARK: - AppKit and QuartzCore, as this provider calls them

@ObjCWrapper("NSView")
class NSView: NSObject {
    @ObjCMethod("bounds") func bounds() -> CGRect
    @ObjCMethod("setWantsLayer:") func setWantsLayer(_ wants: Bool)
    @ObjCMethod("layer") func layer() -> CALayer?
    @ObjCMethod("window") func window() -> NSWindow?
}

@ObjCWrapper("NSWindow")
class NSWindow: NSObject {
    @ObjCMethod("backingScaleFactor") func backingScaleFactor() -> CGFloat
}

@ObjCWrapper("NSColor")
class NSColor: NSObject {
    @ObjCClassMethod("colorWithRed:green:blue:alpha:") static func make(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> NSColor
    @ObjCMethod("CGColor") func cgColor() -> UnsafeMutableRawPointer?
}

@ObjCWrapper("CALayer")
class CALayer: NSObject {
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: UnsafeMutableRawPointer?)
}
