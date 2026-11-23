import Foundation

// AppKit's Cocoa error codes: text reading and writing, services, sharing
// services and fonts, under their current names and the deprecated ones.
// The values are AppKitErrors.h's, which Swift's import of it leaves out.

@available(macOS 10.9, *)
extension CocoaError.Code {
    public static var textReadInapplicableDocumentType: CocoaError.Code { CocoaError.Code(rawValue: 65806) }
    public static var textWriteInapplicableDocumentType: CocoaError.Code { CocoaError.Code(rawValue: 66062) }
    public static var serviceApplicationNotFound: CocoaError.Code { CocoaError.Code(rawValue: 66560) }
    public static var serviceApplicationLaunchFailed: CocoaError.Code { CocoaError.Code(rawValue: 66561) }
    public static var serviceRequestTimedOut: CocoaError.Code { CocoaError.Code(rawValue: 66562) }
    public static var serviceInvalidPasteboardData: CocoaError.Code { CocoaError.Code(rawValue: 66563) }
    public static var serviceMalformedServiceDictionary: CocoaError.Code { CocoaError.Code(rawValue: 66564) }
    public static var serviceMiscellaneousError: CocoaError.Code { CocoaError.Code(rawValue: 66800) }
    public static var sharingServiceNotConfigured: CocoaError.Code { CocoaError.Code(rawValue: 67072) }
    @available(macOS 10.13, *)
    public static var fontAssetDownloadError: CocoaError.Code { CocoaError.Code(rawValue: 66304) }
}

@available(macOS 10.9, *)
extension CocoaError.Code {
    @available(*, deprecated, renamed: "textReadInapplicableDocumentType")
    public static var textReadInapplicableDocumentTypeError: CocoaError.Code { CocoaError.Code(rawValue: 65806) }
    @available(*, deprecated, renamed: "textWriteInapplicableDocumentType")
    public static var textWriteInapplicableDocumentTypeError: CocoaError.Code { CocoaError.Code(rawValue: 66062) }
    @available(*, deprecated, renamed: "serviceApplicationNotFound")
    public static var serviceApplicationNotFoundError: CocoaError.Code { CocoaError.Code(rawValue: 66560) }
    @available(*, deprecated, renamed: "serviceApplicationLaunchFailed")
    public static var serviceApplicationLaunchFailedError: CocoaError.Code { CocoaError.Code(rawValue: 66561) }
    @available(*, deprecated, renamed: "serviceRequestTimedOut")
    public static var serviceRequestTimedOutError: CocoaError.Code { CocoaError.Code(rawValue: 66562) }
    @available(*, deprecated, renamed: "serviceInvalidPasteboardData")
    public static var serviceInvalidPasteboardDataError: CocoaError.Code { CocoaError.Code(rawValue: 66563) }
    @available(*, deprecated, renamed: "serviceMalformedServiceDictionary")
    public static var serviceMalformedServiceDictionaryError: CocoaError.Code { CocoaError.Code(rawValue: 66564) }
    @available(*, deprecated, renamed: "serviceMiscellaneousError")
    public static var serviceMiscellaneous: CocoaError.Code { CocoaError.Code(rawValue: 66800) }
    @available(*, deprecated, renamed: "sharingServiceNotConfigured")
    public static var sharingServiceNotConfiguredError: CocoaError.Code { CocoaError.Code(rawValue: 67072) }
}

@available(macOS 10.9, *)
extension CocoaError.Code {
    @available(*, deprecated, renamed: "textReadInapplicableDocumentType")
    public static var TextReadInapplicableDocumentTypeError: CocoaError.Code { CocoaError.Code(rawValue: 65806) }
    @available(*, deprecated, renamed: "textWriteInapplicableDocumentType")
    public static var TextWriteInapplicableDocumentTypeError: CocoaError.Code { CocoaError.Code(rawValue: 66062) }
    @available(*, deprecated, renamed: "serviceApplicationNotFound")
    public static var ServiceApplicationNotFoundError: CocoaError.Code { CocoaError.Code(rawValue: 66560) }
    @available(*, deprecated, renamed: "serviceApplicationLaunchFailed")
    public static var ServiceApplicationLaunchFailedError: CocoaError.Code { CocoaError.Code(rawValue: 66561) }
    @available(*, deprecated, renamed: "serviceRequestTimedOut")
    public static var ServiceRequestTimedOutError: CocoaError.Code { CocoaError.Code(rawValue: 66562) }
    @available(*, deprecated, renamed: "serviceInvalidPasteboardData")
    public static var ServiceInvalidPasteboardDataError: CocoaError.Code { CocoaError.Code(rawValue: 66563) }
    @available(*, deprecated, renamed: "serviceMalformedServiceDictionary")
    public static var ServiceMalformedServiceDictionaryError: CocoaError.Code { CocoaError.Code(rawValue: 66564) }
    @available(*, deprecated, renamed: "serviceMiscellaneous")
    public static var ServiceMiscellaneousError: CocoaError.Code { CocoaError.Code(rawValue: 66800) }
    @available(*, deprecated, renamed: "sharingServiceNotConfigured")
    public static var SharingServiceNotConfiguredError: CocoaError.Code { CocoaError.Code(rawValue: 67072) }
}

@available(macOS 10.9, *)
extension CocoaError {
    public static var textReadInapplicableDocumentType: CocoaError.Code { CocoaError.Code(rawValue: 65806) }
    public static var textWriteInapplicableDocumentType: CocoaError.Code { CocoaError.Code(rawValue: 66062) }
    public static var serviceApplicationNotFound: CocoaError.Code { CocoaError.Code(rawValue: 66560) }
    public static var serviceApplicationLaunchFailed: CocoaError.Code { CocoaError.Code(rawValue: 66561) }
    public static var serviceRequestTimedOut: CocoaError.Code { CocoaError.Code(rawValue: 66562) }
    public static var serviceInvalidPasteboardData: CocoaError.Code { CocoaError.Code(rawValue: 66563) }
    public static var serviceMalformedServiceDictionary: CocoaError.Code { CocoaError.Code(rawValue: 66564) }
    public static var serviceMiscellaneous: CocoaError.Code { CocoaError.Code(rawValue: 66800) }
    public static var sharingServiceNotConfigured: CocoaError.Code { CocoaError.Code(rawValue: 67072) }
    @available(macOS 10.13, *)
    public static var fontAssetDownloadError: CocoaError.Code { CocoaError.Code(rawValue: 66304) }
}

@available(macOS 10.9, *)
extension CocoaError {
    @available(*, deprecated, renamed: "textReadInapplicableDocumentType")
    public static var textReadInapplicableDocumentTypeError: CocoaError.Code { CocoaError.Code(rawValue: 65806) }
    @available(*, deprecated, renamed: "textWriteInapplicableDocumentType")
    public static var textWriteInapplicableDocumentTypeError: CocoaError.Code { CocoaError.Code(rawValue: 66062) }
    @available(*, deprecated, renamed: "serviceApplicationNotFound")
    public static var serviceApplicationNotFoundError: CocoaError.Code { CocoaError.Code(rawValue: 66560) }
    @available(*, deprecated, renamed: "serviceApplicationLaunchFailed")
    public static var serviceApplicationLaunchFailedError: CocoaError.Code { CocoaError.Code(rawValue: 66561) }
    @available(*, deprecated, renamed: "serviceRequestTimedOut")
    public static var serviceRequestTimedOutError: CocoaError.Code { CocoaError.Code(rawValue: 66562) }
    @available(*, deprecated, renamed: "serviceInvalidPasteboardData")
    public static var serviceInvalidPasteboardDataError: CocoaError.Code { CocoaError.Code(rawValue: 66563) }
    @available(*, deprecated, renamed: "serviceMalformedServiceDictionary")
    public static var serviceMalformedServiceDictionaryError: CocoaError.Code { CocoaError.Code(rawValue: 66564) }
    @available(*, deprecated, renamed: "serviceMiscellaneous")
    public static var serviceMiscellaneousError: CocoaError.Code { CocoaError.Code(rawValue: 66800) }
    @available(*, deprecated, renamed: "sharingServiceNotConfigured")
    public static var sharingServiceNotConfiguredError: CocoaError.Code { CocoaError.Code(rawValue: 67072) }
}

@available(macOS 10.9, *)
extension CocoaError {
    @available(*, deprecated, renamed: "textReadInapplicableDocumentType")
    public static var TextReadInapplicableDocumentTypeError: CocoaError.Code { CocoaError.Code(rawValue: 65806) }
    @available(*, deprecated, renamed: "textWriteInapplicableDocumentType")
    public static var TextWriteInapplicableDocumentTypeError: CocoaError.Code { CocoaError.Code(rawValue: 66062) }
    @available(*, deprecated, renamed: "serviceApplicationNotFound")
    public static var ServiceApplicationNotFoundError: CocoaError.Code { CocoaError.Code(rawValue: 66560) }
    @available(*, deprecated, renamed: "serviceApplicationLaunchFailed")
    public static var ServiceApplicationLaunchFailedError: CocoaError.Code { CocoaError.Code(rawValue: 66561) }
    @available(*, deprecated, renamed: "serviceRequestTimedOut")
    public static var ServiceRequestTimedOutError: CocoaError.Code { CocoaError.Code(rawValue: 66562) }
    @available(*, deprecated, renamed: "serviceInvalidPasteboardData")
    public static var ServiceInvalidPasteboardDataError: CocoaError.Code { CocoaError.Code(rawValue: 66563) }
    @available(*, deprecated, renamed: "serviceMalformedServiceDictionary")
    public static var ServiceMalformedServiceDictionaryError: CocoaError.Code { CocoaError.Code(rawValue: 66564) }
    @available(*, deprecated, renamed: "serviceMiscellaneous")
    public static var ServiceMiscellaneousError: CocoaError.Code { CocoaError.Code(rawValue: 66800) }
    @available(*, deprecated, renamed: "sharingServiceNotConfigured")
    public static var SharingServiceNotConfiguredError: CocoaError.Code { CocoaError.Code(rawValue: 67072) }
}

@available(macOS 10.9, *)
extension CocoaError {
    public var isServiceError: Bool {
        (66560...66817).contains(code.rawValue)
    }

    public var isSharingServiceError: Bool {
        (67072...67327).contains(code.rawValue)
    }

    public var isTextReadWriteError: Bool {
        (65792...66303).contains(code.rawValue)
    }

    @available(macOS 10.13, *)
    public var isFontError: Bool {
        (66304...66335).contains(code.rawValue)
    }
}
