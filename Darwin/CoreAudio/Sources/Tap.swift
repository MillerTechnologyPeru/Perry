import Foundation

// The audio hardware's API is macOS's alone.
#if os(macOS)

// CATapDescription's initializers and properties with process object IDs
// and the stream index as Swift numbers.

extension CATapDescription {
    private static func numbers(_ ids: [AudioObjectID]) -> [NSNumber] {
        ids.map { NSNumber(value: $0) }
    }

    public convenience init(stereoMixdownOfProcesses processesIDsToIncludeInTap: [AudioObjectID]) {
        self.init(__stereoMixdownOfProcesses: Self.numbers(processesIDsToIncludeInTap))
    }

    public convenience init(monoMixdownOfProcesses processesIDsToIncludeInTap: [AudioObjectID]) {
        self.init(__monoMixdownOfProcesses: Self.numbers(processesIDsToIncludeInTap))
    }

    public convenience init(stereoGlobalTapButExcludeProcesses processesIDsToExcludeFromTap: [AudioObjectID]) {
        self.init(__stereoGlobalTapButExcludeProcesses: Self.numbers(processesIDsToExcludeFromTap))
    }

    public convenience init(monoGlobalTapButExcludeProcesses processesIDsToExcludeFromTap: [AudioObjectID]) {
        self.init(__monoGlobalTapButExcludeProcesses: Self.numbers(processesIDsToExcludeFromTap))
    }

    public convenience init(processes processesIDsToIncludeInTap: [AudioObjectID], deviceUID: String, stream: UInt) {
        self.init(__processes: Self.numbers(processesIDsToIncludeInTap), andDeviceUID: deviceUID, withStream: Int(stream))
    }

    public convenience init(excludingProcesses processesIDsToExcludeFromTap: [AudioObjectID], deviceUID: String, stream: UInt) {
        self.init(__excludingProcesses: Self.numbers(processesIDsToExcludeFromTap), andDeviceUID: deviceUID, withStream: Int(stream))
    }

    public var processes: [AudioObjectID] {
        get { __processes.map { $0.uint32Value } }
        set(processObjectIDs) { __processes = Self.numbers(processObjectIDs) }
    }

    public var stream: UInt? {
        get { __stream?.uintValue }
        set(streamObject) { __stream = streamObject.map { NSNumber(value: $0) } }
    }
}

#endif
