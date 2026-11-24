import FoundationEssentials
import PerryObjCInterop

// NSDateInterval: a start date and a duration, as URL task metrics give a
// task's span of time.

final class DateIntervalStorage {
    let start: Date
    let duration: Double

    init(start: Date, duration: Double) {
        self.start = start
        self.duration = duration
    }
}

@ObjCClass("NSDateInterval")
public final class NSDateInterval: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
    }

    private var storage: DateIntervalStorage {
        Storage.get(objcObject, as: DateIntervalStorage.self) ?? DateIntervalStorage(start: Date(timeIntervalSinceReferenceDate: 0), duration: 0)
    }

    private func set(start: Date, duration: Double) -> Self {
        Storage.set(objcObject, DateIntervalStorage(start: start, duration: max(duration, 0)))
        return self
    }

    @ObjCMethod("init")
    func initialize() -> Self { set(start: Date(), duration: 0) }

    @ObjCMethod("initWithStartDate:duration:")
    func initialize(start: NSDate, duration: Double) -> Self { set(start: start.date, duration: duration) }

    @ObjCMethod("initWithStartDate:endDate:")
    func initialize(start: NSDate, end: NSDate) -> Self {
        set(start: start.date, duration: end.date.timeIntervalSince(start.date))
    }

    @ObjCMethod("startDate") func startDate() -> NSDate { Dates.wrapped(storage.start) }
    @ObjCMethod("endDate") func endDate() -> NSDate { Dates.wrapped(storage.start.addingTimeInterval(storage.duration)) }
    @ObjCMethod("duration") func duration() -> Double { storage.duration }

    @ObjCMethod("containsDate:")
    func contains(_ date: NSDate) -> Bool {
        let seconds = date.date.timeIntervalSince(storage.start)
        return seconds >= 0 && seconds <= storage.duration
    }

    private var end: Date { storage.start.addingTimeInterval(storage.duration) }

    /// NSComparisonResult: by start date, then by duration.
    @ObjCMethod("compare:")
    func compare(_ other: NSDateInterval) -> Int {
        let (mine, theirs) = (storage, other.storage)
        if mine.start != theirs.start { return mine.start < theirs.start ? -1 : 1 }
        if mine.duration != theirs.duration { return mine.duration < theirs.duration ? -1 : 1 }
        return 0
    }

    /// Whether either contains an end of the other.
    @ObjCMethod("intersectsDateInterval:")
    func intersects(_ other: NSDateInterval) -> Bool {
        let (start, end) = (storage.start, self.end), (otherStart, otherEnd) = (other.storage.start, other.end)
        return (start...end).contains(otherStart) || (start...end).contains(otherEnd)
            || (otherStart...otherEnd).contains(start) || (otherStart...otherEnd).contains(end)
    }

    /// The span both cover; nil when they don't meet.
    @ObjCMethod("intersectionWithDateInterval:")
    func intersection(with other: NSDateInterval) -> UnsafeMutableRawPointer? {
        guard intersects(other) else { return nil }
        let start = max(storage.start, other.storage.start), end = min(self.end, other.end)
        let object = Storage.allocate(ObjC.objectGetClass(objcObject).map { UnsafeMutableRawPointer($0) })
        guard let object else { return nil }
        Storage.set(object, DateIntervalStorage(start: start, duration: end.timeIntervalSince(start)))
        return ObjC.autorelease(object)
    }

    @ObjCMethod("isEqualToDateInterval:")
    func isEqual(toDateInterval other: NSDateInterval?) -> Bool {
        guard let other else { return false }
        return other.storage.start == storage.start && other.storage.duration == storage.duration
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, let interval = Storage.get(other.id, as: DateIntervalStorage.self) else { return false }
        return interval.start == storage.start && interval.duration == storage.duration
    }

    @ObjCMethod("hash") func hashValue() -> UInt { UInt(bitPattern: storage.start.hashValue ^ storage.duration.hashValue) }

    /// Immutable: a copy is the interval itself.
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjC.retain(objcObject) }

    @ObjCMethod("description")
    func description() -> String {
        "\(Dates.description(storage.start)) to \(Dates.description(storage.start.addingTimeInterval(storage.duration)))"
    }
}
