// How an interpolated value is printed and who may see it: the privacy,
// number, alignment, pointer and extended formats of OSLogMessage, and
// the format-string specifiers and argument flags they make.

// MARK: Privacy

@frozen public struct OSLogPrivacy {
    @usableFromInline
    internal enum PrivacyOption {
        case `private`
        case `public`
        case sensitive
        case auto
    }

    /// A redaction applied in place of the value: its hash, or a kind of
    /// Mail data.
    public enum Mask {
        case hash
        case none
        case _mailName
        case _mailAddress
        case _mailSubject
        case _mailSummary
        case _mailAccount
        case _mailbox
        case _mailboxPath
        case _mailAttachmentFileName
    }

    public enum _MailMask {
        case name
        case address
        case subject
        case summary
        case account
        case mailbox
        case mailboxPath
        case attachmentFileName
    }

    @usableFromInline
    internal var privacy: PrivacyOption

    @usableFromInline
    internal var mask: Mask

    @usableFromInline
    internal init(privacy: PrivacyOption, mask: Mask) {
        self.privacy = privacy
        self.mask = mask
    }

    public static var `public`: OSLogPrivacy { OSLogPrivacy(privacy: .public, mask: .none) }
    public static var `private`: OSLogPrivacy { OSLogPrivacy(privacy: .private, mask: .none) }
    public static func `private`(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(privacy: .private, mask: mask) }
    public static var sensitive: OSLogPrivacy { OSLogPrivacy(privacy: .sensitive, mask: .none) }
    public static func sensitive(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(privacy: .sensitive, mask: mask) }
    public static var auto: OSLogPrivacy { OSLogPrivacy(privacy: .auto, mask: .none) }
    public static func auto(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(privacy: .auto, mask: mask) }

    /// Private, masked as the kind of Mail data given.
    public static func mail(_ mask: _MailMask) -> OSLogPrivacy {
        switch mask {
        case .name: return .private(mask: ._mailName)
        case .address: return .private(mask: ._mailAddress)
        case .subject: return .private(mask: ._mailSubject)
        case .summary: return .private(mask: ._mailSummary)
        case .account: return .private(mask: ._mailAccount)
        case .mailbox: return .private(mask: ._mailbox)
        case .mailboxPath: return .private(mask: ._mailboxPath)
        case .attachmentFileName: return .private(mask: ._mailAttachmentFileName)
        }
    }

    /// The low nibble of an argument's descriptor.
    @usableFromInline
    internal var argumentFlag: UInt8 {
        switch privacy {
        case .private: return 0x1
        case .public: return 0x2
        case .sensitive: return 0x5
        case .auto: return 0
        }
    }

    @usableFromInline
    internal var isAtleastPrivate: Bool {
        switch privacy {
        case .public, .auto: return false
        case .private, .sensitive: return true
        }
    }

    /// Whether the specifier names the privacy: an explicit one, or a hash
    /// mask.
    @usableFromInline
    internal var needsPrivacySpecifier: Bool {
        if case .hash = mask { return true }
        if case .auto = privacy { return false }
        return true
    }

    @usableFromInline
    internal var hasMask: Bool {
        if case .none = mask { return false }
        return true
    }

    /// The mask's name, as the little-endian bytes of the mask argument.
    @usableFromInline
    internal var maskValue: UInt64 {
        var value: UInt64 = 0
        for (index, byte) in maskSpecifier.utf8.prefix(8).enumerated() {
            value |= UInt64(byte) << (8 * UInt64(index))
        }
        return value
    }

    /// "public", "private" or "sensitive", with ",mask.<name>" for a mask;
    /// nil for automatic privacy without one.
    @usableFromInline
    internal var privacySpecifier: String? {
        var specifier: String
        switch privacy {
        case .public: specifier = "public"
        case .private: specifier = "private"
        case .sensitive: specifier = "sensitive"
        case .auto:
            guard hasMask else { return nil }
            specifier = ""
        }
        if hasMask {
            if !specifier.isEmpty { specifier += "," }
            specifier += "mask." + maskSpecifier
        }
        return specifier
    }

    @usableFromInline
    internal var maskSpecifier: String {
        switch mask {
        case ._mailName: return "mailname"
        case ._mailAddress: return "mailaddr"
        case ._mailSubject: return "mailsubj"
        case ._mailSummary: return "mailsumm"
        case ._mailAccount: return "mailacco"
        case ._mailbox: return "mailbox"
        case ._mailboxPath: return "mailmbup"
        case ._mailAttachmentFileName: return "mailatta"
        case .hash, .none: return "hash"
        }
    }
}

extension OSLogPrivacy.PrivacyOption: Equatable, Hashable {}
extension OSLogPrivacy.Mask: Equatable, Hashable {}
extension OSLogPrivacy._MailMask: Equatable, Hashable {}

// MARK: Floating-point numbers

@frozen public struct OSLogFloatFormatting {
    @usableFromInline
    internal var explicitPositiveSign: Bool

    @usableFromInline
    internal var uppercase: Bool

    @usableFromInline
    internal var precision: (() -> Int)?

    @usableFromInline
    internal enum Notation {
        case hex
        case fixed
        case exponential
        case hybrid
    }

    @usableFromInline
    internal var notation: Notation

    @usableFromInline
    internal init(explicitPositiveSign: Bool = false, uppercase: Bool = false, precision: (() -> Int)?, notation: Notation) {
        self.explicitPositiveSign = explicitPositiveSign
        self.uppercase = uppercase
        self.precision = precision
        self.notation = notation
    }

    public static var fixed: OSLogFloatFormatting { .fixed() }

    public static func fixed(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false,
                             uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(explicitPositiveSign: explicitPositiveSign, uppercase: uppercase, precision: precision, notation: .fixed)
    }

    public static func fixed(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(explicitPositiveSign: explicitPositiveSign, uppercase: uppercase, precision: nil, notation: .fixed)
    }

    public static var hex: OSLogFloatFormatting { .hex() }

    public static func hex(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(explicitPositiveSign: explicitPositiveSign, uppercase: uppercase, precision: nil, notation: .hex)
    }

    public static var exponential: OSLogFloatFormatting { .exponential() }

    public static func exponential(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false,
                                   uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(explicitPositiveSign: explicitPositiveSign, uppercase: uppercase, precision: precision, notation: .exponential)
    }

    public static func exponential(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(explicitPositiveSign: explicitPositiveSign, uppercase: uppercase, precision: nil, notation: .exponential)
    }

    public static var hybrid: OSLogFloatFormatting { .hybrid() }

    public static func hybrid(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false,
                              uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(explicitPositiveSign: explicitPositiveSign, uppercase: uppercase, precision: precision, notation: .hybrid)
    }

    public static func hybrid(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(explicitPositiveSign: explicitPositiveSign, uppercase: uppercase, precision: nil, notation: .hybrid)
    }
}

extension OSLogFloatFormatting.Notation: Equatable, Hashable {}

// MARK: Integers

@frozen public struct OSLogIntegerFormatting {
    @usableFromInline
    internal var radix: Int

    @usableFromInline
    internal var explicitPositiveSign: Bool

    @usableFromInline
    internal var includePrefix: Bool

    @usableFromInline
    internal var uppercase: Bool

    @usableFromInline
    internal var minDigits: (() -> Int)?

    @usableFromInline
    internal init(radix: Int = 10, explicitPositiveSign: Bool = false, includePrefix: Bool = false,
                  uppercase: Bool = false, minDigits: (() -> Int)?) {
        self.radix = radix
        self.explicitPositiveSign = explicitPositiveSign
        self.includePrefix = includePrefix
        self.uppercase = uppercase
        self.minDigits = minDigits
    }

    public static func decimal(explicitPositiveSign: Bool = false, minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 10, explicitPositiveSign: explicitPositiveSign, minDigits: minDigits)
    }

    public static func decimal(explicitPositiveSign: Bool = false) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 10, explicitPositiveSign: explicitPositiveSign, minDigits: nil)
    }

    public static var decimal: OSLogIntegerFormatting { .decimal() }

    public static func hex(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false,
                           minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 16, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix,
                               uppercase: uppercase, minDigits: minDigits)
    }

    public static func hex(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 16, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix,
                               uppercase: uppercase, minDigits: nil)
    }

    public static var hex: OSLogIntegerFormatting { .hex() }

    public static func octal(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false,
                             minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 8, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix,
                               uppercase: uppercase, minDigits: minDigits)
    }

    public static func octal(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: 8, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix,
                               uppercase: uppercase, minDigits: nil)
    }

    public static var octal: OSLogIntegerFormatting { .octal() }
}

// MARK: Alignment

@usableFromInline
internal enum OSLogCollectionBound {
    case start
    case end
}

extension OSLogCollectionBound: Equatable, Hashable {}

@frozen public struct OSLogStringAlignment {
    @usableFromInline
    internal var minimumColumnWidth: (() -> Int)?

    @usableFromInline
    internal var anchor: OSLogCollectionBound

    @usableFromInline
    internal init(minimumColumnWidth: (() -> Int)? = nil, anchor: OSLogCollectionBound = .end) {
        self.minimumColumnWidth = minimumColumnWidth
        self.anchor = anchor
    }

    public static var none: OSLogStringAlignment { OSLogStringAlignment(anchor: .end) }

    /// Padded on the left to the width.
    public static func right(columns: @autoclosure @escaping () -> Int) -> OSLogStringAlignment {
        OSLogStringAlignment(minimumColumnWidth: columns, anchor: .end)
    }

    /// Padded on the right to the width.
    public static func left(columns: @autoclosure @escaping () -> Int) -> OSLogStringAlignment {
        OSLogStringAlignment(minimumColumnWidth: columns, anchor: .start)
    }
}

// MARK: Other formats

public enum OSLogPointerFormat {
    case ipv6Address
    case timeval
    case timespec
    case uuid
    case sockaddr
    case none
}

extension OSLogPointerFormat: Equatable, Hashable {}

public enum OSLogBoolFormat {
    case truth
    case answer
}

extension OSLogBoolFormat: Equatable, Hashable {}

public enum OSLogInt32ExtendedFormat {
    case ipv4Address
    case secondsSince1970
    case darwinErrno
    case darwinMode
    case darwinSignal
    case machErrno
    case bitrate
    case bitrateIEC
    case byteCount
    case byteCountIEC
    case truth
    case answer

    /// The value type os_log decodes the argument as.
    internal var tag: String {
        switch self {
        case .ipv4Address: return "network:in_addr"
        case .secondsSince1970: return "time_t"
        case .darwinErrno: return "darwin.errno"
        case .darwinMode: return "darwin.mode"
        case .darwinSignal: return "darwin.signal"
        case .machErrno: return "mach.errno"
        case .bitrate: return "bitrate"
        case .bitrateIEC: return "iec-bitrate"
        case .byteCount: return "bytes"
        case .byteCountIEC: return "iec-bytes"
        case .truth: return "bool"
        case .answer: return "BOOL"
        }
    }
}

extension OSLogInt32ExtendedFormat: Equatable, Hashable {}

public enum OSLogIntExtendedFormat {
    case bitrate
    case bitrateIEC
    case byteCount
    case byteCountIEC
    case secondsSince1970

    /// The value type os_log decodes the argument as.
    @_alwaysEmitIntoClient
    internal var tag: String {
        switch self {
        case .bitrate: return "bitrate"
        case .bitrateIEC: return "iec-bitrate"
        case .byteCount: return "bytes"
        case .byteCountIEC: return "iec-bytes"
        case .secondsSince1970: return "time_t"
        @unknown default: return ""
        }
    }
}

extension OSLogIntExtendedFormat: Equatable, Hashable {}

/// What a metric's value does, which the metric types' inlined methods
/// pass on.
@usableFromInline
internal enum OSMetricOperation {
    case add
    case subtract
    case set
    case reset
}

extension OSMetricOperation: Equatable, Hashable {}
