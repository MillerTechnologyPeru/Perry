// SafariServices' Swift API: whether the Safari Services framework of a
// given version is present. The framework publishes two data symbols for
// this, which its header keeps from Swift: _SFSafariServicesAvailable,
// which exists when the framework does, and _SFSafariServicesVersion, the
// framework's version. Both are weak imports in the header, so they are
// looked up by name rather than linked: a runtime without them answers
// that Safari Services is not available.

import Darwin

/// The address of a data symbol of the process, or nil without one.
private func address(of symbol: String) -> UnsafeMutableRawPointer? {
    // RTLD_DEFAULT: every image of the process.
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol)
}

/// Whether Safari Services of at least the version given is available.
@available(macOS 10.11, *)
public func SFSafariServicesAvailable(_ version: SFSafariServicesVersion = SFSafariServicesVersion.version10_0) -> Bool {
    guard address(of: "_SFSafariServicesAvailable") != nil,
          let current = address(of: "_SFSafariServicesVersion") else {
        return false
    }
    return current.load(as: SFSafariServicesVersion.RawValue.self) >= version.rawValue
}
