import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
import PerryObjCInterop

// CFDateComponents, CoreFoundation's private type that NSDateComponents
// bridges to: a date components object is an NSDateComponents object over
// swift-foundation's DateComponents. Values are CFIndex, with
// CFDateComponentUndefined (LONG_MAX) for a unit that has none.

/// kCFCalendarUnitLeapMonth, whose value is 1 or 0.
private let leapMonthUnit: UInt = 1 << 30

@c(_CFDateComponentsGetTypeID) public func CFDateComponentsGetTypeID() -> UInt { 66 }

/// Empty date components (+1).
@c(_CFDateComponentsCreate)
public func CFDateComponentsCreate(_ allocator: UnsafeRawPointer?) -> id? {
    ObjC.retain(DateComponentsBox.autoreleased(DateComponents()))
}

/// A copy of the components (+1).
@c(_CFDateComponentsCreateCopy)
public func CFDateComponentsCreateCopy(_ allocator: UnsafeRawPointer?, _ components: id?) -> id? {
    guard let components else { return nil }
    return ObjC.retain(DateComponentsBox.autoreleased(DateComponentsBox.value(components)))
}

/// The unit's value, or CFDateComponentUndefined.
@c(_CFDateComponentsGetValue)
public func CFDateComponentsGetValue(_ components: id?, _ unit: UInt) -> Int {
    guard let components else { return dateComponentUndefined }
    if unit == leapMonthUnit {
        return DateComponentsBox.value(components).isLeapMonth.map { $0 ? 1 : 0 } ?? dateComponentUndefined
    }
    let component: Calendar.Component? = unit == 1 << 8 ? .weekOfYear : CalendarUnits.component(unit)
    return component.map { DateComponentsBox.get(components, $0) } ?? dateComponentUndefined
}

/// Sets the unit's value; CFDateComponentUndefined clears it.
@c(_CFDateComponentsSetValue)
public func CFDateComponentsSetValue(_ components: id?, _ unit: UInt, _ value: Int) {
    guard let components else { return }
    if unit == leapMonthUnit {
        DateComponentsBox.box(components).components.isLeapMonth = value == dateComponentUndefined ? nil : value != 0
        return
    }
    let component: Calendar.Component? = unit == 1 << 8 ? .weekOfYear : CalendarUnits.component(unit)
    if let component { DateComponentsBox.set(components, component, value) }
}

/// The components' calendar (+1), or NULL.
@c(_CFDateComponentsCopyCalendar)
public func CFDateComponentsCopyCalendar(_ components: id?) -> id? {
    guard let calendar = DateComponentsBox.value(components).calendar else { return nil }
    return ObjC.retain(Calendars.autoreleased(calendar))
}

@c(_CFDateComponentsSetCalendar)
public func CFDateComponentsSetCalendar(_ components: id?, _ calendar: id?) {
    guard let components else { return }
    DateComponentsBox.box(components).components.calendar = Calendars.calendar(calendar)
}

/// The components' time zone (+1), or NULL.
@c(_CFDateComponentsCopyTimeZone)
public func CFDateComponentsCopyTimeZone(_ components: id?) -> id? {
    guard let zone = DateComponentsBox.value(components).timeZone else { return nil }
    return ObjC.retain(TimeZones.autoreleased(zone))
}

@c(_CFDateComponentsSetTimeZone)
public func CFDateComponentsSetTimeZone(_ components: id?, _ zone: id?) {
    guard let components else { return }
    DateComponentsBox.box(components).components.timeZone = TimeZones.zone(zone)
}

/// Whether the month is a leap month, false if unset.
@c(_CFDateComponentsIsLeapMonth)
public func CFDateComponentsIsLeapMonth(_ components: id?) -> Bool { DateComponentsBox.value(components).isLeapMonth ?? false }

/// Whether the leap month flag was set.
@c(_CFDateComponentsIsLeapMonthSet)
public func CFDateComponentsIsLeapMonthSet(_ components: id?) -> Bool { DateComponentsBox.value(components).isLeapMonth != nil }

/// Whether the components name a date in their own calendar; false without
/// one.
@c(_CFDateComponentsIsValidDate)
public func CFDateComponentsIsValidDate(_ components: id?) -> Bool { DateComponentsBox.value(components).isValidDate }

/// Whether the components name a date in the calendar, or in their own for
/// NULL.
@c(_CFDateComponentsIsValidDateInCalendar)
public func CFDateComponentsIsValidDateInCalendar(_ components: id?, _ calendar: id?) -> Bool {
    let value = DateComponentsBox.value(components)
    guard let calendar = Calendars.calendar(calendar) else { return value.isValidDate }
    return value.isValidDate(in: calendar)
}

/// Whether the date has each of the components' values in the calendar.
@c(_CFDateComponentsDateMatchesComponents)
public func CFDateComponentsDateMatchesComponents(_ components: id?, _ calendar: id?, _ date: id?) -> Bool {
    guard let calendar = Calendars.calendar(calendar) else { return false }
    return calendar.date(Dates.date(date), matchesComponents: DateComponentsBox.value(components))
}
