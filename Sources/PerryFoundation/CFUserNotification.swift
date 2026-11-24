import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFUserNotification: an alert a program, usually one without windows,
// asks the system to show, and the user's answer to it. Foundation has no
// way to show one here (NSAlert is AppKit's, and a program using this
// usually has no application to run one), and no user to answer. So each
// is told on stderr, its header, message and buttons, and answered at once
// as the closest a user could have:
//
// - With a default button, as though it were pressed: response
//   kCFUserNotificationDefaultResponse (0), with the check boxes and pop-up
//   selection the flags began with, and the text fields' values as given.
// - With kCFUserNotificationNoDefaultButtonFlag, as though it timed out:
//   kCFUserNotificationCancelResponse (3), as Darwin answers one that times
//   out or is cancelled.
//
// So receiving the response never waits, and a run loop source calls its
// callout once, on the loop's next pass after it's added.

/// CFUserNotificationCallBack: (notification, response flags).
public typealias CFUserNotificationCallout = @convention(c) (UnsafeMutableRawPointer?, UInt) -> Void

final class UserNotificationStorage: FiringSource {
    let lock = NSLockStorage()
    /// The notification's dictionary, an immutable copy (+1).
    var dictionary: id?
    var flags: UInt
    var timeout: Double
    var responseFlags: UInt = UserNotifications.cancelResponse
    /// The values the user gave (+1), or nil.
    var responseDictionary: id?
    /// The CFUserNotification, not retained: it owns this.
    var object: id?
    var callout: CFUserNotificationCallout?
    var delivered = false
    var source: (object: id, storage: CustomSourceStorage)?

    init(dictionary: id?, flags: UInt, timeout: Double) {
        (self.dictionary, self.flags, self.timeout) = (dictionary, flags, timeout)
    }

    deinit {
        ObjC.release(dictionary)
        ObjC.release(responseDictionary)
    }

    /// Shows (tells of) the notification and answers it.
    func answer() {
        let answer = UserNotifications.answer(dictionary: dictionary, flags: flags)
        UserNotifications.tell(dictionary: dictionary, flags: flags, timeout: timeout, response: answer.flags)
        let old = lock.locked { () -> id? in
            defer { (responseFlags, responseDictionary) = (answer.flags, answer.dictionary) }
            return responseDictionary
        }
        ObjC.release(old)
    }

    /// The response, once, to the program's callout.
    func fire() {
        let due = lock.locked { () -> (CFUserNotificationCallout, id, UInt)? in
            guard !delivered, let callout, let object else { return nil }
            delivered = true
            return (callout, object, responseFlags)
        }
        guard let due else { return }
        due.0(due.1, due.2)
    }
}

enum UserNotifications {
    nonisolated(unsafe) static var notificationClass: Class!

    static let typeID: UInt = 54

    /// Responses: kCFUserNotificationDefaultResponse, Alternate, Other and
    /// Cancel.
    static let defaultResponse: UInt = 0, cancelResponse: UInt = 3
    /// The flags' alert level (kCFUserNotificationStopAlertLevel 0, Note 1,
    /// Caution 2, Plain 3).
    static let levelMask: UInt = 3
    static let noDefaultButtonFlag: UInt = 1 << 5
    /// CFUserNotificationCheckBoxChecked(i), 1 << (8 + i), and
    /// CFUserNotificationPopUpSelection(n), n << 24: the user's state, which
    /// the flags given begin with.
    static let checkBoxMask: UInt = 0xFFFF << 8
    static let popUpMask: UInt = ~UInt(0) << 24

    static let headerKey = "AlertHeader", messageKey = "AlertMessage"
    static let defaultButtonKey = "DefaultButtonTitle", alternateButtonKey = "AlternateButtonTitle"
    static let otherButtonKey = "OtherButtonTitle", textFieldValuesKey = "TextFieldValues"

    static func storage(_ object: id?) -> UserNotificationStorage? { Storage.get(object, as: UserNotificationStorage.self) }

    /// The value for a key named by a Swift string, +0.
    static func value(_ dictionary: id?, _ key: String) -> id? {
        guard let dictionary else { return nil }
        let name = Strings.make(key)
        defer { ObjC.release(name) }
        return Dictionaries.value(dictionary, for: name)
    }

    static func string(_ dictionary: id?, _ key: String) -> String? {
        let object = value(dictionary, key)
        if let text = Strings.value(of: object) { return text }
        // A localized key may be an array of strings; the first is shown.
        guard let object, ObjC.isKind(object, of: Arrays.arrayClass) else { return nil }
        return Arrays.elements(object).compactMap { Strings.value(of: $0) }.first
    }

    /// An immutable copy (+1) of the program's dictionary, or nil.
    static func copy(_ dictionary: id?) -> id? {
        guard let dictionary else { return nil }
        return Dictionaries.make(Dictionaries.entries(dictionary))
    }

    /// The response the user would most likely have given, and its
    /// dictionary (+1): the text fields' values as they began.
    static func answer(dictionary: id?, flags: UInt) -> (flags: UInt, dictionary: id?) {
        guard flags & noDefaultButtonFlag == 0 else { return (cancelResponse, nil) }
        let state = flags & (checkBoxMask | popUpMask)
        guard let values = value(dictionary, textFieldValuesKey) else { return (defaultResponse | state, nil) }
        let key = Strings.make(textFieldValuesKey)
        defer { ObjC.release(key) }
        return (defaultResponse | state, Dictionaries.make([(key: key, value: values)]))
    }

    /// Tells of the notification on stderr, as there's no way to show it.
    static func tell(header: String?, message: String?, buttons: [String], flags: UInt, timeout: Double, response: UInt) {
        let levels = ["stop", "note", "caution", "plain"]
        var line = "perry: user notification (\(levels[Int(flags & levelMask)])"
        if timeout > 0 { line += ", timeout \(timeout)s" }
        line += "): \(header ?? "")"
        if let message, !message.isEmpty { line += ": \(message)" }
        if !buttons.isEmpty { line += " [\(buttons.joined(separator: " | "))]" }
        if response & levelMask == cancelResponse {
            line += " - not shown; answered as timed out"
        } else {
            line += " - not shown; answered with the default button (\(buttons.first ?? "OK"))"
        }
        line += "\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }

    static func tell(dictionary: id?, flags: UInt, timeout: Double, response: UInt) {
        var buttons: [String] = []
        if flags & noDefaultButtonFlag == 0 { buttons.append(string(dictionary, defaultButtonKey) ?? "OK") }
        if let alternate = string(dictionary, alternateButtonKey) { buttons.append(alternate) }
        if let other = string(dictionary, otherButtonKey) { buttons.append(other) }
        tell(header: string(dictionary, headerKey), message: string(dictionary, messageKey), buttons: buttons, flags: flags,
             timeout: timeout, response: response)
    }

    /// The response flags for an alert of these buttons, told on stderr.
    static func display(timeout: Double, flags: UInt, header: id?, message: id?, defaultButton: id?, alternateButton: id?,
                        otherButton: id?) -> UInt {
        let response = flags & noDefaultButtonFlag == 0 ? defaultResponse : cancelResponse
        var buttons: [String] = []
        if flags & noDefaultButtonFlag == 0 { buttons.append(Strings.value(of: defaultButton) ?? "OK") }
        if let alternate = Strings.value(of: alternateButton) { buttons.append(alternate) }
        if let other = Strings.value(of: otherButton) { buttons.append(other) }
        tell(header: Strings.value(of: header), message: Strings.value(of: message), buttons: buttons, flags: flags, timeout: timeout,
             response: response)
        return response
    }

    /// No more callouts: the source is removed from its loops and released.
    static func invalidate(_ storage: UserNotificationStorage) {
        let source = storage.lock.locked { () -> (object: id, storage: CustomSourceStorage)? in
            defer {
                storage.source = nil
                storage.object = nil
                storage.delivered = true
            }
            return storage.source
        }
        guard let source else { return }
        source.storage.remove(from: nil)
        ObjC.release(source.object)
    }
}

@ObjCClass("__NSCFUserNotification")
final class NSCFUserNotification: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        UserNotifications.notificationClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UserNotifications.storage(objcObject).map(UserNotifications.invalidate)
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: UserNotifications.notificationClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { UserNotifications.typeID }
}

@c(_CFUserNotificationGetTypeID) public func CFUserNotificationGetTypeID() -> UInt { UserNotifications.typeID }

/// The notification (+1), told on stderr and answered at once; *error is 0.
@c(_CFUserNotificationCreate)
public func CFUserNotificationCreate(_ allocator: UnsafeRawPointer?, _ timeout: Double.ObjCType, _ flags: UInt,
                                     _ error: UnsafeMutablePointer<Int32>?, _ dictionary: id?) -> id? {
    guard let object = Storage.allocate(UnsafeMutableRawPointer(UserNotifications.notificationClass)) else {
        error?.pointee = -1
        return nil
    }
    let storage = UserNotificationStorage(dictionary: UserNotifications.copy(dictionary), flags: flags,
                                          timeout: Double(objCArgument: timeout))
    storage.object = object
    Storage.set(object, storage)
    storage.answer()
    error?.pointee = 0
    return object
}

/// The response, at once: it was answered when made.
@c(_CFUserNotificationReceiveResponse)
public func CFUserNotificationReceiveResponse(_ notification: id?, _ timeout: Double.ObjCType,
                                              _ responseFlags: UnsafeMutablePointer<UInt>?) -> Int32 {
    guard let storage = UserNotifications.storage(notification) else { return -1 }
    responseFlags?.pointee = storage.lock.locked { storage.responseFlags }
    return 0
}

/// The response's value (+0) for a key: a string, or the string at `index`
/// of an array of them (kCFUserNotificationTextFieldValuesKey's).
@c(_CFUserNotificationGetResponseValue)
public func CFUserNotificationGetResponseValue(_ notification: id?, _ key: id?, _ index: Int) -> id? {
    guard let storage = UserNotifications.storage(notification), let key else { return nil }
    guard let response = storage.lock.locked({ storage.responseDictionary }),
          let value = Dictionaries.value(response, for: key) else { return nil }
    if Strings.value(of: value) != nil { return index == 0 ? value : nil }
    guard ObjC.isKind(value, of: Arrays.arrayClass) else { return nil }
    let elements = Arrays.elements(value)
    guard elements.indices.contains(index), Strings.value(of: elements[index]) != nil else { return nil }
    return elements[index]
}

/// The values the user gave (+0), or NULL when there were none.
@c(_CFUserNotificationGetResponseDictionary)
public func CFUserNotificationGetResponseDictionary(_ notification: id?) -> id? {
    guard let storage = UserNotifications.storage(notification) else { return nil }
    return storage.lock.locked { storage.responseDictionary }
}

/// Takes the new contents, told on stderr. It was already answered, as
/// Darwin's would be by then, so the response is the same.
@c(_CFUserNotificationUpdate)
public func CFUserNotificationUpdate(_ notification: id?, _ timeout: Double.ObjCType, _ flags: UInt, _ dictionary: id?) -> Int32 {
    guard let storage = UserNotifications.storage(notification) else { return -1 }
    let copy = UserNotifications.copy(dictionary)
    let old = storage.lock.locked { () -> id? in
        defer { (storage.dictionary, storage.flags, storage.timeout) = (copy, flags, Double(objCArgument: timeout)) }
        return storage.dictionary
    }
    ObjC.release(old)
    let response = storage.lock.locked { storage.responseFlags }
    UserNotifications.tell(dictionary: copy, flags: flags, timeout: Double(objCArgument: timeout), response: response)
    return 0
}

/// It was already answered, so there's nothing to cancel.
@c(_CFUserNotificationCancel)
public func CFUserNotificationCancel(_ notification: id?) -> Int32 {
    UserNotifications.storage(notification) == nil ? -1 : 0
}

/// The notification's source (+1), which calls `callout` with the response
/// once, on a loop it's added to. Made once; later calls give the same one.
@c(_CFUserNotificationCreateRunLoopSource)
public func CFUserNotificationCreateRunLoopSource(_ allocator: UnsafeRawPointer?, _ notification: id?,
                                                  _ callout: CFUserNotificationCallout?, _ order: Int) -> id? {
    guard let storage = UserNotifications.storage(notification) else { return nil }
    if let existing = storage.lock.locked({ storage.source?.object }) { return ObjC.retain(existing) }
    guard let made = FiringSources.make(for: storage) else { return nil }
    let source = storage.lock.locked { () -> id in
        if let current = storage.source { return current.object }
        storage.source = made
        storage.callout = callout
        return made.0
    }
    if source != made.0 {
        ObjC.release(made.0)
    } else {
        // Answered already: the callout is due as soon as it's on a loop.
        made.1.signal()
    }
    return ObjC.retain(source)
}

/// A notice with one button, told on stderr; it isn't waited for.
@c(_CFUserNotificationDisplayNotice)
public func CFUserNotificationDisplayNotice(_ timeout: Double.ObjCType, _ flags: UInt, _ iconURL: id?, _ soundURL: id?,
                                            _ localizationURL: id?, _ alertHeader: id?, _ alertMessage: id?,
                                            _ defaultButtonTitle: id?) -> Int32 {
    _ = UserNotifications.display(timeout: Double(objCArgument: timeout), flags: flags, header: alertHeader, message: alertMessage,
                                  defaultButton: defaultButtonTitle, alternateButton: nil, otherButton: nil)
    return 0
}

/// An alert of up to three buttons, told on stderr, and *responseFlags the
/// default button's response (or a timed-out one's, with no default button).
@c(_CFUserNotificationDisplayAlert)
public func CFUserNotificationDisplayAlert(_ timeout: Double.ObjCType, _ flags: UInt, _ iconURL: id?, _ soundURL: id?,
                                           _ localizationURL: id?, _ alertHeader: id?, _ alertMessage: id?,
                                           _ defaultButtonTitle: id?, _ alternateButtonTitle: id?, _ otherButtonTitle: id?,
                                           _ responseFlags: UnsafeMutablePointer<UInt>?) -> Int32 {
    let response = UserNotifications.display(timeout: Double(objCArgument: timeout), flags: flags, header: alertHeader,
                                             message: alertMessage, defaultButton: defaultButtonTitle,
                                             alternateButton: alternateButtonTitle, otherButton: otherButtonTitle)
    responseFlags?.pointee = response
    return 0
}
