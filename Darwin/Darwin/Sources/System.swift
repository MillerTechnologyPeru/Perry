import _DarwinFoundation2._stdio
import _DarwinFoundation3._signal
import _DarwinFoundation3.unistd

// The C library's variadic functions in fixed forms, its streams and
// environment, and the macros the import of the headers can't give Swift:
// file modes, signal handlers and failure values.
//
// A variadic C function is reached here through a prototype of its own
// that takes the extra argument as a fixed one, which the x86_64 calling
// convention passes the same way.

// MARK: Files

@_silgen_name("open")
private func c_open(_ path: UnsafePointer<CChar>, _ oflag: Int32, _ mode: UInt32) -> Int32

@_silgen_name("openat")
private func c_openat(_ fd: Int32, _ path: UnsafePointer<CChar>, _ oflag: Int32, _ mode: UInt32) -> Int32

@_silgen_name("fcntl")
private func c_fcntl(_ fd: Int32, _ cmd: Int32, _ value: Int) -> Int32

@_silgen_name("ioctl")
private func c_ioctl(_ fd: Int32, _ request: UInt, _ value: Int) -> Int32

public func open(_ path: UnsafePointer<CChar>, _ oflag: Int32) -> Int32 {
    c_open(path, oflag, 0)
}

public func open(_ path: UnsafePointer<CChar>, _ oflag: Int32, _ mode: mode_t) -> Int32 {
    c_open(path, oflag, UInt32(mode))
}

public func openat(_ fd: Int32, _ path: UnsafePointer<CChar>, _ oflag: Int32) -> Int32 {
    c_openat(fd, path, oflag, 0)
}

public func openat(_ fd: Int32, _ path: UnsafePointer<CChar>, _ oflag: Int32, _ mode: mode_t) -> Int32 {
    c_openat(fd, path, oflag, UInt32(mode))
}

public func fcntl(_ fd: Int32, _ cmd: Int32) -> Int32 {
    c_fcntl(fd, cmd, 0)
}

public func fcntl(_ fd: Int32, _ cmd: Int32, _ value: Int32) -> Int32 {
    c_fcntl(fd, cmd, Int(value))
}

public func fcntl(_ fd: Int32, _ cmd: Int32, _ ptr: UnsafeMutableRawPointer) -> Int32 {
    c_fcntl(fd, cmd, Int(bitPattern: ptr))
}

public func ioctl(_ fd: CInt, _ request: UInt, _ value: CInt) -> CInt {
    c_ioctl(fd, request, Int(value))
}

public func ioctl(_ fd: CInt, _ request: UInt, _ ptr: UnsafeMutableRawPointer) -> CInt {
    c_ioctl(fd, request, Int(bitPattern: ptr))
}

public func ioctl(_ fd: CInt, _ request: UInt) -> CInt {
    c_ioctl(fd, request, 0)
}

// MARK: Semaphores and mappings

public typealias Semaphore = UnsafeMutablePointer<sem_t>

@_silgen_name("sem_open")
private func c_sem_open(_ name: UnsafePointer<CChar>, _ oflag: Int32, _ mode: UInt32, _ value: UInt32) -> Semaphore?

/// SEM_FAILED, the address -1.
public var SEM_FAILED: Semaphore? {
    Semaphore(bitPattern: -1)
}

public func sem_open(_ name: UnsafePointer<CChar>, _ oflag: Int32) -> Semaphore? {
    c_sem_open(name, oflag, 0, 0)
}

public func sem_open(_ name: UnsafePointer<CChar>, _ oflag: Int32, _ mode: mode_t, _ value: CUnsignedInt) -> Semaphore? {
    c_sem_open(name, oflag, UInt32(mode), value)
}

/// MAP_FAILED, the address -1.
public var MAP_FAILED: UnsafeMutableRawPointer! {
    UnsafeMutableRawPointer(bitPattern: -1)
}

// MARK: Streams and formatting

public var stdin: UnsafeMutablePointer<FILE> {
    get { __stdinp }
    set { __stdinp = newValue }
}

public var stdout: UnsafeMutablePointer<FILE> {
    get { __stdoutp }
    set { __stdoutp = newValue }
}

public var stderr: UnsafeMutablePointer<FILE> {
    get { __stderrp }
    set { __stderrp = newValue }
}

public func dprintf(_ fd: Int, _ format: UnsafePointer<Int8>, _ args: any CVarArg...) -> Int32 {
    withVaList(args) { vdprintf(Int32(fd), format, $0) }
}

public func snprintf(ptr: UnsafeMutablePointer<Int8>, _ len: Int, _ format: UnsafePointer<Int8>, _ args: any CVarArg...) -> Int32 {
    withVaList(args) { vsnprintf(ptr, len, format, $0) }
}

// MARK: Processes

@_silgen_name("_NSGetEnviron")
private func environLocation() -> UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>>

/// The process's environment, which _NSGetEnviron() points to.
public var environ: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
    environLocation().pointee
}

@_silgen_name("fork")
private func c_fork() -> Int32

@_silgen_name("vfork")
private func c_vfork() -> Int32

// Swift marks these unavailable in programs (a forked child can't run
// Swift code safely); they still do what they say.
public func fork() -> Int32 {
    c_fork()
}

public func vfork() -> Int32 {
    c_vfork()
}

// MARK: Signals

public var SIG_DFL: sig_t? {
    nil
}

public var SIG_IGN: sig_t {
    unsafeBitCast(1 as Int, to: sig_t.self)
}

public var SIG_ERR: sig_t {
    unsafeBitCast(-1 as Int, to: sig_t.self)
}

public var SIG_HOLD: sig_t {
    unsafeBitCast(5 as Int, to: sig_t.self)
}

// MARK: File modes

public var S_IFMT: mode_t { 0o170000 }
public var S_IFIFO: mode_t { 0o010000 }
public var S_IFCHR: mode_t { 0o020000 }
public var S_IFDIR: mode_t { 0o040000 }
public var S_IFBLK: mode_t { 0o060000 }
public var S_IFREG: mode_t { 0o100000 }
public var S_IFLNK: mode_t { 0o120000 }
public var S_IFSOCK: mode_t { 0o140000 }
public var S_IFWHT: mode_t { 0o160000 }

public var S_IRWXU: mode_t { 0o700 }
public var S_IRUSR: mode_t { 0o400 }
public var S_IWUSR: mode_t { 0o200 }
public var S_IXUSR: mode_t { 0o100 }
public var S_IRWXG: mode_t { 0o070 }
public var S_IRGRP: mode_t { 0o040 }
public var S_IWGRP: mode_t { 0o020 }
public var S_IXGRP: mode_t { 0o010 }
public var S_IRWXO: mode_t { 0o007 }
public var S_IROTH: mode_t { 0o004 }
public var S_IWOTH: mode_t { 0o002 }
public var S_IXOTH: mode_t { 0o001 }

public var S_ISUID: mode_t { 0o4000 }
public var S_ISGID: mode_t { 0o2000 }
public var S_ISVTX: mode_t { 0o1000 }
public var S_ISTXT: mode_t { S_ISVTX }
public var S_IREAD: mode_t { S_IRUSR }
public var S_IWRITE: mode_t { S_IWUSR }
public var S_IEXEC: mode_t { S_IXUSR }

// MARK: Processes' start times

extension extern_proc {
    /// The start time, a member of the p_un union.
    @_transparent
    public var p_starttime: timeval {
        get { p_un.__p_starttime }
        set { p_un.__p_starttime = newValue }
    }
}
