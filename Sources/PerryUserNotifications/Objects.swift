import PerryObjCInterop

// UserNotifications' value classes: content (immutable and mutable),
// sounds, triggers, requests, delivered notifications and responses,
// actions and categories, and settings. Each keeps its values in Swift
// state; all are NSSecureCoding and copy as Darwin's do.

// MARK: - Content

final class ContentState: @unchecked Sendable {
    var title: String?
    var subtitle: String?
    var body: String?
    var badge: NSObject?
    var sound: NSObject?
    var launchImageName = ""
    var userInfo: NSObject = NSDictionary.empty()
    var attachments: NSObject = NSMutableArray.of([])
    var categoryIdentifier = ""
    var threadIdentifier = ""
    var targetContentIdentifier: String?
    var summaryArgument = ""
    var summaryArgumentCount: UInt = 0
    /// UNNotificationInterruptionLevel: passive 0, active 1, time-sensitive 2, critical 3.
    var interruptionLevel: UInt = 1
    var relevanceScore = 0.0
    var filterCriteria: String?

    func copy() -> ContentState {
        let copy = ContentState()
        (copy.title, copy.subtitle, copy.body, copy.badge, copy.sound) = (title, subtitle, body, badge, sound)
        (copy.launchImageName, copy.userInfo, copy.attachments) = (launchImageName, userInfo.copyObject(), attachments.copyObject())
        (copy.categoryIdentifier, copy.threadIdentifier, copy.targetContentIdentifier) = (categoryIdentifier, threadIdentifier, targetContentIdentifier)
        (copy.summaryArgument, copy.summaryArgumentCount) = (summaryArgument, summaryArgumentCount)
        (copy.interruptionLevel, copy.relevanceScore, copy.filterCriteria) = (interruptionLevel, relevanceScore, filterCriteria)
        return copy
    }

    func isEqual(to other: ContentState) -> Bool {
        title == other.title && subtitle == other.subtitle && body == other.body && equal(badge, other.badge)
            && equal(sound, other.sound) && launchImageName == other.launchImageName && equal(userInfo, other.userInfo)
            && equal(attachments, other.attachments) && categoryIdentifier == other.categoryIdentifier
            && threadIdentifier == other.threadIdentifier && targetContentIdentifier == other.targetContentIdentifier
            && interruptionLevel == other.interruptionLevel && relevanceScore == other.relevanceScore
    }

    func encode(_ coder: NSObject) {
        coder.encode(title.map(NSObject.string), forKey: "title")
        coder.encode(subtitle.map(NSObject.string), forKey: "subtitle")
        coder.encode(body.map(NSObject.string), forKey: "body")
        coder.encode(badge, forKey: "badge")
        coder.encode(sound, forKey: "sound")
        coder.encode(NSObject.string(launchImageName), forKey: "launchImageName")
        coder.encode(userInfo, forKey: "userInfo")
        coder.encode(attachments, forKey: "attachments")
        coder.encode(NSObject.string(categoryIdentifier), forKey: "categoryIdentifier")
        coder.encode(NSObject.string(threadIdentifier), forKey: "threadIdentifier")
        coder.encode(targetContentIdentifier.map(NSObject.string), forKey: "targetContentIdentifier")
        coder.encode(integer: Int(interruptionLevel), forKey: "interruptionLevel")
        coder.encode(double: relevanceScore, forKey: "relevanceScore")
    }

    static func decode(_ coder: NSObject) -> ContentState {
        let state = ContentState()
        state.title = coder.decodeString("title")
        state.subtitle = coder.decodeString("subtitle")
        state.body = coder.decodeString("body")
        state.badge = coder.decodeObject(forKey: "badge")
        state.sound = coder.decodeObject(forKey: "sound")
        state.launchImageName = coder.decodeString("launchImageName") ?? ""
        state.userInfo = coder.decodeObject(forKey: "userInfo") ?? NSDictionary.empty()
        state.attachments = coder.decodeObject(forKey: "attachments") ?? NSMutableArray.of([])
        state.categoryIdentifier = coder.decodeString("categoryIdentifier") ?? ""
        state.threadIdentifier = coder.decodeString("threadIdentifier") ?? ""
        state.targetContentIdentifier = coder.decodeString("targetContentIdentifier")
        state.interruptionLevel = UInt(coder.decodeInteger(forKey: "interruptionLevel"))
        state.relevanceScore = coder.decodeDouble(forKey: "relevanceScore")
        return state
    }
}

enum Contents {
    static let states = StateTable<ContentState>()

    static func state(_ object: NSObject?) -> ContentState? { states[object?.objcObject] }

    /// A content object of the class (+0) with the state.
    static func object(_ state: ContentState, mutable: Bool) -> NSObject {
        let cls = mutable ? UNMutableNotificationContent.objCClass : UNNotificationContent.objCClass
        let object = cls.autoreleasedInstance()
        states.set(object.objcObject, state)
        return object
    }
}

/// UNNotificationContent.
@ObjCClass("UNNotificationContent")
open class UNNotificationContent: NSObject {
    var state: ContentState {
        if let state = Contents.states[objcObject] { return state }
        let state = ContentState()
        Contents.states.set(objcObject, state)
        return state
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Contents.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UNNotificationContent.objCClass.pointer)
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = state
        return self
    }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }
    @ObjCMethod("encodeWithCoder:") func encode(with coder: NSObject) { state.encode(coder) }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        Contents.states.set(objcObject, ContentState.decode(coder))
        return self
    }

    @ObjCMethod("title") func title() -> String? { state.title }
    @ObjCMethod("subtitle") func subtitle() -> String? { state.subtitle }
    @ObjCMethod("body") func body() -> String? { state.body }
    @ObjCMethod("badge") func badge() -> NSObject? { state.badge }
    @ObjCMethod("sound") func sound() -> NSObject? { state.sound }
    @ObjCMethod("launchImageName") func launchImageName() -> String { state.launchImageName }
    @ObjCMethod("userInfo") func userInfo() -> NSObject { state.userInfo }
    @ObjCMethod("attachments") func attachments() -> NSObject { state.attachments }
    @ObjCMethod("categoryIdentifier") func categoryIdentifier() -> String { state.categoryIdentifier }
    @ObjCMethod("threadIdentifier") func threadIdentifier() -> String { state.threadIdentifier }
    @ObjCMethod("targetContentIdentifier") func targetContentIdentifier() -> String? { state.targetContentIdentifier }
    @ObjCMethod("summaryArgument") func summaryArgument() -> String { state.summaryArgument }
    @ObjCMethod("summaryArgumentCount") func summaryArgumentCount() -> UInt { state.summaryArgumentCount }
    @ObjCMethod("interruptionLevel") func interruptionLevel() -> UInt { state.interruptionLevel }
    @ObjCMethod("relevanceScore") func relevanceScore() -> Double { state.relevanceScore }
    @ObjCMethod("filterCriteria") func filterCriteria() -> String? { state.filterCriteria }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        ObjCRuntime.retain(Contents.object(state.copy(), mutable: false).objcObject)!
    }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        ObjCRuntime.retain(Contents.object(state.copy(), mutable: true).objcObject)!
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool { Contents.state(other).map(state.isEqual(to:)) ?? false }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: (state.title ?? "").hashValue ^ (state.body ?? "").hashValue) }

    @ObjCMethod("description")
    func description() -> String {
        "<UNNotificationContent: \(objcObject); title: \(state.title == nil ? "(null)" : "<redacted>"), "
            + "categoryIdentifier: \(state.categoryIdentifier), threadIdentifier: \(state.threadIdentifier)>"
    }
}

/// UNMutableNotificationContent.
@ObjCClass("UNMutableNotificationContent")
open class UNMutableNotificationContent: UNNotificationContent {
    @ObjCMethod("setTitle:") func setTitle(_ value: String?) { state.title = value }
    @ObjCMethod("setSubtitle:") func setSubtitle(_ value: String?) { state.subtitle = value }
    @ObjCMethod("setBody:") func setBody(_ value: String?) { state.body = value }
    @ObjCMethod("setBadge:") func setBadge(_ value: NSObject?) { state.badge = value }
    @ObjCMethod("setSound:") func setSound(_ value: NSObject?) { state.sound = value }
    @ObjCMethod("setLaunchImageName:") func setLaunchImageName(_ value: String?) { state.launchImageName = value ?? "" }
    @ObjCMethod("setUserInfo:") func setUserInfo(_ value: NSObject?) { state.userInfo = value?.copyObject() ?? NSDictionary.empty() }
    @ObjCMethod("setAttachments:") func setAttachments(_ value: NSObject?) { state.attachments = value?.copyObject() ?? NSMutableArray.of([]) }
    @ObjCMethod("setCategoryIdentifier:") func setCategoryIdentifier(_ value: String?) { state.categoryIdentifier = value ?? "" }
    @ObjCMethod("setThreadIdentifier:") func setThreadIdentifier(_ value: String?) { state.threadIdentifier = value ?? "" }
    @ObjCMethod("setTargetContentIdentifier:") func setTargetContentIdentifier(_ value: String?) { state.targetContentIdentifier = value }
    @ObjCMethod("setSummaryArgument:") func setSummaryArgument(_ value: String?) { state.summaryArgument = value ?? "" }
    @ObjCMethod("setSummaryArgumentCount:") func setSummaryArgumentCount(_ value: UInt) { state.summaryArgumentCount = value }
    @ObjCMethod("setInterruptionLevel:") func setInterruptionLevel(_ value: UInt) { state.interruptionLevel = value }
    @ObjCMethod("setRelevanceScore:") func setRelevanceScore(_ value: Double) { state.relevanceScore = value }
    @ObjCMethod("setFilterCriteria:") func setFilterCriteria(_ value: String?) { state.filterCriteria = value }
}

// MARK: - Sounds

final class SoundState: @unchecked Sendable {
    /// nil for the default sound.
    let name: String?
    let critical: Bool
    let volume: Float

    init(name: String?, critical: Bool = false, volume: Float = 1) {
        self.name = name
        self.critical = critical
        self.volume = volume
    }
}

/// UNNotificationSound.
@ObjCClass("UNNotificationSound")
open class UNNotificationSound: NSObject {
    static let states = StateTable<SoundState>()

    static func object(_ state: SoundState) -> NSObject {
        let object = objCClass.autoreleasedInstance()
        states.set(object.objcObject, state)
        return object
    }

    var state: SoundState { UNNotificationSound.states[objcObject] ?? SoundState(name: nil) }

    @ObjCMethod("dealloc")
    func dealloc() {
        UNNotificationSound.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UNNotificationSound.objCClass.pointer)
    }

    @ObjCClassMethod("defaultSound") static func defaultSound() -> NSObject { object(SoundState(name: nil)) }
    @ObjCClassMethod("defaultRingtoneSound") static func defaultRingtoneSound() -> NSObject { object(SoundState(name: "ringtone")) }
    @ObjCClassMethod("defaultCriticalSound") static func defaultCriticalSound() -> NSObject { object(SoundState(name: nil, critical: true)) }

    @ObjCClassMethod("defaultCriticalSoundWithAudioVolume:")
    static func defaultCriticalSound(volume: Float) -> NSObject { object(SoundState(name: nil, critical: true, volume: volume)) }

    @ObjCClassMethod("soundNamed:") static func sound(named name: String) -> NSObject { object(SoundState(name: name)) }
    @ObjCClassMethod("ringtoneSoundNamed:") static func ringtoneSound(named name: String) -> NSObject { object(SoundState(name: name)) }
    @ObjCClassMethod("criticalSoundNamed:") static func criticalSound(named name: String) -> NSObject { object(SoundState(name: name, critical: true)) }

    @ObjCClassMethod("criticalSoundNamed:withAudioVolume:")
    static func criticalSound(named name: String, volume: Float) -> NSObject { object(SoundState(name: name, critical: true, volume: volume)) }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }

    @ObjCMethod("encodeWithCoder:")
    func encode(with coder: NSObject) {
        coder.encode(state.name.map(NSObject.string), forKey: "name")
        coder.encode(bool: state.critical, forKey: "critical")
        coder.encode(double: Double(state.volume), forKey: "volume")
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        UNNotificationSound.states.set(objcObject, SoundState(name: coder.decodeString("name"), critical: coder.decodeBool(forKey: "critical"),
                                                              volume: Float(coder.decodeDouble(forKey: "volume"))))
        return self
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = UNNotificationSound.states[other?.objcObject] else { return false }
        return other.name == state.name && other.critical == state.critical && other.volume == state.volume
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: (state.name ?? "").hashValue) }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

// MARK: - Triggers

final class TriggerState: @unchecked Sendable {
    enum Kind { case interval(Double), calendar(NSObject), push }
    let kind: Kind
    let repeats: Bool
    /// When a time interval trigger was made, which its next date counts from.
    let created = NSDate.now()

    init(_ kind: Kind, repeats: Bool) {
        self.kind = kind
        self.repeats = repeats
    }

    /// Seconds from now to the next firing; nil when it never fires.
    var secondsToNext: Double? {
        switch kind {
        case .interval(let seconds): return created.timeIntervalSinceNow() + seconds
        case .calendar(let components):
            // NSCalendarMatchNextTime.
            return NSCalendar.current().nextDate(after: NSDate.now(), matching: components, options: 1 << 10)?.timeIntervalSinceNow()
        case .push: return nil
        }
    }
}

enum Triggers {
    static let states = StateTable<TriggerState>()

    static func object(_ cls: ObjCClass, _ state: TriggerState) -> NSObject {
        let object = cls.autoreleasedInstance()
        states.set(object.objcObject, state)
        return object
    }
}

/// UNNotificationTrigger.
@ObjCClass("UNNotificationTrigger")
open class UNNotificationTrigger: NSObject {
    var trigger: TriggerState { Triggers.states[objcObject] ?? TriggerState(.push, repeats: false) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Triggers.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UNNotificationTrigger.objCClass.pointer)
    }

    @ObjCMethod("repeats") func repeats() -> Bool { trigger.repeats }
    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }

    @ObjCMethod("encodeWithCoder:")
    func encode(with coder: NSObject) {
        coder.encode(bool: trigger.repeats, forKey: "repeats")
        switch trigger.kind {
        case .interval(let seconds): coder.encode(double: seconds, forKey: "timeInterval")
        case .calendar(let components): coder.encode(components, forKey: "dateComponents")
        case .push: break
        }
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let repeats = coder.decodeBool(forKey: "repeats")
        let kind: TriggerState.Kind
        if let components = coder.decodeObject(forKey: "dateComponents") {
            kind = .calendar(components)
        } else if objCClass.pointer == UNPushNotificationTrigger.objCClass.pointer {
            kind = .push
        } else {
            kind = .interval(coder.decodeDouble(forKey: "timeInterval"))
        }
        Triggers.states.set(objcObject, TriggerState(kind, repeats: repeats))
        return self
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

/// UNPushNotificationTrigger.
@ObjCClass("UNPushNotificationTrigger")
open class UNPushNotificationTrigger: UNNotificationTrigger {}

/// UNTimeIntervalNotificationTrigger.
@ObjCClass("UNTimeIntervalNotificationTrigger")
open class UNTimeIntervalNotificationTrigger: UNNotificationTrigger {
    @ObjCClassMethod("triggerWithTimeInterval:repeats:")
    static func make(_ cls: ObjCClass, timeInterval: Double, repeats: Bool) -> NSObject {
        guard timeInterval > 0 else { notificationsFatal("time interval must be greater than 0") }
        guard !repeats || timeInterval >= 60 else { notificationsFatal("time interval must be at least 60 if repeating") }
        return Triggers.object(cls, TriggerState(.interval(timeInterval), repeats: repeats))
    }

    @ObjCMethod("timeInterval")
    func timeInterval() -> Double {
        if case .interval(let seconds) = trigger.kind { return seconds }
        return 0
    }

    @ObjCMethod("nextTriggerDate")
    func nextTriggerDate() -> NSDate? { trigger.secondsToNext.map { NSDate.make(sinceNow: $0) } }
}

/// UNCalendarNotificationTrigger.
@ObjCClass("UNCalendarNotificationTrigger")
open class UNCalendarNotificationTrigger: UNNotificationTrigger {
    @ObjCClassMethod("triggerWithDateMatchingComponents:repeats:")
    static func make(_ cls: ObjCClass, components: NSObject, repeats: Bool) -> NSObject {
        Triggers.object(cls, TriggerState(.calendar(components.copyObject()), repeats: repeats))
    }

    @ObjCMethod("dateComponents")
    func dateComponents() -> NSObject? {
        if case .calendar(let components) = trigger.kind { return components }
        return nil
    }

    @ObjCMethod("nextTriggerDate")
    func nextTriggerDate() -> NSDate? { trigger.secondsToNext.map { NSDate.make(sinceNow: $0) } }
}

// MARK: - Requests and notifications

final class RequestState: @unchecked Sendable {
    let identifier: String
    let content: NSObject
    let trigger: NSObject?

    init(identifier: String, content: NSObject, trigger: NSObject?) {
        self.identifier = identifier
        self.content = content
        self.trigger = trigger
    }
}

/// UNNotificationRequest.
@ObjCClass("UNNotificationRequest")
open class UNNotificationRequest: NSObject {
    static let states = StateTable<RequestState>()

    var request: RequestState? { UNNotificationRequest.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UNNotificationRequest.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UNNotificationRequest.objCClass.pointer)
    }

    /// The content is copied, immutable.
    @ObjCClassMethod("requestWithIdentifier:content:trigger:")
    static func make(_ cls: ObjCClass, identifier: String, content: NSObject, trigger: NSObject?) -> NSObject {
        let object = cls.autoreleasedInstance()
        states.set(object.objcObject, RequestState(identifier: identifier, content: content.copyObject(), trigger: trigger))
        return object
    }

    @ObjCMethod("identifier") func identifier() -> String { request?.identifier ?? "" }
    @ObjCMethod("content") func content() -> NSObject? { request?.content }
    @ObjCMethod("trigger") func trigger() -> NSObject? { request?.trigger }
    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }

    @ObjCMethod("encodeWithCoder:")
    func encode(with coder: NSObject) {
        coder.encode(NSObject.string(identifier()), forKey: "identifier")
        coder.encode(request?.content, forKey: "content")
        coder.encode(request?.trigger, forKey: "trigger")
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let content = coder.decodeObject(forKey: "content") ?? Contents.object(ContentState(), mutable: false)
        UNNotificationRequest.states.set(objcObject, RequestState(identifier: coder.decodeString("identifier") ?? "", content: content,
                                                                  trigger: coder.decodeObject(forKey: "trigger")))
        return self
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("description")
    func description() -> String { "<UNNotificationRequest: \(objcObject); identifier: \(identifier())>" }
}

final class NotificationState: @unchecked Sendable {
    let date: NSObject
    let request: NSObject

    init(date: NSObject, request: NSObject) {
        self.date = date
        self.request = request
    }
}

/// UNNotification: a delivered request.
@ObjCClass("UNNotification")
open class UNNotification: NSObject {
    static let states = StateTable<NotificationState>()

    static func object(request: NSObject) -> NSObject {
        let object = objCClass.autoreleasedInstance()
        states.set(object.objcObject, NotificationState(date: NSDate.now(), request: request))
        return object
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UNNotification.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UNNotification.objCClass.pointer)
    }

    @ObjCMethod("date") func date() -> NSObject? { UNNotification.states[objcObject]?.date }
    @ObjCMethod("request") func request() -> NSObject? { UNNotification.states[objcObject]?.request }
    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

final class ResponseState: @unchecked Sendable {
    let notification: NSObject
    let actionIdentifier: String
    let userText: String?

    init(notification: NSObject, actionIdentifier: String, userText: String?) {
        self.notification = notification
        self.actionIdentifier = actionIdentifier
        self.userText = userText
    }
}

/// UNNotificationResponse.
@ObjCClass("UNNotificationResponse")
open class UNNotificationResponse: NSObject {
    static let states = StateTable<ResponseState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        UNNotificationResponse.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UNNotificationResponse.objCClass.pointer)
    }

    @ObjCMethod("notification") func notification() -> NSObject? { UNNotificationResponse.states[objcObject]?.notification }
    @ObjCMethod("actionIdentifier") func actionIdentifier() -> String { UNNotificationResponse.states[objcObject]?.actionIdentifier ?? "" }
    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }
}

/// UNTextInputNotificationResponse.
@ObjCClass("UNTextInputNotificationResponse")
open class UNTextInputNotificationResponse: UNNotificationResponse {
    @ObjCMethod("userText") func userText() -> String { UNNotificationResponse.states[objcObject]?.userText ?? "" }
}

// MARK: - Actions and categories

final class ActionState: @unchecked Sendable {
    let identifier: String
    let title: String
    let options: UInt
    let icon: NSObject?
    let buttonTitle: String
    let placeholder: String

    init(identifier: String, title: String, options: UInt, icon: NSObject? = nil, buttonTitle: String = "", placeholder: String = "") {
        self.identifier = identifier
        self.title = title
        self.options = options
        self.icon = icon
        self.buttonTitle = buttonTitle
        self.placeholder = placeholder
    }
}

/// UNNotificationAction.
@ObjCClass("UNNotificationAction")
open class UNNotificationAction: NSObject {
    static let states = StateTable<ActionState>()

    var action: ActionState { UNNotificationAction.states[objcObject] ?? ActionState(identifier: "", title: "", options: 0) }

    static func object(_ cls: ObjCClass, _ state: ActionState) -> NSObject {
        let object = cls.autoreleasedInstance()
        states.set(object.objcObject, state)
        return object
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UNNotificationAction.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UNNotificationAction.objCClass.pointer)
    }

    @ObjCClassMethod("actionWithIdentifier:title:options:")
    static func make(_ cls: ObjCClass, identifier: String, title: String, options: UInt) -> NSObject {
        object(cls, ActionState(identifier: identifier, title: title, options: options))
    }

    @ObjCClassMethod("actionWithIdentifier:title:options:icon:")
    static func make(_ cls: ObjCClass, identifier: String, title: String, options: UInt, icon: NSObject?) -> NSObject {
        object(cls, ActionState(identifier: identifier, title: title, options: options, icon: icon))
    }

    @ObjCMethod("identifier") func identifier() -> String { action.identifier }
    @ObjCMethod("title") func title() -> String { action.title }
    @ObjCMethod("options") func options() -> UInt { action.options }
    @ObjCMethod("icon") func icon() -> NSObject? { action.icon }
    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = UNNotificationAction.states[other?.objcObject] else { return false }
        return other.identifier == action.identifier && other.title == action.title && other.options == action.options
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: action.identifier.hashValue) }
}

/// UNTextInputNotificationAction.
@ObjCClass("UNTextInputNotificationAction")
open class UNTextInputNotificationAction: UNNotificationAction {
    @ObjCClassMethod("actionWithIdentifier:title:options:textInputButtonTitle:textInputPlaceholder:")
    static func make(_ cls: ObjCClass, identifier: String, title: String, options: UInt, buttonTitle: String,
                     placeholder: String) -> NSObject {
        object(cls, ActionState(identifier: identifier, title: title, options: options, buttonTitle: buttonTitle, placeholder: placeholder))
    }

    @ObjCClassMethod("actionWithIdentifier:title:options:icon:textInputButtonTitle:textInputPlaceholder:")
    static func make(_ cls: ObjCClass, identifier: String, title: String, options: UInt, icon: NSObject?, buttonTitle: String,
                     placeholder: String) -> NSObject {
        object(cls, ActionState(identifier: identifier, title: title, options: options, icon: icon, buttonTitle: buttonTitle,
                                placeholder: placeholder))
    }

    @ObjCMethod("textInputButtonTitle") func textInputButtonTitle() -> String { action.buttonTitle }
    @ObjCMethod("textInputPlaceholder") func textInputPlaceholder() -> String { action.placeholder }
}

final class CategoryState: @unchecked Sendable {
    let identifier: String
    let actions: NSObject
    let intentIdentifiers: NSObject
    let options: UInt
    let previewPlaceholder: String?
    let summaryFormat: String?

    init(identifier: String, actions: NSObject, intentIdentifiers: NSObject, options: UInt, previewPlaceholder: String? = nil,
         summaryFormat: String? = nil) {
        self.identifier = identifier
        self.actions = actions
        self.intentIdentifiers = intentIdentifiers
        self.options = options
        self.previewPlaceholder = previewPlaceholder
        self.summaryFormat = summaryFormat
    }
}

/// UNNotificationCategory.
@ObjCClass("UNNotificationCategory")
open class UNNotificationCategory: NSObject {
    static let states = StateTable<CategoryState>()

    var category: CategoryState? { UNNotificationCategory.states[objcObject] }

    static func object(_ cls: ObjCClass, _ state: CategoryState) -> NSObject {
        let object = cls.autoreleasedInstance()
        states.set(object.objcObject, state)
        return object
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UNNotificationCategory.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UNNotificationCategory.objCClass.pointer)
    }

    @ObjCClassMethod("categoryWithIdentifier:actions:intentIdentifiers:options:")
    static func make(_ cls: ObjCClass, identifier: String, actions: NSObject, intents: NSObject, options: UInt) -> NSObject {
        object(cls, CategoryState(identifier: identifier, actions: actions.copyObject(), intentIdentifiers: intents.copyObject(), options: options))
    }

    @ObjCClassMethod("categoryWithIdentifier:actions:intentIdentifiers:hiddenPreviewsBodyPlaceholder:options:")
    static func make(_ cls: ObjCClass, identifier: String, actions: NSObject, intents: NSObject, placeholder: String?,
                     options: UInt) -> NSObject {
        object(cls, CategoryState(identifier: identifier, actions: actions.copyObject(), intentIdentifiers: intents.copyObject(),
                                  options: options, previewPlaceholder: placeholder))
    }

    @ObjCClassMethod("categoryWithIdentifier:actions:intentIdentifiers:hiddenPreviewsBodyPlaceholder:categorySummaryFormat:options:")
    static func make(_ cls: ObjCClass, identifier: String, actions: NSObject, intents: NSObject, placeholder: String?,
                     summaryFormat: String?, options: UInt) -> NSObject {
        object(cls, CategoryState(identifier: identifier, actions: actions.copyObject(), intentIdentifiers: intents.copyObject(),
                                  options: options, previewPlaceholder: placeholder, summaryFormat: summaryFormat))
    }

    @ObjCMethod("identifier") func identifier() -> String { category?.identifier ?? "" }
    @ObjCMethod("actions") func actions() -> NSObject? { category?.actions }
    @ObjCMethod("intentIdentifiers") func intentIdentifiers() -> NSObject? { category?.intentIdentifiers }
    @ObjCMethod("options") func options() -> UInt { category?.options ?? 0 }
    @ObjCMethod("hiddenPreviewsBodyPlaceholder") func hiddenPreviewsBodyPlaceholder() -> String { category?.previewPlaceholder ?? "" }
    @ObjCMethod("categorySummaryFormat") func categorySummaryFormat() -> String { category?.summaryFormat ?? "" }
    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = UNNotificationCategory.states[other?.objcObject], let category else { return false }
        return other.identifier == category.identifier && equal(other.actions, category.actions) && other.options == category.options
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: identifier().hashValue) }
}

// MARK: - Settings

/// UNNotificationSettings: UNAuthorizationStatus, then UNNotificationSetting
/// for each kind (not supported 0, disabled 1, enabled 2).
final class SettingsState: @unchecked Sendable {
    let status: Int
    init(status: Int) { self.status = status }
    var setting: Int { status == 2 || status == 3 || status == 4 ? 2 : 1 }
}

@ObjCClass("UNNotificationSettings")
open class UNNotificationSettings: NSObject {
    static let states = StateTable<SettingsState>()

    static func object(status: Int) -> NSObject {
        let object = objCClass.autoreleasedInstance()
        states.set(object.objcObject, SettingsState(status: status))
        return object
    }

    var settings: SettingsState { UNNotificationSettings.states[objcObject] ?? SettingsState(status: 0) }

    @ObjCMethod("dealloc")
    func dealloc() {
        UNNotificationSettings.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UNNotificationSettings.objCClass.pointer)
    }

    @ObjCMethod("authorizationStatus") func authorizationStatus() -> Int { settings.status }
    @ObjCMethod("soundSetting") func soundSetting() -> Int { settings.setting }
    @ObjCMethod("badgeSetting") func badgeSetting() -> Int { settings.setting }
    @ObjCMethod("alertSetting") func alertSetting() -> Int { settings.setting }
    @ObjCMethod("notificationCenterSetting") func notificationCenterSetting() -> Int { settings.setting }
    @ObjCMethod("lockScreenSetting") func lockScreenSetting() -> Int { settings.setting }
    @ObjCMethod("carPlaySetting") func carPlaySetting() -> Int { 0 }
    @ObjCMethod("criticalAlertSetting") func criticalAlertSetting() -> Int { 0 }
    @ObjCMethod("announcementSetting") func announcementSetting() -> Int { 0 }
    @ObjCMethod("timeSensitiveSetting") func timeSensitiveSetting() -> Int { 0 }
    @ObjCMethod("scheduledDeliverySetting") func scheduledDeliverySetting() -> Int { 1 }
    @ObjCMethod("directMessagesSetting") func directMessagesSetting() -> Int { 0 }
    /// UNAlertStyle: none 0, banner 1, alert 2.
    @ObjCMethod("alertStyle") func alertStyle() -> Int { settings.setting == 2 ? 1 : 0 }
    /// UNShowPreviewsSetting: always 0.
    @ObjCMethod("showPreviewsSetting") func showPreviewsSetting() -> Int { 0 }
    @ObjCMethod("providesAppNotificationSettings") func providesAppNotificationSettings() -> Bool { false }
}

/// The action identifiers and error domain.
@ObjCConstants
enum NotificationConstants {
    static let UNNotificationDefaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"
    static let UNNotificationDismissActionIdentifier = "com.apple.UNNotificationDismissActionIdentifier"
    static let UNErrorDomain = "UNErrorDomain"
}
