// MarketplaceKit's AppDistributor: where the app was installed from, which
// advertising and analytics libraries ask when the system is iOS 17.4 or
// later. Apps here are their owners' App Store copies, so that is the
// answer; no region is eligible for other marketplaces.

@available(iOS 17.4, *)
public enum AppDistributor {
    public static var current: AppDistributor {
        get async throws { .appStore }
    }

    @available(iOS 26.4, *)
    public static var eligibilityRegion: String? {
        get async { nil }
    }

    case appStore
    case testFlight
    case marketplace(String)
    @available(iOS 17.5, *)
    case web
    case other
}

public typealias AppleItemID = UInt64
