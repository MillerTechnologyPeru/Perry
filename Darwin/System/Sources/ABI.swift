// Entry points Apple's System library exports that swift-system's sources
// declare differently today: FileDescriptor's _duplicate(as:retryOnInterrupt:)
// and _read(into:retryOnInterrupt:) as throwing functions returning a
// Result, which inlinable code of System 0.0.2 calls. Each forwards to the
// non-throwing function of the same name, under the throwing one's symbol.

extension FileDescriptor {
    @available(System 0.0.2, *)
    @usableFromInline
    @_silgen_name("$s6System14FileDescriptorV10_duplicate2as16retryOnInterrupts6ResultOyAcA5ErrnoVGACSg_SbtKF")
    internal func _perryThrowingDuplicate(as target: FileDescriptor?, retryOnInterrupt: Bool) throws -> Result<FileDescriptor, Errno> {
        _duplicate(as: target, retryOnInterrupt: retryOnInterrupt)
    }

    @available(System 0.0.1, *)
    @usableFromInline
    @_silgen_name("$s6System14FileDescriptorV5_read4into16retryOnInterrupts6ResultOySiAA5ErrnoVGSw_SbtKF")
    internal func _perryThrowingRead(into buffer: UnsafeMutableRawBufferPointer, retryOnInterrupt: Bool) throws -> Result<Int, Errno> {
        _read(into: buffer, retryOnInterrupt: retryOnInterrupt)
    }
}
