import CPerryGeometry
import PerryObjCInterop

// CLGeocoder, with no geocoding service: each request completes on the
// main queue with no placemarks and kCLErrorNetwork. CLPlacemark holds a
// location and an address dictionary, as MKPlacemark makes them.

/// CLError: network 2.
private let networkError = 2

@ObjCClass("CLGeocoder")
open class CLGeocoder: NSObject {
    /// void (^)(NSArray<CLPlacemark *> *placemarks, NSError *error).
    private func fail(_ completionHandler: ObjCBlock?) {
        guard let completionHandler else { return }
        Dispatch.onMain {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
            completionHandler.function(as: Invoke.self)(completionHandler.object, nil, NSError.location(networkError).objcObject)
        }
    }

    @ObjCMethod("isGeocoding") func isGeocoding() -> Bool { false }
    @ObjCMethod("cancelGeocode") func cancelGeocode() {}

    @ObjCMethod("geocodeAddressString:completionHandler:")
    func geocode(addressString: String?, completionHandler: ObjCBlock?) { fail(completionHandler) }

    @ObjCMethod("geocodeAddressString:inRegion:completionHandler:")
    func geocode(addressString: String?, in region: NSObject?, completionHandler: ObjCBlock?) { fail(completionHandler) }

    @ObjCMethod("geocodeAddressString:inRegion:preferredLocale:completionHandler:")
    func geocode(addressString: String?, in region: NSObject?, preferredLocale: NSObject?, completionHandler: ObjCBlock?) {
        fail(completionHandler)
    }

    @ObjCMethod("geocodeAddressDictionary:completionHandler:")
    func geocode(addressDictionary: NSObject?, completionHandler: ObjCBlock?) { fail(completionHandler) }

    @ObjCMethod("geocodePostalAddress:completionHandler:")
    func geocode(postalAddress: NSObject?, completionHandler: ObjCBlock?) { fail(completionHandler) }

    @ObjCMethod("reverseGeocodeLocation:completionHandler:")
    func reverseGeocode(_ location: NSObject?, completionHandler: ObjCBlock?) { fail(completionHandler) }

    @ObjCMethod("reverseGeocodeLocation:preferredLocale:completionHandler:")
    func reverseGeocode(_ location: NSObject?, preferredLocale: NSObject?, completionHandler: ObjCBlock?) { fail(completionHandler) }
}

final class PlacemarkState: ObjectState {
    var location: CLLocation?
    var addressDictionary: NSDictionary?
    var region: NSObject?
    var areasOfInterest: NSObject?
}

@ObjCClass("CLPlacemark")
open class CLPlacemark: NSObject {
    static let states = StateTable<PlacemarkState>()
    var placemark: PlacemarkState { CLPlacemark.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CLPlacemark.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CLPlacemark.objCClass.pointer)
    }

    @ObjCMethod("initWithPlacemark:")
    func initialize(placemark other: CLPlacemark) -> Self {
        let state = placemark, source = other.placemark
        (state.location, state.addressDictionary, state.region, state.areasOfInterest) =
            (source.location, source.addressDictionary, source.region, source.areasOfInterest)
        return self
    }

    /// Darwin's own initializer, which MKPlacemark's call.
    @ObjCMethod("initWithLocation:addressDictionary:region:areasOfInterest:")
    func initialize(location: CLLocation?, addressDictionary: NSDictionary?, region: NSObject?, areasOfInterest: NSObject?) -> Self {
        (placemark.location, placemark.addressDictionary, placemark.region, placemark.areasOfInterest) =
            (location, addressDictionary, region, areasOfInterest)
        return self
    }

    @ObjCMethod("location") func location() -> CLLocation? { placemark.location }
    @ObjCMethod("region") func region() -> NSObject? { placemark.region }
    @ObjCMethod("areasOfInterest") func areasOfInterest() -> NSObject? { placemark.areasOfInterest }
    @ObjCMethod("addressDictionary") func addressDictionary() -> NSDictionary? { placemark.addressDictionary }
    @ObjCMethod("timeZone") func timeZone() -> NSObject? { nil }
    @ObjCMethod("postalAddress") func postalAddress() -> NSObject? { nil }
    @ObjCMethod("inlandWater") func inlandWater() -> String? { nil }
    @ObjCMethod("ocean") func ocean() -> String? { nil }

    /// The address's fields, under the Address Book keys Darwin uses.
    private func field(_ key: String) -> String? { placemark.addressDictionary?.object(forKey: key)?.stringValue }

    @ObjCMethod("name") func name() -> String? { field("Name") }
    @ObjCMethod("thoroughfare") func thoroughfare() -> String? { field("Thoroughfare") }
    @ObjCMethod("subThoroughfare") func subThoroughfare() -> String? { field("SubThoroughfare") }
    @ObjCMethod("locality") func locality() -> String? { field("City") }
    @ObjCMethod("subLocality") func subLocality() -> String? { field("SubLocality") }
    @ObjCMethod("administrativeArea") func administrativeArea() -> String? { field("State") }
    @ObjCMethod("subAdministrativeArea") func subAdministrativeArea() -> String? { field("SubAdministrativeArea") }
    @ObjCMethod("postalCode") func postalCode() -> String? { field("ZIP") }
    @ObjCMethod("ISOcountryCode") func isoCountryCode() -> String? { field("CountryCode") }
    @ObjCMethod("country") func country() -> String? { field("Country") }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}

extension NSObject {
    var stringValue: String { String(objCArgument: objcObject) }
}
