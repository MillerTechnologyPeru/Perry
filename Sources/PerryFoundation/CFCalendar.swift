import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
import PerryObjCInterop

// CFCalendar, toll-free bridged to NSCalendar: a calendar is an NSCalendar
// object over swift-foundation's Calendar. CFCalendarComposeAbsoluteTime
// and CFCalendarDecomposeAbsoluteTime are variadic, their components named
// by a string of unit characters (y year, M month, d day, H hour, m minute,
// s second, E weekday, F weekday ordinal, w week of year, W week of month,
// G era, Q quarter); variadic.S passes their Darwin va_list here.

private func calendar(_ object: id?) -> Calendar? { Storage.get(object, as: CalendarStorage.self)?.calendar }

private func component(_ unit: CChar) -> Calendar.Component? {
    switch UInt8(bitPattern: unit) {
    case UInt8(ascii: "y"): .year
    case UInt8(ascii: "M"): .month
    case UInt8(ascii: "d"): .day
    case UInt8(ascii: "H"): .hour
    case UInt8(ascii: "m"): .minute
    case UInt8(ascii: "s"): .second
    case UInt8(ascii: "E"): .weekday
    case UInt8(ascii: "F"): .weekdayOrdinal
    case UInt8(ascii: "w"): .weekOfYear
    case UInt8(ascii: "W"): .weekOfMonth
    case UInt8(ascii: "G"): .era
    case UInt8(ascii: "Q"): .quarter
    default: nil
    }
}

@c(_CFCalendarCreateWithIdentifier)
public func CFCalendarCreateWithIdentifier(_ allocator: UnsafeRawPointer?, _ identifier: id?) -> id? {
    guard let name = Strings.value(of: identifier), let kind = CalendarIdentifiers.identifier(name) else { return nil }
    return ObjC.retain(Calendars.autoreleased(Calendars.make(kind)))
}

@c(_CFCalendarCopyCurrent)
public func CFCalendarCopyCurrent() -> id? { ObjC.retain(Calendars.autoreleased(Calendars.make(Locales.current.calendar.identifier))) }

@c(_CFCalendarGetIdentifier)
public func CFCalendarGetIdentifier(_ object: id?) -> id? {
    guard let calendar = calendar(object) else { return nil }
    return Strings.autoreleased(CalendarIdentifiers.name(calendar.identifier))
}

@c(_CFCalendarSetTimeZone)
public func CFCalendarSetTimeZone(_ object: id?, _ zone: id?) {
    Storage.get(object, as: CalendarStorage.self)?.calendar.timeZone = TimeZones.zone(zone) ?? TimeZones.current
}

@c(_CFCalendarCopyTimeZone)
public func CFCalendarCopyTimeZone(_ object: id?) -> id? {
    guard let calendar = calendar(object) else { return nil }
    return ObjC.retain(TimeZones.autoreleased(calendar.timeZone))
}

@c(_CFCalendarSetLocale)
public func CFCalendarSetLocale(_ object: id?, _ locale: id?) { Storage.get(object, as: CalendarStorage.self)?.calendar.locale = Locales.locale(locale) }

@c(_CFCalendarGetFirstWeekday)
public func CFCalendarGetFirstWeekday(_ object: id?) -> Int { calendar(object)?.firstWeekday ?? 1 }

@c(_CFCalendarSetFirstWeekday)
public func CFCalendarSetFirstWeekday(_ object: id?, _ weekday: Int) { Storage.get(object, as: CalendarStorage.self)?.calendar.firstWeekday = weekday }

/// Boolean CFCalendarDecomposeAbsoluteTime(CFCalendarRef, CFAbsoluteTime,
/// const char *components, int *...): each unit's value into the next int.
@_cdecl("perry_foundation_cf_calendar_decompose")
public func perry_foundation_cf_calendar_decompose(_ object: id?, _ units: UnsafePointer<CChar>?, _ arguments: UnsafeRawPointer?,
                                                   _ time: Double) -> Bool {
    guard let calendar = calendar(object), let units, let arguments else { return false }
    let date = Date(timeIntervalSinceReferenceDate: time)
    var darwin = DarwinArguments(arguments)
    var unit = units
    while unit.pointee != 0 {
        guard let component = component(unit.pointee) else { return false }
        let value = calendar.component(component, from: date)
        if let out = darwin.nextPointer() {
            out.storeBytes(of: Int32(truncatingIfNeeded: value), as: Int32.self)
        }
        unit += 1
    }
    return true
}

/// Boolean CFCalendarComposeAbsoluteTime(CFCalendarRef, CFAbsoluteTime *,
/// const char *components, int...): the time the units' values name.
@_cdecl("perry_foundation_cf_calendar_compose")
public func perry_foundation_cf_calendar_compose(_ object: id?, _ time: UnsafeMutablePointer<Double>?, _ units: UnsafePointer<CChar>?,
                                                 _ arguments: UnsafeRawPointer?) -> Bool {
    guard let calendar = calendar(object), let units, let arguments else { return false }
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    var darwin = DarwinArguments(arguments)
    var unit = units
    while unit.pointee != 0 {
        guard let component = component(unit.pointee) else { return false }
        components.setValue(Int(Int32(truncatingIfNeeded: darwin.next())), for: component)
        unit += 1
    }
    guard let date = calendar.date(from: components) else { return false }
    time?.pointee = date.timeIntervalSinceReferenceDate
    return true
}
