import CPerryObjC
import PerryInterface
import PerryObjCRuntime

// libPerryobjc: the provider for /usr/lib/libobjc.A.dylib.

private let libSystem = "/usr/lib/libSystem.B.dylib"

/// Called by the loader after every image is bound and before any
/// initializer runs.
@c
public func perry_provider_startup(_ info: UnsafePointer<perry_startup_info>?) {
    RootClasses.bootstrap()
    guard let info, info.pointee.version >= 2, let lookup = info.pointee.lookup_symbol else { return }

    func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        libSystem.withCString { library in name.withCString { lookup(library, $0) } }
    }

    // Blocks are objects: build their classes in libSystem's storage.
    BlockClasses.install(
        .init(stack: symbol("__NSConcreteStackBlock"), malloc: symbol("__NSConcreteMallocBlock"),
              global: symbol("__NSConcreteGlobalBlock"), auto: symbol("__NSConcreteAutoBlock"),
              finalizing: symbol("__NSConcreteFinalizingBlock"),
              weakVariable: symbol("__NSConcreteWeakBlockVariable")),
        copy: symbol("__Block_copy"), release: symbol("__Block_release"))

    ThrowTrace.install(lookup)

    // Objects captured by blocks are retained through this runtime.
    if let useRR2 = symbol("__Block_use_RR2") {
        typealias UseRR2 = @convention(c) (UnsafePointer<perry_block_callbacks>) -> Void
        var callbacks = perry_block_callbacks(
            size: MemoryLayout<perry_block_callbacks>.size,
            retain: { object in
                if let object { _ = Objects.retain(UnsafeMutableRawPointer(mutating: object)) }
            },
            release: { object in
                if let object { Objects.release(UnsafeMutableRawPointer(mutating: object)) }
            },
            destruct_instance: { object in
                if let object { Objects.destructInstance(UnsafeMutableRawPointer(mutating: object)) }
            })
        unsafeBitCast(useRR2, to: UseRR2.self)(&callbacks)
    }
}

/// Called for each Mach-O image just before its initializers run.
@c
public func perry_provider_image_init(_ image: UnsafePointer<perry_image_info>?) {
    guard let image, let header = image.pointee.header else { return }
    RootClasses.bootstrap()
    Runtime.mapImage(header: header, slide: image.pointee.slide, path: image.pointee.path)
}

// MARK: - objc_msgSend's slow paths

@c @implementation
public func perry_objc_lookup_slow(_ receiver: UnsafeMutableRawPointer?, _ sel: UnsafeRawPointer?,
                                   _ cls: UnsafeMutablePointer<perry_objc_class>?) -> UnsafeMutableRawPointer? {
    guard let sel, let cls else { return Runtime.msgForward }
    return Runtime.lookUpIMP(receiver: receiver, selector: sel.assumingMemoryBound(to: CChar.self), cls: cls)
}

@c @implementation
public func perry_objc_forward(_ receiver: UnsafeMutableRawPointer?, _ sel: UnsafeRawPointer?) -> perry_forward_result {
    guard let sel else { return perry_forward_result(target: nil, handler: nil) }
    let result = Runtime.forward(receiver: receiver, selector: sel.assumingMemoryBound(to: CChar.self))
    if result.target == nil && result.handler == nil {
        // A message to nil reached the forwarder: nothing to do but return.
        objcFatal("message \(String(cString: sel.assumingMemoryBound(to: CChar.self))) could not be forwarded")
    }
    return perry_forward_result(target: result.target, handler: result.handler)
}
