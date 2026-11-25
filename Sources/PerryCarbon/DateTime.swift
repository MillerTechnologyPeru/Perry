import GraphiteBase

// The Date and Time Utilities and the Mac's clocks, over Graphite's MacDate
// and SystemClock: seconds since 1904 in local time, and ticks and
// microseconds of the monotonic clock.

private func store(_ parts: DateParts, at date: UnsafeMutablePointer<DateTimeRec>) {
    date.pointee = DateTimeRec(year: parts.year, month: parts.month, day: parts.day, hour: parts.hour,
                               minute: parts.minute, second: parts.second, dayOfWeek: parts.dayOfWeek)
}

/// void GetDateTime(unsigned long *secs).
@c(_GetDateTime)
public func GetDateTime(_ seconds: UnsafeMutablePointer<UInt32>?) {
    seconds?.pointee = MacDate.now.classicSeconds
}

/// void SecondsToDate(unsigned long secs, DateTimeRec *d).
@c(_SecondsToDate)
public func SecondsToDate(_ seconds: UInt32, _ date: UnsafeMutablePointer<DateTimeRec>?) {
    guard let date else { return }
    store(MacDate(classicSeconds: seconds).parts, at: date)
}

/// void GetTime(DateTimeRec *d): now, in local time.
@c(_GetTime)
public func GetTime(_ date: UnsafeMutablePointer<DateTimeRec>?) {
    guard let date else { return }
    store(MacDate.now.parts, at: date)
}

/// void LongSecondsToDate(const LongDateTime *, LongDateRec *): fourteen
/// shorts, era first; the last three reserved.
@c(_LongSecondsToDate)
public func LongSecondsToDate(_ seconds: UnsafeRawPointer?, _ date: UnsafeMutableRawPointer?) {
    guard let seconds, let date else { return }
    let parts = MacDate(seconds: seconds.loadUnaligned(as: Int64.self)).longParts
    let fields = [parts.era, parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second,
                  parts.dayOfWeek, parts.dayOfYear, parts.weekOfYear, parts.pm, 0, 0, 0]
    for (index, field) in fields.enumerated() {
        date.storeBytes(of: field, toByteOffset: index * 2, as: Int16.self)
    }
}

/// void ReadLocation(MachineLocation *): latitude and longitude, not known
/// here, and the time zone's offset with daylight saving time's flag.
@c(_ReadLocation)
public func ReadLocation(_ location: UnsafeMutableRawPointer?) {
    guard let location else { return }
    let current = MachineLocation.current
    location.storeBytes(of: current.latitude.rawValue, as: Int32.self)
    location.storeBytes(of: current.longitude.rawValue, toByteOffset: 4, as: Int32.self)
    location.storeBytes(of: current.packedGMTDelta, toByteOffset: 8, as: Int32.self)
}

/// OSStatus ConvertUTCToLocalTime(const UTCDateTime *, LocalDateTime *):
/// each a 48-bit count of seconds since 1904 (a UInt16 and a UInt32, packed
/// to two bytes) and a fraction.
@c(_ConvertUTCToLocalTime)
public func ConvertUTCToLocalTime(_ utc: UnsafeRawPointer?, _ local: UnsafeMutableRawPointer?) -> Int32 {
    guard let utc, let local else { return MacError.parameter.status }
    let seconds = Int64(utc.loadUnaligned(as: UInt16.self)) << 32 | Int64(utc.loadUnaligned(fromByteOffset: 2, as: UInt32.self))
    let fraction = utc.loadUnaligned(fromByteOffset: 6, as: UInt16.self)
    let localSeconds = MacDate(utcSeconds: seconds).seconds
    local.storeBytes(of: UInt16(truncatingIfNeeded: localSeconds >> 32), as: UInt16.self)
    local.storeBytes(of: UInt32(truncatingIfNeeded: localSeconds), toByteOffset: 2, as: UInt32.self)
    local.storeBytes(of: fraction, toByteOffset: 6, as: UInt16.self)
    return 0
}

/// UInt32 TickCount(void): sixtieths of a second since the system started.
@c(_TickCount)
public func TickCount() -> UInt32 {
    SystemClock.ticks
}

/// void Microseconds(UnsignedWide *): an UnsignedWide's words are a 64-bit
/// number's in the processor's order, so it is stored as one.
@c(_Microseconds)
public func Microseconds(_ microseconds: UnsafeMutableRawPointer?) {
    microseconds?.storeBytes(of: SystemClock.microseconds, as: UInt64.self)
}

/// UInt32 GetDblTime(void).
@c(_GetDblTime)
public func GetDblTime() -> UInt32 {
    SystemClock.doubleClickTicks
}

/// UInt32 GetCaretTime(void).
@c(_GetCaretTime)
public func GetCaretTime() -> UInt32 {
    SystemClock.caretBlinkTicks
}
