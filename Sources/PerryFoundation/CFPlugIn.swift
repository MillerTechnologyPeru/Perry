import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFPlugIn: a plug-in is a CFBundle, as on Darwin, whose Info.plist names
// factories (CFPlugInFactories: factory UUID to function name) and the
// types each makes (CFPlugInTypes: type UUID to factory UUIDs), or which
// registers them itself (CFPlugInDynamicRegistration). A factory makes an
// instance of a type, a COM-style interface, by calling its function.

/// CFPlugInFactoryFunction: (allocator, type UUID) -> the instance.
public typealias CFPlugInFactoryFunction = @convention(c) (UnsafeRawPointer?, id?) -> UnsafeMutableRawPointer?

/// CFPlugInDynamicRegisterFunction: (plug-in).
public typealias CFPlugInDynamicRegisterFunction = @convention(c) (id?) -> Void

final class PlugInFactory {
    /// Retained.
    let uuid: id
    var function: CFPlugInFactoryFunction?
    var functionName: String?
    /// The plug-in it's in, for a function by name; not retained, as
    /// bundles live as long as the program.
    var plugIn: id?
    var instances = 0

    init(uuid: id) { self.uuid = ObjC.retain(uuid) ?? uuid }
    deinit { ObjC.release(uuid) }
}

enum PlugIns {
    nonisolated(unsafe) private static let mutex: UnsafeMutablePointer<pthread_mutex_t> = {
        let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        return mutex
    }()
    /// By the factory's UUID string.
    nonisolated(unsafe) static var factories: [String: PlugInFactory] = [:]
    /// Type UUID string to its factories' UUID strings, in the order
    /// registered.
    nonisolated(unsafe) static var types: [String: [String]] = [:]
    /// The bundles whose plug-in registration was done, and those not to be
    /// loaded on demand.
    nonisolated(unsafe) static var registered: Set<UInt> = []
    nonisolated(unsafe) static var notOnDemand: Set<UInt> = []

    static func locked<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }

    static func key(_ uuid: id?) -> String? { NSCFUUID.uuid(uuid)?.uuidString }

    static func address(_ bundle: id) -> UInt { UInt(bitPattern: bundle) }

    @discardableResult
    static func register(_ uuid: id?, _ configure: (PlugInFactory) -> Void) -> Bool {
        guard let uuid, let key = key(uuid) else { return false }
        locked {
            let factory = factories[key] ?? PlugInFactory(uuid: uuid)
            configure(factory)
            factories[key] = factory
        }
        return true
    }

    /// The bundle's factories and types, from its Info.plist, or by its
    /// dynamic registration function.
    static func registerContents(of bundle: id) {
        let first = locked { registered.insert(address(bundle)).inserted }
        guard first, let info = CFBundleGetInfoDictionary(bundle) else { return }
        func value(_ key: String) -> id? { ObjC.send(info, ObjC.selector("objectForKey:"), Strings.autoreleased(key)) }
        if let dynamic = value("CFPlugInDynamicRegistration"), isYes(dynamic) {
            let name = value("CFPlugInDynamicRegisterFunction").flatMap { Strings.value(of: $0) } ?? "CFPlugInDynamicRegister"
            _ = CFBundleLoadExecutable(bundle)
            let function = Strings.make(name)
            defer { ObjC.release(function) }
            if let pointer = CFBundleGetFunctionPointerForName(bundle, function) {
                unsafeBitCast(pointer, to: CFPlugInDynamicRegisterFunction.self)(bundle)
            }
            return
        }
        if let factories = value("CFPlugInFactories") {
            for (uuidString, name) in Dictionaries.entries(factories) {
                guard let uuid = CFUUIDCreateFromString(nil, uuidString) else { continue }
                defer { ObjC.release(uuid) }
                register(uuid) { factory in
                    factory.function = nil
                    factory.functionName = Strings.value(of: name)
                    factory.plugIn = bundle
                }
            }
        }
        if let types = value("CFPlugInTypes") {
            for (typeString, factoryStrings) in Dictionaries.entries(types) {
                guard let type = Strings.value(of: typeString).flatMap(UUID.init(uuidString:))?.uuidString else { continue }
                for factoryString in Arrays.elements(factoryStrings) {
                    guard let factory = Strings.value(of: factoryString).flatMap(UUID.init(uuidString:))?.uuidString else { continue }
                    locked {
                        if !(PlugIns.types[type] ?? []).contains(factory) { PlugIns.types[type, default: []].append(factory) }
                    }
                }
            }
        }
    }

    /// A plist's YES: a string, or a number or boolean.
    static func isYes(_ value: id) -> Bool {
        if let string = Strings.value(of: value) { return ["yes", "true", "1"].contains(string.lowercased()) }
        return ObjC.sendBool(value, ObjC.selector("boolValue"), nil)
    }

    /// New, retained CFUUIDs of the factories.
    static func uuids(_ keys: [String]) -> id? {
        let objects = locked { keys.compactMap { factories[$0]?.uuid } }
        guard !objects.isEmpty else { return nil }
        return Arrays.make(objects)
    }
}

/// CFBundle's: a plug-in is a bundle.
@c(_CFPlugInGetTypeID) public func CFPlugInGetTypeID() -> UInt { CFTypeIDs.bundle }

/// The bundle at the URL (+1), its factories and types registered; the
/// main bundle for its own URL, as on Darwin.
@c(_CFPlugInCreate)
public func CFPlugInCreate(_ allocator: UnsafeRawPointer?, _ url: id?) -> id? {
    let mainURL = CFBundleGetMainBundle().flatMap { ObjC.send($0, ObjC.selector("bundleURL")) }
    let path = { (url: id?) in url.flatMap { ObjC.send($0, ObjC.selector("standardizedURL")) }.flatMap { ObjC.send($0, ObjC.selector("path")) }
        .flatMap { Strings.value(of: $0) } }
    let bundle: id?
    if let main = CFBundleGetMainBundle(), let mainPath = path(mainURL), mainPath == path(url) {
        bundle = ObjC.retain(main)
    } else {
        bundle = CFBundleCreate(allocator, url)
    }
    guard let bundle else { return nil }
    PlugIns.registerContents(of: bundle)
    return bundle
}

@c(_CFPlugInGetBundle) public func CFPlugInGetBundle(_ plugIn: id?) -> id? { plugIn }

@c(_CFPlugInSetLoadOnDemand)
public func CFPlugInSetLoadOnDemand(_ plugIn: id?, _ onDemand: Bool) {
    guard let plugIn else { return }
    PlugIns.locked {
        if onDemand { PlugIns.notOnDemand.remove(PlugIns.address(plugIn)) } else { PlugIns.notOnDemand.insert(PlugIns.address(plugIn)) }
    }
    if !onDemand { _ = CFBundleLoadExecutable(plugIn) }
}

@c(_CFPlugInIsLoadOnDemand)
public func CFPlugInIsLoadOnDemand(_ plugIn: id?) -> Bool {
    guard let plugIn else { return false }
    return PlugIns.locked { !PlugIns.notOnDemand.contains(PlugIns.address(plugIn)) }
}

/// The factories that make the type (+1); NULL for none, as on Darwin.
@c(_CFPlugInFindFactoriesForPlugInType)
public func CFPlugInFindFactoriesForPlugInType(_ type: id?) -> id? {
    guard let type = PlugIns.key(type) else { return nil }
    return PlugIns.uuids(PlugIns.locked { PlugIns.types[type] ?? [] })
}

@c(_CFPlugInFindFactoriesForPlugInTypeInPlugIn)
public func CFPlugInFindFactoriesForPlugInTypeInPlugIn(_ type: id?, _ plugIn: id?) -> id? {
    guard let type = PlugIns.key(type), let plugIn else { return nil }
    let keys = PlugIns.locked { (PlugIns.types[type] ?? []).filter { PlugIns.factories[$0]?.plugIn == plugIn } }
    return PlugIns.uuids(keys)
}

/// An instance of `type` from the factory: what its function returns, its
/// plug-in's executable loaded first for a function by name. NULL when the
/// factory doesn't make the type.
@c(_CFPlugInInstanceCreate)
public func CFPlugInInstanceCreate(_ allocator: UnsafeRawPointer?, _ factoryUUID: id?, _ type: id?) -> UnsafeMutableRawPointer? {
    guard let key = PlugIns.key(factoryUUID), let typeKey = PlugIns.key(type) else { return nil }
    let found = PlugIns.locked { () -> (CFPlugInFactoryFunction?, String?, id?)? in
        guard let factory = PlugIns.factories[key], PlugIns.types[typeKey]?.contains(key) == true else { return nil }
        return (factory.function, factory.functionName, factory.plugIn)
    }
    guard let (function, name, plugIn) = found else { return nil }
    if let function { return function(allocator, type) }
    guard let name, let plugIn else { return nil }
    _ = CFBundleLoadExecutable(plugIn)
    let symbol = Strings.make(name)
    defer { ObjC.release(symbol) }
    guard let pointer = CFBundleGetFunctionPointerForName(plugIn, symbol) else { return nil }
    let resolved = unsafeBitCast(pointer, to: CFPlugInFactoryFunction.self)
    PlugIns.locked { PlugIns.factories[key]?.function = resolved }
    return resolved(allocator, type)
}

@c(_CFPlugInRegisterFactoryFunction)
public func CFPlugInRegisterFactoryFunction(_ factoryUUID: id?, _ function: CFPlugInFactoryFunction?) -> Bool {
    PlugIns.register(factoryUUID) { factory in
        factory.function = function
        factory.functionName = nil
    }
}

@c(_CFPlugInRegisterFactoryFunctionByName)
public func CFPlugInRegisterFactoryFunctionByName(_ factoryUUID: id?, _ plugIn: id?, _ name: id?) -> Bool {
    guard let name = Strings.value(of: name) else { return false }
    return PlugIns.register(factoryUUID) { factory in
        factory.function = nil
        factory.functionName = name
        factory.plugIn = plugIn
    }
}

@c(_CFPlugInUnregisterFactory)
public func CFPlugInUnregisterFactory(_ factoryUUID: id?) -> Bool {
    guard let key = PlugIns.key(factoryUUID) else { return false }
    return PlugIns.locked {
        for type in PlugIns.types.keys { PlugIns.types[type]?.removeAll { $0 == key } }
        return PlugIns.factories.removeValue(forKey: key) != nil
    }
}

@c(_CFPlugInRegisterPlugInType)
public func CFPlugInRegisterPlugInType(_ factoryUUID: id?, _ type: id?) -> Bool {
    guard let key = PlugIns.key(factoryUUID), let typeKey = PlugIns.key(type) else { return false }
    PlugIns.locked {
        if !(PlugIns.types[typeKey] ?? []).contains(key) { PlugIns.types[typeKey, default: []].append(key) }
    }
    return true
}

@c(_CFPlugInUnregisterPlugInType)
public func CFPlugInUnregisterPlugInType(_ factoryUUID: id?, _ type: id?) -> Bool {
    guard let key = PlugIns.key(factoryUUID), let typeKey = PlugIns.key(type) else { return false }
    return PlugIns.locked {
        guard let index = PlugIns.types[typeKey]?.firstIndex(of: key) else { return false }
        PlugIns.types[typeKey]?.remove(at: index)
        return true
    }
}

/// Counted, as Darwin counts them; a plug-in is never unloaded here.
@c(_CFPlugInAddInstanceForFactory)
public func CFPlugInAddInstanceForFactory(_ factoryUUID: id?) {
    guard let key = PlugIns.key(factoryUUID) else { return }
    PlugIns.locked { PlugIns.factories[key]?.instances += 1 }
}

@c(_CFPlugInRemoveInstanceForFactory)
public func CFPlugInRemoveInstanceForFactory(_ factoryUUID: id?) {
    guard let key = PlugIns.key(factoryUUID) else { return }
    PlugIns.locked { PlugIns.factories[key].map { $0.instances = max(0, $0.instances - 1) } }
}

// MARK: - Instances

/// CFPlugInInstance, the older way: data of a size, a factory's name, and
/// a function that finds an interface's function table.
/// CFPlugInInstanceDeallocateInstanceDataFunction: (instance data).
public typealias CFPlugInInstanceDeallocate = @convention(c) (UnsafeMutableRawPointer?) -> Void

/// CFPlugInInstanceGetInterfaceFunction: (instance, interface name, function table out) -> found.
public typealias CFPlugInInstanceGetInterface = @convention(c) (id?, id?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UInt8

final class PlugInInstanceStorage {
    typealias Deallocate = CFPlugInInstanceDeallocate
    typealias GetInterface = CFPlugInInstanceGetInterface

    let data: UnsafeMutableRawPointer
    let deallocate: Deallocate?
    let factoryName: id?
    let getInterface: GetInterface?

    init(size: Int, deallocate: Deallocate?, factoryName: id?, getInterface: GetInterface?) {
        data = UnsafeMutableRawPointer.allocate(byteCount: max(size, 1), alignment: 16)
        data.initializeMemory(as: UInt8.self, repeating: 0, count: max(size, 1))
        self.deallocate = deallocate
        self.factoryName = factoryName.flatMap { ObjC.retain($0) }
        self.getInterface = getInterface
    }

    deinit {
        deallocate?(data)
        data.deallocate()
        if let factoryName { ObjC.release(factoryName) }
    }
}

enum PlugInInstances {
    nonisolated(unsafe) static var instanceClass: Class!

    static func storage(_ instance: id?) -> PlugInInstanceStorage? { Storage.get(instance, as: PlugInInstanceStorage.self) }
}

@ObjCClass("__NSCFPlugInInstance")
final class NSCFPlugInInstance: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        PlugInInstances.instanceClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: PlugInInstances.instanceClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 33 }
}

@c(_CFPlugInInstanceGetTypeID) public func CFPlugInInstanceGetTypeID() -> UInt { 33 }

@c(_CFPlugInInstanceCreateWithInstanceDataSize)
public func CFPlugInInstanceCreateWithInstanceDataSize(_ allocator: UnsafeRawPointer?, _ size: Int,
                                                       _ deallocate: CFPlugInInstanceDeallocate?, _ factoryName: id?,
                                                       _ getInterface: CFPlugInInstanceGetInterface?) -> id? {
    guard let object = Storage.allocate(UnsafeMutableRawPointer(PlugInInstances.instanceClass)) else { return nil }
    Storage.set(object, PlugInInstanceStorage(size: size, deallocate: deallocate, factoryName: factoryName, getInterface: getInterface))
    return object
}

@c(_CFPlugInInstanceGetInstanceData)
public func CFPlugInInstanceGetInstanceData(_ instance: id?) -> UnsafeMutableRawPointer? { PlugInInstances.storage(instance)?.data }

@c(_CFPlugInInstanceGetFactoryName)
public func CFPlugInInstanceGetFactoryName(_ instance: id?) -> id? { PlugInInstances.storage(instance)?.factoryName }

@c(_CFPlugInInstanceGetInterfaceFunctionTable)
public func CFPlugInInstanceGetInterfaceFunctionTable(_ instance: id?, _ interface: id?,
                                                      _ table: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    guard let storage = PlugInInstances.storage(instance), let getInterface = storage.getInterface else { return false }
    return getInterface(instance, interface, table) != 0
}
