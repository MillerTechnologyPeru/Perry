import FoundationEssentials
import PerryObjCInterop
import PerryURLLoading

// NSURLResponse and NSHTTPURLResponse hold a PerryURLLoading response.

enum Responses {
    static let states = StateTable<Response>()

    static func response(_ object: UnsafeMutableRawPointer) -> Response? { states.get(object) }

    /// The object for a response: NSHTTPURLResponse for HTTP's.
    static func object(_ response: Response) -> NSObject {
        let cls = response.isHTTP ? NSHTTPURLResponse.objCClass : NSURLResponse.objCClass
        let object = cls.autoreleasedInstance()
        states.set(object.objcObject, response)
        return object
    }
}

/// NSURLResponse.
@ObjCClass("NSURLResponse")
open class NSURLResponse: NSObject {
    var response: Response? { Responses.response(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Responses.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLResponse.objCClass.pointer)
    }

    @ObjCMethod("initWithURL:MIMEType:expectedContentLength:textEncodingName:")
    func initialize(url: NSURL, mimeType: String?, expectedContentLength length: Int, textEncodingName: String?) -> Self {
        if let url = url.url {
            Responses.states.set(objcObject, Response(url: url, mimeType: mimeType, expectedLength: length,
                                                      textEncodingName: textEncodingName))
        }
        return self
    }

    @ObjCMethod("URL") func url() -> NSURL? { response?.url.flatMap(NSURL.of) }
    @ObjCMethod("MIMEType") func mimeType() -> String? { response?.mimeType }
    @ObjCMethod("expectedContentLength") func expectedContentLength() -> Int64 { response?.expectedLength ?? -1 }
    @ObjCMethod("textEncodingName") func textEncodingName() -> String? { response?.textEncodingName }
    @ObjCMethod("suggestedFilename") func suggestedFilename() -> String? { response?.suggestedFilename }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("description")
    func description() -> String {
        let name = isKind(of: NSHTTPURLResponse.objCClass) ? "NSHTTPURLResponse" : "NSURLResponse"
        return "<\(name): \(objcObject)> { URL: \(response?.url?.absoluteString ?? "(null)") }"
    }
}

/// NSHTTPURLResponse.
@ObjCClass("NSHTTPURLResponse")
open class NSHTTPURLResponse: NSURLResponse {
    @ObjCMethod("initWithURL:statusCode:HTTPVersion:headerFields:")
    func initialize(url: NSURL, statusCode: Int, httpVersion: String?, headerFields: NSDictionary?) -> UnsafeMutableRawPointer? {
        guard let url = url.url,
              let response = Response(url: url, statusCode: statusCode, httpVersion: httpVersion,
                                      headers: headerFields?.strings) else { return nil }
        Responses.states.set(objcObject, response)
        // The receiver's wrapper adopted its reference; the result is +1.
        return ObjCRuntime.retain(objcObject)
    }

    @ObjCMethod("statusCode") func statusCode() -> Int { response?.statusCode ?? 0 }

    @ObjCMethod("allHeaderFields")
    func allHeaderFields() -> NSDictionary {
        NSMutableDictionary.of((response?.headers ?? []).map { ($0.name, NSObject.string($0.value)) })
    }

    @ObjCMethod("valueForHTTPHeaderField:") func value(forHTTPHeaderField name: String) -> String? { response?.header(name) }

    @ObjCClassMethod("localizedStringForStatusCode:")
    static func localizedString(forStatusCode code: Int) -> String { Response.localizedString(forStatusCode: code) }
}
