// The terminal ioctl requests of <sys/ttycom.h> and <sys/ioctl_compat.h>,
// function-like macros the import of the headers can't give Swift. Each is
// made as _IO, _IOR and _IOW make it: the direction, the size of the
// argument, the group 't' and the number. The old sgttyb, tchars and
// ltchars structures are six bytes.

private let ioctlVoid: UInt = 0x2000_0000
private let ioctlOut: UInt = 0x4000_0000
private let ioctlIn: UInt = 0x8000_0000

private func ioctlRequest(_ direction: UInt, _ number: UInt, _ size: Int = 0) -> UInt {
    direction | ((UInt(size) & 0x1fff) << 16) | (UInt(UInt8(ascii: "t")) << 8) | number
}

public var TIOCHPCL: UInt { ioctlRequest(ioctlVoid, 2) }
public var TIOCGETP: UInt { ioctlRequest(ioctlOut, 8, 6) }
public var TIOCSETP: UInt { ioctlRequest(ioctlIn, 9, 6) }
public var TIOCSETN: UInt { ioctlRequest(ioctlIn, 10, 6) }
public var TIOCSETC: UInt { ioctlRequest(ioctlIn, 17, 6) }
public var TIOCGETC: UInt { ioctlRequest(ioctlOut, 18, 6) }
public var TIOCLBIS: UInt { ioctlRequest(ioctlIn, 127, MemoryLayout<Int32>.size) }
public var TIOCLBIC: UInt { ioctlRequest(ioctlIn, 126, MemoryLayout<Int32>.size) }
public var TIOCLSET: UInt { ioctlRequest(ioctlIn, 125, MemoryLayout<Int32>.size) }
public var TIOCLGET: UInt { ioctlRequest(ioctlOut, 124, MemoryLayout<Int32>.size) }
public var TIOCSLTC: UInt { ioctlRequest(ioctlIn, 117, 6) }
public var TIOCGLTC: UInt { ioctlRequest(ioctlOut, 116, 6) }
public var TIOCMODG: UInt { ioctlRequest(ioctlOut, 3, MemoryLayout<Int32>.size) }
public var TIOCMODS: UInt { ioctlRequest(ioctlIn, 4, MemoryLayout<Int32>.size) }
public var TIOCEXCL: UInt { ioctlRequest(ioctlVoid, 13) }
public var TIOCNXCL: UInt { ioctlRequest(ioctlVoid, 14) }
public var TIOCFLUSH: UInt { ioctlRequest(ioctlIn, 16, MemoryLayout<Int32>.size) }
public var TIOCGETA: UInt { ioctlRequest(ioctlOut, 19, MemoryLayout<termios>.size) }
public var TIOCSETA: UInt { ioctlRequest(ioctlIn, 20, MemoryLayout<termios>.size) }
public var TIOCSETAW: UInt { ioctlRequest(ioctlIn, 21, MemoryLayout<termios>.size) }
public var TIOCSETAF: UInt { ioctlRequest(ioctlIn, 22, MemoryLayout<termios>.size) }
public var TIOCGETD: UInt { ioctlRequest(ioctlOut, 26, MemoryLayout<Int32>.size) }
public var TIOCSETD: UInt { ioctlRequest(ioctlIn, 27, MemoryLayout<Int32>.size) }
public var TIOCIXON: UInt { ioctlRequest(ioctlVoid, 129) }
public var TIOCIXOFF: UInt { ioctlRequest(ioctlVoid, 128) }
public var TIOCSBRK: UInt { ioctlRequest(ioctlVoid, 123) }
public var TIOCCBRK: UInt { ioctlRequest(ioctlVoid, 122) }
public var TIOCSDTR: UInt { ioctlRequest(ioctlVoid, 121) }
public var TIOCCDTR: UInt { ioctlRequest(ioctlVoid, 120) }
public var TIOCGPGRP: UInt { ioctlRequest(ioctlOut, 119, MemoryLayout<Int32>.size) }
public var TIOCSPGRP: UInt { ioctlRequest(ioctlIn, 118, MemoryLayout<Int32>.size) }
public var TIOCOUTQ: UInt { ioctlRequest(ioctlOut, 115, MemoryLayout<Int32>.size) }
public var TIOCSTI: UInt { ioctlRequest(ioctlIn, 114, 1) }
public var TIOCNOTTY: UInt { ioctlRequest(ioctlVoid, 113) }
public var TIOCPKT: UInt { ioctlRequest(ioctlIn, 112, MemoryLayout<Int32>.size) }
public var TIOCSTOP: UInt { ioctlRequest(ioctlVoid, 111) }
public var TIOCSTART: UInt { ioctlRequest(ioctlVoid, 110) }
public var TIOCMSET: UInt { ioctlRequest(ioctlIn, 109, MemoryLayout<Int32>.size) }
public var TIOCMBIS: UInt { ioctlRequest(ioctlIn, 108, MemoryLayout<Int32>.size) }
public var TIOCMBIC: UInt { ioctlRequest(ioctlIn, 107, MemoryLayout<Int32>.size) }
public var TIOCMGET: UInt { ioctlRequest(ioctlOut, 106, MemoryLayout<Int32>.size) }
public var TIOCREMOTE: UInt { ioctlRequest(ioctlIn, 105, MemoryLayout<Int32>.size) }
public var TIOCGWINSZ: UInt { ioctlRequest(ioctlOut, 104, MemoryLayout<winsize>.size) }
public var TIOCSWINSZ: UInt { ioctlRequest(ioctlIn, 103, MemoryLayout<winsize>.size) }
public var TIOCUCNTL: UInt { ioctlRequest(ioctlIn, 102, MemoryLayout<Int32>.size) }
public var TIOCSTAT: UInt { ioctlRequest(ioctlVoid, 101) }
public var TIOCSCONS: UInt { ioctlRequest(ioctlVoid, 99) }
public var TIOCCONS: UInt { ioctlRequest(ioctlIn, 98, MemoryLayout<Int32>.size) }
public var TIOCSCTTY: UInt { ioctlRequest(ioctlVoid, 97) }
public var TIOCEXT: UInt { ioctlRequest(ioctlIn, 96, MemoryLayout<Int32>.size) }
public var TIOCSIG: UInt { ioctlRequest(ioctlVoid, 95) }
public var TIOCDRAIN: UInt { ioctlRequest(ioctlVoid, 94) }
public var TIOCMSDTRWAIT: UInt { ioctlRequest(ioctlIn, 91, MemoryLayout<Int32>.size) }
public var TIOCMGDTRWAIT: UInt { ioctlRequest(ioctlOut, 90, MemoryLayout<Int32>.size) }
public var TIOCTIMESTAMP: UInt { ioctlRequest(ioctlOut, 89, MemoryLayout<timeval>.size) }
public var TIOCDCDTIMESTAMP: UInt { ioctlRequest(ioctlOut, 88, MemoryLayout<timeval>.size) }
public var TIOCSDRAINWAIT: UInt { ioctlRequest(ioctlIn, 87, MemoryLayout<Int32>.size) }
public var TIOCGDRAINWAIT: UInt { ioctlRequest(ioctlOut, 86, MemoryLayout<Int32>.size) }
public var TIOCDSIMICROCODE: UInt { ioctlRequest(ioctlVoid, 85) }
public var TIOCPTYGRANT: UInt { ioctlRequest(ioctlVoid, 84) }
public var TIOCPTYGNAME: UInt { ioctlRequest(ioctlOut, 83, 128) }
public var TIOCPTYUNLK: UInt { ioctlRequest(ioctlVoid, 82) }
