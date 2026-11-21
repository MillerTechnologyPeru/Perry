import DBus
import Glibc

// NetworkManager, Linux's network service, through its D-Bus API on the
// system bus. CoreWLAN's interfaces and scans read live state from it: the
// Wi-Fi devices, their power and hardware address, and the access points each
// one sees. One connection serves every interface.
//
// NetworkManager does not implement ObjectManager, so there is no single
// GetManagedObjects as BlueZ has; each query fetches the current properties
// with org.freedesktop.DBus.Properties, which matches CoreWLAN's synchronous
// calls (an interface asks, NetworkManager answers, the call returns).

struct NMError: Error, Sendable {
    let name: String
    let message: String
}

enum NM {
    static let service = "org.freedesktop.NetworkManager"
    static let rootPath = "/org/freedesktop/NetworkManager"
    static let manager = "org.freedesktop.NetworkManager"
    static let device = "org.freedesktop.NetworkManager.Device"
    static let wireless = "org.freedesktop.NetworkManager.Device.Wireless"
    static let accessPoint = "org.freedesktop.NetworkManager.AccessPoint"
    static let properties = "org.freedesktop.DBus.Properties"
    static let deviceTypeWiFi = 2
}

/// A Wi-Fi device, as CoreWLAN's CWInterface reflects it.
struct NMDevice: Sendable {
    let path: String
    let interface: String        // "wlan0"
    let hardwareAddress: String  // "aa:bb:cc:dd:ee:ff"
    let state: Int
    let activeAccessPoint: String?
}

/// An access point, as CWNetwork reflects it.
struct NMAccessPoint: Sendable, Hashable {
    let path: String
    let ssid: [UInt8]
    let bssid: String
    let frequency: Int           // MHz
    let strength: Int            // 0–100
    let flags: Int
    let wpaFlags: Int
    let rsnFlags: Int
    let mode: Int
}

actor NetworkManager {
    static let shared = NetworkManager()

    private enum Phase {
        case idle, connecting, connected(DBusConnection), unavailable
    }

    private var phase = Phase.idle
    private var waiting: [CheckedContinuation<DBusConnection?, Never>] = []

    // MARK: Connection

    /// The connection, made on first use; nil when there is no system bus or
    /// NetworkManager is not on it.
    func connection() async -> DBusConnection? {
        switch phase {
        case .connected(let connection):
            if await connection.isConnected { return connection }
            phase = .unavailable
            return nil
        case .unavailable: return nil
        case .idle:
            phase = .connecting
            Task.detached { await NetworkManager.run() }
        case .connecting: break
        }
        return await withCheckedContinuation { waiting.append($0) }
    }

    private static func run() async {
        do {
            await NetworkManager.shared.connected(try await DBusConnection.connect(to: .system))
        } catch {
            await NetworkManager.shared.closed()
        }
    }

    private func connected(_ connection: DBusConnection) async {
        phase = .connected(connection)
        let waiters = waiting
        waiting = []
        waiters.forEach { $0.resume(returning: connection) }
    }

    private func closed() {
        phase = .unavailable
        let waiters = waiting
        waiting = []
        waiters.forEach { $0.resume(returning: nil) }
    }

    var isAvailable: Bool {
        if case .connected = phase { return true }
        return false
    }

    // MARK: Calls

    private func call(_ path: String, _ interface: String, _ method: String, _ body: [DBusValue] = []) async throws -> [DBusValue] {
        guard let connection = await connection() else {
            throw NMError(name: "org.freedesktop.DBus.Error.ServiceUnknown", message: "NetworkManager is not running")
        }
        guard let destination = DBusBusName(rawValue: NM.service), let path = DBusObjectPath(rawValue: path),
              let interface = DBusInterface(rawValue: interface), let method = DBusMember(rawValue: method) else {
            throw NMError(name: "org.freedesktop.DBus.Error.InvalidArgs", message: "\(path) \(interface).\(method)")
        }
        do {
            // No timeout: a call waits for its answer.
            return try await connection.callMethod(destination: destination, path: path, interface: interface, method: method,
                                                   arguments: body, timeout: nil)
        } catch let error as DBusError {
            throw NMError(name: error.name.rawValue, message: error.message)
        }
    }

    /// Every property of an object's interface, a{sv}.
    private func getAll(_ path: String, _ interface: String) async -> [String: DBusValue] {
        guard let reply = try? await call(path, NM.properties, "GetAll", [.string(interface)]),
              case .dictionary(let entries)? = reply.first else { return [:] }
        var properties: [String: DBusValue] = [:]
        for entry in entries {
            guard let name = entry.key.stringValue else { continue }
            properties[name] = entry.value.unwrapped
        }
        return properties
    }

    private func get(_ path: String, _ interface: String, _ property: String) async -> DBusValue? {
        guard let reply = try? await call(path, NM.properties, "Get", [.string(interface), .string(property)]) else {
            return nil
        }
        return reply.first?.unwrapped
    }

    // MARK: Wi-Fi

    /// The managed Wi-Fi devices, in path order.
    func wifiDevices() async -> [NMDevice] {
        guard let reply = try? await call(NM.rootPath, NM.manager, "GetAllDevices"),
              case .array(let paths)? = reply.first else { return [] }
        var devices: [NMDevice] = []
        for value in paths {
            guard let path = value.pathValue else { continue }
            let device = await getAll(path, NM.device)
            guard device["DeviceType"]?.intValue == NM.deviceTypeWiFi else { continue }
            let wireless = await getAll(path, NM.wireless)
            let hw = wireless["HwAddress"]?.stringValue ?? device["HwAddress"]?.stringValue ?? ""
            devices.append(NMDevice(
                path: path,
                interface: device["Interface"]?.stringValue ?? "",
                hardwareAddress: hw,
                state: device["State"]?.intValue ?? 0,
                activeAccessPoint: wireless["ActiveAccessPoint"]?.pathValue.flatMap { $0 == "/" ? nil : $0 }))
        }
        return devices.sorted { $0.path < $1.path }
    }

    /// The device with that interface name, or the first Wi-Fi device when the
    /// name is nil.
    func wifiDevice(named name: String?) async -> NMDevice? {
        let devices = await wifiDevices()
        guard let name else { return devices.first }
        return devices.first { $0.interface == name }
    }

    var wirelessEnabled: Bool {
        get async { await get(NM.rootPath, NM.manager, "WirelessEnabled")?.boolValue ?? false }
    }

    func setWirelessEnabled(_ enabled: Bool) async -> Bool {
        do {
            _ = try await call(NM.rootPath, NM.properties, "Set",
                               [.string(NM.manager), .string("WirelessEnabled"), .variant(DBusVariant(.boolean(enabled)))])
            return true
        } catch { return false }
    }

    private func accessPoint(_ path: String) async -> NMAccessPoint? {
        let p = await getAll(path, NM.accessPoint)
        guard !p.isEmpty else { return nil }
        return NMAccessPoint(
            path: path,
            ssid: p["Ssid"]?.bytes ?? [],
            bssid: p["HwAddress"]?.stringValue ?? "",
            frequency: p["Frequency"]?.intValue ?? 0,
            strength: p["Strength"]?.intValue ?? 0,
            flags: p["Flags"]?.intValue ?? 0,
            wpaFlags: p["WpaFlags"]?.intValue ?? 0,
            rsnFlags: p["RsnFlags"]?.intValue ?? 0,
            mode: p["Mode"]?.intValue ?? 0)
    }

    /// The access points a device sees now.
    func accessPoints(ofDevice path: String) async -> [NMAccessPoint] {
        guard let value = await get(path, NM.wireless, "AccessPoints"), case .array(let paths) = value else {
            wlanTrace("AccessPoints(\(path)): property missing or not an array")
            return []
        }
        var points: [NMAccessPoint] = []
        for apPath in paths.compactMap(\.pathValue) {
            if let ap = await accessPoint(apPath) { points.append(ap) }
        }
        return points
    }

    func activeAccessPoint(ofDevice path: String) async -> NMAccessPoint? {
        guard let apPath = await get(path, NM.wireless, "ActiveAccessPoint")?.pathValue, apPath != "/" else { return nil }
        return await accessPoint(apPath)
    }

    private func lastScan(ofDevice path: String) async -> Int {
        await get(path, NM.wireless, "LastScan")?.intValue ?? -1
    }

    /// Asks the device to scan and waits, bounded, for the scan to finish,
    /// then returns the access points it sees. Returns what it has even when
    /// the request is refused (NetworkManager rate-limits scans) or times out.
    func scan(deviceAt path: String, timeout: Double = 8) async -> [NMAccessPoint] {
        let before = await lastScan(ofDevice: path)
        do {
            _ = try await call(path, NM.wireless, "RequestScan", [.options()])
            wlanTrace("RequestScan(\(path)) accepted")
        } catch let error as NMError {
            wlanTrace("RequestScan(\(path)) refused: \(error.name)")
        } catch {}
        let deadline = now() + timeout
        while now() < deadline {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let after = await lastScan(ofDevice: path)
            if after != before && after > 0 { break }
        }
        let points = await accessPoints(ofDevice: path)
        wlanTrace("scan(\(path)) -> \(points.count) access points")
        return points
    }

    private func now() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1_000_000_000
    }
}

// MARK: - D-Bus value helpers

typealias DBusValue = DBusMessageArgument
typealias DBusVariant = DBusMessageArgument.Variant

extension DBusMessageArgument {
    var unwrapped: DBusValue {
        if case .variant(let variant) = self { return variant.element.unwrapped }
        return self
    }

    /// An object path's text, or a string's.
    var pathValue: String? {
        if case .objectPath(let path) = unwrapped { return path.rawValue }
        return stringValue
    }

    var boolValue: Bool? {
        if case .boolean(let value) = unwrapped { return value }
        return nil
    }

    var intValue: Int? {
        switch unwrapped {
        case .byte(let value): Int(value)
        case .int16(let value): Int(value)
        case .uint16(let value): Int(value)
        case .int32(let value): Int(value)
        case .uint32(let value): Int(value)
        case .int64(let value): Int(value)
        case .uint64(let value): Int(value)
        default: nil
        }
    }

    /// ay.
    var bytes: [UInt8]? {
        guard case .array(let elements) = unwrapped else { return nil }
        return elements.compactMap { if case .byte(let byte) = $0 { byte } else { nil } }
    }

    /// a{sv}, each value in a variant.
    static func options(_ entries: [String: DBusValue] = [:]) -> DBusValue {
        .dictionary(Dictionary(keyType: .string, valueType: .variant,
                               entries.sorted { $0.key < $1.key }.map { .init(key: .string($0.key), value: .variant(DBusVariant($0.value))) })!)
    }
}
