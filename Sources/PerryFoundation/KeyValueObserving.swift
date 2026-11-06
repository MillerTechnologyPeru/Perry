import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// Key-value observing as Darwin does it: an observed object's class
// becomes a subclass, NSKVONotifying_<Class>, whose -class answers the
// original and whose setters for observed keys send -willChangeValueForKey:
// and -didChangeValueForKey: around the original setter. The object gets
// its class back when its last observer is removed. Observers are notified
// newest first; a key's dependents (+keyPathsForValuesAffecting<Key>)
// change with it; a key path through other objects observes each of them
// in turn, following the path when an object along it is replaced.

/// One observer's registration for a key path of an object. A link is the
/// registration a key path makes on the next object along it: it reports
/// to the registration it serves instead of to an observer.
final class Observance {
    let observer: id?
    let keyPath: String
    let options: UInt
    let context: UnsafeMutableRawPointer?
    /// The keys of the observed object whose changes change the key path.
    var triggers: Set<String> = []
    /// For a link: the registration it serves and the object that one observes.
    var owner: (object: id, observance: Observance)?
    /// The link on the next object along the key path.
    var link: (target: id, observance: Observance)?

    var first: String { keyPath.split(separator: ".", maxSplits: 1).first.map(String.init) ?? keyPath }
    var rest: String? {
        let parts = keyPath.split(separator: ".", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : nil
    }

    init(observer: id?, keyPath: String, options: UInt, context: UnsafeMutableRawPointer?) {
        self.observer = observer
        self.keyPath = keyPath
        self.options = options
        self.context = context
    }
}

enum KeyValueObserving {
    static let optionNew: UInt = 1, optionOld: UInt = 2, optionInitial: UInt = 4, optionPrior: UInt = 8
    static let setting: UInt = 1, insertion: UInt = 2, removal: UInt = 3, replacement: UInt = 4

    /// A class made for observed instances of another.
    final class Subclass {
        let original: Class
        /// Setter selectors replaced, and their keys.
        var setters: [UnsafeRawPointer: String] = [:]

        init(original: Class) {
            self.original = original
        }
    }

    /// A change between -willChange… and -didChange…, with each affected
    /// registration's old value (retained).
    struct Pending {
        let object: id
        let key: String
        let thread: pthread_t
        let kind: UInt
        let indexes: id?
        var entries: [(observance: Observance, old: id?)]
    }

    /// Recursive: removing a registration can remove the links it made.
    nonisolated(unsafe) static let lock: UnsafeMutablePointer<pthread_mutex_t> = {
        let lock = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(lock, &attributes)
        return lock
    }()
    nonisolated(unsafe) static var subclasses: [Class: Subclass] = [:]
    nonisolated(unsafe) static var byOriginal: [Class: Class] = [:]
    nonisolated(unsafe) static var observances: [id: [Observance]] = [:]
    nonisolated(unsafe) static var pending: [Pending] = []

    static func locked<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(lock)
        defer { pthread_mutex_unlock(lock) }
        return body()
    }

    /// The class an object had before it was observed.
    static func original(_ object: id) -> Class {
        let cls = ObjC.objectGetClass(object)!
        return locked { subclasses[cls]?.original } ?? cls
    }

    // MARK: Subclasses

    static let classIMP: @convention(c) (id, SEL) -> UnsafeMutableRawPointer = { object, _ in
        UnsafeMutableRawPointer(original(object))
    }

    static let isKVOIMP: @convention(c) (id, SEL) -> Bool = { _, _ in true }

    /// Forgets the object's registrations, then deallocates it as its class does.
    static let deallocIMP: @convention(c) (id, SEL) -> Void = { object, selector in
        let cls = original(object)
        for observance in locked({ observances.removeValue(forKey: object) }) ?? [] { unhook(observance) }
        let imp = ObjC.methodImplementation(cls, selector)!
        unsafeBitCast(imp, to: (@convention(c) (id, SEL) -> Void).self)(object, selector)
    }

    static func subclass(of original: Class) -> Class {
        locked {
            if let existing = byOriginal[original] { return existing }
            let name = "NSKVONotifying_" + ObjC.className(UnsafeMutableRawPointer(original))
            let cls = name.withCString { ObjC.allocateClassPair(original, $0, 0) }!
            _ = ObjC.addMethod(cls, ObjC.selector("class"), unsafeBitCast(classIMP, to: UnsafeRawPointer.self), "#16@0:8")
            _ = ObjC.addMethod(cls, ObjC.selector("dealloc"), unsafeBitCast(deallocIMP, to: UnsafeRawPointer.self), "v16@0:8")
            _ = ObjC.addMethod(cls, ObjC.selector("_isKVOA"), unsafeBitCast(isKVOIMP, to: UnsafeRawPointer.self), "B16@0:8")
            ObjC.registerClassPair(cls)
            subclasses[cls] = Subclass(original: original)
            byOriginal[original] = cls
            return cls
        }
    }

    /// Replaces the setter for `key` in the object's subclass, when the class
    /// has one and notifies automatically for the key.
    static func notify(_ subclass: Class, original: Class, key: String) {
        let selector = ObjC.selector("set" + key.prefix(1).uppercased() + key.dropFirst() + ":")
        guard locked({ subclasses[subclass]?.setters[UnsafeRawPointer(selector)] }) == nil,
              let method = ObjC.instanceMethod(original, selector), let types = ObjC.methodTypes(method),
              ObjC.sendBool(UnsafeMutableRawPointer(original), ObjC.selector("automaticallyNotifiesObserversForKey:"),
                            Strings.autoreleased(key)) else { return }
        _ = ObjC.addMethod(subclass, selector, unsafeBitCast(perry_kvo_setter as @convention(c) () -> Void, to: UnsafeRawPointer.self), types)
        locked { subclasses[subclass]?.setters[UnsafeRawPointer(selector)] = key }
    }

    /// The keys whose changes change `key`: itself and, in turn, those its
    /// +keyPathsForValuesAffectingValueForKey: name.
    static func triggers(_ cls: Class, _ key: String, into keys: inout Set<String>) {
        guard keys.insert(key).inserted else { return }
        let paths = ObjC.send(UnsafeMutableRawPointer(cls), ObjC.selector("keyPathsForValuesAffectingValueForKey:"),
                              Strings.autoreleased(key))
        for path in paths.map(Sets.elements) ?? [] {
            guard let path = Strings.value(of: path), let first = path.split(separator: ".").first else { continue }
            triggers(cls, String(first), into: &keys)
        }
    }

    // MARK: Registration

    static func add(_ observance: Observance, to object: id) {
        let cls = original(object)
        var keys: Set<String> = []
        triggers(cls, observance.first, into: &keys)
        observance.triggers = keys
        let subclass = subclass(of: cls)
        for key in keys { notify(subclass, original: cls, key: key) }
        locked { observances[object, default: []].append(observance) }
        if ObjC.objectGetClass(object) != subclass { _ = ObjC.objectSetClass(object, subclass) }
        hook(observance, object)
    }

    static func remove(_ observance: Observance, from object: id) {
        unhook(observance)
        let empty: Bool = locked {
            observances[object]?.removeAll { $0 === observance }
            guard observances[object]?.isEmpty ?? true else { return false }
            observances[object] = nil
            return true
        }
        if empty { _ = ObjC.objectSetClass(object, original(object)) }
    }

    /// Observes the rest of a key path on the object the first key leads to.
    static func hook(_ observance: Observance, _ object: id) {
        guard let rest = observance.rest,
              let target = ObjC.send(object, ObjC.selector("valueForKey:"), Strings.autoreleased(observance.first)) else { return }
        let link = Observance(observer: nil, keyPath: rest, options: observance.options & ~optionInitial, context: nil)
        link.owner = (object, observance)
        observance.link = (target, link)
        add(link, to: target)
    }

    static func unhook(_ observance: Observance) {
        guard let (target, link) = observance.link else { return }
        observance.link = nil
        remove(link, from: target)
    }

    // MARK: Notifications

    static func value(_ object: id, _ keyPath: String) -> id {
        ObjC.send(object, ObjC.selector("valueForKeyPath:"), Strings.autoreleased(keyPath)) ?? Nulls.null
    }

    static func elements(_ object: id, _ key: String, _ indexes: id?) -> id? {
        ObjC.send(ObjC.send(object, ObjC.selector("valueForKey:"), Strings.autoreleased(key)),
                  ObjC.selector("objectsAtIndexes:"), indexes)
    }

    /// Sends the change to the observer, or up through the registration a link serves.
    static func deliver(_ observance: Observance, _ object: id, _ change: id?) {
        if let (owner, served) = observance.owner { return deliver(served, owner, change) }
        guard let observer = observance.observer else { return }
        unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id, SEL, id?, id, id?, UnsafeMutableRawPointer?) -> Void).self)(
            observer, ObjC.selector("observeValueForKeyPath:ofObject:change:context:"),
            Strings.autoreleased(observance.keyPath), object, change, observance.context)
    }

    static func change(kind: UInt, new: id?, old: id?, indexes: id?, prior: Bool) -> id? {
        var entries: [(key: id, value: id)] = [(Strings.autoreleased("kind"), Numbers.make(nil, .unsigned(UInt64(kind)))!)]
        if let new { entries.append((Strings.autoreleased("new"), new)) }
        if let old { entries.append((Strings.autoreleased("old"), old)) }
        if let indexes { entries.append((Strings.autoreleased("indexes"), indexes)) }
        if prior { entries.append((Strings.autoreleased("notificationIsPrior"), perry_foundation_boolean(1))) }
        return Dictionaries.autoreleased(entries)
    }

    static func willChange(_ object: id, _ key: String, kind: UInt, indexes: id?) {
        let affected = locked { observances[object] ?? [] }.reversed().filter { $0.triggers.contains(key) }
        var entries: [(observance: Observance, old: id?)] = []
        for observance in affected {
            var old: id?
            if observance.options & optionOld != 0 {
                if kind == setting || observance.keyPath != key { old = value(object, observance.keyPath) }
                else if kind != insertion { old = elements(object, key, indexes) }
            }
            if observance.options & optionPrior != 0 {
                deliver(observance, object, change(kind: kind, new: nil, old: old, indexes: indexes, prior: true))
            }
            if observance.first == key { unhook(observance) }
            entries.append((observance, ObjC.retain(old)))
        }
        let pendingChange = Pending(object: object, key: key, thread: pthread_self(), kind: kind,
                                    indexes: ObjC.retain(indexes), entries: entries)
        locked { pending.append(pendingChange) }
    }

    static func didChange(_ object: id, _ key: String) {
        let thread = pthread_self()
        guard let change = locked({ () -> Pending? in
            guard let index = pending.lastIndex(where: { $0.object == object && $0.key == key && pthread_equal($0.thread, thread) != 0 })
            else { return nil }
            return pending.remove(at: index)
        }) else { return }
        defer {
            ObjC.release(change.indexes)
            for entry in change.entries { ObjC.release(entry.old) }
        }
        for (observance, old) in change.entries {
            // Removed since the will-change.
            guard locked({ observances[object]?.contains { $0 === observance } ?? false }) else { continue }
            if observance.first == key { hook(observance, object) }
            var new: id?
            if observance.options & optionNew != 0 {
                if change.kind == setting || observance.keyPath != key { new = value(object, observance.keyPath) }
                else if change.kind != removal { new = elements(object, key, change.indexes) }
            }
            let indexes = observance.keyPath == key ? change.indexes : nil
            deliver(observance, object, Self.change(kind: change.kind, new: new, old: old, indexes: indexes, prior: false))
        }
    }
}

/// The setter perry_kvo_setter replaces: it sends -willChangeValueForKey:
/// and returns the class's own setter.
@c
public func perry_foundation_kvo_will(_ object: id, _ selector: SEL) -> UnsafeRawPointer? {
    let cls = ObjC.objectGetClass(object)!
    let (original, key) = KeyValueObserving.locked {
        (KeyValueObserving.subclasses[cls]?.original ?? cls, KeyValueObserving.subclasses[cls]?.setters[UnsafeRawPointer(selector)])
    }
    if let key { _ = ObjC.send(object, ObjC.selector("willChangeValueForKey:"), Strings.autoreleased(key)) }
    return ObjC.methodImplementation(original, selector)
}

@c
public func perry_foundation_kvo_did(_ object: id, _ selector: SEL) {
    let cls = ObjC.objectGetClass(object)!
    guard let key = KeyValueObserving.locked({ KeyValueObserving.subclasses[cls]?.setters[UnsafeRawPointer(selector)] }) else { return }
    _ = ObjC.send(object, ObjC.selector("didChangeValueForKey:"), Strings.autoreleased(key))
}

@ObjCCategory("KeyValueObserving")
extension NSObject {
    /// The observation info Foundation keeps for an object: here what was
    /// set, by object, else nil; Perry keeps its observers elsewhere.
    nonisolated(unsafe) static var observationInfos: [UnsafeMutableRawPointer: UnsafeMutableRawPointer] = [:]

    @ObjCMethod("observationInfo")
    func observationInfo() -> UnsafeMutableRawPointer? { KeyValueObserving.locked { NSObject.observationInfos[objcObject] } }

    @ObjCMethod("setObservationInfo:")
    func setObservationInfo(_ info: UnsafeMutableRawPointer?) {
        let object = objcObject
        KeyValueObserving.locked { NSObject.observationInfos[object] = info }
    }

    @ObjCMethod("addObserver:forKeyPath:options:context:")
    func addObserver(_ observer: ObjCObject?, forKeyPath keyPath: String, options: UInt, context: UnsafeMutableRawPointer?) {
        guard let observer else { return }
        let observance = Observance(observer: observer.objcObject, keyPath: keyPath, options: options, context: context)
        KeyValueObserving.add(observance, to: objcObject)
        if options & KeyValueObserving.optionInitial != 0 {
            let new = options & KeyValueObserving.optionNew != 0 ? KeyValueObserving.value(objcObject, keyPath) : nil
            KeyValueObserving.deliver(observance, objcObject,
                                      KeyValueObserving.change(kind: KeyValueObserving.setting, new: new, old: nil, indexes: nil, prior: false))
        }
    }

    /// The newest matching registration.
    private func removeObservance(_ observer: ObjCObject?, _ keyPath: String, matching context: UnsafeMutableRawPointer??) {
        let object = objcObject
        let found = KeyValueObserving.locked {
            KeyValueObserving.observances[object]?.last { observance in
                observance.observer == observer?.objcObject && observance.keyPath == keyPath
                    && (context.map { observance.context == $0 } ?? true)
            }
        }
        guard let found else {
            foundationFatal("Cannot remove an observer <\(ObjC.className(observer?.objcObject)) \(observer?.objcObject.debugDescription ?? "nil")> "
                            + "for the key path \"\(keyPath)\" from <\(ObjC.className(UnsafeMutableRawPointer(KeyValueObserving.original(object)))) "
                            + "\(object)> because it is not registered as an observer.")
        }
        KeyValueObserving.remove(found, from: object)
    }

    @ObjCMethod("removeObserver:forKeyPath:")
    func removeObserver(_ observer: ObjCObject?, forKeyPath keyPath: String) { removeObservance(observer, keyPath, matching: nil) }

    @ObjCMethod("removeObserver:forKeyPath:context:")
    func removeObserver(_ observer: ObjCObject?, forKeyPath keyPath: String, context: UnsafeMutableRawPointer?) {
        removeObservance(observer, keyPath, matching: .some(context))
    }

    @ObjCMethod("willChangeValueForKey:")
    func willChangeValue(forKey key: String) {
        KeyValueObserving.willChange(objcObject, key, kind: KeyValueObserving.setting, indexes: nil)
    }

    @ObjCMethod("didChangeValueForKey:")
    func didChangeValue(forKey key: String) {
        KeyValueObserving.didChange(objcObject, key)
        Operations.didChangeValue(objcObject, forKey: key)
    }

    @ObjCMethod("willChange:valuesAtIndexes:forKey:")
    func willChange(_ kind: UInt, valuesAt indexes: ObjCObject?, forKey key: String) {
        KeyValueObserving.willChange(objcObject, key, kind: kind, indexes: indexes?.objcObject)
    }

    @ObjCMethod("didChange:valuesAtIndexes:forKey:")
    func didChange(_ kind: UInt, valuesAt indexes: ObjCObject?, forKey key: String) { KeyValueObserving.didChange(objcObject, key) }

    @ObjCMethod("observeValueForKeyPath:ofObject:change:context:")
    func observeValue(forKeyPath keyPath: String, of object: ObjCObject?, change: ObjCObject?, context: UnsafeMutableRawPointer?) {
        foundationFatal("<\(ObjC.className(objcObject)): \(objcObject)>: An -observeValueForKeyPath:ofObject:change:context: "
                        + "message was received but not handled.\nKey path: \(keyPath)")
    }

    /// +automaticallyNotifiesObserversOf<Key> if the class has it; otherwise YES.
    @ObjCClassMethod("automaticallyNotifiesObserversForKey:")
    static func automaticallyNotifiesObservers(_ cls: ObjCClass, forKey key: String) -> Bool {
        let selector = ObjC.selector("automaticallyNotifiesObserversOf" + key.prefix(1).uppercased() + key.dropFirst())
        guard ObjC.sendBool(cls.pointer, ObjC.selector("respondsToSelector:"), UnsafeMutableRawPointer(mutating: selector)) else { return true }
        return ObjC.sendBool(cls.pointer, selector, nil)
    }

    /// +keyPathsForValuesAffecting<Key> if the class has it; otherwise none.
    @ObjCClassMethod("keyPathsForValuesAffectingValueForKey:")
    static func keyPathsForValuesAffectingValue(_ cls: ObjCClass, forKey key: String) -> UnsafeMutableRawPointer? {
        let selector = ObjC.selector("keyPathsForValuesAffecting" + key.prefix(1).uppercased() + key.dropFirst())
        guard ObjC.sendBool(cls.pointer, ObjC.selector("respondsToSelector:"), UnsafeMutableRawPointer(mutating: selector)) else {
            return Sets.autoreleased([])
        }
        return ObjC.send(cls.pointer, selector)
    }
}

/// The change dictionary's keys.
@ObjCConstants
enum KeyValueChangeKeys {
    static let NSKeyValueChangeKindKey = "kind"
    static let NSKeyValueChangeNewKey = "new"
    static let NSKeyValueChangeOldKey = "old"
    static let NSKeyValueChangeIndexesKey = "indexes"
    static let NSKeyValueChangeNotificationIsPriorKey = "notificationIsPrior"
}
