import CPerryGeometry
import Glibc
import PerryObjCInterop

// UIDatePicker: wheels of months, days and years, or hours, minutes and
// AM/PM, or both, or a countdown's hours and minutes. Dragging a wheel
// turns it a row at a time; tapping a row turns it there. The date stays
// between the minimum and maximum dates, and each change sends value
// changed. The compact style is a pill showing the date, which opens the
// wheels at the bottom of the screen; the inline style is drawn as wheels.

final class DatePickerState: ObjectState {
    /// Seconds since the reference date.
    var date: Double = Clock.referenceNow
    var minimumDate: Double?
    var maximumDate: Double?
    /// UIDatePickerMode: time 0, date 1, date and time 2, countdown 3,
    /// year and month 4.
    var mode = 2
    /// UIDatePickerStyle: automatic 0, wheels 1, compact 2, inline 3.
    var preferredStyle = 0
    var locale: NSObject?
    var calendar: NSObject?
    var timeZone: NSObject?
    var minuteInterval = 1
    var countDownDuration: Double = 0
    var roundsToMinuteInterval = true
    /// Shown as a text field's input view or the compact pill's wheels.
    var asInput = false
    /// The compact picker this one's wheels edit, unretained.
    var editing: UnsafeMutableRawPointer?

    // A drag under way: the wheel, where it began and how far it has come.
    var column: Int?
    var startY: CGFloat = 0
    var dragged: CGFloat = 0
}

@ObjCWrapper("NSDate")
class PickerDate: NSObject {
    @ObjCClassMethod("dateWithTimeIntervalSinceReferenceDate:") static func make(_ interval: Double) -> PickerDate
    @ObjCMethod("timeIntervalSinceReferenceDate") func interval() -> Double
}

@ObjCWrapper("NSCalendar")
class PickerCalendar: NSObject {
    @ObjCClassMethod("currentCalendar") static func current() -> PickerCalendar
    @ObjCMethod("components:fromDate:") func components(_ units: UInt, from date: PickerDate) -> PickerComponents
    @ObjCMethod("dateFromComponents:") func date(from components: PickerComponents) -> PickerDate?
    @ObjCMethod("shortMonthSymbols") func shortMonthSymbols() -> NSArray
    @ObjCMethod("monthSymbols") func monthSymbols() -> NSArray
    @ObjCMethod("AMSymbol") func amSymbol() -> String
    @ObjCMethod("PMSymbol") func pmSymbol() -> String
}

@ObjCWrapper("NSDateComponents")
class PickerComponents: NSObject {
    @ObjCMethod("year") func year() -> Int
    @ObjCMethod("setYear:") func setYear(_ year: Int)
    @ObjCMethod("month") func month() -> Int
    @ObjCMethod("setMonth:") func setMonth(_ month: Int)
    @ObjCMethod("day") func day() -> Int
    @ObjCMethod("setDay:") func setDay(_ day: Int)
    @ObjCMethod("hour") func hour() -> Int
    @ObjCMethod("setHour:") func setHour(_ hour: Int)
    @ObjCMethod("minute") func minute() -> Int
    @ObjCMethod("setMinute:") func setMinute(_ minute: Int)
    @ObjCMethod("setSecond:") func setSecond(_ second: Int)
}

extension Clock {
    /// The wall clock's time, in seconds since the reference date (2001).
    static var referenceNow: Double {
        var time = timespec()
        clock_gettime(CLOCK_REALTIME, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9 - 978_307_200
    }
}

/// A date's parts, in the picker's calendar.
struct DateParts {
    var year, month, day, hour, minute: Int

    static func daysIn(_ month: Int, of year: Int) -> Int {
        switch month {
        case 2: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

/// One wheel: how many rows, which is chosen, what each says, and the
/// parts with another row chosen.
struct Wheel {
    let count: Int
    let index: Int
    let wraps: Bool
    let label: (Int) -> String
    let choose: (Int, inout DateParts) -> Void
}

@ObjCClass("UIDatePicker")
open class UIDatePicker: UIControl {
    static let pickerStates = StateTable<DatePickerState>()
    var picker: DatePickerState { UIDatePicker.pickerStates[objcObject] }

    static let rowHeight: CGFloat = 32
    static let wheelsHeight: CGFloat = 216

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIDatePicker.pickerStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        if decoded.has("UIDatePickerMode") { picker.mode = decoded.integer("UIDatePickerMode") }
        if decoded.has("UIDatePickerStyle") { picker.preferredStyle = decoded.integer("UIDatePickerStyle") }
        if let date = decoded.object("UIDate")?.as(PickerDate.self) { picker.date = date.interval() }
        picker.minimumDate = decoded.object("UIMinimumDate")?.as(PickerDate.self)?.interval()
        picker.maximumDate = decoded.object("UIMaximumDate")?.as(PickerDate.self)?.interval()
        if decoded.has("UIMinuteInterval") { picker.minuteInterval = max(decoded.integer("UIMinuteInterval"), 1) }
        return self
    }

    // MARK: Properties

    @ObjCMethod("date") func date() -> NSObject { PickerDate.make(picker.date) }
    @ObjCMethod("setDate:") func setDate(_ date: NSObject?) { setDate(date, animated: false) }
    @ObjCMethod("setDate:animated:")
    func setDate(_ date: NSObject?, animated: Bool) {
        guard let date = date?.as(PickerDate.self) else { return }
        picker.date = clamped(date.interval())
        changed()
    }

    @ObjCMethod("minimumDate") func minimumDate() -> NSObject? { picker.minimumDate.map(PickerDate.make) }
    @ObjCMethod("setMinimumDate:")
    func setMinimumDate(_ date: NSObject?) {
        picker.minimumDate = date?.as(PickerDate.self)?.interval()
        picker.date = clamped(picker.date)
        changed()
    }
    @ObjCMethod("maximumDate") func maximumDate() -> NSObject? { picker.maximumDate.map(PickerDate.make) }
    @ObjCMethod("setMaximumDate:")
    func setMaximumDate(_ date: NSObject?) {
        picker.maximumDate = date?.as(PickerDate.self)?.interval()
        picker.date = clamped(picker.date)
        changed()
    }

    @ObjCMethod("datePickerMode") func datePickerMode() -> Int { picker.mode }
    @ObjCMethod("setDatePickerMode:") func setDatePickerMode(_ mode: Int) { picker.mode = mode; changed() }
    @ObjCMethod("preferredDatePickerStyle") func preferredDatePickerStyle() -> Int { picker.preferredStyle }
    @ObjCMethod("setPreferredDatePickerStyle:")
    func setPreferredDatePickerStyle(_ style: Int) {
        picker.preferredStyle = style
        changed()
        superviewNeedsLayout()
    }

    /// The style shown: compact when automatic, except as an input view
    /// or in countdown mode, which are wheels.
    @ObjCMethod("datePickerStyle")
    func datePickerStyle() -> Int {
        if picker.asInput || picker.mode == 3 { return 1 }
        return picker.preferredStyle == 0 ? 2 : picker.preferredStyle
    }

    var isCompact: Bool { datePickerStyle() == 2 }

    @ObjCMethod("locale") func locale() -> NSObject? { picker.locale }
    @ObjCMethod("setLocale:") func setLocale(_ locale: NSObject?) { picker.locale = locale; changed() }
    @ObjCMethod("calendar") func calendarObject() -> NSObject { picker.calendar ?? PickerCalendar.current() }
    @ObjCMethod("setCalendar:") func setCalendar(_ calendar: NSObject?) { picker.calendar = calendar; changed() }
    @ObjCMethod("timeZone") func timeZone() -> NSObject? { picker.timeZone }
    @ObjCMethod("setTimeZone:") func setTimeZone(_ zone: NSObject?) { picker.timeZone = zone; changed() }
    @ObjCMethod("minuteInterval") func minuteInterval() -> Int { picker.minuteInterval }
    @ObjCMethod("setMinuteInterval:") func setMinuteInterval(_ interval: Int) { picker.minuteInterval = max(1, min(interval, 30)); changed() }
    @ObjCMethod("countDownDuration") func countDownDuration() -> Double { picker.countDownDuration }
    @ObjCMethod("setCountDownDuration:") func setCountDownDuration(_ duration: Double) { picker.countDownDuration = max(0, duration); changed() }
    @ObjCMethod("roundsToMinuteInterval") func roundsToMinuteInterval() -> Bool { picker.roundsToMinuteInterval }
    @ObjCMethod("setRoundsToMinuteInterval:") func setRoundsToMinuteInterval(_ rounds: Bool) { picker.roundsToMinuteInterval = rounds }

    private func changed() {
        setNeedsDisplay()
        // The compact pill's wheels show what the pill does.
        if let editing = picker.editing { UIView.wrap(editing).setNeedsDisplay() }
    }

    private func clamped(_ date: Double) -> Double {
        var date = date
        if let minimum = picker.minimumDate { date = max(date, minimum) }
        if let maximum = picker.maximumDate { date = min(date, maximum) }
        return date
    }

    // MARK: Dates and their parts

    private var calendar: PickerCalendar { calendarObject().unsafeCast(to: PickerCalendar.self) }

    private var parts: DateParts {
        let components = calendar.components(4 | 8 | 16 | 32 | 64, from: PickerDate.make(picker.date))
        return DateParts(year: components.year(), month: components.month(), day: components.day(),
                         hour: components.hour(), minute: components.minute())
    }

    private func setParts(_ parts: DateParts) {
        let components = PickerComponents.objCClass.object.newInstance().unsafeCast(to: PickerComponents.self)
        var parts = parts
        parts.day = min(parts.day, DateParts.daysIn(parts.month, of: parts.year))
        components.setYear(parts.year)
        components.setMonth(parts.month)
        components.setDay(parts.day)
        components.setHour(parts.hour)
        components.setMinute(parts.minute)
        components.setSecond(0)
        guard let date = calendar.date(from: components) else { return }
        let new = clamped(date.interval())
        guard new != picker.date else { setNeedsDisplay(); return }
        picker.date = new
        changed()
        sendActions(for: 1 << 12)
    }

    /// The date as the compact pill shows it: "Nov 6, 2026", "9:41 AM".
    var shortText: String {
        let parts = parts
        let months = calendar.shortMonthSymbols().elements.map(\.stringValue)
        let dateText = "\(months.indices.contains(parts.month - 1) ? months[parts.month - 1] : "\(parts.month)") \(parts.day), \(parts.year)"
        let hour = (parts.hour + 11) % 12 + 1
        let timeText = "\(hour):\(parts.minute < 10 ? "0" : "")\(parts.minute) \(parts.hour < 12 ? calendar.amSymbol() : calendar.pmSymbol())"
        switch picker.mode {
        case 0: return timeText
        case 2: return dateText + " " + timeText
        default: return dateText
        }
    }

    /// The wheels the mode shows, left to right.
    var wheels: [Wheel] {
        let parts = parts
        let calendar = calendar
        let interval = max(picker.minuteInterval, 1)
        let minute = Wheel(count: 60 / interval, index: parts.minute / interval, wraps: true,
                           label: { let m = $0 * interval; return m < 10 ? "0\(m)" : "\(m)" },
                           choose: { $1.minute = $0 * interval })
        let hour = Wheel(count: 12, index: (parts.hour + 11) % 12, wraps: true, label: { "\($0 + 1)" },
                         choose: { index, parts in parts.hour = (index + 1) % 12 + (parts.hour >= 12 ? 12 : 0) })
        let period = Wheel(count: 2, index: parts.hour < 12 ? 0 : 1, wraps: false,
                           label: { $0 == 0 ? calendar.amSymbol() : calendar.pmSymbol() },
                           choose: { index, parts in parts.hour = parts.hour % 12 + index * 12 })
        let months = calendar.monthSymbols().elements.map(\.stringValue)
        let month = Wheel(count: 12, index: parts.month - 1, wraps: true,
                          label: { months.indices.contains($0) ? months[$0] : "\($0 + 1)" }, choose: { $1.month = $0 + 1 })
        let day = Wheel(count: DateParts.daysIn(parts.month, of: parts.year), index: parts.day - 1, wraps: true,
                        label: { "\($0 + 1)" }, choose: { $1.day = $0 + 1 })
        let firstYear = picker.minimumDate.map { calendarYear($0) } ?? 1900
        let lastYear = max(picker.maximumDate.map { calendarYear($0) } ?? 2100, firstYear)
        let year = Wheel(count: lastYear - firstYear + 1, index: min(max(parts.year - firstYear, 0), lastYear - firstYear), wraps: false,
                         label: { "\(firstYear + $0)" }, choose: { $1.year = firstYear + $0 })
        switch picker.mode {
        case 0: return [hour, minute, period]
        case 1: return [month, day, year]
        case 3:
            let total = Int(picker.countDownDuration) / 60
            return [Wheel(count: 24, index: total / 60, wraps: false, label: { "\($0) hours" }, choose: { index, _ in
                        self.setCountDown(hours: index, minutes: total % 60) }),
                    Wheel(count: 60 / interval, index: (total % 60) / interval, wraps: true, label: { "\($0 * interval) min" },
                          choose: { index, _ in self.setCountDown(hours: total / 60, minutes: index * interval) })]
        case 4: return [month, year]
        default: return [month, day, year, hour, minute, period]
        }
    }

    private func calendarYear(_ date: Double) -> Int { calendar.components(4, from: PickerDate.make(date)).year() }

    private func setCountDown(hours: Int, minutes: Int) {
        picker.countDownDuration = Double(hours * 3600 + minutes * 60)
        changed()
        sendActions(for: 1 << 12)
    }

    /// A wheel's width, by the widest of its labels.
    private func widths(_ wheels: [Wheel], in width: CGFloat) -> [CGFloat] {
        let font = UIFont.systemFont(size: 20)
        let natural = wheels.map { wheel -> CGFloat in
            let samples = wheel.count <= 31 ? Array(0..<wheel.count) : [0, wheel.count - 1]
            return (samples.map { Text.width(wheel.label($0), font: font) }.max() ?? 0) + 24
        }
        let total = natural.reduce(0, +)
        guard total > 0 else { return natural }
        return natural.map { $0 * width / total }
    }

    // MARK: Size

    @ObjCMethod("intrinsicContentSize")
    func intrinsicContentSize() -> CGSize {
        if isCompact {
            let width = Text.width(shortText, font: UIFont.systemFont(size: 17)).rounded(.up) + 24
            return CGSize(width: width, height: 34)
        }
        return CGSize(width: 320, height: UIDatePicker.wheelsHeight)
    }

    @ObjCMethod("sizeThatFits:")
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let natural = intrinsicContentSize()
        return isCompact ? natural : CGSize(width: size.width > 0 ? size.width : natural.width, height: natural.height)
    }

    // MARK: Touches

    @ObjCMethod("touchesBegan:withEvent:")
    override func touchesBegan(_ touches: NSObject, with event: NSObject?) {
        guard control.enabled, let touch = touches.as(NSSet.self)?.anyObject()?.as(UITouch.self) else { return }
        control.tracking = true
        if isCompact { return }
        let point = touch.location(in: self)
        let wheels = wheels
        var x: CGFloat = 0
        picker.column = nil
        for (index, width) in widths(wheels, in: state.bounds.width).enumerated() {
            if point.x >= x && point.x < x + width { picker.column = index }
            x += width
        }
        picker.startY = point.y
        picker.dragged = 0
    }

    @ObjCMethod("touchesMoved:withEvent:")
    override func touchesMoved(_ touches: NSObject, with event: NSObject?) {
        guard control.tracking, picker.column != nil, let touch = touches.as(NSSet.self)?.anyObject()?.as(UITouch.self) else { return }
        picker.dragged = touch.location(in: self).y - picker.startY
        setNeedsDisplay()
    }

    @ObjCMethod("touchesEnded:withEvent:")
    override func touchesEnded(_ touches: NSObject, with event: NSObject?) {
        guard control.tracking else { return }
        control.tracking = false
        if isCompact {
            showWheels()
            return
        }
        guard let column = picker.column else { return }
        let touch = touches.as(NSSet.self)?.anyObject()?.as(UITouch.self)
        // A drag turns the wheel the rows it moved; a tap turns it to the
        // row tapped.
        let rows: Int
        if abs(picker.dragged) >= 6 {
            rows = -Int((picker.dragged / UIDatePicker.rowHeight).rounded())
        } else if let point = touch?.location(in: self) {
            rows = Int(((point.y - state.bounds.midY) / UIDatePicker.rowHeight).rounded())
        } else {
            rows = 0
        }
        picker.column = nil
        picker.dragged = 0
        turn(column, by: rows)
    }

    @ObjCMethod("touchesCancelled:withEvent:")
    override func touchesCancelled(_ touches: NSObject, with event: NSObject?) {
        control.tracking = false
        picker.column = nil
        picker.dragged = 0
        setNeedsDisplay()
    }

    /// Turns wheel `column` by `rows`, wrapping if it wraps.
    func turn(_ column: Int, by rows: Int) {
        let wheels = wheels
        guard wheels.indices.contains(column), rows != 0 else { setNeedsDisplay(); return }
        let wheel = wheels[column]
        var index = wheel.index + rows
        index = wheel.wraps ? ((index % wheel.count) + wheel.count) % wheel.count : min(max(index, 0), wheel.count - 1)
        var parts = parts
        wheel.choose(index, &parts)
        if picker.mode != 3 { setParts(parts) }
        // The compact picker the wheels edit tells its own targets.
        if let editing = picker.editing {
            let compact = UIView.wrap(editing).unsafeCast(to: UIDatePicker.self)
            compact.picker.date = picker.date
            compact.picker.countDownDuration = picker.countDownDuration
            compact.setNeedsDisplay()
            compact.sendActions(for: 1 << 12)
        }
    }

    /// The compact pill opens wheels editing its date at the bottom of
    /// the screen.
    private func showWheels() {
        let wheels = UIDatePicker.objCClass.object.allocated()
            .initializeView(frame: CGRect(x: 0, y: 0, width: Screen.bounds.width, height: UIDatePicker.wheelsHeight))
            .unsafeCast(to: UIDatePicker.self)
        let source = picker, target = wheels.picker
        (target.date, target.minimumDate, target.maximumDate, target.mode) = (source.date, source.minimumDate, source.maximumDate, source.mode)
        (target.locale, target.calendar, target.minuteInterval, target.countDownDuration) =
            (source.locale, source.calendar, source.minuteInterval, source.countDownDuration)
        target.asInput = true
        target.editing = objcObject
        sendActions(for: 1 << 16)
        InputViews.show(wheels, accessory: nil, withDone: true) { [objcObject] in
            UIView.wrap(objcObject).unsafeCast(to: UIDatePicker.self).sendActions(for: 1 << 18)
        }
    }

    // MARK: Drawing

    @ObjCMethod("drawRect:")
    override func draw(_ rect: CGRect) {
        guard let context = Graphics.current else { return }
        let bounds = state.bounds
        if isCompact {
            let pill = UIColor.rgb(118.0 / 255, 118.0 / 255, 128.0 / 255, 0.12)
            withExtendedLifetime(pill) {
                CG.setFillColorWithColor(context, pill.state.makeCGColor())
                if let shape = roundedRectPath(bounds, radius: 8, corners: 0xf) {
                    CG.addPath(context, shape.object)
                    CG.fillPath(context)
                }
            }
            let font = UIFont.systemFont(size: 17)
            let text = Text.truncated(shortText, font: font, width: bounds.width - 16)
            let width = Text.width(text, font: font)
            Text.draw(text, at: CGPoint(x: bounds.midX - width / 2, y: bounds.midY - Text.lineHeight(font) / 2), font: font,
                      color: control.enabled ? UIColor.label() : UIColor.systemGray())
            return
        }
        let row = UIDatePicker.rowHeight
        // The band behind the chosen rows.
        let band = UIColor.rgb(118.0 / 255, 118.0 / 255, 128.0 / 255, 0.12)
        withExtendedLifetime(band) {
            CG.setFillColorWithColor(context, band.state.makeCGColor())
            if let shape = roundedRectPath(CGRect(x: 8, y: bounds.midY - row / 2, width: bounds.width - 16, height: row), radius: 8, corners: 0xf) {
                CG.addPath(context, shape.object)
                CG.fillPath(context)
            }
        }
        let font = UIFont.systemFont(size: 20)
        let wheels = wheels
        let widths = widths(wheels, in: bounds.width)
        let visible = Int((bounds.height / row / 2).rounded(.up))
        var x: CGFloat = 0
        for (column, wheel) in wheels.enumerated() {
            let width = widths[column]
            let offset = picker.column == column ? picker.dragged : 0
            let shift = Int((offset / row).rounded(.towardZero))
            for step in (-visible - 1 - abs(shift))...(visible + 1 + abs(shift)) {
                var index = wheel.index + step
                if wheel.wraps { index = ((index % wheel.count) + wheel.count) % wheel.count }
                guard index >= 0, index < wheel.count else { continue }
                let y = bounds.midY + CGFloat(step) * row + offset
                // Only rows inside the picker: its layer doesn't clip them.
                guard y - Text.lineHeight(font) / 2 >= 0, y + Text.lineHeight(font) / 2 <= bounds.height else { continue }
                let distance = abs(y - bounds.midY) / (bounds.height / 2)
                let text = wheel.label(index)
                let textWidth = Text.width(text, font: font)
                let color = distance < 0.15 ? UIColor.label() : UIColor.gray(0, max(0.15, 0.6 - distance * 0.5))
                Text.draw(text, at: CGPoint(x: x + (width - textWidth) / 2, y: y - Text.lineHeight(font) / 2), font: font, color: color)
            }
            x += width
        }
    }
}

// MARK: - Input views

/// A text field's input view, or a compact picker's wheels, across the
/// bottom of the screen in the keyboard's place, its accessory view above
/// it, and, for the wheels, a Done button closing it.
enum InputViews {
    nonisolated(unsafe) private static var host: UIView?
    nonisolated(unsafe) private static var closed: (() -> Void)?

    static func show(_ view: UIView, accessory: UIView?, withDone: Bool, closed: (() -> Void)? = nil) {
        hide()
        guard let window = Windows.key.map({ UIWindow(objcObject: $0, ownership: .retain) }) else { return }
        let screen = window.state.bounds
        let bottom = Screen.safeAreaInsets.bottom
        var height = view.state.bounds.height > 0 ? view.state.bounds.height : UIDatePicker.wheelsHeight
        if view.is(UIDatePicker.self) { height = UIDatePicker.wheelsHeight }
        let bar: CGFloat = withDone ? 44 : 0
        let accessoryHeight = accessory?.state.bounds.height ?? 0
        let total = accessoryHeight + bar + height + bottom
        let host = UIView.objCClass.object.allocated()
            .initializeView(frame: CGRect(x: 0, y: screen.height - total, width: screen.width, height: total)).unsafeCast(to: UIView.self)
        host.setBackgroundColor(UIColor.gray(0.97))
        var y: CGFloat = 0
        if let accessory {
            accessory.sendSetFrame(CGRect(x: 0, y: 0, width: screen.width, height: accessoryHeight))
            host.addSubview(accessory)
            y += accessoryHeight
        }
        if withDone {
            let line = UIView.objCClass.object.allocated().initializeView(frame: CGRect(x: 0, y: y, width: screen.width, height: Screen.pixel))
                .unsafeCast(to: UIView.self)
            line.setBackgroundColor(UIColor.separator())
            host.addSubview(line)
            let done = UIButton.button(UIButton.objCClass, type: 1).unsafeCast(to: UIButton.self)
            done.sendSetFrame(CGRect(x: screen.width - 80, y: y, width: 72, height: bar))
            done.setTitle("Done", for: 0)
            done.titleLabel().setFont(UIFont.boldSystemFont(size: 17))
            done.addTarget(InputViewTarget.shared, action: ObjCSelector("_perryInputDone:"), for: 1 << 6)
            host.addSubview(done)
            y += bar
        }
        view.sendSetFrame(CGRect(x: 0, y: y, width: screen.width, height: height))
        host.addSubview(view)
        window.addSubview(host)
        InputViews.host = host
        InputViews.closed = closed
        Display.markDirty()
    }

    static func hide() {
        guard let host else { return }
        InputViews.host = nil
        host.removeFromSuperview()
        let closed = InputViews.closed
        InputViews.closed = nil
        closed?()
        Display.markDirty()
    }

    /// Whether `view` is in the input view shown.
    static func contains(_ view: UIView?) -> Bool {
        guard let host else { return false }
        var current = view
        while let candidate = current {
            if candidate.objcObject == host.objcObject { return true }
            current = candidate.state.superview.map(UIView.wrap)
        }
        return false
    }
}

/// Done's target: the input view closes, and the field editing with it.
@ObjCClass("_PerryInputViewTarget")
open class InputViewTarget: NSObject {
    nonisolated(unsafe) static let shared: InputViewTarget = objCClass.object.newInstance().unsafeCast(to: InputViewTarget.self)

    @ObjCMethod("_perryInputDone:")
    func done(_ sender: NSObject?) {
        if let responder = Keyboard.responder { _ = responder.sendResignFirstResponder() }
        InputViews.hide()
    }
}
