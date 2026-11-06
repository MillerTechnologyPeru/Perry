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

/// Binds a Swift object as an object's peer (RetainCounts), for the interop
/// layer's initializers.
@c(_perry_objc_bindPeer)
public func perry_objc_bindPeer(_ object: id?, _ peer: UnsafeMutableRawPointer?, _ retained: Bool) {
    guard let object, let peer else { return }
    Objects.bindPeer(object, peer, retained: retained)
}

/// The object's peer, unretained; nil if it has none.
@c(_perry_objc_peer)
public func perry_objc_peer(_ object: id?) -> UnsafeMutableRawPointer? { object.flatMap(Objects.peer) }

/// A peer's deinit has begun: true when the object should be deallocated.
@c(_perry_objc_peerWillDeinitialize)
public func perry_objc_peerWillDeinitialize(_ object: id?) -> Bool { object.map(Objects.peerWillDeinitialize) ?? false }

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

// The pool functions' names in Darwin's private API, which the Swift
// runtime calls.
@c(__objc_autoreleasePoolPush)
public func _objc_autoreleasePoolPush() -> UnsafeMutableRawPointer? {
    AutoreleasePool.push()
}

@c(__objc_autoreleasePoolPop)
public func _objc_autoreleasePoolPop(_ token: UnsafeMutableRawPointer?) {
    AutoreleasePool.pop(token)
}

/// Autoreleases an object of a class that overrides -autorelease, from
/// its override, as NSObject's would.
@c(__objc_rootAutorelease)
public func _objc_rootAutorelease(_ object: id?) -> id? {
    if let object { AutoreleasePool.add(object) }
    return object
}

@c(_objc_isUniquelyReferenced)
public func objc_isUniquelyReferenced(_ object: id?) -> Bool {
    object.map(Objects.isUniquelyReferenced) ?? false
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

/// A C++ object property's atomic getter or setter: the object's own
/// copy, `helper`, made with the property's lock held.
@c(_objc_copyCppObjectAtomic)
public func objc_copyCppObjectAtomic(_ destination: UnsafeMutableRawPointer?, _ source: UnsafeRawPointer?,
                                     _ helper: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void)?) {
    guard let source, let helper else { return }
    propertyLock(source).withLock { helper(destination, source) }
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
    return SwiftNames.demangle(info.name) ?? info.name
}

/// Swift's classes by their demangled names, as Apple's libobjc gives them.
@c(_class_getName)
public func class_getName(_ cls: Class?) -> UnsafePointer<CChar>? {
    guard let cls, let info = Runtime.info(cls) else { return nilClassName }
    return SwiftNames.demangle(info.name) ?? info.name
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
    guard let cls, let name else { return false }
    return Runtime.addIvar(cls, name: name, size: size, alignment: alignment, types: types)
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

/// A selector's name; for a null selector, "<null selector>", as Darwin's
/// libobjc answers.
@c(_sel_getName)
public func sel_getName(_ sel: UnsafePointer<CChar>?) -> UnsafePointer<CChar>? {
    sel ?? nullSelectorName
}

nonisolated(unsafe) private let nullSelectorName = UnsafePointer(strdup("<null selector>")!)

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

/// The class's own methods, in a malloc'd array the caller frees.
@c(_class_copyMethodList)
public func class_copyMethodList(_ cls: Class?, _ count: UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<UnsafeMutableRawPointer?>? {
    let methods = cls.flatMap { Runtime.info($0) }?.ownMethods ?? []
    count?.pointee = UInt32(methods.count)
    guard !methods.isEmpty else { return nil }
    let array = malloc(MemoryLayout<UnsafeMutableRawPointer?>.stride * (methods.count + 1))!
        .bindMemory(to: UnsafeMutableRawPointer?.self, capacity: methods.count + 1)
    for (index, method) in methods.enumerated() { array[index] = UnsafeMutableRawPointer(method) }
    array[methods.count] = nil
    return array
}

/// How many classes there are, writing up to `count` of them to `buffer`.
@c(_objc_getClassList)
public func objc_getClassList(_ buffer: UnsafeMutablePointer<Class?>?, _ count: Int32) -> Int32 {
    let classes = Runtime.classes
    if let buffer {
        for (index, cls) in classes.prefix(Int(max(count, 0))).enumerated() { buffer[index] = cls }
    }
    return Int32(classes.count)
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

/// The attributes as a list of name and value strings, in one malloc'd
/// block the caller frees.
@c(_property_copyAttributeList)
public func property_copyAttributeList(_ property: UnsafeRawPointer?, _ count: UnsafeMutablePointer<UInt32>?)
    -> UnsafeMutablePointer<perry_property_attribute>? {
    let parts = property.flatMap(Properties.attributes).map { String(cString: $0).split(separator: ",").map(String.init) } ?? []
    count?.pointee = UInt32(parts.count)
    guard !parts.isEmpty else { return nil }
    let header = MemoryLayout<perry_property_attribute>.stride * (parts.count + 1)
    let text = parts.reduce(0) { $0 + $1.utf8.count + 2 }
    let block = calloc(1, header + text)!
    let attributes = block.bindMemory(to: perry_property_attribute.self, capacity: parts.count + 1)
    var strings = block.advanced(by: header).assumingMemoryBound(to: CChar.self)
    func store(_ string: Substring) -> UnsafePointer<CChar> {
        let start = strings
        for byte in string.utf8 {
            strings.pointee = CChar(bitPattern: byte)
            strings += 1
        }
        strings.pointee = 0
        strings += 1
        return UnsafePointer(start)
    }
    for (index, part) in parts.enumerated() {
        attributes[index] = perry_property_attribute(name: store(part.prefix(1)), value: store(part.dropFirst()))
    }
    return attributes
}

/// Adds a property declaration; false when the class already has one by
/// that name.
@c(_class_addProperty)
public func class_addProperty(_ cls: Class?, _ name: UnsafePointer<CChar>?, _ attributes: UnsafePointer<perry_property_attribute>?,
                              _ count: UInt32) -> Bool {
    guard let cls, let name, let info = Runtime.info(cls), Properties.find(info, name) == nil else { return false }
    let text = (0..<Int(count)).compactMap { index -> String? in
        guard let attribute = attributes?[index], let key = attribute.name else { return nil }
        return String(cString: key) + (attribute.value.map { String(cString: $0) } ?? "")
    }.joined(separator: ",")
    // A property list of one entry: entsize and count, then name and attributes.
    let list = malloc(8 + Layout.pair)!
    list.storeBytes(of: UInt32(Layout.pair), as: UInt32.self)
    list.storeBytes(of: UInt32(1), toByteOffset: 4, as: UInt32.self)
    list.storeBytes(of: UnsafePointer(strdup(name)), toByteOffset: 8, as: UnsafePointer<CChar>?.self)
    list.storeBytes(of: UnsafePointer(strdup(text)), toByteOffset: 8 + Layout.word, as: UnsafePointer<CChar>?.self)
    Properties.add(UnsafeRawPointer(list), to: info)
    return true
}

// MARK: - Instance variables

/// The class's own ivar_t entries, from its class_ro_t.
private func ivars(of cls: Class) -> [UnsafeMutablePointer<perry_ivar>] {
    guard let ro = UnsafePointer<perry_class_ro>(bitPattern: UInt(cls.pointee.bits) & Layout.classBitsMask), let list = ro.pointee.ivars else { return [] }
    var result: [UnsafeMutablePointer<perry_ivar>] = []
    IvarList.forEach(list) { result.append($0) }
    return result
}

/// The instance variable named `name` in the class or a superclass.
@c(_class_getInstanceVariable)
public func class_getInstanceVariable(_ cls: Class?, _ name: UnsafePointer<CChar>?) -> UnsafeMutablePointer<perry_ivar>? {
    guard let name else { return nil }
    var current = cls
    while let candidate = current {
        _ = Runtime.info(candidate)
        if let ivar = ivars(of: candidate).first(where: { $0.pointee.name.map { strcmp($0, name) == 0 } ?? false }) { return ivar }
        current = candidate.pointee.superclass
    }
    return nil
}

@c(_class_copyIvarList)
public func class_copyIvarList(_ cls: Class?, _ count: UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<UnsafeMutablePointer<perry_ivar>?>? {
    let list = cls.map { cls -> [UnsafeMutablePointer<perry_ivar>] in
        _ = Runtime.info(cls)
        return ivars(of: cls)
    } ?? []
    count?.pointee = UInt32(list.count)
    guard !list.isEmpty else { return nil }
    let array = malloc(MemoryLayout<UnsafeMutablePointer<perry_ivar>?>.stride * (list.count + 1))!
        .bindMemory(to: UnsafeMutablePointer<perry_ivar>?.self, capacity: list.count + 1)
    for (index, ivar) in list.enumerated() { array[index] = ivar }
    array[list.count] = nil
    return array
}

@c(_ivar_getName)
public func ivar_getName(_ ivar: UnsafeMutablePointer<perry_ivar>?) -> UnsafePointer<CChar>? { ivar?.pointee.name }

@c(_ivar_getTypeEncoding)
public func ivar_getTypeEncoding(_ ivar: UnsafeMutablePointer<perry_ivar>?) -> UnsafePointer<CChar>? { ivar?.pointee.type }

@c(_ivar_getOffset)
public func ivar_getOffset(_ ivar: UnsafeMutablePointer<perry_ivar>?) -> Int { Int(ivar?.pointee.offset?.pointee ?? 0) }

/// An object ivar's value, unretained.
@c(_object_getIvar)
public func object_getIvar(_ object: id?, _ ivar: UnsafeMutablePointer<perry_ivar>?) -> id? {
    guard let object, let offset = ivar?.pointee.offset?.pointee else { return nil }
    return object.load(fromByteOffset: Int(offset), as: id?.self)
}

/// Stores an object ivar without retaining, as for an unretained ivar.
@c(_object_setIvar)
public func object_setIvar(_ object: id?, _ ivar: UnsafeMutablePointer<perry_ivar>?, _ value: id?) {
    guard let object, let offset = ivar?.pointee.offset?.pointee else { return }
    object.storeBytes(of: value, toByteOffset: Int(offset), as: id?.self)
}

/// Images are not named to libobjc here, so no image lists its classes.
/// The paths of the images whose classes are registered, in a malloc'd
/// array with a NULL after them.
@c(_objc_copyImageNames)
public func objc_copyImageNames(_ count: UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<UnsafePointer<CChar>?>? {
    copyNames(Runtime.imageNames(), count)
}

/// The names of the classes an image, named by path, defines.
@c(_objc_copyClassNamesForImage)
public func objc_copyClassNamesForImage(_ image: UnsafePointer<CChar>?, _ count: UnsafeMutablePointer<UInt32>?)
    -> UnsafeMutablePointer<UnsafePointer<CChar>?>? {
    copyNames(image.map(Runtime.classNames(forImage:)) ?? [], count)
}

private func copyNames(_ names: [UnsafePointer<CChar>], _ count: UnsafeMutablePointer<UInt32>?)
    -> UnsafeMutablePointer<UnsafePointer<CChar>?>? {
    count?.pointee = UInt32(names.count)
    guard !names.isEmpty else { return nil }
    let buffer = malloc((names.count + 1) * MemoryLayout<UnsafePointer<CChar>?>.stride)!
        .assumingMemoryBound(to: UnsafePointer<CChar>?.self)
    for (index, name) in names.enumerated() { buffer[index] = name }
    buffer[names.count] = nil
    return buffer
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

// MARK: - Blocks as methods

/// An IMP that calls a copy of `block` with the receiver and the method's
/// arguments, the selector left out.
@c(_imp_implementationWithBlock)
public func imp_implementationWithBlock(_ block: id?) -> UnsafeMutableRawPointer? {
    guard let copy = BlockClasses.copy(block) else { return nil }
    return perry_objc_trampoline_create(copy)
}

@c(_imp_getBlock)
public func imp_getBlock(_ imp: UnsafeMutableRawPointer?) -> id? {
    perry_objc_trampoline_block(imp)
}

/// Releases the block; the trampoline is reused. Methods still using it
/// must have been replaced, as on Darwin.
@c(_imp_removeBlock)
public func imp_removeBlock(_ imp: UnsafeMutableRawPointer?) -> Bool {
    guard let imp, let block = perry_objc_trampoline_block(imp) else { return false }
    Objects.release(block)
    perry_objc_trampoline_remove(imp)
    return true
}

// MARK: - Swift

// Swift's runtime registers its types and conformances as images load,
// finds and names its classes through these hooks, and has classes it
// builds realized. Each hook setter hands back the previous hook.

@c(_objc_addLoadImageFunc2)
public func objc_addLoadImageFunc2(_ function: Runtime.LoadImageFunction?) {
    if let function { Runtime.addLoadImageFunction(function) }
}

/// The older form's function takes only the header; the handle passed
/// after it goes unread.
@c(_objc_addLoadImageFunc)
public func objc_addLoadImageFunc(_ function: Runtime.LoadImageFunction?) {
    if let function { Runtime.addLoadImageFunction(function) }
}

@c(_objc_setHook_getClass)
public func objc_setHook_getClass(_ hook: Hooks.GetClass?, _ previous: UnsafeMutablePointer<Hooks.GetClass>?) {
    guard let hook else { return }
    previous?.pointee = Hooks.getClass
    Hooks.getClass = hook
}

@c(_objc_setHook_getImageName)
public func objc_setHook_getImageName(_ hook: Hooks.GetImageName?, _ previous: UnsafeMutablePointer<Hooks.GetImageName>?) {
    guard let hook else { return }
    previous?.pointee = Hooks.getImageName
    Hooks.getImageName = hook
}

@c(_objc_setHook_lazyClassNamer)
public func objc_setHook_lazyClassNamer(_ hook: Hooks.LazyClassNamer?, _ previous: UnsafeMutablePointer<Hooks.LazyClassNamer>?) {
    guard let hook else { return }
    previous?.pointee = Hooks.lazyClassNamer
    Hooks.lazyClassNamer = hook
}

@c(__objc_realizeClassFromSwift)
public func _objc_realizeClassFromSwift(_ cls: Class?, _ previously: UnsafeMutableRawPointer?) -> Class? {
    cls.map(Runtime.realizeFromSwift)
}

@c(_objc_readClassPair)
public func objc_readClassPair(_ cls: Class?, _ imageInfo: UnsafeRawPointer?) -> Class? {
    cls.map(Runtime.realizeFromSwift)
}

/// Classes are realized when first messaged, not when first looked at:
/// Swift's runtime messages a class before using it.
@c(__objc_supportsLazyRealization)
public func _objc_supportsLazyRealization() -> Bool { false }

@c(_class_setSuperclass)
public func class_setSuperclass(_ cls: Class?, _ superclass: Class?) -> Class? {
    guard let cls, let superclass else { return nil }
    return Runtime.setSuperclass(cls, superclass)
}

// MARK: - Exceptions

/// The function an exception no @catch handles goes to before the process
/// ends; Foundation sets one that reports the exception.
nonisolated(unsafe) private var uncaughtExceptionHandler: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?

@c(_objc_setUncaughtExceptionHandler)
public func objc_setUncaughtExceptionHandler(_ handler: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?)
    -> (@convention(c) (UnsafeMutableRawPointer?) -> Void)? {
    let previous = uncaughtExceptionHandler
    uncaughtExceptionHandler = handler
    return previous
}

/// An exception no @catch handles: the handler reports it, and the process
/// ends as Darwin's does after an uncaught exception.
@c
public func perry_objc_uncaught_exception(_ exception: UnsafeMutableRawPointer?) -> Never {
    if let handler = uncaughtExceptionHandler { handler(exception) }
    objcFatal("terminating with uncaught exception of type NSException")
}

#if !arch(arm)
/// Throws an exception. Perry cannot unwind arm64 Mach-O frames to a
/// @catch, so every exception is uncaught. On armv7, exceptions_arm.c
/// throws and catches them.
@c(_objc_exception_throw)
public func objc_exception_throw(_ exception: UnsafeMutableRawPointer?) -> Never {
    perry_objc_uncaught_exception(exception)
}

@c(_objc_exception_rethrow)
public func objc_exception_rethrow() -> Never {
    objcFatal("an exception was rethrown, which Perry cannot unwind")
}
#endif

@c(_objc_terminate)
public func objc_terminate() -> Never {
    objcFatal("terminating")
}

#if !arch(arm)
/// The personality routine Objective-C code's unwind tables name. Code
/// that only cleans up (ARC, @autoreleasepool) refers to it without
/// throwing; Perry cannot unwind arm64 Mach-O frames, so reaching it stops.
@c(___objc_personality_v0)
public func objc_personality_v0(_ version: Int32, _ actions: Int32, _ exceptionClass: UInt64, _ exception: UnsafeMutableRawPointer?,
                                _ context: UnsafeMutableRawPointer?) -> Int32 {
    objcFatal("an exception is unwinding through Objective-C code, which Perry cannot do")
}
#endif

// MARK: - Protocol introspection

/// A malloc'd array of `items` with a NULL after them, and its count.
private func copyList<T>(_ items: [T], _ count: UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<T>? {
    count?.pointee = UInt32(items.count)
    guard !items.isEmpty else { return nil }
    let buffer = malloc((items.count + 1) * MemoryLayout<T>.stride)!.assumingMemoryBound(to: T.self)
    buffer.initialize(from: items, count: items.count)
    memset(buffer + items.count, 0, MemoryLayout<T>.stride)
    return buffer
}

@c(_class_copyProtocolList)
public func class_copyProtocolList(_ cls: Class?, _ count: UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<ProtocolPointer>? {
    guard let cls, let info = Runtime.info(cls) else {
        count?.pointee = 0
        return nil
    }
    return copyList(Protocols.listed(by: info), count)
}

@c(_protocol_copyProtocolList)
public func protocol_copyProtocolList(_ proto: ProtocolPointer?, _ count: UnsafeMutablePointer<UInt32>?)
    -> UnsafeMutablePointer<ProtocolPointer>? {
    copyList(proto.map { Protocols.adopted(UnsafePointer($0)) } ?? [], count)
}

/// objc_method_description: the selector and its types.
@c(_protocol_copyMethodDescriptionList)
public func protocol_copyMethodDescriptionList(_ proto: ProtocolPointer?, _ required: Bool, _ instance: Bool,
                                               _ count: UnsafeMutablePointer<UInt32>?) -> UnsafeMutableRawPointer? {
    let methods = proto.map { Protocols.methods($0, required: required, instance: instance) } ?? []
    count?.pointee = UInt32(methods.count)
    guard !methods.isEmpty else { return nil }
    let buffer = calloc(methods.count + 1, Layout.pair)!
    for (index, method) in methods.enumerated() {
        buffer.storeBytes(of: method.0, toByteOffset: index * Layout.pair, as: SEL.self)
        buffer.storeBytes(of: method.1, toByteOffset: index * Layout.pair + Layout.word, as: UnsafePointer<CChar>?.self)
    }
    return buffer
}

/// The protocol's method for `selector`, or one of nils.
@c(_protocol_getMethodDescription)
public func protocol_getMethodDescription(_ proto: ProtocolPointer?, _ selector: SEL?, _ required: Bool, _ instance: Bool)
    -> perry_method_description {
    guard let proto, let selector,
          let method = Protocols.methods(proto, required: required, instance: instance).first(where: { $0.0 == selector }) else {
        return perry_method_description(name: nil, types: nil)
    }
    return perry_method_description(name: method.0, types: method.1)
}

@c(_protocol_copyPropertyList)
public func protocol_copyPropertyList(_ proto: ProtocolPointer?, _ count: UnsafeMutablePointer<UInt32>?)
    -> UnsafeMutablePointer<UnsafeRawPointer>? {
    copyList(proto.map { Protocols.properties(UnsafePointer($0)) } ?? [], count)
}

// MARK: - Catching

#if !arch(arm)
/// Entering and leaving a @catch. Exceptions are never unwound to one (see
/// objc_exception_throw), so these are bound but not reached. armv7 unwinds
/// to them, and has its own (exceptions_arm.c).
@c(_objc_begin_catch)
public func objc_begin_catch(_ exception: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    objcFatal("an exception reached a @catch, which Perry cannot unwind to")
}

@c(_objc_end_catch)
public func objc_end_catch() {}
#endif
