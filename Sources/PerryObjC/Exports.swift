import CPerryObjC
import Glibc
import PerryObjCRuntime

// libobjc's C API under its Mach-O names. Each function only adapts types
// and calls the engine in PerryObjCRuntime. objc_msgSend and the other
// entry points that forward arguments are in CPerryObjC/msgsend.S.

public typealias id = UnsafeMutableRawPointer
public typealias Class = UnsafeMutablePointer<perry_objc_class>
public typealias Method = UnsafeMutablePointer<perry_method>
public typealias ProtocolPointer = UnsafeMutablePointer<perry_protocol>

@inline(__always) private func asObject(_ cls: Class?) -> id? { cls.map { id($0) } }
@inline(__always) private func asClass(_ object: id?) -> Class? { object?.assumingMemoryBound(to: perry_objc_class.self) }

private enum Selector {
    nonisolated(unsafe) static let alloc = Selectors.register("alloc")
    nonisolated(unsafe) static let allocWithZone = Selectors.register("allocWithZone:")
    nonisolated(unsafe) static let `init` = Selectors.register("init")
    nonisolated(unsafe) static let new = Selectors.register("new")
    nonisolated(unsafe) static let `class` = Selectors.register("class")
    nonisolated(unsafe) static let isKindOfClass = Selectors.register("isKindOfClass:")
    nonisolated(unsafe) static let respondsToSelector = Selectors.register("respondsToSelector:")
    nonisolated(unsafe) static let copyWithZone = Selectors.register("copyWithZone:")
    nonisolated(unsafe) static let mutableCopyWithZone = Selectors.register("mutableCopyWithZone:")
}

// MARK: - ARC

@c(_objc_retain)
public func objc_retain(_ object: id?) -> id? {
    object.map(Objects.retain)
}

@c(_objc_release)
public func objc_release(_ object: id?) {
    if let object { Objects.release(object) }
}

@c(_objc_autorelease)
public func objc_autorelease(_ object: id?) -> id? {
    object.map(Objects.autorelease)
}

@c(_objc_retainAutorelease)
public func objc_retainAutorelease(_ object: id?) -> id? {
    object.map { Objects.autorelease(Objects.retain($0)) }
}

@c(_objc_retainAutoreleaseReturnValue)
public func objc_retainAutoreleaseReturnValue(_ object: id?) -> id? {
    object.map { Objects.autorelease(Objects.retain($0)) }
}

// The return-value handshake is not optimized: the callee autoreleases and
// the caller retains, which is what the unoptimized protocol does.
@c(_objc_autoreleaseReturnValue)
public func objc_autoreleaseReturnValue(_ object: id?) -> id? {
    object.map(Objects.autorelease)
}

@c(_objc_retainAutoreleasedReturnValue)
public func objc_retainAutoreleasedReturnValue(_ object: id?) -> id? {
    object.map(Objects.retain)
}

@c(_objc_claimAutoreleasedReturnValue)
public func objc_claimAutoreleasedReturnValue(_ object: id?) -> id? {
    object.map(Objects.retain)
}

@c(_objc_unsafeClaimAutoreleasedReturnValue)
public func objc_unsafeClaimAutoreleasedReturnValue(_ object: id?) -> id? {
    object
}

@c(_objc_storeStrong)
public func objc_storeStrong(_ location: UnsafeMutablePointer<id?>?, _ object: id?) {
    guard let location else { return }
    let old = location.pointee
    if old == object { return }
    location.pointee = object.map(Objects.retain)
    if let old { Objects.release(old) }
}

@c(_objc_retainBlock)
public func objc_retainBlock(_ block: id?) -> id? {
    BlockClasses.copy(block)
}

@c(_objc_autoreleasePoolPush)
public func objc_autoreleasePoolPush() -> UnsafeMutableRawPointer? {
    AutoreleasePool.push()
}

@c(_objc_autoreleasePoolPop)
public func objc_autoreleasePoolPop(_ token: UnsafeMutableRawPointer?) {
    AutoreleasePool.pop(token)
}

@c(_objc_retainedObject)
public func objc_retainedObject(_ pointer: id?) -> id? { pointer }

@c(_objc_unretainedObject)
public func objc_unretainedObject(_ pointer: id?) -> id? { pointer }

@c(_objc_unretainedPointer)
public func objc_unretainedPointer(_ object: id?) -> id? { object }

// MARK: - Weak references

@c(_objc_initWeak)
public func objc_initWeak(_ location: UnsafeMutablePointer<id?>?, _ object: id?) -> id? {
    guard let location else { return nil }
    location.pointee = nil
    return WeakReferences.store(location, object)
}

@c(_objc_storeWeak)
public func objc_storeWeak(_ location: UnsafeMutablePointer<id?>?, _ object: id?) -> id? {
    guard let location else { return nil }
    return WeakReferences.store(location, object)
}

@c(_objc_loadWeakRetained)
public func objc_loadWeakRetained(_ location: UnsafeMutablePointer<id?>?) -> id? {
    location.flatMap(WeakReferences.loadRetained)
}

@c(_objc_loadWeak)
public func objc_loadWeak(_ location: UnsafeMutablePointer<id?>?) -> id? {
    location.flatMap(WeakReferences.loadRetained).map(Objects.autorelease)
}

@c(_objc_destroyWeak)
public func objc_destroyWeak(_ location: UnsafeMutablePointer<id?>?) {
    if let location { WeakReferences.store(location, nil) }
}

@c(_objc_copyWeak)
public func objc_copyWeak(_ destination: UnsafeMutablePointer<id?>?, _ source: UnsafeMutablePointer<id?>?) {
    guard let destination, let source else { return }
    let object = WeakReferences.loadRetained(source)
    destination.pointee = nil
    WeakReferences.store(destination, object)
    if let object { Objects.release(object) }
}

@c(_objc_moveWeak)
public func objc_moveWeak(_ destination: UnsafeMutablePointer<id?>?, _ source: UnsafeMutablePointer<id?>?) {
    objc_copyWeak(destination, source)
    objc_destroyWeak(source)
}

// MARK: - Allocation

@c(_objc_alloc)
public func objc_alloc(_ cls: Class?) -> id? {
    Messages.send(asObject(cls), Selector.alloc)
}

@c(_objc_allocWithZone)
public func objc_allocWithZone(_ cls: Class?) -> id? {
    Messages.send(asObject(cls), Selector.allocWithZone, nil)
}

@c(_objc_alloc_init)
public func objc_alloc_init(_ cls: Class?) -> id? {
    Messages.send(Messages.send(asObject(cls), Selector.alloc), Selector.`init`)
}

@c(_objc_opt_new)
public func objc_opt_new(_ cls: Class?) -> id? {
    Messages.send(asObject(cls), Selector.new)
}

@c(_objc_opt_class)
public func objc_opt_class(_ object: id?) -> id? {
    Messages.send(object, Selector.class)
}

@c(_objc_opt_self)
public func objc_opt_self(_ object: id?) -> id? { object }

@c(_objc_opt_isKindOfClass)
public func objc_opt_isKindOfClass(_ object: id?, _ cls: Class?) -> Bool {
    guard let object else { return false }
    return Messages.sendBool(object, Selector.isKindOfClass, UnsafeRawPointer(cls))
}

@c(_objc_opt_respondsToSelector)
public func objc_opt_respondsToSelector(_ object: id?, _ sel: UnsafePointer<CChar>?) -> Bool {
    guard let object else { return false }
    return Messages.sendBool(object, Selector.respondsToSelector, UnsafeRawPointer(sel))
}

@c(_class_createInstance)
public func class_createInstance(_ cls: Class?, _ extraBytes: Int) -> id? {
    cls.flatMap { Objects.createInstance($0, extraBytes: extraBytes) }
}

@c(_objc_constructInstance)
public func objc_constructInstance(_ cls: Class?, _ bytes: id?) -> id? {
    guard let cls, let bytes else { return nil }
    bytes.storeBytes(of: cls, as: Class.self)
    return bytes
}

@c(_objc_destructInstance)
public func objc_destructInstance(_ object: id?) -> id? {
    if let object { Objects.destructInstance(object) }
    return object
}

@c(_object_dispose)
public func object_dispose(_ object: id?) -> id? {
    if let object { Objects.dispose(object) }
    return nil
}

// MARK: - Properties

private let propertyLocks: [RecursiveLock] = (0..<64).map { _ in RecursiveLock() }

/// Atomic properties lock their slot's stripe, as Apple's runtime does.
private func propertyLock(_ address: UnsafeRawPointer) -> RecursiveLock {
    propertyLocks[Int((UInt(bitPattern: address) >> 4) & 63)]
}

@c(_objc_getProperty)
public func objc_getProperty(_ object: id?, _ cmd: UnsafePointer<CChar>?, _ offset: Int, _ atomic: Bool) -> id? {
    guard let object else { return nil }
    let slot = (object + offset).assumingMemoryBound(to: id?.self)
    if !atomic { return slot.pointee }
    let value = propertyLock(slot).withLock { slot.pointee.map(Objects.retain) }
    return value.map(Objects.autorelease)
}

private func setProperty(_ object: id?, _ offset: Int, _ value: id?, atomic: Bool, copy: Int8) {
    guard let object else { return }
    let slot = (object + offset).assumingMemoryBound(to: id?.self)
    let stored: id?
    switch copy {
    case 1: stored = Messages.send(value, Selector.copyWithZone, nil)
    case 2: stored = Messages.send(value, Selector.mutableCopyWithZone, nil)
    default:
        if slot.pointee == value { return }
        stored = value.map(Objects.retain)
    }
    let old: id?
    if atomic {
        old = propertyLock(slot).withLock {
            let old = slot.pointee
            slot.pointee = stored
            return old
        }
    } else {
        old = slot.pointee
        slot.pointee = stored
    }
    if let old { Objects.release(old) }
}

@c(_objc_setProperty)
public func objc_setProperty(_ object: id?, _ cmd: UnsafePointer<CChar>?, _ offset: Int, _ value: id?,
                             _ atomic: Bool, _ shouldCopy: Int8) {
    setProperty(object, offset, value, atomic: atomic, copy: shouldCopy)
}

@c(_objc_setProperty_atomic)
public func objc_setProperty_atomic(_ object: id?, _ cmd: UnsafePointer<CChar>?, _ value: id?, _ offset: Int) {
    setProperty(object, offset, value, atomic: true, copy: 0)
}

@c(_objc_setProperty_nonatomic)
public func objc_setProperty_nonatomic(_ object: id?, _ cmd: UnsafePointer<CChar>?, _ value: id?, _ offset: Int) {
    setProperty(object, offset, value, atomic: false, copy: 0)
}

@c(_objc_setProperty_atomic_copy)
public func objc_setProperty_atomic_copy(_ object: id?, _ cmd: UnsafePointer<CChar>?, _ value: id?, _ offset: Int) {
    setProperty(object, offset, value, atomic: true, copy: 1)
}

@c(_objc_setProperty_nonatomic_copy)
public func objc_setProperty_nonatomic_copy(_ object: id?, _ cmd: UnsafePointer<CChar>?, _ value: id?, _ offset: Int) {
    setProperty(object, offset, value, atomic: false, copy: 1)
}

@c(_objc_copyStruct)
public func objc_copyStruct(_ destination: UnsafeMutableRawPointer?, _ source: UnsafeRawPointer?, _ size: Int,
                            _ atomic: Bool, _ hasStrong: Bool) {
    guard let destination, let source else { return }
    if atomic {
        propertyLock(source).withLock { _ = memmove(destination, source, size) }
    } else {
        memmove(destination, source, size)
    }
}

// MARK: - Classes

@c(_objc_getClass)
public func objc_getClass(_ name: UnsafePointer<CChar>?) -> Class? {
    name.flatMap(Runtime.lookUpClass)
}

@c(_objc_lookUpClass)
public func objc_lookUpClass(_ name: UnsafePointer<CChar>?) -> Class? {
    name.flatMap(Runtime.lookUpClass)
}

@c(_objc_getRequiredClass)
public func objc_getRequiredClass(_ name: UnsafePointer<CChar>?) -> Class? {
    guard let cls = name.flatMap(Runtime.lookUpClass) else {
        objcFatal("link error: class '\(name.map { String(cString: $0) } ?? "")' not found")
    }
    return cls
}

@c(_objc_getMetaClass)
public func objc_getMetaClass(_ name: UnsafePointer<CChar>?) -> Class? {
    name.flatMap(Runtime.lookUpClass)?.pointee.isa
}

@c(_object_getClass)
public func object_getClass(_ object: id?) -> Class? {
    object.map(classOf)
}

@c(_object_setClass)
public func object_setClass(_ object: id?, _ cls: Class?) -> Class? {
    guard let object, let cls else { return nil }
    let old = classOf(object)
    object.storeBytes(of: cls, as: Class.self)
    return old
}

nonisolated(unsafe) private let nilClassName = permanentName("nil")

private func permanentName(_ string: String) -> UnsafePointer<CChar> {
    UnsafePointer(strdup(string)!)
}

@c(_object_getClassName)
public func object_getClassName(_ object: id?) -> UnsafePointer<CChar>? {
    guard let object, let info = Runtime.info(classOf(object)) else { return nilClassName }
    return info.name
}

@c(_class_getName)
public func class_getName(_ cls: Class?) -> UnsafePointer<CChar>? {
    guard let cls, let info = Runtime.info(cls) else { return nilClassName }
    return info.name
}

@c(_class_getSuperclass)
public func class_getSuperclass(_ cls: Class?) -> Class? {
    cls?.pointee.superclass
}

@c(_class_isMetaClass)
public func class_isMetaClass(_ cls: Class?) -> Bool {
    cls.flatMap(Runtime.info)?.isMeta ?? false
}

@c(_class_getInstanceSize)
public func class_getInstanceSize(_ cls: Class?) -> Int {
    cls.flatMap(Runtime.info)?.instanceSize ?? 0
}

@c(_object_getIndexedIvars)
public func object_getIndexedIvars(_ object: id?) -> UnsafeMutableRawPointer? {
    guard let object, let info = Runtime.info(classOf(object)) else { return nil }
    return object + info.instanceSize
}

@c(_class_respondsToSelector)
public func class_respondsToSelector(_ cls: Class?, _ sel: UnsafePointer<CChar>?) -> Bool {
    guard let cls, let sel, let info = Runtime.info(cls) else { return false }
    return Runtime.responds(info, sel)
}

@c(_class_getMethodImplementation)
public func class_getMethodImplementation(_ cls: Class?, _ sel: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let cls, let sel else { return nil }
    return Runtime.lookUpIMP(receiver: nil, selector: sel, cls: cls)
}

@c(_class_getInstanceMethod)
public func class_getInstanceMethod(_ cls: Class?, _ sel: UnsafePointer<CChar>?) -> Method? {
    guard let cls, let sel, let info = Runtime.info(cls) else { return nil }
    return Runtime.findMethod(info, sel)
}

@c(_class_getClassMethod)
public func class_getClassMethod(_ cls: Class?, _ sel: UnsafePointer<CChar>?) -> Method? {
    class_getInstanceMethod(cls?.pointee.isa, sel)
}

@c(_class_addMethod)
public func class_addMethod(_ cls: Class?, _ sel: UnsafePointer<CChar>?, _ imp: UnsafeMutableRawPointer?,
                            _ types: UnsafePointer<CChar>?) -> Bool {
    guard let cls, let sel, let info = Runtime.info(cls) else { return false }
    if Runtime.findOwnMethod(info, sel) != nil { return false }
    Runtime.addMethod(info, sel, types: types.map { UnsafePointer(strdup($0)!) }, imp: imp, replacing: false)
    return true
}

@c(_class_replaceMethod)
public func class_replaceMethod(_ cls: Class?, _ sel: UnsafePointer<CChar>?, _ imp: UnsafeMutableRawPointer?,
                                _ types: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let cls, let sel, let info = Runtime.info(cls) else { return nil }
    return Runtime.addMethod(info, sel, types: types.map { UnsafePointer(strdup($0)!) }, imp: imp, replacing: true)
}

@c(_class_conformsToProtocol)
public func class_conformsToProtocol(_ cls: Class?, _ proto: ProtocolPointer?) -> Bool {
    guard let cls, let proto, let info = Runtime.info(cls) else { return false }
    return Protocols.classConforms(info, to: proto)
}

@c(_class_addIvar)
public func class_addIvar(_ cls: Class?, _ name: UnsafePointer<CChar>?, _ size: Int, _ alignment: UInt8,
                          _ types: UnsafePointer<CChar>?) -> Bool {
    false
}

@c(_objc_allocateClassPair)
public func objc_allocateClassPair(_ superclass: Class?, _ name: UnsafePointer<CChar>?, _ extraBytes: Int) -> Class? {
    RootClasses.bootstrap()
    guard let name, Runtime.lookUpClass(name) == nil else { return nil }
    return Runtime.allocateClassPair(superclass: superclass, name: UnsafePointer(strdup(name)!), extraBytes: extraBytes)
}

/// Builds a class in storage the caller provides, as Foundation does for
/// classes it exports by symbol. Register it with objc_registerClassPair.
@c(_objc_initializeClassPair)
public func objc_initializeClassPair(_ superclass: Class?, _ name: UnsafePointer<CChar>?, _ cls: Class?,
                                     _ metaclass: Class?) -> Class? {
    guard let name, let cls, let metaclass else { return nil }
    RootClasses.bootstrap()
    return Runtime.initializeClassPair(superclass: superclass, name: UnsafePointer(strdup(name)!),
                                       cls: cls, metaclass: metaclass)
}

@c(_objc_registerClassPair)
public func objc_registerClassPair(_ cls: Class?) {
    if let cls { Runtime.registerClassPair(cls) }
}

// MARK: - Methods

@c(_method_getName)
public func method_getName(_ method: Method?) -> UnsafePointer<CChar>? {
    method?.pointee.name
}

@c(_method_getImplementation)
public func method_getImplementation(_ method: Method?) -> UnsafeMutableRawPointer? {
    method?.pointee.imp
}

@c(_method_getTypeEncoding)
public func method_getTypeEncoding(_ method: Method?) -> UnsafePointer<CChar>? {
    method?.pointee.types
}

@c(_method_setImplementation)
public func method_setImplementation(_ method: Method?, _ imp: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let method else { return nil }
    let old = Runtime.setImplementation(method, imp)
    return old
}

@c(_method_exchangeImplementations)
public func method_exchangeImplementations(_ first: Method?, _ second: Method?) {
    guard let first, let second else { return }
    Runtime.exchangeImplementations(first, second)
}

// MARK: - Selectors

@c(_sel_registerName)
public func sel_registerName(_ name: UnsafePointer<CChar>?) -> UnsafePointer<CChar>? {
    name.map { Selectors.register($0) }
}

@c(_sel_getUid)
public func sel_getUid(_ name: UnsafePointer<CChar>?) -> UnsafePointer<CChar>? {
    name.map { Selectors.register($0) }
}

@c(_sel_getName)
public func sel_getName(_ sel: UnsafePointer<CChar>?) -> UnsafePointer<CChar>? {
    sel
}

@c(_sel_isEqual)
public func sel_isEqual(_ lhs: UnsafePointer<CChar>?, _ rhs: UnsafePointer<CChar>?) -> Bool {
    lhs == rhs
}

// MARK: - Protocols

@c(_objc_getProtocol)
public func objc_getProtocol(_ name: UnsafePointer<CChar>?) -> ProtocolPointer? {
    name.flatMap(Protocols.lookUp)
}

@c(_protocol_getName)
public func protocol_getName(_ proto: ProtocolPointer?) -> UnsafePointer<CChar>? {
    proto?.pointee.name
}

@c(_protocol_conformsToProtocol)
public func protocol_conformsToProtocol(_ proto: ProtocolPointer?, _ other: ProtocolPointer?) -> Bool {
    guard let proto, let other else { return false }
    return Protocols.conforms(proto, to: other)
}

/// A new protocol to fill in and register; nil if the name is taken.
@c(_objc_allocateProtocol)
public func objc_allocateProtocol(_ name: UnsafePointer<CChar>?) -> ProtocolPointer? {
    RootClasses.bootstrap()
    return name.flatMap(Protocols.allocate)
}

@c(_protocol_addProtocol)
public func protocol_addProtocol(_ proto: ProtocolPointer?, _ addition: ProtocolPointer?) {
    guard let proto, let addition else { return }
    Protocols.add(addition, to: proto)
}

@c(_protocol_addMethodDescription)
public func protocol_addMethodDescription(_ proto: ProtocolPointer?, _ name: UnsafePointer<CChar>?,
                                          _ types: UnsafePointer<CChar>?, _ isRequired: Bool, _ isInstanceMethod: Bool) {
    guard let proto, let name else { return }
    Protocols.addMethod(Selectors.register(name), types: types, to: proto,
                        isRequired: isRequired, isInstanceMethod: isInstanceMethod)
}

@c(_objc_registerProtocol)
public func objc_registerProtocol(_ proto: ProtocolPointer?) {
    if let proto { Protocols.register(proto) }
}

@c(_class_addProtocol)
public func class_addProtocol(_ cls: Class?, _ proto: ProtocolPointer?) -> Bool {
    guard let cls, let proto, let info = Runtime.info(cls) else { return false }
    return Protocols.add(proto, toClass: info)
}

// MARK: - Properties

@c(_class_getProperty)
public func class_getProperty(_ cls: Class?, _ name: UnsafePointer<CChar>?) -> UnsafeRawPointer? {
    guard let cls, let name, let info = Runtime.info(cls) else { return nil }
    return Properties.find(info, name)
}

/// The class's own properties, in a malloc'd array the caller frees.
@c(_class_copyPropertyList)
public func class_copyPropertyList(_ cls: Class?, _ count: UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<UnsafeRawPointer?>? {
    let properties = cls.flatMap { Runtime.info($0) }.map(Properties.list) ?? []
    count?.pointee = UInt32(properties.count)
    guard !properties.isEmpty else { return nil }
    let array = malloc(MemoryLayout<UnsafeRawPointer?>.stride * (properties.count + 1))!
        .bindMemory(to: UnsafeRawPointer?.self, capacity: properties.count + 1)
    for (index, property) in properties.enumerated() { array[index] = property }
    array[properties.count] = nil
    return array
}

@c(_property_getName)
public func property_getName(_ property: UnsafeRawPointer?) -> UnsafePointer<CChar>? {
    property.flatMap(Properties.name)
}

@c(_property_getAttributes)
public func property_getAttributes(_ property: UnsafeRawPointer?) -> UnsafePointer<CChar>? {
    property.flatMap(Properties.attributes)
}

/// One attribute's value, malloc'd for the caller to free.
@c(_property_copyAttributeValue)
public func property_copyAttributeValue(_ property: UnsafeRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let property, let name, let value = Properties.attributeValue(property, name) else { return nil }
    return strdup(value)
}

// MARK: - Associated objects

@c(_objc_setAssociatedObject)
public func objc_setAssociatedObject(_ object: id?, _ key: UnsafeRawPointer?, _ value: id?, _ policy: UInt) {
    guard let object, let key else { return }
    Associations.set(object, key: key, value: value, policy: policy)
}

@c(_objc_getAssociatedObject)
public func objc_getAssociatedObject(_ object: id?, _ key: UnsafeRawPointer?) -> id? {
    guard let object, let key else { return nil }
    return Associations.get(object, key: key)
}

@c(_objc_removeAssociatedObjects)
public func objc_removeAssociatedObjects(_ object: id?) {
    if let object { Associations.removeAll(object) }
}

// MARK: - @synchronized

@c(_objc_sync_enter)
public func objc_sync_enter(_ object: id?) -> Int32 {
    if let object { Synchronized.enter(object) }
    return 0
}

@c(_objc_sync_exit)
public func objc_sync_exit(_ object: id?) -> Int32 {
    if let object { Synchronized.exit(object) }
    return 0
}

// MARK: - Hooks

nonisolated(unsafe) private var enumerationMutationHandler: (@convention(c) (id?) -> Void)?

@c(_objc_setEnumerationMutationHandler)
public func objc_setEnumerationMutationHandler(_ handler: (@convention(c) (id?) -> Void)?) {
    enumerationMutationHandler = handler
}

@c(_objc_enumerationMutation)
public func objc_enumerationMutation(_ object: id?) {
    if let enumerationMutationHandler {
        enumerationMutationHandler(object)
        return
    }
    objcFatal("collection \(object.map { "\($0)" } ?? "nil") was mutated while being enumerated")
}

@c(_objc_setForwardHandler)
public func objc_setForwardHandler(_ forward: UnsafeMutableRawPointer?, _ forwardStret: UnsafeMutableRawPointer?) {
    Runtime.forwardHandler = forward
}
