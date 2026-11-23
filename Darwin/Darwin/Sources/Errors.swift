import _DarwinFoundation1._errno

// The error codes of the C library and of Mach as Swift enumerations,
// and errno. Each case's raw value is the C constant's.

/// An errno value: the codes of <sys/errno.h>.
@objc public enum POSIXErrorCode: Int32, Sendable {
    case EPERM = 1
    case ENOENT = 2
    case ESRCH = 3
    case EINTR = 4
    case EIO = 5
    case ENXIO = 6
    case E2BIG = 7
    case ENOEXEC = 8
    case EBADF = 9
    case ECHILD = 10
    case EDEADLK = 11
    case ENOMEM = 12
    case EACCES = 13
    case EFAULT = 14
    case ENOTBLK = 15
    case EBUSY = 16
    case EEXIST = 17
    case EXDEV = 18
    case ENODEV = 19
    case ENOTDIR = 20
    case EISDIR = 21
    case EINVAL = 22
    case ENFILE = 23
    case EMFILE = 24
    case ENOTTY = 25
    case ETXTBSY = 26
    case EFBIG = 27
    case ENOSPC = 28
    case ESPIPE = 29
    case EROFS = 30
    case EMLINK = 31
    case EPIPE = 32
    case EDOM = 33
    case ERANGE = 34
    case EAGAIN = 35
    case EINPROGRESS = 36
    case EALREADY = 37
    case ENOTSOCK = 38
    case EDESTADDRREQ = 39
    case EMSGSIZE = 40
    case EPROTOTYPE = 41
    case ENOPROTOOPT = 42
    case EPROTONOSUPPORT = 43
    case ESOCKTNOSUPPORT = 44
    case ENOTSUP = 45
    case EPFNOSUPPORT = 46
    case EAFNOSUPPORT = 47
    case EADDRINUSE = 48
    case EADDRNOTAVAIL = 49
    case ENETDOWN = 50
    case ENETUNREACH = 51
    case ENETRESET = 52
    case ECONNABORTED = 53
    case ECONNRESET = 54
    case ENOBUFS = 55
    case EISCONN = 56
    case ENOTCONN = 57
    case ESHUTDOWN = 58
    case ETOOMANYREFS = 59
    case ETIMEDOUT = 60
    case ECONNREFUSED = 61
    case ELOOP = 62
    case ENAMETOOLONG = 63
    case EHOSTDOWN = 64
    case EHOSTUNREACH = 65
    case ENOTEMPTY = 66
    case EPROCLIM = 67
    case EUSERS = 68
    case EDQUOT = 69
    case ESTALE = 70
    case EREMOTE = 71
    case EBADRPC = 72
    case ERPCMISMATCH = 73
    case EPROGUNAVAIL = 74
    case EPROGMISMATCH = 75
    case EPROCUNAVAIL = 76
    case ENOLCK = 77
    case ENOSYS = 78
    case EFTYPE = 79
    case EAUTH = 80
    case ENEEDAUTH = 81
    case EPWROFF = 82
    case EDEVERR = 83
    case EOVERFLOW = 84
    case EBADEXEC = 85
    case EBADARCH = 86
    case ESHLIBVERS = 87
    case EBADMACHO = 88
    case ECANCELED = 89
    case EIDRM = 90
    case ENOMSG = 91
    case EILSEQ = 92
    case ENOATTR = 93
    case EBADMSG = 94
    case EMULTIHOP = 95
    case ENODATA = 96
    case ENOLINK = 97
    case ENOSR = 98
    case ENOSTR = 99
    case EPROTO = 100
    case ETIME = 101
    case _EOPNOTSUPP_UNIX2003 = 102
    case ENOPOLICY = 103
    case ENOTRECOVERABLE = 104
    case EOWNERDEAD = 105
    case EQFULL = 106
    case ENOTCAPABLE = 107

    /// EWOULDBLOCK, which is EAGAIN.
    public static var EWOULDBLOCK: POSIXErrorCode { .EAGAIN }

    /// EOPNOTSUPP, the UNIX 2003 value.
    public static var EOPNOTSUPP: POSIXErrorCode { ._EOPNOTSUPP_UNIX2003 }

    /// ELAST, the largest code.
    public static var ELAST: POSIXErrorCode { .ENOTCAPABLE }
}

extension POSIXErrorCode: Equatable {}
extension POSIXErrorCode: Hashable {}
extension POSIXErrorCode: RawRepresentable {}

/// A kern_return_t: the codes of <mach/kern_return.h>.
@objc public enum MachErrorCode: Int32, Sendable {
    case success = 0
    case invalidAddress = 1
    case protectionFailure = 2
    case noSpace = 3
    case invalidArgument = 4
    case failure = 5
    case resourceShortage = 6
    case notReceiver = 7
    case noAccess = 8
    case memoryFailure = 9
    case memoryError = 10
    case alreadyInSet = 11
    case notInSet = 12
    case nameExists = 13
    case aborted = 14
    case invalidName = 15
    case invalidTask = 16
    case invalidRight = 17
    case invalidValue = 18
    case userReferencesOverflow = 19
    case invalidCapability = 20
    case rightExists = 21
    case invalidHost = 22
    case memoryPresent = 23
    case memoryDataMoved = 24
    case memoryRestartCopy = 25
    case invalidProcessorSet = 26
    case policyLimit = 27
    case invalidPolicy = 28
    case invalidObject = 29
    case alreadyWaiting = 30
    case defaultSet = 31
    case exceptionProtected = 32
    case invalidLedger = 33
    case invalidMemoryControl = 34
    case invalidSecurity = 35
    case notDepressed = 36
    case terminated = 37
    case lockSetDestroyed = 38
    case lockUnstable = 39
    case lockOwned = 40
    case lockOwnedSelf = 41
    case semaphoreDestroyed = 42
    case rpcServerTerminated = 43
    case rpcTerminateOrphan = 44
    case rpcContinueOrphan = 45
    case notSupported = 46
    case nodeDown = 47
    case notWaiting = 48
    case operationTimedOut = 49
    case codesignError = 50
    case policyStatic = 51
}

extension MachErrorCode: Equatable {}
extension MachErrorCode: Hashable {}
extension MachErrorCode: RawRepresentable {}

/// The calling thread's errno, which the C library keeps where
/// __error() points.
public var errno: Int32 {
    get { errnoLocation().pointee }
    set { errnoLocation().pointee = newValue }
}

@_silgen_name("__error")
private func errnoLocation() -> UnsafeMutablePointer<Int32>

/// noErr, the OSStatus of success.
@inlinable
public var noErr: OSStatus {
    0
}
