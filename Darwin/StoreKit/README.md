# StoreKit

Perry's `StoreKit.framework` Swift part: StoreKit 2's `Product`,
`Transaction`, `VerificationResult` and `AppStore`, for apps that check what
has been bought. There is no App Store here: nothing has been bought, no
product is for sale, and a purchase ends as cancelled.
`Scripts/build-framework.sh StoreKit` builds it on a Mac into the Swift
runtime directory (`PERRY_SWIFT_RUNTIME`), where the loader finds it.

Declarations follow the iOS SDK's StoreKit interface (frozen types and their
cases), so apps built against Apple's bind to them by the same symbols.
StoreKit's Objective-C classes (`SKPaymentQueue` and the rest) aren't here.
