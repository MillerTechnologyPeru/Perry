import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
import PerryObjCInterop

// The rest of CFCalendar: ranges and ordinality of units, date components,
// week rules and the Gregorian start date. CFCalendarAddComponents and
// CFCalendarGetComponentDifference are variadic like
// CFCalendarComposeAbsoluteTime, their components named by the same unit
// characters; variadic.S passes their Darwin va_list here.

/// kCFNotFound.
private let calendarNotFound = -1

/// A CFCalendarUnit's component, counting the deprecated kCFCalendarUnitWeek
/// (1 << 8) as the week of the year, as Darwin does.
private func calendarComponent(_ unit: UInt) -> Calendar.Component? {
    unit == 1 << 8 ? .weekOfYear : CalendarUnits.component(unit)
}

/// A component description character's component, as CFCalendar.h names
/// them.
private func calendarComponent(character: CChar) -> Calendar.Component? {
    switch UInt8(bitPattern: character) {
    case UInt8(ascii: "G"): .era
    case UInt8(ascii: "y"): .year
    case UInt8(ascii: "Q"): .quarter
    case UInt8(ascii: "M"): .month
    case UInt8(ascii: "d"): .day
    case UInt8(ascii: "D"): .dayOfYear
    case UInt8(ascii: "H"): .hour
    case UInt8(ascii: "m"): .minute
    case UInt8(ascii: "s"): .second
    case UInt8(ascii: "S"): .nanosecond
    case UInt8(ascii: "E"): .weekday
    case UInt8(ascii: "F"): .weekdayOrdinal
    case UInt8(ascii: "w"): .weekOfYear
    case UInt8(ascii: "W"): .weekOfMonth
    case UInt8(ascii: "Y"): .yearForWeekOfYear
    default: nil
    }
}

private func cfRange(_ range: Range<Int>?) -> CFRange {
    guard let range else { return CFRange(location: calendarNotFound, length: calendarNotFound) }
    return CFRange(location: range.lowerBound, length: range.count)
}

/// kCFCalendarComponentsWrap.
private func wraps(_ options: UInt) -> Bool { options & (1 << 0) != 0 }

@c(_CFCalendarGetTypeID) public func CFCalendarGetTypeID() -> UInt { 49 }

/// The calendar's locale, or the current one if it has none (+1).
@c(_CFCalendarCopyLocale)
public func CFCalendarCopyLocale(_ object: id?) -> id? {
    guard let calendar = Calendars.calendar(object) else { return nil }
    return ObjC.retain(Locales.autoreleased(calendar.locale ?? Locales.current))
}

@c(_CFCalendarGetMinimumDaysInFirstWeek)
public func CFCalendarGetMinimumDaysInFirstWeek(_ object: id?) -> Int { Calendars.calendar(object)?.minimumDaysInFirstWeek ?? 1 }

@c(_CFCalendarSetMinimumDaysInFirstWeek)
public func CFCalendarSetMinimumDaysInFirstWeek(_ object: id?, _ days: Int) {
    Storage.get(object, as: CalendarStorage.self)?.calendar.minimumDaysInFirstWeek = days
}

// MARK: Gregorian start date

/// ICU's default Gregorian change, 15 October 1582, as an absolute time.
private let defaultGregorianStart = -13_197_600_000.0

/// The Gregorian start dates calendars were given, by calendar object;
/// swift-foundation's Calendar keeps its own fixed.
private final class GregorianStart {
    weak var storage: CalendarStorage?
    let time: Double

    init(storage: CalendarStorage, time: Double) {
        self.storage = storage
        self.time = time
    }
}

nonisolated(unsafe) private var gregorianStarts: [UInt: GregorianStart] = [:]

private func hasGregorianChange(_ calendar: Calendar) -> Bool {
    calendar.identifier == .gregorian || calendar.identifier == .iso8601
}

/// The date a Gregorian calendar switches from the Julian one (+1), or NULL
/// for other calendars.
@c(_CFCalendarCopyGregorianStartDate)
public func CFCalendarCopyGregorianStartDate(_ object: id?) -> id? {
    guard let object, let storage = Storage.get(object, as: CalendarStorage.self), hasGregorianChange(storage.calendar) else {
        return nil
    }
    var time = defaultGregorianStart
    if let start = gregorianStarts[UInt(bitPattern: object)], start.storage === storage { time = start.time }
    return ObjC.retain(Dates.autoreleased(time))
}

/// Sets a Gregorian calendar's switch from the Julian one; NULL restores
/// the default. Calendars other than the Gregorian ignore it.
@c(_CFCalendarSetGregorianStartDate)
public func CFCalendarSetGregorianStartDate(_ object: id?, _ date: id?) {
    guard let object, let storage = Storage.get(object, as: CalendarStorage.self), hasGregorianChange(storage.calendar) else {
        return
    }
    gregorianStarts = gregorianStarts.filter { $0.value.storage != nil }
    let key = UInt(bitPattern: object)
    if let date {
        gregorianStarts[key] = GregorianStart(storage: storage, time: Dates.interval(date))
    } else {
        gregorianStarts[key] = nil
    }
}

// MARK: Ranges

/// The smallest range the unit's values take, or {kCFNotFound, kCFNotFound}.
@c(_CFCalendarGetMinimumRangeOfUnit)
public func CFCalendarGetMinimumRangeOfUnit(_ object: id?, _ unit: UInt) -> CFRange {
    guard let calendar = Calendars.calendar(object), let component = calendarComponent(unit) else { return cfRange(nil) }
    return cfRange(calendar.minimumRange(of: component))
}

/// The largest range the unit's values take, or {kCFNotFound, kCFNotFound}.
@c(_CFCalendarGetMaximumRangeOfUnit)
public func CFCalendarGetMaximumRangeOfUnit(_ object: id?, _ unit: UInt) -> CFRange {
    guard let calendar = Calendars.calendar(object), let component = calendarComponent(unit) else { return cfRange(nil) }
    return cfRange(calendar.maximumRange(of: component))
}

/// The range of the smaller unit's values in the bigger unit holding the
/// time, or {kCFNotFound, kCFNotFound}.
@DarwinC("_CFCalendarGetRangeOfUnit")
public func CFCalendarGetRangeOfUnit(_ object: id?, _ smaller: UInt, _ bigger: UInt, _ time: Double) -> CFRange {
    guard let calendar = Calendars.calendar(object), let small = calendarComponent(smaller),
          let large = calendarComponent(bigger) else { return cfRange(nil) }
    return cfRange(calendar.range(of: small, in: large, for: Date(timeIntervalSinceReferenceDate: time)))
}

/// Which of the bigger unit's smaller units holds the time, from 1, or
/// kCFNotFound.
@DarwinC("_CFCalendarGetOrdinalityOfUnit")
public func CFCalendarGetOrdinalityOfUnit(_ object: id?, _ smaller: UInt, _ bigger: UInt, _ time: Double) -> Int {
    guard let calendar = Calendars.calendar(object), let small = calendarComponent(smaller),
          let large = calendarComponent(bigger) else { return calendarNotFound }
    return calendar.ordinality(of: small, in: large, for: Date(timeIntervalSinceReferenceDate: time)) ?? calendarNotFound
}

/// The start and length of the unit holding the time.
@DarwinC("_CFCalendarGetTimeRangeOfUnit")
public func CFCalendarGetTimeRangeOfUnit(_ object: id?, _ unit: UInt, _ time: Double, _ start: UnsafeMutablePointer<Double>?,
                                         _ length: UnsafeMutablePointer<Double>?) -> Bool {
    guard let calendar = Calendars.calendar(object), let component = calendarComponent(unit),
          let interval = calendar.dateInterval(of: component, for: Date(timeIntervalSinceReferenceDate: time)) else { return false }
    start?.pointee = interval.start.timeIntervalSinceReferenceDate
    length?.pointee = interval.duration
    return true
}

// MARK: Components

/// The unit's value for the date, or NSDateComponentUndefined for a unit
/// that has none, as NSCalendar's -component:fromDate: gives.
@c(_CFCalendarGetComponentFromDate)
public func CFCalendarGetComponentFromDate(_ object: id?, _ unit: UInt, _ date: id?) -> Int {
    guard let calendar = Calendars.calendar(object), let component = calendarComponent(unit) else { return dateComponentUndefined }
    return calendar.component(component, from: Dates.date(date))
}

/// The date's components in the units (+1).
@c(_CFCalendarCreateDateComponentsFromDate)
public func CFCalendarCreateDateComponentsFromDate(_ allocator: UnsafeRawPointer?, _ object: id?, _ units: UInt, _ date: id?) -> id? {
    guard let calendar = Calendars.calendar(object) else { return nil }
    var components = CalendarUnits.components(units)
    if units & (1 << 8) != 0 { components.insert(.weekOfYear) }
    return ObjC.retain(DateComponentsBox.autoreleased(calendar.dateComponents(components, from: Dates.date(date))))
}

/// The date the components name (+1), or NULL.
@c(_CFCalendarCreateDateFromComponents)
public func CFCalendarCreateDateFromComponents(_ allocator: UnsafeRawPointer?, _ object: id?, _ components: id?) -> id? {
    guard let calendar = Calendars.calendar(object), let date = calendar.date(from: DateComponentsBox.value(components)) else {
        return nil
    }
    return ObjC.retain(Dates.autoreleased(date))
}

/// Boolean CFCalendarAddComponents(CFCalendarRef, CFAbsoluteTime *,
/// CFOptionFlags, const char *components, int...): the time moved by each
/// unit's amount, wrapping within bigger units with kCFCalendarComponentsWrap.
@_cdecl("perry_foundation_cf_calendar_add")
public func perry_foundation_cf_calendar_add(_ object: id?, _ time: UnsafeMutablePointer<Double>?, _ options: UInt,
                                             _ units: UnsafePointer<CChar>?, _ arguments: UnsafeRawPointer?) -> Bool {
    guard let calendar = Calendars.calendar(object), let time, let units, let arguments else { return false }
    var components = DateComponents()
    var darwin = DarwinArguments(arguments)
    var unit = units
    while unit.pointee != 0 {
        guard let component = calendarComponent(character: unit.pointee) else { return false }
        components.setValue(Int(Int32(truncatingIfNeeded: darwin.next())), for: component)
        unit += 1
    }
    guard let date = calendar.date(byAdding: components, to: Date(timeIntervalSinceReferenceDate: time.pointee),
                                   wrappingComponents: wraps(options)) else { return false }
    time.pointee = date.timeIntervalSinceReferenceDate
    return true
}

/// Boolean CFCalendarGetComponentDifference(CFCalendarRef, CFAbsoluteTime
/// start, CFAbsoluteTime result, CFOptionFlags, const char *components,
/// int *...): the difference from start to result in the units, each into
/// the next int. Its arguments are in C's order, so the va_list follows the
/// integer ones on every ABI.
@_cdecl("perry_foundation_cf_calendar_difference")
public func perry_foundation_cf_calendar_difference(_ object: id?, _ start: Double, _ result: Double, _ options: UInt,
                                                    _ units: UnsafePointer<CChar>?, _ arguments: UnsafeRawPointer?) -> Bool {
    guard let calendar = Calendars.calendar(object), let units, let arguments else { return false }
    var wanted: [Calendar.Component] = []
    var unit = units
    while unit.pointee != 0 {
        guard let component = calendarComponent(character: unit.pointee) else { return false }
        wanted.append(component)
        unit += 1
    }
    let difference = calendar.dateComponents(Set(wanted), from: Date(timeIntervalSinceReferenceDate: start),
                                             to: Date(timeIntervalSinceReferenceDate: result))
    var darwin = DarwinArguments(arguments)
    for component in wanted {
        if let out = darwin.nextPointer() {
            out.storeBytes(of: Int32(truncatingIfNeeded: difference.value(for: component) ?? 0), as: Int32.self)
        }
    }
    return true
}

// MARK: Date formats

/// The best date format for each template (skeleton) in the locale, or the
/// current one for NULL (+1), as CFDateFormatterCreateDateFormatFromTemplate
/// gives one; a template with no format is left out.
@c(_CFDateFormatterCreateDateFormatsFromTemplates)
public func CFDateFormatterCreateDateFormatsFromTemplates(_ allocator: UnsafeRawPointer?, _ templates: id?, _ options: UInt,
                                                          _ locale: id?) -> id? {
    guard let templates else { return nil }
    let identifier = (locale.map { Locales.locale($0) } ?? Locales.current).identifier
    let formats = Arrays.elements(templates).compactMap { template in
        Strings.value(of: template).flatMap { DateFormatterStorage.pattern(fromTemplate: $0, locale: identifier) }
    }
    return ObjC.retain(Arrays.autoreleased(formats.map { Strings.autoreleased($0) }))
}
