import Foundation

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
public enum CGContentToneMappingInfo {
    public enum LightLevel: Equatable, Hashable {
        case relative(Float)
        case nits(Int)
    }

    public enum DynamicRange: Equatable, Hashable {
        case high
        case constrained
        case standard
    }

    public struct DefaultOptions: Equatable, Hashable {
        public var contentAverageLightLevel: LightLevel
        public var preferredDynamicRange: DynamicRange

        public init() {
            contentAverageLightLevel = .relative(0)
            preferredDynamicRange = .standard
        }

        @_alwaysEmitIntoClient
        public init(contentAverageLightLevel: LightLevel = .relative(0.0), preferredDynamicRange: DynamicRange = .standard) {
            self.init()
            self.contentAverageLightLevel = contentAverageLightLevel
            self.preferredDynamicRange = preferredDynamicRange
        }
    }

    public struct ITURecommendedOptions: Equatable, Hashable {
        public var skipBoostToHDR: Bool
        public var use100nitsHLGOOTF: Bool
        public var useBT1886ForCoreVideoGamma: Bool
        public var useLegacyHDREcosystem: Bool

        public init() {
            skipBoostToHDR = true
            use100nitsHLGOOTF = true
            useBT1886ForCoreVideoGamma = true
            useLegacyHDREcosystem = true
        }

        @_alwaysEmitIntoClient
        public init(skipBoostToHDR: Bool = true, use100nitsHLGOOTF: Bool = true, useBT1886ForCoreVideoGamma: Bool = true,
                    useLegacyHDREcosystem: Bool = true) {
            self.init()
            self.skipBoostToHDR = skipBoostToHDR
            self.use100nitsHLGOOTF = use100nitsHLGOOTF
            self.useBT1886ForCoreVideoGamma = useBT1886ForCoreVideoGamma
            self.useLegacyHDREcosystem = useLegacyHDREcosystem
        }
    }

    public struct EXRGammaOptions: Equatable, Hashable {
        public var defog: Float
        public var exposure: Float
        public var kneeHigh: Float
        public var kneeLow: Float

        public init() {
            defog = 0
            exposure = 0
            kneeHigh = 5
            kneeLow = 0
        }

        @_alwaysEmitIntoClient
        public init(defog: Float = 0.0, exposure: Float = 0.0, kneeHigh: Float = 5.0, kneeLow: Float = 0.0) {
            self.init()
            self.defog = defog
            self.exposure = exposure
            self.kneeHigh = kneeHigh
            self.kneeLow = kneeLow
        }
    }

    case `default`(DefaultOptions)
    case imageSpecificLumaScaling(DefaultOptions)
    case referenceWhiteBased(DefaultOptions)
    case ituRecommended(ITURecommendedOptions)
    case exrGamma(EXRGammaOptions)
    case none
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CGContentToneMappingInfo: Equatable, Hashable {}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CGContentToneMappingInfo: Identifiable {
    @_alwaysEmitIntoClient public var id: CGToneMapping {
        switch self {
        case .default: .default
        case .imageSpecificLumaScaling: .imageSpecificLumaScaling
        case .referenceWhiteBased: .referenceWhiteBased
        case .ituRecommended: .ituRecommended
        case .exrGamma: .exrGamma
        case .none: .none
        @unknown default: .none
        }
    }
}

// The C form: a method and a dictionary of its options.

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CGContentToneMappingInfo.DefaultOptions {
    init(_ options: [String: Any]) {
        self.init()
        if let nits = options[__kCGContentAverageLightLevelNits as String] as? NSNumber {
            contentAverageLightLevel = .nits(nits.intValue)
        } else if let level = options[__kCGContentAverageLightLevel as String] as? NSNumber {
            contentAverageLightLevel = .relative(level.floatValue)
        }
        let range = options[__kCGPreferredDynamicRange as String] as? String
        if range == __kCGDynamicRangeHigh as String {
            preferredDynamicRange = .high
        } else if range == __kCGDynamicRangeConstrained as String {
            preferredDynamicRange = .constrained
        } else {
            preferredDynamicRange = .standard
        }
    }

    var dictionary: [String: Any] {
        var options: [String: Any] = [:]
        switch contentAverageLightLevel {
        case .relative(let level): options[__kCGContentAverageLightLevel as String] = NSNumber(value: level)
        case .nits(let nits): options[__kCGContentAverageLightLevelNits as String] = NSNumber(value: nits)
        }
        let range: CFString
        switch preferredDynamicRange {
        case .high: range = __kCGDynamicRangeHigh
        case .constrained: range = __kCGDynamicRangeConstrained
        case .standard: range = __kCGDynamicRangeStandard
        }
        options[__kCGPreferredDynamicRange as String] = range as String
        return options
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CGContentToneMappingInfo {
    init(_ info: __CGContentToneMappingInfo) {
        let options = info.options?.takeUnretainedValue() as? [String: Any] ?? [:]
        func bool(_ key: CFString, _ value: Bool) -> Bool {
            (options[key as String] as? NSNumber)?.boolValue ?? value
        }
        func float(_ key: CFString, _ value: Float) -> Float {
            (options[key as String] as? NSNumber)?.floatValue ?? value
        }
        switch info.method {
        case .imageSpecificLumaScaling: self = .imageSpecificLumaScaling(DefaultOptions(options))
        case .referenceWhiteBased: self = .referenceWhiteBased(DefaultOptions(options))
        case .ituRecommended:
            var itu = ITURecommendedOptions()
            itu.skipBoostToHDR = bool(kCGSkipBoostToHDR, itu.skipBoostToHDR)
            itu.use100nitsHLGOOTF = bool(kCGUse100nitsHLGOOTF, itu.use100nitsHLGOOTF)
            itu.useBT1886ForCoreVideoGamma = bool(kCGUseBT1886ForCoreVideoGamma, itu.useBT1886ForCoreVideoGamma)
            itu.useLegacyHDREcosystem = bool(kCGUseLegacyHDREcosystem, itu.useLegacyHDREcosystem)
            self = .ituRecommended(itu)
        case .exrGamma:
            var exr = EXRGammaOptions()
            exr.defog = float(kCGEXRToneMappingGammaDefog, exr.defog)
            exr.exposure = float(kCGEXRToneMappingGammaExposure, exr.exposure)
            exr.kneeHigh = float(kCGEXRToneMappingGammaKneeHigh, exr.kneeHigh)
            exr.kneeLow = float(kCGEXRToneMappingGammaKneeLow, exr.kneeLow)
            self = .exrGamma(exr)
        case .none: self = .none
        default: self = .default(DefaultOptions(options))
        }
    }

    var method: CGToneMapping {
        switch self {
        case .default: .default
        case .imageSpecificLumaScaling: .imageSpecificLumaScaling
        case .referenceWhiteBased: .referenceWhiteBased
        case .ituRecommended: .ituRecommended
        case .exrGamma: .exrGamma
        case .none: .none
        }
    }

    var options: [String: Any]? {
        switch self {
        case .default(let options), .imageSpecificLumaScaling(let options), .referenceWhiteBased(let options):
            return options.dictionary
        case .ituRecommended(let itu):
            return [kCGSkipBoostToHDR as String: itu.skipBoostToHDR,
                    kCGUse100nitsHLGOOTF as String: itu.use100nitsHLGOOTF,
                    kCGUseBT1886ForCoreVideoGamma as String: itu.useBT1886ForCoreVideoGamma,
                    kCGUseLegacyHDREcosystem as String: itu.useLegacyHDREcosystem]
        case .exrGamma(let exr):
            return [kCGEXRToneMappingGammaDefog as String: exr.defog,
                    kCGEXRToneMappingGammaExposure as String: exr.exposure,
                    kCGEXRToneMappingGammaKneeHigh as String: exr.kneeHigh,
                    kCGEXRToneMappingGammaKneeLow as String: exr.kneeLow]
        case .none:
            return nil
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CGContext {
    public var contentToneMappingInfo: CGContentToneMappingInfo {
        get { CGContentToneMappingInfo(__CGContextGetContentToneMappingInfo(self)) }
        set {
            let options = newValue.options.map { $0 as NSDictionary as CFDictionary }
            withExtendedLifetime(options) {
                let info = __CGContentToneMappingInfo(method: newValue.method, options: options.map { Unmanaged.passUnretained($0) })
                __CGContextSetContentToneMappingInfo(self, info)
            }
        }
    }
}
