import CPerryFoundation
import Glibc
import PerryObjCInterop

// NSInvocation: a message as a value, with its arguments in the shape its
// method signature gives them. -invoke places them as x86_64's calling
// convention does; other architectures don't have the call yet.

final class InvocationStorage {
    let signature: id
    /// The target, the selector, then the arguments, as the signature's types.
    var arguments: [[UInt8]]
    var result: [UInt8]
    var retained = false

    init(signature: id, _ details: MethodSignatureStorage) {
        self.signature = ObjC.retain(signature)!
        arguments = details.sizes.dropFirst().map { [UInt8](repeating: 0, count: max($0, 8)) }
        result = [UInt8](repeating: 0, count: max(details.sizes[0], 16))
    }

    deinit { ObjC.release(signature) }

    func object(at index: Int) -> id? {
        arguments[index].withUnsafeBytes { $0.load(as: id?.self) }
    }

    func setObject(_ object: id?, at index: Int) {
        withUnsafeBytes(of: object) { source in
            arguments[index].withUnsafeMutableBytes { $0.copyMemory(from: source) }
        }
    }
}

enum Invocations {
    nonisolated(unsafe) static var invocationClass: Class!
    static func storage(_ object: id?) -> InvocationStorage? { Storage.get(object, as: InvocationStorage.self) }
}

@ObjCClass("NSInvocation")
public final class NSInvocation: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Invocations.invocationClass = cls.storage
    }

    private var storage: InvocationStorage? { Invocations.storage(objcObject) }

    @ObjCClassMethod("invocationWithMethodSignature:")
    static func invocation(signature: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let signature, let details = MethodSignatures.storage(signature) else {
            foundationFatal("+[NSInvocation invocationWithMethodSignature:]: method signature argument cannot be nil")
        }
        let object = Storage.allocate(UnsafeMutableRawPointer(Invocations.invocationClass))!
        Storage.set(object, InvocationStorage(signature: signature, details))
        return ObjC.autorelease(object)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        if let storage, storage.retained { releaseArguments(storage) }
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Invocations.invocationClass)
    }

    private func isObject(_ storage: InvocationStorage, _ index: Int) -> Bool {
        guard let details = MethodSignatures.storage(storage.signature) else { return false }
        let type = String(cString: details.parts[index + 1]).drop { "rnNoORVAj".contains($0) }
        return type.first == "@" && !type.hasPrefix("@?")
    }

    private func releaseArguments(_ storage: InvocationStorage) {
        for index in storage.arguments.indices where isObject(storage, index) {
            if let object = storage.object(at: index) { ObjC.release(object) }
        }
    }

    @ObjCMethod("methodSignature") func methodSignature() -> UnsafeMutableRawPointer? { storage?.signature }

    @ObjCMethod("target") func target() -> UnsafeMutableRawPointer? { storage?.object(at: 0) }

    @ObjCMethod("setTarget:")
    func setTarget(_ target: UnsafeMutableRawPointer?) {
        guard let storage else { return }
        setArgument(storage, at: 0, target)
    }

    @ObjCMethod("selector") func selector() -> ObjCSelector? { storage?.object(at: 1).map { ObjCSelector(UnsafeRawPointer($0)) } }

    @ObjCMethod("setSelector:")
    func setSelector(_ selector: ObjCSelector?) {
        storage?.setObject(selector.map { UnsafeMutableRawPointer(mutating: $0.pointer) }, at: 1)
    }

    private func setArgument(_ storage: InvocationStorage, at index: Int, _ object: id?) {
        if storage.retained, isObject(storage, index) {
            if let object { _ = ObjC.retain(object) }
            if let old = storage.object(at: index) { ObjC.release(old) }
        }
        storage.setObject(object, at: index)
    }

    private func checked(_ index: Int) -> InvocationStorage {
        guard let storage, storage.arguments.indices.contains(index) else {
            foundationFatal("-[NSInvocation setArgument:atIndex:]: index (\(index)) out of bounds")
        }
        return storage
    }

    @ObjCMethod("getArgument:atIndex:")
    func getArgument(_ buffer: UnsafeMutableRawPointer?, at index: Int) {
        let storage = checked(index)
        guard let buffer, let details = MethodSignatures.storage(storage.signature) else { return }
        storage.arguments[index].withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: details.sizes[index + 1]) }
    }

    @ObjCMethod("setArgument:atIndex:")
    func setArgument(_ buffer: UnsafeRawPointer?, at index: Int) {
        let storage = checked(index)
        guard let buffer, let details = MethodSignatures.storage(storage.signature) else { return }
        if isObject(storage, index) {
            setArgument(storage, at: index, UnsafeMutableRawPointer(bitPattern: buffer.load(as: UInt.self)))
            return
        }
        storage.arguments[index].withUnsafeMutableBytes { $0.baseAddress!.copyMemory(from: buffer, byteCount: details.sizes[index + 1]) }
    }

    @ObjCMethod("getReturnValue:")
    func getReturnValue(_ buffer: UnsafeMutableRawPointer?) {
        guard let storage, let buffer, let details = MethodSignatures.storage(storage.signature) else { return }
        storage.result.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: details.sizes[0]) }
    }

    @ObjCMethod("setReturnValue:")
    func setReturnValue(_ buffer: UnsafeRawPointer?) {
        guard let storage, let buffer, let details = MethodSignatures.storage(storage.signature) else { return }
        storage.result.withUnsafeMutableBytes { $0.baseAddress!.copyMemory(from: buffer, byteCount: details.sizes[0]) }
    }

    @ObjCMethod("argumentsRetained") func argumentsRetained() -> Bool { storage?.retained ?? false }

    @ObjCMethod("retainArguments")
    func retainArguments() {
        guard let storage, !storage.retained else { return }
        storage.retained = true
        for index in storage.arguments.indices where isObject(storage, index) {
            if let object = storage.object(at: index) { _ = ObjC.retain(object) }
        }
    }

    @ObjCMethod("invokeWithTarget:")
    func invoke(target: UnsafeMutableRawPointer?) {
        setTarget(target)
        invoke()
    }

    @ObjCMethod("invoke")
    func invoke() {
        guard let storage, let details = MethodSignatures.storage(storage.signature),
              let target = storage.object(at: 0), let selector = storage.object(at: 1) else { return }
        let sel = UnsafePointer(selector.assumingMemoryBound(to: CChar.self))
        guard let imp = ObjC.methodImplementation(ObjC.objectGetClass(target), sel) else { return }
        #if arch(x86_64)
        var general = [UInt64](), vector = [UInt64](), stack = [UInt64]()
        let returnSize = details.sizes[0]
        let indirect = returnSize > 16
        for (index, bytes) in storage.arguments.enumerated() {
            let size = details.sizes[index + 1]
            let words = (0..<(max(size, 1) + 7) / 8).map { word -> UInt64 in
                var value: UInt64 = 0
                withUnsafeMutableBytes(of: &value) { target in
                    let count = min(8, size - word * 8)
                    if count > 0 { bytes.withUnsafeBytes { target.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0[word * 8..<word * 8 + count])) } }
                }
                return value
            }
            let floating = Structures.floatingMembers(String(cString: details.parts[index + 1])) != nil
            if size > 16 {
                stack += words
            } else if floating, vector.count + words.count <= 8 {
                vector += words
            } else if !floating, general.count + (indirect ? 1 : 0) + words.count <= 6 {
                general += words
            } else {
                stack += words
            }
        }
        var out = [UInt64](repeating: 0, count: 4)
        storage.result.withUnsafeMutableBytes { result in
            if indirect { general.insert(UInt64(UInt(bitPattern: result.baseAddress)), at: 0) }
            general += [UInt64](repeating: 0, count: 6 - general.count)
            vector += [UInt64](repeating: 0, count: 8 - vector.count)
            perry_foundation_invoke(imp, general, vector, stack, stack.count, &out)
            guard !indirect, returnSize > 0 else { return }
            let first = Structures.floatingMembers(String(cString: details.parts[0])) != nil ? 2 : 0
            withUnsafeBytes(of: (out[first], out[first + 1])) { source in
                result.copyMemory(from: UnsafeRawBufferPointer(rebasing: source[0..<min(returnSize, 16)]))
            }
        }
        #else
        foundationFatal("-[NSInvocation invoke] is available on x86_64 only")
        #endif
    }
}

/// Zones are gone from Darwin too: every allocation comes from the one heap.
@c(_NSDefaultMallocZone)
public func NSDefaultMallocZone() -> UnsafeMutableRawPointer? { nil }
