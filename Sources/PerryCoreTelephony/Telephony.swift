import PerryObjCInterop

/// The network information of a device without a SIM: no carrier and no
/// radio access technology.
@ObjCClass("CTTelephonyNetworkInfo")
open class CTTelephonyNetworkInfo: NSObject {
    @ObjCMethod("subscriberCellularProvider") func subscriberCellularProvider() -> NSObject? { nil }
    @ObjCMethod("serviceSubscriberCellularProviders") func serviceSubscriberCellularProviders() -> NSObject? { nil }
    @ObjCMethod("currentRadioAccessTechnology") func currentRadioAccessTechnology() -> NSObject? { nil }
    @ObjCMethod("serviceCurrentRadioAccessTechnology") func serviceCurrentRadioAccessTechnology() -> NSObject? { nil }
    @ObjCMethod("dataServiceIdentifier") func dataServiceIdentifier() -> NSObject? { nil }
    @ObjCMethod("delegate") func delegate() -> NSObject? { nil }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) {}
    @ObjCMethod("subscriberCellularProviderDidUpdateNotifier") func subscriberCellularProviderDidUpdateNotifier() -> NSObject? { nil }
    @ObjCMethod("setSubscriberCellularProviderDidUpdateNotifier:")
    func setSubscriberCellularProviderDidUpdateNotifier(_ notifier: NSObject?) {}
}

/// No calls are ever in progress.
@ObjCClass("CTCallCenter")
open class CTCallCenter: NSObject {
    @ObjCMethod("currentCalls") func currentCalls() -> NSObject? { nil }
    @ObjCMethod("callEventHandler") func callEventHandler() -> NSObject? { nil }
    @ObjCMethod("setCallEventHandler:") func setCallEventHandler(_ handler: NSObject?) {}
}

/// Radio access technologies and the notification of a change.
@ObjCConstants
enum TelephonyConstants {
    static let CTRadioAccessTechnologyDidChangeNotification = "kCTRadioAccessTechnologyDidChangeNotification"
    static let CTServiceRadioAccessTechnologyDidChangeNotification = "kCTServiceRadioAccessTechnologyDidChangeNotification"
    static let CTRadioAccessTechnologyGPRS = "CTRadioAccessTechnologyGPRS"
    static let CTRadioAccessTechnologyEdge = "CTRadioAccessTechnologyEdge"
    static let CTRadioAccessTechnologyWCDMA = "CTRadioAccessTechnologyWCDMA"
    static let CTRadioAccessTechnologyHSDPA = "CTRadioAccessTechnologyHSDPA"
    static let CTRadioAccessTechnologyHSUPA = "CTRadioAccessTechnologyHSUPA"
    static let CTRadioAccessTechnologyCDMA1x = "CTRadioAccessTechnologyCDMA1x"
    static let CTRadioAccessTechnologyCDMAEVDORev0 = "CTRadioAccessTechnologyCDMAEVDORev0"
    static let CTRadioAccessTechnologyCDMAEVDORevA = "CTRadioAccessTechnologyCDMAEVDORevA"
    static let CTRadioAccessTechnologyCDMAEVDORevB = "CTRadioAccessTechnologyCDMAEVDORevB"
    static let CTRadioAccessTechnologyeHRPD = "CTRadioAccessTechnologyeHRPD"
    static let CTRadioAccessTechnologyLTE = "CTRadioAccessTechnologyLTE"
    static let CTRadioAccessTechnologyNRNSA = "CTRadioAccessTechnologyNRNSA"
    static let CTRadioAccessTechnologyNR = "CTRadioAccessTechnologyNR"
}
