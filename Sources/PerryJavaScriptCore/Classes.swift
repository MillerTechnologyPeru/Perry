import CJavaScriptCore
import Glibc
import PerryObjCInterop

// JSVirtualMachine (a context group), JSContext (a global context, with
// its exception and exception handler) and JSValue (a protected value in a
// context), and JSManagedValue.

// MARK: - Virtual machines

final class MachineState: @unchecked Sendable {
    let group: JSContextGroupRef
    init(_ group: JSContextGroupRef) { self.group = JSContextGroupRetain(group) }
    deinit { JSContextGroupRelease(group) }
}

@ObjCClass("JSVirtualMachine")
public final class JSVirtualMachine: NSObject {
    static let states = StateTable<MachineState>()
    nonisolated(unsafe) static var byGroup: [JSContextGroupRef: Ref] = [:]

    static func object(for group: JSContextGroupRef) -> Ref {
        if let machine = byGroup[group] { return machine }
        let machine = objCClass.autoreleasedInstance().objcObject
        _ = ObjCRuntime.retain(machine)
        states.set(machine, MachineState(group))
        byGroup[group] = machine
        return machine
    }

    var group: JSContextGroupRef {
        if let state = JSVirtualMachine.states[objcObject] { return state.group }
        let group = JSContextGroupCreate()!
        JSVirtualMachine.states.set(objcObject, MachineState(group))
        JSContextGroupRelease(group)
        JSVirtualMachine.byGroup[group] = objcObject
        return group
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = group
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        if let state = JSVirtualMachine.states[objcObject] { JSVirtualMachine.byGroup[state.group] = nil }
        JSVirtualMachine.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: JSVirtualMachine.objCClass.pointer)
    }

    @ObjCMethod("addManagedReference:withOwner:") func addManagedReference(_ object: NSObject?, owner: NSObject?) {}
    @ObjCMethod("removeManagedReference:withOwner:") func removeManagedReference(_ object: NSObject?, owner: NSObject?) {}
}

// MARK: - Contexts

final class ContextState: @unchecked Sendable {
    let ref: JSGlobalContextRef
    let machine: Ref
    var exception: ValueState?
    var handler: ObjCBlock?
    var name: String?

    init(ref: JSGlobalContextRef, machine: Ref) {
        self.ref = JSGlobalContextRetain(ref)
        self.machine = ObjCRuntime.retain(machine)!
    }

    deinit {
        JSGlobalContextRelease(ref)
        ObjCRuntime.release(machine)
    }
}

enum Contexts {
    static let states = StateTable<ContextState>()
    /// The JSContext for each global context, unretained.
    nonisolated(unsafe) static var byRef: [JSGlobalContextRef: Ref] = [:]

    /// The JSContext for a global context, made for one the C API created.
    static func object(for ref: JSGlobalContextRef) -> Ref {
        if let context = byRef[ref] { return context }
        let context = JSContext.objCClass.autoreleasedInstance().objcObject
        attach(context, ref: ref, machine: JSVirtualMachine.object(for: JSContextGetGroup(ref)))
        return context
    }

    static func attach(_ context: Ref, ref: JSGlobalContextRef, machine: Ref) {
        states.set(context, ContextState(ref: ref, machine: machine))
        byRef[ref] = context
    }

    static func ref(_ context: Ref?) -> JSGlobalContextRef? { states[context]?.ref }

    /// An exception: to the handler if there is one, else kept as the
    /// context's exception.
    static func report(_ context: Ref, _ exception: JSValueRef?) {
        guard let exception, let state = states[context] else { return }
        let value = JSValues.make(exception, in: context)
        if let handler = state.handler {
            typealias Handler = @convention(c) (Ref, Ref?, Ref?) -> Void
            handler.function(as: Handler.self)(handler.object, context, value)
        } else {
            state.exception = JSValues.state(value)
        }
    }
}

@ObjCClass("JSContext")
public final class JSContext: NSObject {
    var state: ContextState {
        if let state = Contexts.states[objcObject] { return state }
        let machine = JSVirtualMachine.objCClass.autoreleasedInstance().objcObject
        let ref = JSGlobalContextCreateInGroup(NSObject(machine).unsafeCast(to: JSVirtualMachine.self).group, nil)!
        Contexts.attach(objcObject, ref: ref, machine: machine)
        JSGlobalContextRelease(ref)
        return Contexts.states[objcObject]!
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = state
        return self
    }

    @ObjCMethod("initWithVirtualMachine:")
    func initialize(virtualMachine: NSObject) -> Self {
        let ref = JSGlobalContextCreateInGroup(virtualMachine.unsafeCast(to: JSVirtualMachine.self).group, nil)!
        Contexts.attach(objcObject, ref: ref, machine: virtualMachine.objcObject)
        JSGlobalContextRelease(ref)
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        if let state = Contexts.states[objcObject] { Contexts.byRef[state.ref] = nil }
        Contexts.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: JSContext.objCClass.pointer)
    }

    @ObjCClassMethod("contextWithJSGlobalContextRef:")
    static func context(globalContextRef ref: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let ref else { return nil }
        return Contexts.object(for: JSGlobalContextRef(ref))
    }

    @ObjCMethod("JSGlobalContextRef") func globalContextRef() -> UnsafeMutableRawPointer { UnsafeMutableRawPointer(state.ref) }
    @ObjCMethod("virtualMachine") func virtualMachine() -> UnsafeMutableRawPointer { state.machine }

    @ObjCMethod("evaluateScript:")
    func evaluate(_ script: String) -> UnsafeMutableRawPointer? { evaluate(script, sourceURL: nil) }

    @ObjCMethod("evaluateScript:withSourceURL:")
    func evaluate(_ script: String, sourceURL: NSObject?) -> UnsafeMutableRawPointer? {
        let source = Bridge.jsString(script)
        defer { JSStringRelease(source) }
        let url = sourceURL.map { Bridge.jsString($0.describedByObject() ?? "") }
        defer { url.map(JSStringRelease) }
        var exception: JSValueRef?
        let result = JSEvaluateScript(state.ref, source, nil, url, 1, &exception)
        if let exception {
            Contexts.report(objcObject, exception)
            return JSValues.make(JSValueMakeUndefined(state.ref), in: objcObject)
        }
        return JSValues.make(result, in: objcObject)
    }

    @ObjCMethod("globalObject")
    func globalObject() -> UnsafeMutableRawPointer? { JSValues.make(JSContextGetGlobalObject(state.ref), in: objcObject) }

    @ObjCMethod("exception") func exception() -> UnsafeMutableRawPointer? { state.exception?.object }

    @ObjCMethod("setException:")
    func setException(_ value: NSObject?) { state.exception = value.flatMap { JSValues.state($0.objcObject) } }

    @ObjCMethod("exceptionHandler") func exceptionHandler() -> ObjCBlock? { state.handler }
    @ObjCMethod("setExceptionHandler:") func setExceptionHandler(_ handler: ObjCBlock?) { state.handler = handler }

    @ObjCMethod("name") func name() -> String? { state.name }

    @ObjCMethod("setName:")
    func setName(_ name: String?) {
        state.name = name
        let text = name.map(Bridge.jsString)
        JSGlobalContextSetName(state.ref, text)
        text.map(JSStringRelease)
    }

    @ObjCMethod("objectForKeyedSubscript:")
    func object(forKeyedSubscript key: NSObject) -> UnsafeMutableRawPointer? {
        let global = JSContextGetGlobalObject(state.ref)!
        return JSValues.make(Bridge.property(state.ref, global, key.describedByObject() ?? ""), in: objcObject)
    }

    @ObjCMethod("setObject:forKeyedSubscript:")
    func setObject(_ object: NSObject?, forKeyedSubscript key: NSObject) {
        let global = JSContextGetGlobalObject(state.ref)!
        Bridge.setProperty(state.ref, global, key.describedByObject() ?? "", Bridge.value(object?.objcObject, state.ref))
    }

    // The callback running now.

    @ObjCClassMethod("currentContext")
    static func currentContext() -> UnsafeMutableRawPointer? { Callbacks.stack.last?.context }

    @ObjCClassMethod("currentThis")
    static func currentThis() -> UnsafeMutableRawPointer? {
        guard let frame = Callbacks.stack.last else { return nil }
        return JSValues.make(frame.this ?? JSValueMakeUndefined(frame.contextRef), in: frame.context)
    }

    @ObjCClassMethod("currentCallee")
    static func currentCallee() -> UnsafeMutableRawPointer? {
        guard let frame = Callbacks.stack.last else { return nil }
        return JSValues.make(frame.callee, in: frame.context)
    }

    @ObjCClassMethod("currentArguments")
    static func currentArguments() -> UnsafeMutableRawPointer? {
        guard let frame = Callbacks.stack.last else { return nil }
        let array = NSMutableArray.empty()
        for argument in frame.arguments { array.add(NSObject(JSValues.make(argument, in: frame.context)!)) }
        return array.objCReturnValue()
    }
}

// MARK: - Values

final class ValueState: @unchecked Sendable {
    /// The JSValue object, unretained: the state lives as long as it.
    let object: Ref
    let context: Ref
    let ref: JSValueRef

    init(object: Ref, context: Ref, ref: JSValueRef) {
        self.object = object
        self.context = ObjCRuntime.retain(context)!
        self.ref = ref
        if let global = Contexts.ref(context) { JSValueProtect(global, ref) }
    }

    deinit {
        if let global = Contexts.ref(context) { JSValueUnprotect(global, ref) }
        ObjCRuntime.release(context)
    }

    var global: JSGlobalContextRef { Contexts.ref(context)! }
}

enum JSValues {
    static let states = StateTable<ValueState>()

    static func state(_ value: Ref?) -> ValueState? { states[value] }

    /// A new JSValue (+0) for the value in the context.
    static func make(_ ref: JSValueRef?, in context: Ref) -> Ref? {
        guard let global = Contexts.ref(context) else { return nil }
        let value = JSValue.objCClass.autoreleasedInstance().objcObject
        states.set(value, ValueState(object: value, context: context, ref: ref ?? JSValueMakeUndefined(global)))
        return value
    }
}

@ObjCClass("JSValue")
public final class JSValue: NSObject {
    var state: ValueState { JSValues.state(objcObject)! }
    var global: JSGlobalContextRef { state.global }
    var objectRef: JSObjectRef? { JSValueIsObject(global, state.ref) ? JSValueToObject(global, state.ref, nil) : nil }

    @ObjCMethod("dealloc")
    func dealloc() {
        JSValues.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: JSValue.objCClass.pointer)
    }

    func make(_ ref: JSValueRef?) -> UnsafeMutableRawPointer? { JSValues.make(ref, in: state.context) }

    /// Runs a call that may throw, reporting the exception.
    func checked(_ body: (UnsafeMutablePointer<JSValueRef?>) -> JSValueRef?) -> UnsafeMutableRawPointer? {
        var exception: JSValueRef?
        let result = body(&exception)
        if let exception {
            Contexts.report(state.context, exception)
            return make(JSValueMakeUndefined(global))
        }
        return make(result)
    }

    // MARK: Making values

    static func inContext(_ context: NSObject, _ make: (JSGlobalContextRef) -> JSValueRef?) -> UnsafeMutableRawPointer? {
        guard let global = Contexts.ref(context.objcObject) else { return nil }
        return JSValues.make(make(global), in: context.objcObject)
    }

    @ObjCClassMethod("valueWithObject:inContext:")
    static func value(object: NSObject?, inContext context: NSObject) -> UnsafeMutableRawPointer? {
        inContext(context) { Bridge.value(object?.objcObject, $0) }
    }

    @ObjCClassMethod("valueWithBool:inContext:")
    static func value(bool: Bool, inContext context: NSObject) -> UnsafeMutableRawPointer? { inContext(context) { JSValueMakeBoolean($0, bool) } }

    @ObjCClassMethod("valueWithDouble:inContext:")
    static func value(double: Double, inContext context: NSObject) -> UnsafeMutableRawPointer? { inContext(context) { JSValueMakeNumber($0, double) } }

    @ObjCClassMethod("valueWithInt32:inContext:")
    static func value(int32: Int32, inContext context: NSObject) -> UnsafeMutableRawPointer? { inContext(context) { JSValueMakeNumber($0, Double(int32)) } }

    @ObjCClassMethod("valueWithUInt32:inContext:")
    static func value(uint32: UInt32, inContext context: NSObject) -> UnsafeMutableRawPointer? { inContext(context) { JSValueMakeNumber($0, Double(uint32)) } }

    @ObjCClassMethod("valueWithNewObjectInContext:")
    static func newObject(inContext context: NSObject) -> UnsafeMutableRawPointer? { inContext(context) { JSObjectMake($0, nil, nil) } }

    @ObjCClassMethod("valueWithNewArrayInContext:")
    static func newArray(inContext context: NSObject) -> UnsafeMutableRawPointer? { inContext(context) { JSObjectMakeArray($0, 0, nil, nil) } }

    @ObjCClassMethod("valueWithNullInContext:")
    static func null(inContext context: NSObject) -> UnsafeMutableRawPointer? { inContext(context) { JSValueMakeNull($0) } }

    @ObjCClassMethod("valueWithUndefinedInContext:")
    static func undefined(inContext context: NSObject) -> UnsafeMutableRawPointer? { inContext(context) { JSValueMakeUndefined($0) } }

    @ObjCClassMethod("valueWithNewRegularExpressionFromPattern:flags:inContext:")
    static func regularExpression(pattern: String, flags: String, inContext context: NSObject) -> UnsafeMutableRawPointer? {
        inContext(context) { global in
            let p = Bridge.jsString(pattern), f = Bridge.jsString(flags)
            defer { JSStringRelease(p); JSStringRelease(f) }
            var arguments: [JSValueRef?] = [JSValueMakeString(global, p), JSValueMakeString(global, f)]
            return JSObjectMakeRegExp(global, 2, &arguments, nil)
        }
    }

    @ObjCClassMethod("valueWithNewErrorFromMessage:inContext:")
    static func error(message: String, inContext context: NSObject) -> UnsafeMutableRawPointer? {
        inContext(context) { global in
            let text = Bridge.jsString(message)
            defer { JSStringRelease(text) }
            var arguments: [JSValueRef?] = [JSValueMakeString(global, text)]
            return JSObjectMakeError(global, 1, &arguments, nil)
        }
    }

    @ObjCClassMethod("valueWithJSValueRef:inContext:")
    static func value(ref: UnsafeMutableRawPointer?, inContext context: NSObject) -> UnsafeMutableRawPointer? {
        inContext(context) { _ in ref.map { JSValueRef($0) } }
    }

    @ObjCMethod("context") func context() -> UnsafeMutableRawPointer { state.context }
    @ObjCMethod("JSValueRef") func valueRef() -> UnsafeMutableRawPointer { UnsafeMutableRawPointer(mutating: UnsafeRawPointer(state.ref)) }

    // MARK: Converting

    @ObjCMethod("toObject") func toObject() -> UnsafeMutableRawPointer? { Bridge.object(state.ref, global) }
    @ObjCMethod("toObjectOfClass:") func toObject(ofClass cls: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { toObject() }
    @ObjCMethod("toBool") func toBool() -> Bool { JSValueToBoolean(global, state.ref) }
    @ObjCMethod("toDouble") func toDouble() -> Double { JSValueToNumber(global, state.ref, nil) }
    @ObjCMethod("toInt32") func toInt32() -> Int32 { Bridge.int32(toDouble()) }
    @ObjCMethod("toUInt32") func toUInt32() -> UInt32 { UInt32(bitPattern: Bridge.int32(toDouble())) }
    @ObjCMethod("toNumber") func toNumber() -> UnsafeMutableRawPointer? { NSNumber.make(double: toDouble()).objCReturnValue() }
    @ObjCMethod("toString") func toString() -> String { Bridge.string(global, state.ref) }
    @ObjCMethod("description") func description() -> String { toString() }

    @ObjCMethod("toDate")
    func toDate() -> UnsafeMutableRawPointer? {
        if JSValueIsDate(global, state.ref) { return toObject() }
        return NSDate.make(since1970: toDouble() / 1000).objCReturnValue()
    }

    @ObjCMethod("toArray")
    func toArray() -> UnsafeMutableRawPointer? { JSValueIsArray(global, state.ref) ? toObject() : nil }

    @ObjCMethod("toDictionary")
    func toDictionary() -> UnsafeMutableRawPointer? { JSValueIsObject(global, state.ref) ? toObject() : nil }

    // MARK: Kinds

    @ObjCMethod("isUndefined") func isUndefined() -> Bool { JSValueIsUndefined(global, state.ref) }
    @ObjCMethod("isNull") func isNull() -> Bool { JSValueIsNull(global, state.ref) }
    @ObjCMethod("isBoolean") func isBoolean() -> Bool { JSValueIsBoolean(global, state.ref) }
    @ObjCMethod("isNumber") func isNumber() -> Bool { JSValueIsNumber(global, state.ref) }
    @ObjCMethod("isString") func isString() -> Bool { JSValueIsString(global, state.ref) }
    @ObjCMethod("isObject") func isObject() -> Bool { JSValueIsObject(global, state.ref) }
    @ObjCMethod("isArray") func isArray() -> Bool { JSValueIsArray(global, state.ref) }
    @ObjCMethod("isDate") func isDate() -> Bool { JSValueIsDate(global, state.ref) }
    @ObjCMethod("isSymbol") func isSymbol() -> Bool { JSValueIsSymbol(global, state.ref) }

    @ObjCMethod("isEqualToObject:")
    func isEqual(toObject other: NSObject?) -> Bool { JSValueIsStrictEqual(global, state.ref, Bridge.value(other?.objcObject, global)) }

    @ObjCMethod("isEqualWithTypeCoercionToObject:")
    func isEqualWithTypeCoercion(toObject other: NSObject?) -> Bool { JSValueIsEqual(global, state.ref, Bridge.value(other?.objcObject, global), nil) }

    @ObjCMethod("isInstanceOf:")
    func isInstance(of other: NSObject?) -> Bool {
        guard let constructor = JSValueToObject(global, Bridge.value(other?.objcObject, global), nil) else { return false }
        return JSValueIsInstanceOfConstructor(global, state.ref, constructor, nil)
    }

    // MARK: Calling

    func references(_ arguments: NSArray?) -> [JSValueRef?] { arguments?.elements.map { Bridge.value($0.objcObject, global) } ?? [] }

    @ObjCMethod("callWithArguments:")
    func call(arguments: NSArray?) -> UnsafeMutableRawPointer? {
        guard let function = objectRef, JSObjectIsFunction(global, function) else { return make(JSValueMakeUndefined(global)) }
        var values = references(arguments)
        return checked { JSObjectCallAsFunction(global, function, nil, values.count, &values, $0) }
    }

    @ObjCMethod("constructWithArguments:")
    func construct(arguments: NSArray?) -> UnsafeMutableRawPointer? {
        guard let constructor = objectRef, JSObjectIsConstructor(global, constructor) else { return make(JSValueMakeUndefined(global)) }
        var values = references(arguments)
        return checked { JSObjectCallAsConstructor(global, constructor, values.count, &values, $0) }
    }

    @ObjCMethod("invokeMethod:withArguments:")
    func invoke(method: String, arguments: NSArray?) -> UnsafeMutableRawPointer? {
        guard let object = objectRef, let function = JSValueToObject(global, Bridge.property(global, object, method), nil),
              JSObjectIsFunction(global, function) else { return make(JSValueMakeUndefined(global)) }
        var values = references(arguments)
        return checked { JSObjectCallAsFunction(global, function, object, values.count, &values, $0) }
    }

    // MARK: Properties

    func key(_ property: NSObject) -> String { property.describedByObject() ?? "" }

    @ObjCMethod("valueForProperty:")
    func value(forProperty property: NSObject) -> UnsafeMutableRawPointer? {
        guard let object = objectRef else { return make(JSValueMakeUndefined(global)) }
        return make(Bridge.property(global, object, key(property)))
    }

    @ObjCMethod("setValue:forProperty:")
    func setValue(_ value: NSObject?, forProperty property: NSObject) {
        guard let object = objectRef else { return }
        Bridge.setProperty(global, object, key(property), Bridge.value(value?.objcObject, global))
    }

    @ObjCMethod("deleteProperty:")
    func deleteProperty(_ property: NSObject) -> Bool {
        guard let object = objectRef else { return false }
        let name = Bridge.jsString(key(property))
        defer { JSStringRelease(name) }
        return JSObjectDeleteProperty(global, object, name, nil)
    }

    @ObjCMethod("hasProperty:")
    func hasProperty(_ property: NSObject) -> Bool {
        guard let object = objectRef else { return false }
        let name = Bridge.jsString(key(property))
        defer { JSStringRelease(name) }
        return JSObjectHasProperty(global, object, name)
    }

    @ObjCMethod("defineProperty:descriptor:")
    func defineProperty(_ property: NSObject, descriptor: NSObject?) {
        guard let object = objectRef, let global = Optional(global),
              let objectConstructor = JSValueToObject(global, Bridge.property(global, JSContextGetGlobalObject(global)!, "Object"), nil),
              let define = JSValueToObject(global, Bridge.property(global, objectConstructor, "defineProperty"), nil) else { return }
        let name = Bridge.jsString(key(property))
        defer { JSStringRelease(name) }
        var arguments: [JSValueRef?] = [object, JSValueMakeString(global, name), Bridge.value(descriptor?.objcObject, global)]
        _ = JSObjectCallAsFunction(global, define, objectConstructor, 3, &arguments, nil)
    }

    @ObjCMethod("valueAtIndex:")
    func value(atIndex index: UInt) -> UnsafeMutableRawPointer? {
        guard let object = objectRef else { return make(JSValueMakeUndefined(global)) }
        return make(JSObjectGetPropertyAtIndex(global, object, UInt32(index), nil))
    }

    @ObjCMethod("setValue:atIndex:")
    func setValue(_ value: NSObject?, atIndex index: UInt) {
        guard let object = objectRef else { return }
        JSObjectSetPropertyAtIndex(global, object, UInt32(index), Bridge.value(value?.objcObject, global), nil)
    }

    @ObjCMethod("objectForKeyedSubscript:")
    func object(forKeyedSubscript key: NSObject) -> UnsafeMutableRawPointer? { value(forProperty: key) }

    @ObjCMethod("setObject:forKeyedSubscript:")
    func setObject(_ object: NSObject?, forKeyedSubscript key: NSObject) { setValue(object, forProperty: key) }

    @ObjCMethod("objectAtIndexedSubscript:")
    func object(atIndexedSubscript index: UInt) -> UnsafeMutableRawPointer? { value(atIndex: index) }

    @ObjCMethod("setObject:atIndexedSubscript:")
    func setObject(_ object: NSObject?, atIndexedSubscript index: UInt) { setValue(object, atIndex: index) }
}

// MARK: - Managed values

final class ManagedState: @unchecked Sendable {
    let value: Ref?
    init(_ value: Ref?) { self.value = value.flatMap { ObjCRuntime.retain($0) } }
    deinit { ObjCRuntime.release(value) }
}

@ObjCClass("JSManagedValue")
public final class JSManagedValue: NSObject {
    static let states = StateTable<ManagedState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        JSManagedValue.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: JSManagedValue.objCClass.pointer)
    }

    @ObjCClassMethod("managedValueWithValue:")
    static func managed(value: NSObject?) -> UnsafeMutableRawPointer? {
        let object = objCClass.autoreleasedInstance().objcObject
        states.set(object, ManagedState(value?.objcObject))
        return object
    }

    @ObjCClassMethod("managedValueWithValue:andOwner:")
    static func managed(value: NSObject?, owner: NSObject?) -> UnsafeMutableRawPointer? { managed(value: value) }

    @ObjCMethod("initWithValue:")
    func initialize(value: NSObject?) -> Self {
        JSManagedValue.states.set(objcObject, ManagedState(value?.objcObject))
        return self
    }

    @ObjCMethod("value") func value() -> UnsafeMutableRawPointer? { JSManagedValue.states[objcObject]?.value }
}
