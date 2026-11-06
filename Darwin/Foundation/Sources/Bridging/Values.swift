// Foundation's value types bridge to the Objective-C classes they stand for:
// each converts to a new object of the class and back from any object of it,
// by the values both hold.

// MARK: Data

extension Data: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSData

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSData {
        withUnsafeBytes { NSData(bytes: $0.baseAddress, length: $0.count) }
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSData, result: inout Data?) {
        result = Data(_bridging: source)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSData, result: inout Data?) -> Bool {
        result = Data(_bridging: source)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSData?) -> Data {
        source.map(Data.init(_bridging:)) ?? Data()
    }

    init(_bridging data: NSData) {
        let count = data.length
        self = count == 0 ? Data() : Data(bytes: data.bytes, count: count)
    }
}

// MARK: Date

extension Date: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSDate

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSDate {
        NSDate(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSDate, result: inout Date?) {
        result = Date(timeIntervalSinceReferenceDate: source.timeIntervalSinceReferenceDate)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSDate, result: inout Date?) -> Bool {
        result = Date(timeIntervalSinceReferenceDate: source.timeIntervalSinceReferenceDate)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSDate?) -> Date {
        Date(timeIntervalSinceReferenceDate: source?.timeIntervalSinceReferenceDate ?? 0)
    }
}

// MARK: DateInterval

extension DateInterval: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSDateInterval

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSDateInterval {
        NSDateInterval(start: start, duration: duration)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSDateInterval, result: inout DateInterval?) {
        result = DateInterval(start: source.startDate, duration: source.duration)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSDateInterval, result: inout DateInterval?) -> Bool {
        result = DateInterval(start: source.startDate, duration: source.duration)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSDateInterval?) -> DateInterval {
        guard let source else { return DateInterval() }
        return DateInterval(start: source.startDate, duration: source.duration)
    }
}

// MARK: URL

extension URL: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSURL

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSURL {
        if let base = baseURL, let url = NSURL(string: relativeString, relativeTo: base) {
            return url
        }
        // Every URL's string parses as a URL again.
        return NSURL(string: absoluteString)!
    }

    static func _bridging(_ source: NSURL) -> URL? {
        if let base = source.baseURL {
            return URL(string: source.relativeString, relativeTo: base)
        }
        return source.absoluteString.flatMap { URL(string: $0) }
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSURL, result: inout URL?) {
        result = _bridging(source)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSURL, result: inout URL?) -> Bool {
        result = _bridging(source)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURL?) -> URL {
        _bridging(source!)!
    }
}

// MARK: URLComponents

extension URLComponents: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSURLComponents

    /// The components, part by part as they are encoded.
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSURLComponents {
        let components = NSURLComponents()
        components.scheme = scheme
        components.percentEncodedUser = percentEncodedUser
        components.percentEncodedPassword = percentEncodedPassword
        components.percentEncodedHost = percentEncodedHost
        components.port = port.map { NSNumber(value: $0) }
        components.percentEncodedPath = percentEncodedPath
        components.percentEncodedQuery = percentEncodedQuery
        components.percentEncodedFragment = percentEncodedFragment
        return components
    }

    static func _bridging(_ source: NSURLComponents) -> URLComponents {
        var components = URLComponents()
        components.scheme = source.scheme
        components.percentEncodedUser = source.percentEncodedUser
        components.percentEncodedPassword = source.percentEncodedPassword
        components.percentEncodedHost = source.percentEncodedHost
        components.port = source.port?.intValue
        components.percentEncodedPath = source.percentEncodedPath ?? ""
        components.percentEncodedQuery = source.percentEncodedQuery
        components.percentEncodedFragment = source.percentEncodedFragment
        return components
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSURLComponents, result: inout URLComponents?) {
        result = _bridging(source)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSURLComponents, result: inout URLComponents?) -> Bool {
        result = _bridging(source)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURLComponents?) -> URLComponents {
        source.map(_bridging) ?? URLComponents()
    }
}

// MARK: URLQueryItem

extension URLQueryItem: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSURLQueryItem

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSURLQueryItem {
        NSURLQueryItem(name: name, value: value)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSURLQueryItem, result: inout URLQueryItem?) {
        result = URLQueryItem(name: source.name, value: source.value)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSURLQueryItem, result: inout URLQueryItem?) -> Bool {
        result = URLQueryItem(name: source.name, value: source.value)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURLQueryItem?) -> URLQueryItem {
        source.map { URLQueryItem(name: $0.name, value: $0.value) } ?? URLQueryItem(name: "", value: nil)
    }
}

// MARK: UUID

extension UUID: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSUUID

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSUUID {
        NSUUID(uuidString: uuidString)!
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSUUID, result: inout UUID?) {
        result = UUID(uuidString: source.uuidString)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSUUID, result: inout UUID?) -> Bool {
        result = UUID(uuidString: source.uuidString)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSUUID?) -> UUID {
        source.flatMap { UUID(uuidString: $0.uuidString) } ?? UUID()
    }
}

// MARK: Locale

extension Locale: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSLocale

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSLocale {
        NSLocale(localeIdentifier: identifier)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSLocale, result: inout Locale?) {
        result = Locale(identifier: source.localeIdentifier)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSLocale, result: inout Locale?) -> Bool {
        result = Locale(identifier: source.localeIdentifier)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSLocale?) -> Locale {
        source.map { Locale(identifier: $0.localeIdentifier) } ?? .current
    }
}

// MARK: TimeZone

extension TimeZone: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSTimeZone

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSTimeZone {
        NSTimeZone(name: identifier) ?? NSTimeZone(forSecondsFromGMT: secondsFromGMT())
    }

    static func _bridging(_ source: NSTimeZone) -> TimeZone? {
        TimeZone(identifier: source.name) ?? TimeZone(secondsFromGMT: source.secondsFromGMT)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSTimeZone, result: inout TimeZone?) {
        result = _bridging(source)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSTimeZone, result: inout TimeZone?) -> Bool {
        result = _bridging(source)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSTimeZone?) -> TimeZone {
        source.flatMap(_bridging) ?? .current
    }
}

// MARK: Calendar

extension Calendar: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSCalendar

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSCalendar {
        let calendar = NSCalendar(calendarIdentifier: NSCalendar.Identifier(rawValue: identifier.cfCalendarIdentifier))
            ?? NSCalendar(calendarIdentifier: .gregorian)!
        calendar.locale = locale
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = minimumDaysInFirstWeek
        return calendar
    }

    static func _bridging(_ source: NSCalendar) -> Calendar {
        var calendar = Calendar(identifier: Calendar.Identifier(identifierString: source.calendarIdentifier.rawValue) ?? .gregorian)
        if let locale = source.locale { calendar.locale = locale }
        calendar.timeZone = source.timeZone
        calendar.firstWeekday = source.firstWeekday
        calendar.minimumDaysInFirstWeek = source.minimumDaysInFirstWeek
        return calendar
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSCalendar, result: inout Calendar?) {
        result = _bridging(source)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSCalendar, result: inout Calendar?) -> Bool {
        result = _bridging(source)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSCalendar?) -> Calendar {
        source.map(_bridging) ?? .current
    }
}

// MARK: IndexPath

extension IndexPath: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSIndexPath

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSIndexPath {
        let indexes = Array(self)
        return indexes.withUnsafeBufferPointer { NSIndexPath(indexes: $0.baseAddress, length: $0.count) }
    }

    static func _bridging(_ source: NSIndexPath) -> IndexPath {
        IndexPath(indexes: (0..<source.length).map { source.index(atPosition: $0) })
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSIndexPath, result: inout IndexPath?) {
        result = _bridging(source)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSIndexPath, result: inout IndexPath?) -> Bool {
        result = _bridging(source)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSIndexPath?) -> IndexPath {
        source.map(_bridging) ?? IndexPath()
    }
}
