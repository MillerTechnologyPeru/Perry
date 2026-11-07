import CJavaScriptCore
import CPerryJavaScriptCore
import Glibc
import PerryObjCInterop

// Between JavaScript values and Objective-C objects. Objective-C goes in as
// JavaScript's own types where there is one (strings, numbers, booleans,
// dates, arrays, dictionaries as objects, NSNull as null, blocks as
// functions); any other object becomes a wrapper that shows what its
// classes export through JSExport protocols: properties as accessors and
// methods named after their selectors ("doFoo:withBar:" is doFooWithBar),
// or the name JSExportAs gives. A class becomes an object of its exported
// class methods. Methods and blocks are called with their arguments
// converted by their type encodings.

typealias Ref = UnsafeMutableRawPointer

/// An Objective-C object a JavaScript object holds (retained).
final class Held {
    let object: Ref
    init(_ object: Ref) { self.object = ObjCRuntime.retain(object)! }
    deinit { ObjCRuntime.release(object) }
}

/// A method a JavaScript function calls on its `this`.
final class MethodInfo {
    let selector: UnsafeRawPointer
    let types: String
    init(selector: UnsafeRawPointer, types: String) {
        self.selector = selector
        self.types = types
    }
}

enum Bridge {
    // MARK: Strings

    static func jsString(_ text: String) -> JSStringRef { JSStringCreateWithUTF8CString(text) }

    static func string(_ string: JSStringRef?) -> String {
        guard let string else { return "" }
        let size = JSStringGetMaximumUTF8CStringSize(string)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        JSStringGetUTF8CString(string, &buffer, size)
        return String(cString: buffer)
    }

    static func string(_ context: JSContextRef, _ value: JSValueRef?) -> String {
        guard let copy = JSValueToStringCopy(context, value, nil) else { return "" }
        defer { JSStringRelease(copy) }
        return string(copy)
    }

    static func property(_ context: JSContextRef, _ object: JSObjectRef, _ name: String) -> JSValueRef? {
        let key = jsString(name)
        defer { JSStringRelease(key) }
        return JSObjectGetProperty(context, object, key, nil)
    }

    static func setProperty(_ context: JSContextRef, _ object: JSObjectRef, _ name: String, _ value: JSValueRef?) {
        let key = jsString(name)
        defer { JSStringRelease(key) }
        JSObjectSetProperty(context, object, key, value, JSPropertyAttributes(kJSPropertyAttributeNone), nil)
    }

    // MARK: Classes

    nonisolated(unsafe) static let wrapperClass: JSClassRef = {
        var definition = kJSClassDefinitionEmpty
        definition.className = UnsafePointer(strdup("ObjCObject"))
        definition.finalize = { object in
            guard let data = JSObjectGetPrivate(object) else { return }
            Unmanaged<Held>.fromOpaque(data).release()
        }
        return JSClassCreate(&definition)
    }()

    nonisolated(unsafe) static let blockClass: JSClassRef = {
        var definition = kJSClassDefinitionEmpty
        definition.className = UnsafePointer(strdup("ObjCBlock"))
        definition.finalize = { object in
            guard let data = JSObjectGetPrivate(object) else { return }
            Unmanaged<Held>.fromOpaque(data).release()
        }
        definition.callAsFunction = { context, function, this, count, arguments, exception in
            guard let context, let function, let data = JSObjectGetPrivate(function) else { return nil }
            let block = Unmanaged<Held>.fromOpaque(data).takeUnretainedValue().object
            return Bridge.callBlock(block, context, function, this, count, arguments, exception)
        }
        return JSClassCreate(&definition)
    }()

    nonisolated(unsafe) static let methodClass: JSClassRef = {
        var definition = kJSClassDefinitionEmpty
        definition.className = UnsafePointer(strdup("ObjCMethod"))
        definition.finalize = { object in
            guard let data = JSObjectGetPrivate(object) else { return }
            Unmanaged<MethodInfo>.fromOpaque(data).release()
        }
        definition.callAsFunction = { context, function, this, count, arguments, exception in
            guard let context, let function, let data = JSObjectGetPrivate(function) else { return nil }
            let method = Unmanaged<MethodInfo>.fromOpaque(data).takeUnretainedValue()
            return Bridge.callMethod(method, context, function, this, count, arguments, exception)
        }
        return JSClassCreate(&definition)
    }()

    static func held(_ value: JSValueRef?, _ context: JSContextRef, of cls: JSClassRef = wrapperClass) -> Ref? {
        guard let value, JSValueIsObjectOfClass(context, value, cls), let object = JSValueToObject(context, value, nil),
              let data = JSObjectGetPrivate(object) else { return nil }
        return Unmanaged<Held>.fromOpaque(data).takeUnretainedValue().object
    }

    // MARK: Objective-C to JavaScript

    static func value(_ object: Ref?, _ context: JSContextRef) -> JSValueRef? {
        guard let object else { return JSValueMakeUndefined(context) }
        if let value = JSValues.state(object) { return value.ref }
        let wrapped = NSObject(object)
        if Runtime.isMetaClass(Runtime.getClass(object)) { return wrap(object, context, classMethods: true) }
        if object == Runtime.booleans.0 || object == Runtime.booleans.1 { return JSValueMakeBoolean(context, object == Runtime.booleans.0) }
        if wrapped.isA("NSNull") { return JSValueMakeNull(context) }
        if wrapped.isA("NSString") {
            let string = jsString(wrapped.stringValue)
            defer { JSStringRelease(string) }
            return JSValueMakeString(context, string)
        }
        if wrapped.isA("NSNumber") { return JSValueMakeNumber(context, wrapped.unsafeCast(to: NSNumber.self).doubleValue()) }
        if wrapped.isA("NSDate") {
            var milliseconds: JSValueRef? = JSValueMakeNumber(context, wrapped.unsafeCast(to: NSDate.self).timeIntervalSince1970() * 1000)
            return JSObjectMakeDate(context, 1, &milliseconds, nil)
        }
        if wrapped.isA("NSArray") {
            var elements = wrapped.unsafeCast(to: NSArray.self).elements.map { value($0.objcObject, context) }
            return JSObjectMakeArray(context, elements.count, &elements, nil)
        }
        if wrapped.isA("NSDictionary") {
            let dictionary = wrapped.unsafeCast(to: NSDictionary.self)
            let result = JSObjectMake(context, nil, nil)!
            for key in dictionary.allKeys().elements {
                setProperty(context, result, key.describedByObject() ?? "", value(dictionary.object(forKey: key)?.objcObject, context))
            }
            return result
        }
        if wrapped.isA("NSBlock") {
            return JSObjectMake(context, blockClass, Unmanaged.passRetained(Held(object)).toOpaque())
        }
        return wrap(object, context, classMethods: false)
    }

    /// A wrapper with the object's exported properties and methods.
    static func wrap(_ object: Ref, _ context: JSContextRef, classMethods: Bool) -> JSObjectRef {
        let wrapper = JSObjectMake(context, wrapperClass, Unmanaged.passRetained(Held(object)).toOpaque())!
        let exports = Exports.of(classMethods ? object : Runtime.getClass(object)!, classMethods: classMethods)
        for method in exports.methods {
            let function = JSObjectMake(context, methodClass,
                                        Unmanaged.passRetained(MethodInfo(selector: method.selector, types: method.types)).toOpaque())
            setProperty(context, wrapper, method.name, function)
        }
        for property in exports.properties {
            let getter = JSObjectMake(context, methodClass,
                                      Unmanaged.passRetained(MethodInfo(selector: property.getter, types: property.getterTypes)).toOpaque())
            let setter: JSValueRef? = property.setter.map {
                JSObjectMake(context, methodClass, Unmanaged.passRetained(MethodInfo(selector: $0, types: property.setterTypes)).toOpaque())
            } ?? JSValueMakeUndefined(context)
            defineAccessor(context, wrapper, property.name, getter, setter)
        }
        return wrapper
    }

    /// Object.defineProperty(object, name, {get, set}).
    static func defineAccessor(_ context: JSContextRef, _ object: JSObjectRef, _ name: String, _ getter: JSValueRef?, _ setter: JSValueRef?) {
        let global = JSContextGetGlobalObject(context)!
        guard let objectConstructor = JSValueToObject(context, property(context, global, "Object"), nil),
              let define = JSValueToObject(context, property(context, objectConstructor, "defineProperty"), nil) else { return }
        let descriptor = JSObjectMake(context, nil, nil)!
        setProperty(context, descriptor, "get", getter)
        setProperty(context, descriptor, "set", setter)
        setProperty(context, descriptor, "enumerable", JSValueMakeBoolean(context, true))
        setProperty(context, descriptor, "configurable", JSValueMakeBoolean(context, true))
        let key = jsString(name)
        defer { JSStringRelease(key) }
        var arguments: [JSValueRef?] = [object, JSValueMakeString(context, key), descriptor]
        _ = JSObjectCallAsFunction(context, define, objectConstructor, 3, &arguments, nil)
    }

    // MARK: JavaScript to Objective-C

    /// The object a value stands for, autoreleased: as toObject converts.
    static func object(_ value: JSValueRef?, _ context: JSContextRef, depth: Int = 0) -> Ref? {
        guard let value, depth < 32 else { return nil }
        switch JSValueGetType(context, value) {
        case kJSTypeUndefined: return nil
        case kJSTypeNull: return NSNull.null().objCReturnValue()
        case kJSTypeBoolean: return JSValueToBoolean(context, value) ? Runtime.booleans.0 : Runtime.booleans.1
        case kJSTypeNumber: return NSNumber.make(double: JSValueToNumber(context, value, nil)).objCReturnValue()
        case kJSTypeString: return NSObject.string(string(context, value)).objCReturnValue()
        case kJSTypeObject:
            if let held = held(value, context) { return held }
            if let block = held(value, context, of: blockClass) { return block }
            guard let object = JSValueToObject(context, value, nil) else { return nil }
            if JSValueIsArray(context, value) {
                let length = Int(JSValueToNumber(context, property(context, object, "length"), nil))
                let array = NSMutableArray.empty()
                for index in 0..<length {
                    let element = JSObjectGetPropertyAtIndex(context, object, UInt32(index), nil)
                    array.add(self.object(element, context, depth: depth + 1).map { NSObject($0) } ?? NSNull.null())
                }
                return array.objCReturnValue()
            }
            if JSValueIsDate(context, value) {
                guard let getTime = JSValueToObject(context, property(context, object, "getTime"), nil) else { return nil }
                let milliseconds = JSValueToNumber(context, JSObjectCallAsFunction(context, getTime, object, 0, nil, nil), nil)
                return NSDate.make(since1970: milliseconds / 1000).objCReturnValue()
            }
            let dictionary = NSMutableDictionary.empty()
            let names = JSObjectCopyPropertyNames(context, object)!
            defer { JSPropertyNameArrayRelease(names) }
            for index in 0..<JSPropertyNameArrayGetCount(names) {
                let name = string(JSPropertyNameArrayGetNameAtIndex(names, index))
                let element = property(context, object, name)
                guard let converted = self.object(element, context, depth: depth + 1) else { continue }
                dictionary.set(NSObject(converted), forKey: NSObject.string(name))
            }
            return dictionary.objCReturnValue()
        default:
            return NSObject.string(string(context, value)).objCReturnValue()
        }
    }

    // MARK: Calling

    /// Types in an encoding: "d24@?0d8d16" is d, @?, d, d.
    static func types(_ encoding: String) -> [String] {
        let characters = Array(encoding)
        var types: [String] = []
        var index = 0
        while index < characters.count {
            while index < characters.count, "rnNoORVA".contains(characters[index]) { index += 1 }
            guard index < characters.count else { break }
            let start = index
            switch characters[index] {
            case "@":
                index += 1
                if index < characters.count, characters[index] == "?" { index += 1 }
                else if index < characters.count, characters[index] == "\"" {
                    index += 1
                    while index < characters.count, characters[index] != "\"" { index += 1 }
                    index += 1
                }
            case "^":
                index += 1
                while index < characters.count, characters[index] == "^" { index += 1 }
                index += 1
            case "{", "(", "[":
                var depth = 0
                repeat {
                    if "{([".contains(characters[index]) { depth += 1 }
                    if "})]".contains(characters[index]) { depth -= 1 }
                    index += 1
                } while depth > 0 && index < characters.count
            default:
                index += 1
            }
            types.append(String(characters[start..<index]))
            while index < characters.count, characters[index].isNumber { index += 1 }
        }
        return types
    }

    /// ToInt32, as JavaScript converts numbers to integers.
    static func int32(_ number: Double) -> Int32 {
        guard number.isFinite else { return 0 }
        let truncated = number.rounded(.towardZero).truncatingRemainder(dividingBy: 4294967296)
        return Int32(truncatingIfNeeded: Int64(truncated < 0 ? truncated + 4294967296 : truncated))
    }

    /// Calls `function` with the fixed register words, then the JavaScript
    /// arguments converted to `argumentTypes`; the result as JavaScript.
    static func invoke(_ function: UnsafeRawPointer, fixed: [UInt64], argumentTypes: [String], returnType: String,
                       _ context: JSContextRef, _ count: Int, _ arguments: UnsafePointer<JSValueRef?>?) -> JSValueRef? {
        var x = [UInt64](repeating: 0, count: 8), d = [UInt64](repeating: 0, count: 8)
        var nextX = 0, nextD = 0
        for word in fixed {
            x[nextX] = word
            nextX += 1
        }
        var keep: [Ref] = []
        for (index, type) in argumentTypes.enumerated() {
            let value: JSValueRef? = index < count ? arguments?[index] : JSValueMakeUndefined(context)
            let first = type.first ?? "@"
            switch first {
            case "d", "f":
                let number = JSValueToNumber(context, value, nil)
                guard nextD < 8 else { continue }
                d[nextD] = first == "d" ? number.bitPattern : UInt64(Float(number).bitPattern)
                nextD += 1
            default:
                guard nextX < 8 else { continue }
                switch first {
                case "@", "#":
                    let object = self.object(value, context)
                    if let object { keep.append(ObjCRuntime.retain(object)!) }
                    x[nextX] = UInt64(UInt(bitPattern: object))
                case "B": x[nextX] = JSValueToBoolean(context, value) ? 1 : 0
                case "c", "C", "s", "S", "i", "I":
                    x[nextX] = UInt64(UInt32(bitPattern: int32(JSValueToNumber(context, value, nil))))
                case "q", "Q", "l", "L":
                    let number = JSValueToNumber(context, value, nil)
                    x[nextX] = UInt64(bitPattern: number.isFinite ? Int64(number) : 0)
                case ":":
                    x[nextX] = UInt64(UInt(bitPattern: ObjCRuntime.selector(string(context, value))))
                case "*":
                    x[nextX] = UInt64(UInt(bitPattern: strdup(string(context, value))))
                default:
                    x[nextX] = 0
                }
            }
            nextX += first == "d" || first == "f" ? 0 : 1
        }
        defer { keep.forEach { ObjCRuntime.release($0) } }
        var d0: UInt64 = 0
        let x0 = perry_jsc_call(function, x, d, &d0)
        switch returnType.first ?? "v" {
        case "v": return JSValueMakeUndefined(context)
        case "@", "#": return value(UnsafeMutableRawPointer(bitPattern: UInt(x0)), context)
        case "d": return JSValueMakeNumber(context, Double(bitPattern: d0))
        case "f": return JSValueMakeNumber(context, Double(Float(bitPattern: UInt32(truncatingIfNeeded: d0))))
        case "B": return JSValueMakeBoolean(context, x0 & 0xff != 0)
        case "c": return JSValueMakeNumber(context, Double(Int8(truncatingIfNeeded: x0)))
        case "C": return JSValueMakeNumber(context, Double(UInt8(truncatingIfNeeded: x0)))
        case "s": return JSValueMakeNumber(context, Double(Int16(truncatingIfNeeded: x0)))
        case "S": return JSValueMakeNumber(context, Double(UInt16(truncatingIfNeeded: x0)))
        case "i": return JSValueMakeNumber(context, Double(Int32(truncatingIfNeeded: x0)))
        case "I": return JSValueMakeNumber(context, Double(UInt32(truncatingIfNeeded: x0)))
        case "Q", "L": return JSValueMakeNumber(context, Double(x0))
        default: return JSValueMakeNumber(context, Double(Int64(bitPattern: x0)))
        }
    }

    /// Runs a callback with the current context, this and arguments set,
    /// turning an exception the Objective-C side set into a JavaScript one.
    static func callback(_ context: JSContextRef, _ function: JSObjectRef, _ this: JSObjectRef?, _ count: Int,
                         _ arguments: UnsafePointer<JSValueRef?>?, _ exception: UnsafeMutablePointer<JSValueRef?>?,
                         _ body: () -> JSValueRef?) -> JSValueRef? {
        let contextObject = Contexts.object(for: JSContextGetGlobalContext(context))
        let state = Contexts.states[contextObject]
        let previous = state?.exception
        state?.exception = nil
        Callbacks.stack.append(Callbacks.Frame(context: contextObject, contextRef: context, this: this,
                                               arguments: (0..<count).map { arguments![$0] }, callee: function))
        let result = body()
        Callbacks.stack.removeLast()
        if let thrown = state?.exception {
            exception?.pointee = thrown.ref
            state?.exception = previous
            return JSValueMakeUndefined(context)
        }
        state?.exception = previous
        return result
    }

    static func callBlock(_ block: Ref, _ context: JSContextRef, _ function: JSObjectRef, _ this: JSObjectRef?, _ count: Int,
                          _ arguments: UnsafePointer<JSValueRef?>?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> JSValueRef? {
        // Block layout: isa, flags, reserved, invoke, descriptor; the
        // descriptor's signature follows its copy and dispose helpers.
        let flags = block.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: Int32.self)
        let entry = block.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer.self)
        let descriptor = block.load(fromByteOffset: 2 * MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer.self)
        var signature = "v8@?0"
        if flags & (1 << 30) != 0 {
            let offset = (flags & (1 << 25) != 0 ? 4 : 2) * MemoryLayout<UnsafeRawPointer>.size
            if let text = descriptor.load(fromByteOffset: offset, as: UnsafePointer<CChar>?.self) { signature = String(cString: text) }
        }
        let types = self.types(signature)
        return callback(context, function, this, count, arguments, exception) {
            invoke(entry, fixed: [UInt64(UInt(bitPattern: block))], argumentTypes: Array(types.dropFirst(2)),
                   returnType: types.first ?? "v", context, count, arguments)
        }
    }

    static func callMethod(_ method: MethodInfo, _ context: JSContextRef, _ function: JSObjectRef, _ this: JSObjectRef?, _ count: Int,
                           _ arguments: UnsafePointer<JSValueRef?>?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> JSValueRef? {
        guard let this, let receiver = held(this, context) else { return JSValueMakeUndefined(context) }
        let types = self.types(method.types)
        return callback(context, function, this, count, arguments, exception) {
            invoke(ObjCRuntime.msgSend, fixed: [UInt64(UInt(bitPattern: receiver)), UInt64(UInt(bitPattern: method.selector))],
                   argumentTypes: Array(types.dropFirst(3)), returnType: types.first ?? "v", context, count, arguments)
        }
    }
}

// MARK: - Exports

enum Exports {
    struct Method {
        let name: String
        let selector: UnsafeRawPointer
        let types: String
    }

    struct Property {
        let name: String
        let getter: UnsafeRawPointer
        let getterTypes: String
        let setter: UnsafeRawPointer?
        let setterTypes: String
    }

    /// "doFoo:withBar:" is doFooWithBar.
    static func jsName(_ selector: String) -> String {
        let parts = selector.split(separator: ":", omittingEmptySubsequences: true)
        guard let first = parts.first else { return selector }
        return String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    /// The protocols a class (or, for a metaclass, its class) adopts along
    /// its superclasses that themselves adopt JSExport, with theirs.
    static func protocols(of cls: Ref) -> [Ref] {
        guard let jsExport = Runtime.getProtocol("JSExport") else { return [] }
        var found: [Ref] = []
        func visit(_ proto: Ref) {
            guard !found.contains(proto), Runtime.conformsToProtocol(proto, jsExport) else { return }
            let name = String(cString: proto.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UnsafePointer<CChar>.self))
            guard name != "JSExport" else { return }
            found.append(proto)
            var count: UInt32 = 0
            if let list = Runtime.protocolCopyProtocolList(proto, &count) {
                for index in 0..<Int(count) { list[index].map(visit) }
                free(list)
            }
        }
        var current: Ref? = cls
        while let c = current {
            var count: UInt32 = 0
            if let list = Runtime.copyProtocolList(c, &count) {
                for index in 0..<Int(count) { list[index].map(visit) }
                free(list)
            }
            current = Runtime.superclass(c)
        }
        return found
    }

    static func of(_ cls: Ref, classMethods: Bool) -> (methods: [Method], properties: [Property]) {
        // Class methods are listed on the class; a metaclass's protocols are its class's.
        let protocols = self.protocols(of: cls)
        var methods: [Method] = []
        var properties: [Property] = []
        var accessors: Set<String> = []
        var renames: [String: String] = [:]
        var all: [(String, String)] = []
        for proto in protocols {
            if !classMethods {
                var count: UInt32 = 0
                if let list = Runtime.copyPropertyList(proto, &count) {
                    for index in 0..<Int(count) {
                        guard let property = list[index], let namePointer = Runtime.propertyName(property) else { continue }
                        let name = String(cString: namePointer)
                        let attributes = Runtime.propertyAttributes(property).map { String(cString: $0) } ?? ""
                        let parts = attributes.split(separator: ",")
                        let type = parts.first.map { String($0.dropFirst()) } ?? "@"
                        let getter = parts.first { $0.hasPrefix("G") }.map { String($0.dropFirst()) } ?? name
                        let readOnly = parts.contains("R")
                        let setter = readOnly ? nil
                            : parts.first { $0.hasPrefix("S") }.map { String($0.dropFirst()) } ?? "set" + name.prefix(1).uppercased() + name.dropFirst() + ":"
                        accessors.insert(getter)
                        if let setter { accessors.insert(setter) }
                        properties.append(Property(name: name, getter: UnsafeRawPointer(ObjCRuntime.selector(getter)),
                                                   getterTypes: type + "16@0:8", setter: setter.map { UnsafeRawPointer(ObjCRuntime.selector($0)) },
                                                   setterTypes: "v24@0:8" + type + "16"))
                    }
                    free(list)
                }
            }
            for required in [true, false] {
                var count: UInt32 = 0
                guard let list = Runtime.copyMethodDescriptions(proto, required, !classMethods, &count) else { continue }
                for index in 0..<Int(count) {
                    let selector = list.load(fromByteOffset: index * 16, as: UnsafePointer<CChar>.self)
                    let types = list.load(fromByteOffset: index * 16 + 8, as: UnsafePointer<CChar>?.self).map { String(cString: $0) } ?? ""
                    let name = String(cString: selector)
                    if let marker = name.firstRange(of: "__JS_EXPORT_AS__") {
                        renames[String(name[..<marker.lowerBound])] = String(name[marker.upperBound...].dropLast())
                    } else {
                        all.append((name, types))
                    }
                }
                free(list)
            }
        }
        for (name, types) in all where !accessors.contains(name) && !methods.contains(where: { String(cString: $0.selector.assumingMemoryBound(to: CChar.self)) == name }) {
            methods.append(Method(name: renames[name] ?? jsName(name), selector: UnsafeRawPointer(ObjCRuntime.selector(name)), types: types))
        }
        return (methods, properties)
    }
}

// MARK: - The current callback

enum Callbacks {
    struct Frame {
        let context: Ref
        let contextRef: JSContextRef
        let this: JSObjectRef?
        let arguments: [JSValueRef?]
        let callee: JSObjectRef
    }

    nonisolated(unsafe) static var stack: [Frame] = []
}
