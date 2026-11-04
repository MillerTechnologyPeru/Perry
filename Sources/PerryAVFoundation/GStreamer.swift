import Glibc

// GStreamer, loaded when a player first needs it: a playbin per item, its
// video converted to RGBA into an appsink the player pulls frames from, its
// audio to the system's output. Without GStreamer (or the plugins a file
// needs) an item can't play, and players report it as finished.

final class GStreamer: @unchecked Sendable {
    typealias Pointer = UnsafeMutableRawPointer

    let parseLaunch: @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<Pointer?>?) -> Pointer?
    let binGetByName: @convention(c) (Pointer, UnsafePointer<CChar>) -> Pointer?
    let setState: @convention(c) (Pointer, Int32) -> Int32
    let getBus: @convention(c) (Pointer) -> Pointer?
    let busPopFiltered: @convention(c) (Pointer, UInt32) -> Pointer?
    let objectUnref: @convention(c) (Pointer) -> Void
    let miniObjectUnref: @convention(c) (Pointer) -> Void
    let pullSample: @convention(c) (Pointer, UInt64) -> Pointer?
    let sampleGetBuffer: @convention(c) (Pointer) -> Pointer?
    let sampleGetCaps: @convention(c) (Pointer) -> Pointer?
    let capsGetStructure: @convention(c) (Pointer, UInt32) -> Pointer?
    let structureGetInt: @convention(c) (Pointer, UnsafePointer<CChar>, UnsafeMutablePointer<Int32>) -> Int32
    let bufferMap: @convention(c) (Pointer, Pointer, Int32) -> Int32
    let bufferUnmap: @convention(c) (Pointer, Pointer) -> Void
    let queryPosition: @convention(c) (Pointer, Int32, UnsafeMutablePointer<Int64>) -> Int32
    let queryDuration: @convention(c) (Pointer, Int32, UnsafeMutablePointer<Int64>) -> Int32
    let seekSimple: @convention(c) (Pointer, Int32, Int32, Int64) -> Int32
    /// g_object_set with one double property: on Linux's arm64 ABI a
    /// variadic call passes its arguments as a fixed one would.
    let setDouble: @convention(c) (Pointer, UnsafePointer<CChar>, Double, Pointer?) -> Void
    let setBool: @convention(c) (Pointer, UnsafePointer<CChar>, Int32, Pointer?) -> Void

    // GstState, GstMessageType, GstFormat, GstSeekFlags and GstMapFlags.
    static let stateNull: Int32 = 1, statePaused: Int32 = 3, statePlaying: Int32 = 4
    static let messageEOS: UInt32 = 1 << 0, messageError: UInt32 = 1 << 1
    static let formatTime: Int32 = 3
    static let seekFlush: Int32 = 1 << 0, seekKeyUnit: Int32 = 1 << 2
    static let mapRead: Int32 = 1
    /// GstMapInfo's size, and where its data and size are.
    static let mapInfoSize = 104, mapInfoData = 16, mapInfoLength = 24

    /// GStreamer, initialized; nil when it isn't installed.
    nonisolated(unsafe) static let shared: GStreamer? = GStreamer()

    private init?() {
        guard let core = dlopen("libgstreamer-1.0.so.0", RTLD_NOW | RTLD_GLOBAL),
              let app = dlopen("libgstapp-1.0.so.0", RTLD_NOW | RTLD_GLOBAL),
              let gobject = dlopen("libgobject-2.0.so.0", RTLD_NOW | RTLD_GLOBAL) else {
            GStreamer.log("GStreamer is not installed; videos finish without playing")
            return nil
        }
        func bind<T>(_ library: UnsafeMutableRawPointer, _ name: String, _: T.Type) -> T? {
            dlsym(library, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let initialize = bind(core, "gst_init_check", (@convention(c) (UnsafeMutablePointer<Int32>?, Pointer?, Pointer?) -> Int32).self),
              let parseLaunch = bind(core, "gst_parse_launch",
                                     (@convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<Pointer?>?) -> Pointer?).self),
              let binGetByName = bind(core, "gst_bin_get_by_name", (@convention(c) (Pointer, UnsafePointer<CChar>) -> Pointer?).self),
              let setState = bind(core, "gst_element_set_state", (@convention(c) (Pointer, Int32) -> Int32).self),
              let getBus = bind(core, "gst_element_get_bus", (@convention(c) (Pointer) -> Pointer?).self),
              let busPopFiltered = bind(core, "gst_bus_pop_filtered", (@convention(c) (Pointer, UInt32) -> Pointer?).self),
              let objectUnref = bind(core, "gst_object_unref", (@convention(c) (Pointer) -> Void).self),
              let miniObjectUnref = bind(core, "gst_mini_object_unref", (@convention(c) (Pointer) -> Void).self),
              let pullSample = bind(app, "gst_app_sink_try_pull_sample", (@convention(c) (Pointer, UInt64) -> Pointer?).self),
              let sampleGetBuffer = bind(core, "gst_sample_get_buffer", (@convention(c) (Pointer) -> Pointer?).self),
              let sampleGetCaps = bind(core, "gst_sample_get_caps", (@convention(c) (Pointer) -> Pointer?).self),
              let capsGetStructure = bind(core, "gst_caps_get_structure", (@convention(c) (Pointer, UInt32) -> Pointer?).self),
              let structureGetInt = bind(core, "gst_structure_get_int",
                                         (@convention(c) (Pointer, UnsafePointer<CChar>, UnsafeMutablePointer<Int32>) -> Int32).self),
              let bufferMap = bind(core, "gst_buffer_map", (@convention(c) (Pointer, Pointer, Int32) -> Int32).self),
              let bufferUnmap = bind(core, "gst_buffer_unmap", (@convention(c) (Pointer, Pointer) -> Void).self),
              let queryPosition = bind(core, "gst_element_query_position",
                                       (@convention(c) (Pointer, Int32, UnsafeMutablePointer<Int64>) -> Int32).self),
              let queryDuration = bind(core, "gst_element_query_duration",
                                       (@convention(c) (Pointer, Int32, UnsafeMutablePointer<Int64>) -> Int32).self),
              let seekSimple = bind(core, "gst_element_seek_simple", (@convention(c) (Pointer, Int32, Int32, Int64) -> Int32).self),
              let setDouble = bind(gobject, "g_object_set", (@convention(c) (Pointer, UnsafePointer<CChar>, Double, Pointer?) -> Void).self),
              let setBool = bind(gobject, "g_object_set", (@convention(c) (Pointer, UnsafePointer<CChar>, Int32, Pointer?) -> Void).self)
        else {
            GStreamer.log("GStreamer is incomplete; videos finish without playing")
            return nil
        }
        guard initialize(nil, nil, nil) != 0 else {
            GStreamer.log("GStreamer did not initialize; videos finish without playing")
            return nil
        }
        (self.parseLaunch, self.binGetByName, self.setState, self.getBus, self.busPopFiltered) =
            (parseLaunch, binGetByName, setState, getBus, busPopFiltered)
        (self.objectUnref, self.miniObjectUnref, self.pullSample, self.sampleGetBuffer, self.sampleGetCaps) =
            (objectUnref, miniObjectUnref, pullSample, sampleGetBuffer, sampleGetCaps)
        (self.capsGetStructure, self.structureGetInt, self.bufferMap, self.bufferUnmap) =
            (capsGetStructure, structureGetInt, bufferMap, bufferUnmap)
        (self.queryPosition, self.queryDuration, self.seekSimple, self.setDouble, self.setBool) =
            (queryPosition, queryDuration, seekSimple, setDouble, setBool)
    }

    static func log(_ message: String) {
        let line = "perry: AVFoundation: \(message)\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }
}

/// One item's pipeline: playbin decoding a URI, video to an appsink.
final class Pipeline {
    let gst: GStreamer
    let element: GStreamer.Pointer
    /// The appsink, found once playbin has put its video sink in place.
    private(set) var sink: GStreamer.Pointer?
    let bus: GStreamer.Pointer?
    /// Ticks the position has been at the end; see `finished()`.
    private var ticksAtEnd = 0
    private let mapInfo = UnsafeMutableRawPointer.allocate(byteCount: GStreamer.mapInfoSize, alignment: 8)

    init?(uri: String, gst: GStreamer) {
        // In quotes, as the pipeline description reads them.
        var quoted = ""
        for character in uri {
            if character == "\\" || character == "\"" { quoted.append("\\") }
            quoted.append(character)
        }
        let description = "playbin uri=\"\(quoted)\" video-sink=\"videoconvert ! videoscale ! video/x-raw,format=RGBA "
            + "! appsink name=perryvideo max-buffers=1 drop=true\""
        var error: GStreamer.Pointer?
        guard let element = description.withCString({ gst.parseLaunch($0, &error) }) else {
            GStreamer.log("can't make a pipeline for \(uri)")
            return nil
        }
        self.gst = gst
        self.element = element
        bus = gst.getBus(element)
    }

    deinit {
        _ = gst.setState(element, GStreamer.stateNull)
        if let sink { gst.objectUnref(sink) }
        if let bus { gst.objectUnref(bus) }
        gst.objectUnref(element)
        mapInfo.deallocate()
    }

    func play() { _ = gst.setState(element, GStreamer.statePlaying) }
    func pause() { _ = gst.setState(element, GStreamer.statePaused) }

    func set(volume: Double, muted: Bool) {
        "volume".withCString { gst.setDouble(element, $0, volume, nil) }
        "mute".withCString { gst.setBool(element, $0, muted ? 1 : 0, nil) }
    }

    /// Whether the stream has ended, or failed, since last asked. A stream
    /// whose position has stayed at its end for half a second has ended
    /// too, as a sink that can't play (no audio device, say) may never
    /// report the end.
    func finished() -> Bool {
        guard let bus else { return true }
        if let message = gst.busPopFiltered(bus, GStreamer.messageEOS | GStreamer.messageError) {
            gst.miniObjectUnref(message)
            return true
        }
        if let position, let duration, duration > 0, position >= duration - 0.05 {
            ticksAtEnd += 1
        } else {
            ticksAtEnd = 0
        }
        return ticksAtEnd >= 30
    }

    /// The newest decoded frame, if one came since last asked: RGBA rows,
    /// top first.
    func pullFrame(into frame: inout VideoFrame) -> Bool {
        if sink == nil { sink = "perryvideo".withCString { gst.binGetByName(element, $0) } }
        guard let sink else { return false }
        var latest: GStreamer.Pointer?
        while let sample = gst.pullSample(sink, 0) {
            if let latest { gst.miniObjectUnref(latest) }
            latest = sample
        }
        guard let sample = latest else { return false }
        defer { gst.miniObjectUnref(sample) }
        var width: Int32 = 0, height: Int32 = 0
        guard let caps = gst.sampleGetCaps(sample), let structure = gst.capsGetStructure(caps, 0),
              "width".withCString({ gst.structureGetInt(structure, $0, &width) }) != 0,
              "height".withCString({ gst.structureGetInt(structure, $0, &height) }) != 0,
              width > 0, height > 0, let buffer = gst.sampleGetBuffer(sample),
              gst.bufferMap(buffer, mapInfo, GStreamer.mapRead) != 0 else { return false }
        defer { gst.bufferUnmap(buffer, mapInfo) }
        let data = mapInfo.load(fromByteOffset: GStreamer.mapInfoData, as: UnsafeRawPointer?.self)
        let length = mapInfo.load(fromByteOffset: GStreamer.mapInfoLength, as: Int.self)
        let rowBytes = Int(width) * 4
        guard let data, length >= rowBytes * Int(height) else { return false }
        frame.width = Int(width)
        frame.height = Int(height)
        frame.pixels = [UInt8](UnsafeRawBufferPointer(start: data, count: rowBytes * Int(height)))
        frame.number &+= 1
        return true
    }

    /// Seconds into the stream, and its length.
    var position: Double? { query(gst.queryPosition) }
    var duration: Double? { query(gst.queryDuration) }

    private func query(_ function: @convention(c) (GStreamer.Pointer, Int32, UnsafeMutablePointer<Int64>) -> Int32) -> Double? {
        var nanoseconds: Int64 = 0
        guard function(element, GStreamer.formatTime, &nanoseconds) != 0, nanoseconds >= 0 else { return nil }
        return Double(nanoseconds) / 1e9
    }

    func seek(to seconds: Double) {
        _ = gst.seekSimple(element, GStreamer.formatTime, GStreamer.seekFlush | GStreamer.seekKeyUnit, Int64(max(seconds, 0) * 1e9))
    }
}

/// A decoded video frame.
struct VideoFrame {
    var width = 0
    var height = 0
    var pixels: [UInt8] = []
    /// Counts the frames pulled, so a view can tell when there's a new one.
    var number: UInt = 0
}
