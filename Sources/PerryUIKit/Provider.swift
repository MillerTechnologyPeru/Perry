import CPerryGeometry
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryUIKit: the provider for UIKit.framework. PerryProviderPlugin
// generates its perry_provider_startup and perry_provider_symbol from the
// module's Objective-C declarations; this file adds the provider's own
// steps. UIKit is a client of libobjc's C API and of Foundation's classes,
// which the loader starts first, and draws with CoreGraphics' C API. Its
// views are backed by QuartzCore's layers, which start before it.

private let libobjc = "/usr/lib/libobjc.A.dylib"

/// Before the generated startup defines UIKit's classes: binds libobjc's C
/// API and checks Foundation is running.
func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    // Before the app's code runs.
    SDL.prepareEnvironment()
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    let loaded = ObjCRuntime.load { symbol(libobjc, $0) }
    guard loaded, Classes.named("NSString") != nil else {
        uikitFatal("UIKit needs libPerryobjc and libPerryFoundation, which are missing or incomplete")
    }
    Methods.implementation = symbol(libobjc, "_class_getMethodImplementation").map { unsafeBitCast($0, to: Methods.Implementation.self) }
    guard Methods.implementation != nil, CG.load(symbol) else {
        uikitFatal("UIKit needs libPerryCoreGraphics, which is missing or incomplete")
    }
    guard Updates.load(symbol) else { uikitFatal("UIKit needs libdispatch's main queue") }
    Display.load(symbol)
    guard QuartzCore.load(symbol) else { uikitFatal("UIKit needs libPerryQuartzCore, which is missing or incomplete") }
    Accessibility.load { symbol(libobjc, $0) }
    AssetCatalog.load(symbol)
    #if !arch(arm)
    // A Mac app's WebKit is AppKit's; UIKit, there for its CoreText, keeps
    // its own WebKit classes under names of its own. armv7 runs only iOS apps.
    if isMacApp(info.main_header) {
        let webKitClasses = ["WKContentWorld", "WKHTTPCookieStore", "WKNavigation", "WKPreferences", "WKProcessPool",
                             "WKUserContentController", "WKUserScript", "WKWebView", "WKWebViewConfiguration",
                             "WKWebpagePreferences", "WKWebsiteDataStore"]
        for name in webKitClasses { ObjCRuntime.privateClassNames[name] = "PerryUIKit" + name }
    }
    #endif
    return true
}

#if !arch(arm)
/// Whether the main executable is a macOS program: its LC_BUILD_VERSION's
/// platform is PLATFORM_MACOS.
private func isMacApp(_ header: UnsafeRawPointer?) -> Bool {
    guard let header, header.load(as: UInt32.self) == 0xFEED_FACF else { return false }
    let count = header.load(fromByteOffset: 16, as: UInt32.self)
    var command = header + 32    // mach_header_64
    for _ in 0..<count {
        let cmd = command.load(as: UInt32.self), size = command.load(fromByteOffset: 4, as: UInt32.self)
        if cmd == 0x32 { return command.load(fromByteOffset: 8, as: UInt32.self) == 1 }   // LC_BUILD_VERSION, PLATFORM_MACOS
        guard size >= 8 else { return false }
        command += Int(size)
    }
    return false
}
#endif

/// UIKit's numeric and structure constants, which the loader asks for
/// while binding images, before the provider starts.
func providerSymbol(_ name: String) -> UnsafeMutableRawPointer? { Constants.values[name] ?? GLES.symbol(name) }

enum Constants {
    /// Storage for each constant, made once.
    nonisolated(unsafe) static let values: [String: UnsafeMutableRawPointer] = {
        func value<T>(_ value: T) -> UnsafeMutableRawPointer {
            let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
            storage.initialize(to: value)
            return UnsafeMutableRawPointer(storage)
        }
        return [
            "_UIScrollViewDecelerationRateNormal": value(CGFloat(0.998)),
            "_UIScrollViewDecelerationRateFast": value(CGFloat(0.99)),
            "_UITableViewAutomaticDimension": value(CGFloat(-1)),
            "_UIViewNoIntrinsicMetric": value(CGFloat(-1)),
            "_UIEdgeInsetsZero": value(UIEdgeInsets.zero),
            "_UIOffsetZero": value(CGSize.zero),
            "_UIWindowLevelNormal": value(CGFloat(0)),
            "_UIWindowLevelStatusBar": value(CGFloat(1000)),
            "_UIWindowLevelAlert": value(CGFloat(2000)),
            "_UIBackgroundTaskInvalid": value(UInt(0)),
            // UIAccessibilityNotifications.
            "_UIAccessibilityScreenChangedNotification": value(UInt32(1000)),
            "_UIAccessibilityLayoutChangedNotification": value(UInt32(1001)),
            "_UIAccessibilityAnnouncementNotification": value(UInt32(1008)),
            "_UILayoutFittingCompressedSize": value(CGSize.zero),
            "_UILayoutFittingExpandedSize": value(CGSize(width: 1e7, height: 1e7)),
            "_UIFontWeightUltraLight": value(CGFloat(-0.8)),
            "_UIFontWeightThin": value(CGFloat(-0.6)),
            "_UIFontWeightLight": value(CGFloat(-0.4)),
            "_UIFontWeightRegular": value(CGFloat(0)),
            "_UIFontWeightMedium": value(CGFloat(0.23)),
            "_UIFontWeightSemibold": value(CGFloat(0.3)),
            "_UIFontWeightBold": value(CGFloat(0.4)),
            "_UIFontWeightHeavy": value(CGFloat(0.56)),
            "_UIFontWeightBlack": value(CGFloat(0.62)),
            // UIAccessibilityTraits.
            "_UIAccessibilityTraitNone": value(UInt64(0)),
            "_UIAccessibilityTraitButton": value(UInt64(1 << 0)),
            "_UIAccessibilityTraitLink": value(UInt64(1 << 1)),
            "_UIAccessibilityTraitImage": value(UInt64(1 << 2)),
            "_UIAccessibilityTraitSelected": value(UInt64(1 << 3)),
            "_UIAccessibilityTraitPlaysSound": value(UInt64(1 << 4)),
            "_UIAccessibilityTraitKeyboardKey": value(UInt64(1 << 5)),
            "_UIAccessibilityTraitStaticText": value(UInt64(1 << 6)),
            "_UIAccessibilityTraitSummaryElement": value(UInt64(1 << 7)),
            "_UIAccessibilityTraitNotEnabled": value(UInt64(1 << 8)),
            "_UIAccessibilityTraitUpdatesFrequently": value(UInt64(1 << 9)),
            "_UIAccessibilityTraitSearchField": value(UInt64(1 << 10)),
            "_UIAccessibilityTraitStartsMediaSession": value(UInt64(1 << 11)),
            "_UIAccessibilityTraitAdjustable": value(UInt64(1 << 12)),
            "_UIAccessibilityTraitAllowsDirectInteraction": value(UInt64(1 << 13)),
            "_UIAccessibilityTraitCausesPageTurn": value(UInt64(1 << 14)),
            "_UIAccessibilityTraitTabBar": value(UInt64(1 << 15)),
            "_UIAccessibilityTraitHeader": value(UInt64(1 << 16)),
            "_UICollectionViewFlowLayoutAutomaticSize": value(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                                     height: CGFloat.greatestFiniteMagnitude)),
            "_GLKMatrix4Identity": value(GLKMath.identity4),
            "_GLKMatrix3Identity": value(GLKMath.identity3),
            "_GLKQuaternionIdentity": value(GLKQuaternion(q: (0, 0, 0, 1))),
        ]
    }()
}

/// Reports a fatal error the way UIKit's assertions do, and aborts.
func uikitFatal(_ message: String) -> Never {
    let line = "perry: UIKit: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

enum Classes {
    /// The class named `name`, if one is registered.
    static func named(_ name: String) -> ObjCClass? {
        name.withCString { ObjCRuntime.functions.getClass($0) }.map(ObjCClass.init)
    }
}

/// No assistive settings are on.
@c(_UIAccessibilityIsBoldTextEnabled) public func UIAccessibilityIsBoldTextEnabled() -> Bool { false }
@c(_UIAccessibilityIsGuidedAccessEnabled) public func UIAccessibilityIsGuidedAccessEnabled() -> Bool { false }
@c(_UIAccessibilityIsVoiceOverRunning) public func UIAccessibilityIsVoiceOverRunning() -> Bool { false }
@c(_UIAccessibilityIsSwitchControlRunning) public func UIAccessibilityIsSwitchControlRunning() -> Bool { false }
@c(_UIAccessibilityIsReduceMotionEnabled) public func UIAccessibilityIsReduceMotionEnabled() -> Bool { false }
@c(_UIAccessibilityIsReduceTransparencyEnabled) public func UIAccessibilityIsReduceTransparencyEnabled() -> Bool { false }
@c(_UIAccessibilityIsInvertColorsEnabled) public func UIAccessibilityIsInvertColorsEnabled() -> Bool { false }
@c(_UIAccessibilityButtonShapesEnabled) public func UIAccessibilityButtonShapesEnabled() -> Bool { false }
@c(_UIAccessibilityPrefersCrossFadeTransitions) public func UIAccessibilityPrefersCrossFadeTransitions() -> Bool { false }
@c(_UIAccessibilityIsAssistiveTouchRunning) public func UIAccessibilityIsAssistiveTouchRunning() -> Bool { false }
@c(_UIAccessibilityIsClosedCaptioningEnabled) public func UIAccessibilityIsClosedCaptioningEnabled() -> Bool { false }
@c(_UIAccessibilityIsGrayscaleEnabled) public func UIAccessibilityIsGrayscaleEnabled() -> Bool { false }
@c(_UIAccessibilityIsMonoAudioEnabled) public func UIAccessibilityIsMonoAudioEnabled() -> Bool { false }
@c(_UIAccessibilityIsShakeToUndoEnabled) public func UIAccessibilityIsShakeToUndoEnabled() -> Bool { false }
@c(_UIAccessibilityIsSpeakScreenEnabled) public func UIAccessibilityIsSpeakScreenEnabled() -> Bool { false }
@c(_UIAccessibilityIsSpeakSelectionEnabled) public func UIAccessibilityIsSpeakSelectionEnabled() -> Bool { false }
@c(_UIAccessibilityDarkerSystemColorsEnabled) public func UIAccessibilityDarkerSystemColorsEnabled() -> Bool { false }
@c(_UIAccessibilityShouldDifferentiateWithoutColor)
public func UIAccessibilityShouldDifferentiateWithoutColor() -> Bool { false }

/// libAccessibility's settings, which UIKit and SwiftUI read: all off.
@c(__AXSCommandAndControlEnabled) public func _AXSCommandAndControlEnabled() -> UInt8 { 0 }
@c(__AXSFullKeyboardAccessEnabled) public func _AXSFullKeyboardAccessEnabled() -> UInt8 { 0 }
@c(__AXSHoverTextEnabled) public func _AXSHoverTextEnabled() -> UInt8 { 0 }
@c(__AXSIncreaseButtonLegibility) public func _AXSIncreaseButtonLegibility() -> UInt8 { 0 }
@c(__AXSPhotosensitiveMitigationEnabled) public func _AXSPhotosensitiveMitigationEnabled() -> UInt8 { 0 }

/// Accessibility.framework's Assistive Access, the simplified interface: off.
@c(_AXAssistiveAccessEnabled) public func AXAssistiveAccessEnabled() -> Bool { false }

/// Accessibility's Swift AccessibilitySettings.animatedImagesEnabled: images
/// animate, as they do unless the setting turns them off.
@_silgen_name("_$sSo21AccessibilitySettingsV0A0E21animatedImagesEnabledSbvgZ")
public func AccessibilitySettingsAnimatedImagesEnabled() -> Bool { true }

/// void UIAccessibilityPostNotification(UIAccessibilityNotifications, id):
/// there is no assistive technology to tell.
@c(_UIAccessibilityPostNotification)
public func UIAccessibilityPostNotification(_ notification: UInt32, _ argument: UnsafeMutableRawPointer?) {}
