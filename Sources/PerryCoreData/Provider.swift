import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryCoreData: the provider for CoreData.framework, over CoreModel.
// PerryProviderPlugin generates its perry_provider_startup and
// perry_provider_symbol from the module's Objective-C declarations; this
// file adds the provider's own steps. Core Data is a client of libobjc's C
// API and of Foundation's classes, which the loader starts first.

private let libobjc = "/usr/lib/libobjc.A.dylib"

/// libobjc functions beyond the interop layer's: property introspection,
/// for the accessors of @dynamic properties.
enum Runtime {
    typealias Pointer = UnsafeMutableRawPointer
    typealias GetProperty = @convention(c) (Pointer?, UnsafePointer<CChar>?) -> UnsafeRawPointer?
    typealias CopyAttributeValue = @convention(c) (UnsafeRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias GetName = @convention(c) (Pointer?) -> UnsafePointer<CChar>?
    typealias GetSuperclass = @convention(c) (Pointer?) -> Pointer?
    nonisolated(unsafe) static var getProperty: GetProperty!
    nonisolated(unsafe) static var copyAttributeValue: CopyAttributeValue!
    nonisolated(unsafe) static var getName: GetName!
    nonisolated(unsafe) static var getSuperclass: GetSuperclass!
    nonisolated(unsafe) static var globalBlockClass: Pointer?

    /// A declared property's type encoding ("q", "@\"NSString\""), if the
    /// class or a superclass declares it.
    static func propertyType(_ cls: ObjCClass, _ name: String) -> String? {
        guard let property = name.withCString({ getProperty(cls.pointer, $0) }),
              let value = "T".withCString({ copyAttributeValue(property, $0) }) else { return nil }
        defer { free(value) }
        return String(cString: value)
    }

    static func name(_ cls: ObjCClass) -> String {
        getName(cls.pointer).map { String(cString: $0) } ?? ""
    }
}

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        libobjc.withCString { library in name.withCString { lookup(library, $0) } }
    }
    let loaded = ObjCRuntime.load(symbol)
    guard loaded, let getProperty = symbol("_class_getProperty"),
          let copyAttributeValue = symbol("_property_copyAttributeValue"),
          let getName = symbol("_class_getName"), let getSuperclass = symbol("_class_getSuperclass"),
          Classes.named("NSPredicate") != nil else {
        coreDataFatal("Core Data needs libPerryobjc and libPerryFoundation, which are missing or incomplete")
    }
    Runtime.getProperty = unsafeBitCast(getProperty, to: Runtime.GetProperty.self)
    Runtime.copyAttributeValue = unsafeBitCast(copyAttributeValue, to: Runtime.CopyAttributeValue.self)
    Runtime.getName = unsafeBitCast(getName, to: Runtime.GetName.self)
    Runtime.getSuperclass = unsafeBitCast(getSuperclass, to: Runtime.GetSuperclass.self)
    Runtime.globalBlockClass = "/usr/lib/libSystem.B.dylib".withCString { library in
        "__NSConcreteGlobalBlock".withCString { lookup(library, $0) }
    }
    return true
}

func providerDidStart(_ info: perry_startup_info) {
    if let globalBlockClass = Runtime.globalBlockClass {
        StoreErrors.registerProvider(globalBlockClass: globalBlockClass)
    }
}

/// Reports a fatal error the way Core Data's exceptions read, and aborts.
func coreDataFatal(_ message: String) -> Never {
    let line = "perry: CoreData: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

enum Classes {
    static func named(_ name: String) -> ObjCClass? {
        name.withCString { ObjCRuntime.functions.getClass($0) }.map(ObjCClass.init)
    }
}
