// CAFrameRateRange's preferred rate is optional in Swift: the C struct
// keeps 0 for "no preference", which the overlay shows as nil.

@available(macOS 12.0, iOS 15.0, tvOS 15.0, visionOS 1.0, *)
@available(watchOS, unavailable)
extension CAFrameRateRange {
    public init(minimum: Float, maximum: Float, preferred: Float? = nil) {
        self.init()
        self.minimum = minimum
        self.maximum = maximum
        self.__preferred = preferred ?? 0
    }

    public var preferred: Float? {
        get { __preferred == 0 ? nil : __preferred }
        set(rate) { __preferred = rate ?? 0 }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, visionOS 1.0, *)
@available(watchOS, unavailable)
extension CAFrameRateRange: Equatable {
    public static func == (lhs: CAFrameRateRange, rhs: CAFrameRateRange) -> Bool {
        __CAFrameRateRangeIsEqualToRange(lhs, rhs)
    }
}
