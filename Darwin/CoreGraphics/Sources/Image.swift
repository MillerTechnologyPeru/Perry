import Foundation

extension CGImage {
    public func copy(maskingColorComponents components: [CGFloat]) -> CGImage? {
        __copy(maskingColorComponents: components)
    }
}

extension CGImage: @unchecked Sendable {}

@available(*, unavailable, renamed: "CGImage.copy(self:maskingColorComponents:)")
public func CGImageCreateWithMaskingColors(_ image: CGImage?, _ components: UnsafePointer<CGFloat>) -> CGImage? {
    image?.__copy(maskingColorComponents: components)
}

// Events and the mouse are macOS's alone.
#if os(macOS)
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
extension CGEvent {
    public var data: CFData? {
        __data(allocator: nil)
    }
}

public func CGGetLastMouseDelta() -> (x: Int32, y: Int32) {
    var x: Int32 = 0
    var y: Int32 = 0
    __CGGetLastMouseDelta(&x, &y)
    return (x, y)
}

@available(*, unavailable, renamed: "CGGetLastMouseDelta")
public func CGGetLastMouseDelta(_ deltaX: UnsafeMutablePointer<Int32>?, _ deltaY: UnsafeMutablePointer<Int32>?) {
    __CGGetLastMouseDelta(deltaX, deltaY)
}
#endif

// The pixel layout enumerations: every case, and a description of each.

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CGImageAlphaInfo: CaseIterable {
    public static var allCases: [CGImageAlphaInfo] {
        [
            .none, .premultipliedLast, .premultipliedFirst, .last, .first, .noneSkipLast, .noneSkipFirst, .alphaOnly,
        ]
    }
}

extension CGImageAlphaInfo: CustomDebugStringConvertible {
    @inlinable public var debugDescription: String {
        switch self {
        case .none: "none"
        case .premultipliedLast: "premultipliedLast"
        case .premultipliedFirst: "premultipliedFirst"
        case .last: "last"
        case .first: "first"
        case .noneSkipLast: "noneSkipLast"
        case .noneSkipFirst: "noneSkipFirst"
        case .alphaOnly: "alphaOnly"
        default: "init(rawValue: \(rawValue))"
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CGImageByteOrderInfo: CaseIterable {
    public static var allCases: [CGImageByteOrderInfo] {
        [
            .orderDefault, .order16Little, .order32Little, .order16Big, .order32Big,
        ]
    }
}

extension CGImageByteOrderInfo: CustomDebugStringConvertible {
    @inlinable public var debugDescription: String {
        switch self {
        case .orderDefault: "orderDefault"
        case .order16Little: "order16Little"
        case .order32Little: "order32Little"
        case .order16Big: "order16Big"
        case .order32Big: "order32Big"
        default: "init(rawValue: \(rawValue))"
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CGImageComponentInfo: CaseIterable {
    public static var allCases: [CGImageComponentInfo] { [.integer, .float] }
}

extension CGImageComponentInfo: CustomDebugStringConvertible {
    @inlinable public var debugDescription: String {
        switch self {
        case .integer: "integer"
        case .float: "float"
        default: "init(rawValue: \(rawValue))"
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CGImagePixelFormatInfo: CaseIterable {
    public static var allCases: [CGImagePixelFormatInfo] { [.packed, .RGB555, .RGB565, .RGB101010, .RGBCIF10] }
}

@available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, visionOS 1.0, *)
extension CGImagePixelFormatInfo: CustomDebugStringConvertible {
    @inlinable public var debugDescription: String {
        switch self {
        case .packed: "packed"
        case .RGB555: "RGB555"
        case .RGB565: "RGB565"
        case .RGB101010: "RGB101010"
        case .RGBCIF10: "RGBCIF10"
        default: "init(rawValue: \(rawValue))"
        }
    }
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
extension CGInterpolationQuality: Codable {}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
extension CGInterpolationQuality: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .default: "default"
        case .none: "none"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        @unknown default: "init(rawValue: \(rawValue))"
        }
    }
}

// CGBitmapInfo's fields. The interface emits these into programs; earlier
// SDKs linked them, so they are inlinable here.

extension CGBitmapInfo {
    @available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, visionOS 1.0, *)
    @_alwaysEmitIntoClient
    public init(alpha: CGImageAlphaInfo = .none, component: CGImageComponentInfo = .integer,
                byteOrder: CGImageByteOrderInfo = .orderDefault, pixelFormat: CGImagePixelFormatInfo = .packed) {
        self.init(rawValue: alpha.rawValue | component.rawValue | byteOrder.rawValue | pixelFormat.rawValue)
    }

    @_alwaysEmitIntoClient
    public init(alpha: CGImageAlphaInfo = .none, component: CGImageComponentInfo = .integer,
                byteOrder: CGImageByteOrderInfo = .orderDefault) {
        self.init(rawValue: alpha.rawValue | component.rawValue | byteOrder.rawValue)
    }

    @inlinable public var alpha: CGImageAlphaInfo {
        get { CGImageAlphaInfo(rawValue: rawValue & CGBitmapInfo.__alphaInfoMask.rawValue)! }
        set { self = CGBitmapInfo(rawValue: (rawValue & ~CGBitmapInfo.__alphaInfoMask.rawValue) | newValue.rawValue) }
    }

    @inlinable public var component: CGImageComponentInfo {
        get { CGImageComponentInfo(rawValue: rawValue & CGBitmapInfo.__componentInfoMask.rawValue)! }
        set { self = CGBitmapInfo(rawValue: (rawValue & ~CGBitmapInfo.__componentInfoMask.rawValue) | newValue.rawValue) }
    }

    @inlinable public var byteOrder: CGImageByteOrderInfo {
        get { CGImageByteOrderInfo(rawValue: rawValue & CGBitmapInfo.__byteOrderInfoMask.rawValue)! }
        set { self = CGBitmapInfo(rawValue: (rawValue & ~CGBitmapInfo.__byteOrderInfoMask.rawValue) | newValue.rawValue) }
    }

    @available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, visionOS 1.0, *)
    @inlinable public var pixelFormat: CGImagePixelFormatInfo {
        get { CGImagePixelFormatInfo(rawValue: rawValue & CGBitmapInfo.__pixelFormatInfoMask.rawValue)! }
        set { self = CGBitmapInfo(rawValue: (rawValue & ~CGBitmapInfo.__pixelFormatInfoMask.rawValue) | newValue.rawValue) }
    }

    @inlinable public static var alphaInfoMask: CGBitmapInfo { CGBitmapInfo.__alphaInfoMask }
    @inlinable public static var floatInfoMask: CGBitmapInfo { CGBitmapInfo.__componentInfoMask }
    @inlinable public static var byteOrderMask: CGBitmapInfo { CGBitmapInfo.__byteOrderInfoMask }

    @inlinable public var isEmpty: Bool { rawValue == 0 }
}

extension CGBitmapInfo: CustomDebugStringConvertible, CustomReflectable {
    @inlinable public var debugDescription: String {
        if #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, visionOS 1.0, *) {
            "CGBitmapInfo(alpha: .\(alpha), component: .\(component), byteOrder: .\(byteOrder), pixelFormat: .\(pixelFormat))"
        } else {
            "CGBitmapInfo(alpha: .\(alpha), component: .\(component), byteOrder: .\(byteOrder))"
        }
    }

    @inlinable public var customMirror: Mirror {
        let children: KeyValuePairs<String, Any>
        if #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, visionOS 1.0, *) {
            children = ["alpha": alpha, "component": component, "byteOrder": byteOrder, "pixelFormat": pixelFormat]
        } else {
            children = ["alpha": alpha, "component": component, "byteOrder": byteOrder]
        }
        return Mirror(self, children: children, displayStyle: .struct)
    }
}

// Rendering buffer providers over a Swift object that locks and unlocks
// the memory.

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
public protocol _CGRenderingBufferProviderInit {
    init?<T: CGRenderingBufferProvider.Info>(info: T, size: Int)
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension _CGRenderingBufferProviderInit where Self: CGRenderingBufferProvider {
    public init?<T: CGRenderingBufferProvider.Info>(info: T, size: Int) {
        let retained = Unmanaged.passRetained(info).toOpaque()
        let lock: (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? = { pointer in
            Unmanaged<T>.fromOpaque(pointer!).takeUnretainedValue().lock()
        }
        let unlock: (UnsafeMutableRawPointer?, UnsafeMutableRawPointer) -> Void = { pointer, bytes in
            Unmanaged<T>.fromOpaque(pointer!).takeUnretainedValue().unlock(bytes)
        }
        let release: (UnsafeMutableRawPointer?) -> Void = { pointer in
            Unmanaged<T>.fromOpaque(pointer!).release()
        }
        guard let provider = __CGRenderingBufferProviderCreate(retained, size, lock, unlock, release) else {
            Unmanaged<T>.fromOpaque(retained).release()
            return nil
        }
        self = unsafeDowncast(provider, to: Self.self)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CGRenderingBufferProvider: _CGRenderingBufferProviderInit {
    public protocol Info: AnyObject {
        func lock() -> UnsafeMutableRawPointer?
        func unlock(_: UnsafeMutableRawPointer)
    }
}

// Tagged PDF structure elements with their attributes.

@available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
extension CGPDFStructureElement {
    public struct Attributes: Sendable, Equatable, Hashable, Codable {
        public var title: String?
        public var language: Locale.Language?
        public var alternativeText: String?
        public var expansionText: String?
        public var actualText: String?

        public init(title: String? = nil, language: Locale.Language? = nil, alternativeText: String? = nil,
                    expansionText: String? = nil, actualText: String? = nil) {
            self.title = title
            self.language = language
            self.alternativeText = alternativeText
            self.expansionText = expansionText
            self.actualText = actualText
        }
    }
}

@available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public protocol _CGPDFStructureElementInitTrampoline {
    init(tagType: CGPDFTagType)
}

@available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
extension _CGPDFStructureElementInitTrampoline where Self == CGPDFStructureElement {
    public init(tagType: CGPDFTagType, attributes: CGPDFStructureElement.Attributes = .init()) {
        self.init(tagType: tagType)
        if let title = attributes.title { __CGPDFStructureElementSetTitle(self, title as CFString) }
        if let language = attributes.language {
            __CGPDFStructureElementSetLanguageIdentifier(self, language.minimalIdentifier as CFString)
        }
        if let text = attributes.alternativeText { __CGPDFStructureElementSetAlternativeText(self, text as CFString) }
        if let text = attributes.expansionText { __CGPDFStructureElementSetExpansionText(self, text as CFString) }
        if let text = attributes.actualText { __CGPDFStructureElementSetActualText(self, text as CFString) }
    }
}

@available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
extension CGPDFStructureElement: _CGPDFStructureElementInitTrampoline {}
