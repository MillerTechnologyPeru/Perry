#if arch(powerpc)
import CPerryObjC
import Glibc

/// Messages across Darwin's ppc ABI and Linux's, through the loader's
/// translation by type encoding (ppc_abi.c): a provider's method is added
/// as its Darwin entry, which takes Darwin's arguments and calls it with
/// Linux's, and a provider's sends go through the loader's sends, which call
/// the method as Darwin code would. Both directions agree, so a provider's
/// send to another provider's method arrives as it left.
enum PPCABI {
    private typealias DarwinEntry = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
    private typealias SetLookup = @convention(c) (
        @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                        UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> UnsafeMutableRawPointer?) -> Void

    // The loader's, which perry exports: RTLD_DEFAULT finds them.
    private static func loader(_ name: String) -> UnsafeMutableRawPointer? { dlsym(nil, name) }

    nonisolated(unsafe) private static let darwinEntry: DarwinEntry? =
        loader("perry_ppc_darwin_entry").map { unsafeBitCast($0, to: DarwinEntry.self) }

    /// The sends providers use, in place of objc_msgSend and its forms.
    nonisolated(unsafe) static let send = UnsafeRawPointer(loader("perry_ppc_send"))
    nonisolated(unsafe) static let sendStret = UnsafeRawPointer(loader("perry_ppc_send_stret"))
    nonisolated(unsafe) static let sendSuper2 = UnsafeRawPointer(loader("perry_ppc_send_super2"))
    nonisolated(unsafe) static let sendSuper2Stret = UnsafeRawPointer(loader("perry_ppc_send_super2_stret"))

    /// What Darwin code calls for `imp`: itself when it is Darwin code, and
    /// for Linux code an entry that sets r2 and moves the arguments.
    static func darwinCallable(_ imp: IMP?, types: UnsafePointer<CChar>?) -> IMP? {
        guard let imp, let types, let darwinEntry else { return imp }
        return darwinEntry(imp, types)
    }

    /// Gives the loader's sends the runtime's lookup.
    static func install() {
        guard let set = loader("perry_ppc_set_method_lookup") else { return }
        unsafeBitCast(set, to: SetLookup.self)(lookUp)
    }

    private static let lookUp: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                                UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> UnsafeMutableRawPointer? = {
        receiver, selector, start, types in
        guard let receiver, let selector else { return nil }
        let sel = selector.assumingMemoryBound(to: CChar.self)
        let cls = start.map { $0.assumingMemoryBound(to: perry_objc_class.self) } ?? classOf(receiver)
        let imp = Runtime.lookUpIMP(receiver: receiver, selector: sel, cls: cls)
        if let info = Runtime.info(cls), let method = Runtime.findMethod(info, sel) {
            types?.pointee = method.pointee.types
        }
        return imp
    }
}
#endif
