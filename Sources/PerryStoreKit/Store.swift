import PerryObjCInterop

/// SKErrorDomain's codes: payments are not allowed, the client is not
/// allowed to issue the request.
enum StoreErrors {
    static let domain = "SKErrorDomain"
    static let clientInvalid = 1
    static let paymentNotAllowed = 4

    static func make(_ code: Int) -> NSError { NSError.make(domain: domain, code: code, userInfo: nil) }
}

// MARK: - Requests

/// A request to the App Store, answered on the main queue once started.
@ObjCClass("SKRequest")
open class SKRequest: NSObject {
    /// The delegate, not retained, as StoreKit's is weak.
    var delegateObject: UnsafeMutableRawPointer?
    var cancelled = false

    @ObjCMethod("delegate") func delegate() -> NSObject? { delegateObject.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { delegateObject = delegate?.objcObject }

    @ObjCMethod("start")
    func start() {
        let request = self
        Dispatch.onMain {
            guard !request.cancelled, let delegate = request.delegate() else { return }
            request.answer(delegate)
        }
    }

    @ObjCMethod("cancel") func cancel() { cancelled = true }

    /// What the request tells its delegate: by default, that it failed.
    func answer(_ delegate: NSObject) {
        if delegate.responds(to: "request:didFailWithError:") {
            delegate.sendRequest(self, didFailWithError: StoreErrors.make(StoreErrors.clientInvalid))
        }
    }
}

/// Products by identifier: none is for sale, so every identifier is
/// invalid.
@ObjCClass("SKProductsRequest")
open class SKProductsRequest: SKRequest {
    var identifiers: NSObject?

    @ObjCMethod("initWithProductIdentifiers:")
    func initialize(productIdentifiers: NSObject?) -> Self {
        identifiers = productIdentifiers
        return self
    }

    override func answer(_ delegate: NSObject) {
        let response = SKProductsResponse()
        response.invalid = identifiers?.sendAllObjects() ?? NSObject.array([])
        if delegate.responds(to: "productsRequest:didReceiveResponse:") {
            delegate.sendProductsRequest(self, didReceive: response)
        }
        if delegate.responds(to: "requestDidFinish:") {
            delegate.sendRequestDidFinish(self)
        }
    }
}

@ObjCClass("SKProductsResponse")
open class SKProductsResponse: NSObject {
    var invalid: NSObject?

    @ObjCMethod("products") func products() -> NSObject { NSObject.array([]) }
    @ObjCMethod("invalidProductIdentifiers") func invalidProductIdentifiers() -> NSObject { invalid ?? NSObject.array([]) }
}

/// A receipt can't be refreshed: there is no App Store account.
@ObjCClass("SKReceiptRefreshRequest")
open class SKReceiptRefreshRequest: SKRequest {
    @ObjCMethod("initWithReceiptProperties:") func initialize(receiptProperties: NSObject?) -> Self { self }
    @ObjCMethod("receiptProperties") func receiptProperties() -> NSObject? { nil }
}

/// A product, which no request returns.
@ObjCClass("SKProduct")
open class SKProduct: NSObject {
    @ObjCMethod("productIdentifier") func productIdentifier() -> String { "" }
    @ObjCMethod("localizedTitle") func localizedTitle() -> String { "" }
    @ObjCMethod("localizedDescription") func localizedDescription() -> String { "" }
}

// MARK: - Payments

@ObjCClass("SKPayment")
open class SKPayment: NSObject {
    var identifier: String?
    var count = 1
    var username: String?
    var data: NSObject?

    @ObjCClassMethod("paymentWithProduct:")
    static func payment(product: NSObject?) -> SKPayment {
        let payment = SKMutablePayment()
        payment.identifier = product?.as(SKProduct.self)?.productIdentifier()
        return payment
    }

    @ObjCClassMethod("paymentWithProductIdentifier:")
    static func payment(productIdentifier: String?) -> SKPayment {
        let payment = SKMutablePayment()
        payment.identifier = productIdentifier
        return payment
    }

    @ObjCMethod("productIdentifier") func productIdentifier() -> String? { identifier }
    @ObjCMethod("quantity") func quantity() -> Int { count }
    @ObjCMethod("applicationUsername") func applicationUsername() -> String? { username }
    @ObjCMethod("requestData") func requestData() -> NSObject? { data }
    @ObjCMethod("simulatesAskToBuyInSandbox") func simulatesAskToBuyInSandbox() -> Bool { false }
}

@ObjCClass("SKMutablePayment")
open class SKMutablePayment: SKPayment {
    @ObjCMethod("setProductIdentifier:") func setProductIdentifier(_ value: String?) { identifier = value }
    @ObjCMethod("setQuantity:") func setQuantity(_ value: Int) { count = value }
    @ObjCMethod("setApplicationUsername:") func setApplicationUsername(_ value: String?) { username = value }
    @ObjCMethod("setRequestData:") func setRequestData(_ value: NSObject?) { data = value }
    @ObjCMethod("setSimulatesAskToBuyInSandbox:") func setSimulatesAskToBuyInSandbox(_ value: Bool) {}
}

/// SKPaymentTransactionState: failed, 2.
@ObjCClass("SKPaymentTransaction")
open class SKPaymentTransaction: NSObject {
    var paymentObject: SKPayment?
    var failure: NSError?

    @ObjCMethod("payment") func payment() -> SKPayment? { paymentObject }
    @ObjCMethod("transactionState") func transactionState() -> Int { 2 }
    @ObjCMethod("error") func error() -> NSError? { failure }
    @ObjCMethod("transactionIdentifier") func transactionIdentifier() -> String? { nil }
    @ObjCMethod("transactionDate") func transactionDate() -> NSObject? { nil }
    @ObjCMethod("originalTransaction") func originalTransaction() -> NSObject? { nil }
    @ObjCMethod("transactionReceipt") func transactionReceipt() -> NSObject? { nil }
    @ObjCMethod("downloads") func downloads() -> NSObject { NSObject.array([]) }
}

/// The payment queue: payments can't be made, so each one added fails, and
/// restoring finds nothing.
@ObjCClass("SKPaymentQueue")
open class SKPaymentQueue: NSObject {
    nonisolated(unsafe) static var shared: SKPaymentQueue?
    /// The observers, not retained, as StoreKit's are weak.
    var observers: [UnsafeMutableRawPointer] = []

    @ObjCClassMethod("defaultQueue")
    static func defaultQueue() -> SKPaymentQueue {
        if let shared { return shared }
        let queue = SKPaymentQueue()
        shared = queue
        return queue
    }

    @ObjCClassMethod("canMakePayments") static func canMakePayments() -> Bool { false }

    @ObjCMethod("addTransactionObserver:")
    func addTransactionObserver(_ observer: NSObject?) {
        guard let observer, !observers.contains(observer.objcObject) else { return }
        observers.append(observer.objcObject)
    }

    @ObjCMethod("removeTransactionObserver:")
    func removeTransactionObserver(_ observer: NSObject?) {
        guard let observer else { return }
        observers.removeAll { $0 == observer.objcObject }
    }

    @ObjCMethod("transactionObservers") func transactionObservers() -> NSObject { NSObject.array(observers.map { NSObject($0) }) }
    @ObjCMethod("transactions") func transactions() -> NSObject { NSObject.array([]) }
    @ObjCMethod("storefront") func storefront() -> NSObject? { nil }
    @ObjCMethod("delegate") func delegate() -> NSObject? { nil }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) {}

    @ObjCMethod("addPayment:")
    func addPayment(_ payment: NSObject?) {
        let transaction = SKPaymentTransaction()
        transaction.paymentObject = payment?.as(SKPayment.self)
        transaction.failure = StoreErrors.make(StoreErrors.paymentNotAllowed)
        let queue = self
        Dispatch.onMain {
            let list = NSObject.array([transaction])
            for observer in queue.observers.map({ NSObject($0) })
            where observer.responds(to: "paymentQueue:updatedTransactions:") {
                observer.sendPaymentQueue(queue, updatedTransactions: list)
            }
        }
    }

    @ObjCMethod("finishTransaction:") func finishTransaction(_ transaction: NSObject?) {}

    @ObjCMethod("restoreCompletedTransactions") func restoreCompletedTransactions() { restoreFinished() }

    @ObjCMethod("restoreCompletedTransactionsWithApplicationUsername:")
    func restoreCompletedTransactions(applicationUsername: String?) { restoreFinished() }

    private func restoreFinished() {
        let queue = self
        Dispatch.onMain {
            for observer in queue.observers.map({ NSObject($0) })
            where observer.responds(to: "paymentQueueRestoreCompletedTransactionsFinished:") {
                observer.sendPaymentQueueRestoreCompletedTransactionsFinished(queue)
            }
        }
    }

    @ObjCMethod("presentCodeRedemptionSheet") func presentCodeRedemptionSheet() {}
    @ObjCMethod("showPriceConsentIfNeeded") func showPriceConsentIfNeeded() {}
}

// MARK: - Reviews and ad attribution

/// Asking for a review shows nothing.
@ObjCClass("SKStoreReviewController")
open class SKStoreReviewController: NSObject {
    @ObjCClassMethod("requestReview") static func requestReview() {}
    @ObjCClassMethod("requestReviewInScene:") static func requestReview(in scene: NSObject?) {}
}

/// Ad network attribution, with no App Store to report to.
@ObjCClass("SKAdNetwork")
open class SKAdNetwork: NSObject {
    @ObjCClassMethod("registerAppForAdNetworkAttribution") static func registerAppForAdNetworkAttribution() {}
    @ObjCClassMethod("updateConversionValue:") static func updateConversionValue(_ value: Int) {}

    // Postback conversion values, which there is no ad network here to
    // take: the handler hears of no error, as it does once one is noted.
    @ObjCClassMethod("updatePostbackConversionValue:completionHandler:")
    static func updatePostbackConversionValue(_ value: Int, completionHandler: ObjCBlock?) { noted(completionHandler) }

    @ObjCClassMethod("updatePostbackConversionValue:coarseValue:completionHandler:")
    static func updatePostbackConversionValue(_ value: Int, coarseValue: NSObject?, completionHandler: ObjCBlock?) {
        noted(completionHandler)
    }

    @ObjCClassMethod("updatePostbackConversionValue:coarseValue:lockWindow:completionHandler:")
    static func updatePostbackConversionValue(_ value: Int, coarseValue: NSObject?, lockWindow: Bool, completionHandler: ObjCBlock?) {
        noted(completionHandler)
    }

    // View-through impressions (iOS 14.5), which ad SDKs start when an ad
    // shows and end when it goes: noted with no error.
    @ObjCClassMethod("startImpression:completionHandler:")
    static func startImpression(_ impression: NSObject?, completionHandler: ObjCBlock?) { noted(completionHandler) }

    @ObjCClassMethod("endImpression:completionHandler:")
    static func endImpression(_ impression: NSObject?, completionHandler: ObjCBlock?) { noted(completionHandler) }

    /// Calls a `^(NSError *error)` handler with no error.
    private static func noted(_ handler: ObjCBlock?) {
        guard let handler else { return }
        handler.function(as: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void).self)(handler.object, nil)
    }
}

/// An ad's view-through impression: what an ad SDK fills in to start and
/// end one with SKAdNetwork. It keeps what it is given.
@ObjCClass("SKAdImpression")
open class SKAdImpression: NSObject {
    var values: [String: NSObject] = [:]

    @ObjCMethod("initWithSourceAppStoreItemIdentifier:advertisedAppStoreItemIdentifier:adNetworkIdentifier:adCampaignIdentifier:adImpressionIdentifier:timestamp:signature:version:")
    func initialize(source: NSObject?, advertised: NSObject?, network: NSObject?, campaign: NSObject?,
                    impression: NSObject?, timestamp: NSObject?, signature: NSObject?, version: NSObject?) -> Self {
        for (key, value) in [("sourceAppStoreItemIdentifier", source), ("advertisedAppStoreItemIdentifier", advertised),
                             ("adNetworkIdentifier", network), ("adCampaignIdentifier", campaign),
                             ("sourceIdentifier", campaign), ("adImpressionIdentifier", impression),
                             ("timestamp", timestamp), ("signature", signature), ("version", version)] {
            values[key] = value
        }
        return self
    }

    @ObjCMethod("sourceAppStoreItemIdentifier") func sourceAppStoreItemIdentifier() -> NSObject? { values["sourceAppStoreItemIdentifier"] }
    @ObjCMethod("setSourceAppStoreItemIdentifier:") func setSourceAppStoreItemIdentifier(_ value: NSObject?) { values["sourceAppStoreItemIdentifier"] = value }
    @ObjCMethod("advertisedAppStoreItemIdentifier") func advertisedAppStoreItemIdentifier() -> NSObject? { values["advertisedAppStoreItemIdentifier"] }
    @ObjCMethod("setAdvertisedAppStoreItemIdentifier:") func setAdvertisedAppStoreItemIdentifier(_ value: NSObject?) { values["advertisedAppStoreItemIdentifier"] = value }
    @ObjCMethod("adNetworkIdentifier") func adNetworkIdentifier() -> NSObject? { values["adNetworkIdentifier"] }
    @ObjCMethod("setAdNetworkIdentifier:") func setAdNetworkIdentifier(_ value: NSObject?) { values["adNetworkIdentifier"] = value }
    @ObjCMethod("adCampaignIdentifier") func adCampaignIdentifier() -> NSObject? { values["adCampaignIdentifier"] }
    @ObjCMethod("setAdCampaignIdentifier:") func setAdCampaignIdentifier(_ value: NSObject?) { values["adCampaignIdentifier"] = value }
    @ObjCMethod("sourceIdentifier") func sourceIdentifier() -> NSObject? { values["sourceIdentifier"] }
    @ObjCMethod("setSourceIdentifier:") func setSourceIdentifier(_ value: NSObject?) { values["sourceIdentifier"] = value }
    @ObjCMethod("adImpressionIdentifier") func adImpressionIdentifier() -> NSObject? { values["adImpressionIdentifier"] }
    @ObjCMethod("setAdImpressionIdentifier:") func setAdImpressionIdentifier(_ value: NSObject?) { values["adImpressionIdentifier"] = value }
    @ObjCMethod("adType") func adType() -> NSObject? { values["adType"] }
    @ObjCMethod("setAdType:") func setAdType(_ value: NSObject?) { values["adType"] = value }
    @ObjCMethod("adDescription") func adDescription() -> NSObject? { values["adDescription"] }
    @ObjCMethod("setAdDescription:") func setAdDescription(_ value: NSObject?) { values["adDescription"] = value }
    @ObjCMethod("adPurchaserName") func adPurchaserName() -> NSObject? { values["adPurchaserName"] }
    @ObjCMethod("setAdPurchaserName:") func setAdPurchaserName(_ value: NSObject?) { values["adPurchaserName"] = value }
    @ObjCMethod("timestamp") func timestamp() -> NSObject? { values["timestamp"] }
    @ObjCMethod("setTimestamp:") func setTimestamp(_ value: NSObject?) { values["timestamp"] = value }
    @ObjCMethod("signature") func signature() -> NSObject? { values["signature"] }
    @ObjCMethod("setSignature:") func setSignature(_ value: NSObject?) { values["signature"] = value }
    @ObjCMethod("version") func version() -> NSObject? { values["version"] }
    @ObjCMethod("setVersion:") func setVersion(_ value: NSObject?) { values["version"] = value }
}

// MARK: - Delegate messages

extension NSObject {
    @ObjCMethod("request:didFailWithError:") func sendRequest(_ request: SKRequest, didFailWithError error: NSError)
    @ObjCMethod("requestDidFinish:") func sendRequestDidFinish(_ request: SKRequest)
    @ObjCMethod("productsRequest:didReceiveResponse:")
    func sendProductsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse)
    @ObjCMethod("paymentQueue:updatedTransactions:") func sendPaymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: NSObject)
    @ObjCMethod("paymentQueueRestoreCompletedTransactionsFinished:")
    func sendPaymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue)
}

// MARK: - Constants

@ObjCConstants
enum StoreConstants {
    static let SKErrorDomain = "SKErrorDomain"
    static let SKStoreProductParameterITunesItemIdentifier = "id"
    static let SKStoreProductParameterProductIdentifier = "productIdentifier"
    static let SKStoreProductParameterAffiliateToken = "at"
    static let SKStoreProductParameterCampaignToken = "ct"
    static let SKStoreProductParameterProviderToken = "pt"
    static let SKStoreProductParameterAdvertisingPartnerToken = "advp"
    static let SKStoreProductParameterAdNetworkIdentifier = "adNetworkId"
    static let SKStoreProductParameterAdNetworkCampaignIdentifier = "adNetworkCampaignId"
    static let SKStoreProductParameterAdNetworkTimestamp = "adNetworkImpressionTimestamp"
    static let SKStoreProductParameterAdNetworkNonce = "adNetworkNonce"
    static let SKStoreProductParameterAdNetworkAttributionSignature = "adNetworkAttributionSignature"
    static let SKStoreProductParameterAdNetworkSourceAppStoreIdentifier = "adNetworkSourceAppStoreIdentifier"
    static let SKStoreProductParameterAdNetworkVersion = "adNetworkPayloadVersion"
    static let SKStoreProductParameterAdNetworkSourceIdentifier = "adNetworkSourceIdentifier"
    static let SKStoreProductParameterCustomProductPageIdentifier = "customProductPageIdentifier"
    static let SKANErrorDomain = "SKANErrorDomain"
    static let SKPaymentQueueDidChangeStorefrontNotification = "SKPaymentQueueDidChangeStorefrontNotification"
    static let SKStorefrontCountryCodeDidChangeNotification = "SKStorefrontCountryCodeDidChangeNotification"
}
