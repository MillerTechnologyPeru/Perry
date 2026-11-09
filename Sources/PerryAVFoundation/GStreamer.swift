import CPerryMedia
import Glibc

// GStreamer, loaded when a player first needs it: a playbin per item, its
// video converted to RGBA (or BGRA) into an appsink the player or its
// item's video output pulls frames from, its audio to the system's output. Without GStreamer (or the plugins a file
// needs) an item can't play, and players report it as finished.

final class GStreamer: @unchecked Sendable {
    typealias Pointer = UnsafeMutableRawPointer

    let parseLaunch: @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<Pointer?>?) -> Pointer?
    let binGetByName: @convention(c) (Pointer, UnsafePointer<CChar>) -> Pointer?
    let setState: @convention(c) (Pointer, Int32) -> Int32
    let getBus: @convention(c) (Pointer) -> Pointer?
    let busPopFiltered: @convention(c) (Pointer, UInt32) -> Pointer?
    /// gst_message_parse_error: the message's GError (domain, code, then
    /// the text) and debug text, for tracing.
    var parseError: (@convention(c) (Pointer, UnsafeMutablePointer<UnsafeMutableRawPointer?>,
                                     UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Void)?
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
    /// g_object_set itself, for a double property, which only a variadic
    /// call passes right on 32-bit ARM (perry_g_object_set_double).
    let objectSet: UnsafeMutableRawPointer
    let setBool: @convention(c) (Pointer, UnsafePointer<CChar>, Int32, Pointer?) -> Void
    // For reading what a stream holds before it plays; nil where an older
    // GStreamer lacks them.
    /// gst_element_get_state: waits, for as long as the nanoseconds given,
    /// for a change of state to finish.
    var getState: (@convention(c) (Pointer, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?, UInt64) -> Int32)?
    var pullPreroll: (@convention(c) (Pointer, UInt64) -> Pointer?)?
    var structureGetFraction: (@convention(c) (Pointer, UnsafePointer<CChar>, UnsafeMutablePointer<Int32>,
                                               UnsafeMutablePointer<Int32>) -> Int32)?
    /// g_object_get with one int property.
    var getInt: (@convention(c) (Pointer, UnsafePointer<CChar>, UnsafeMutablePointer<Int32>, Pointer?) -> Void)?

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
              let objectSet = dlsym(gobject, "g_object_set"),
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
        parseError = bind(core, "gst_message_parse_error", (@convention(c) (Pointer, UnsafeMutablePointer<UnsafeMutableRawPointer?>,
                                                                             UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Void).self)
        (self.objectUnref, self.miniObjectUnref, self.pullSample, self.sampleGetBuffer, self.sampleGetCaps) =
            (objectUnref, miniObjectUnref, pullSample, sampleGetBuffer, sampleGetCaps)
        (self.capsGetStructure, self.structureGetInt, self.bufferMap, self.bufferUnmap) =
            (capsGetStructure, structureGetInt, bufferMap, bufferUnmap)
        (self.queryPosition, self.queryDuration, self.seekSimple, self.objectSet, self.setBool) =
            (queryPosition, queryDuration, seekSimple, objectSet, setBool)
        getState = bind(core, "gst_element_get_state", (@convention(c) (Pointer, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?,
                                                                        UInt64) -> Int32).self)
        pullPreroll = bind(app, "gst_app_sink_try_pull_preroll", (@convention(c) (Pointer, UInt64) -> Pointer?).self)
        structureGetFraction = bind(core, "gst_structure_get_fraction",
                                    (@convention(c) (Pointer, UnsafePointer<CChar>, UnsafeMutablePointer<Int32>,
                                                     UnsafeMutablePointer<Int32>) -> Int32).self)
        getInt = bind(gobject, "g_object_get", (@convention(c) (Pointer, UnsafePointer<CChar>, UnsafeMutablePointer<Int32>, Pointer?) -> Void).self)
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
    /// The order of a frame's bytes: RGBA or BGRA.
    let format: String
    /// Ticks the position has been at the end; see `finished()`.
    private var ticksAtEnd = 0
    private let mapInfo = UnsafeMutableRawPointer.allocate(byteCount: GStreamer.mapInfoSize, alignment: 8)

    /// `format` is the order of a frame's four bytes: RGBA, or BGRA for
    /// the pixel buffers a video output hands out.
    init?(uri: String, gst: GStreamer, video: Bool = true, format: String = "RGBA") {
        // In quotes, as the pipeline description reads them.
        var quoted = ""
        for character in uri {
            if character == "\\" || character == "\"" { quoted.append("\\") }
            quoted.append(character)
        }
        // Sound alone, as for AVAudioPlayer, sends any video nowhere.
        let description = video
            ? "playbin uri=\"\(quoted)\" video-sink=\"videoconvert ! videoscale ! video/x-raw,format=\(format) "
                + "! appsink name=perryvideo max-buffers=1 drop=true\""
            : "playbin uri=\"\(quoted)\" video-sink=fakesink"
        var error: GStreamer.Pointer?
        guard let element = description.withCString({ gst.parseLaunch($0, &error) }) else {
            GStreamer.log("can't make a pipeline for \(uri)")
            return nil
        }
        self.gst = gst
        self.element = element
        self.format = format
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
        "volume".withCString { perry_g_object_set_double(gst.objectSet, element, $0, volume) }
        "mute".withCString { gst.setBool(element, $0, muted ? 1 : 0, nil) }
    }

    /// Whether the stream has ended, or failed, since last asked. A stream
    /// whose position has stayed at its end for half a second has ended
    /// too, as a sink that can't play (no audio device, say) may never
    /// report the end.
    func finished() -> Bool {
        guard let bus else { return true }
        if let message = gst.busPopFiltered(bus, GStreamer.messageError) {
            if Players.tracing, let parse = gst.parseError {
                var error: UnsafeMutableRawPointer?
                var debug: UnsafeMutablePointer<CChar>?
                parse(message, &error, &debug)
                // GError: a quark and an int, then the message.
                let text = error.flatMap { $0.load(fromByteOffset: 8, as: UnsafePointer<CChar>?.self) }.map { String(cString: $0) }
                Players.trace("error: \(text ?? "?") (\(debug.map { String(cString: $0) } ?? ""))")
            }
            gst.miniObjectUnref(message)
            return true
        }
        if let message = gst.busPopFiltered(bus, GStreamer.messageEOS) {
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
        // A view shows RGBA: an asset's pipeline, which makes BGRA for
        // video outputs, has its red and blue changed places.
        if format == "BGRA" {
            frame.pixels.withUnsafeMutableBufferPointer { pixels in
                var index = 0
                while index + 3 < pixels.count {
                    pixels.swapAt(index, index + 2)
                    index += 4
                }
            }
        }
        frame.number &+= 1
        return true
    }

    /// What the stream holds, read with it paused on its first frame:
    /// waits for that as long as `timeout` seconds. Nil when it can't play.
    func describe(timeout: Double) -> MediaDescription? {
        guard let getState = gst.getState, let pullPreroll = gst.pullPreroll else { return nil }
        pause()
        // GST_STATE_CHANGE_FAILURE is 0.
        guard getState(element, nil, nil, UInt64(timeout * 1e9)) != 0 else { return nil }
        var description = MediaDescription()
        description.duration = duration ?? 0
        var audio: Int32 = 0
        if let getInt = gst.getInt { "n-audio".withCString { getInt(element, $0, &audio, nil) } }
        description.audioStreams = Int(audio)
        if sink == nil { sink = "perryvideo".withCString { gst.binGetByName(element, $0) } }
        if let sink, let sample = pullPreroll(sink, UInt64(min(timeout, 2) * 1e9)) {
            defer { gst.miniObjectUnref(sample) }
            var width: Int32 = 0, height: Int32 = 0, numerator: Int32 = 0, denominator: Int32 = 1
            if let caps = gst.sampleGetCaps(sample), let structure = gst.capsGetStructure(caps, 0) {
                _ = "width".withCString { gst.structureGetInt(structure, $0, &width) }
                _ = "height".withCString { gst.structureGetInt(structure, $0, &height) }
                if let fraction = gst.structureGetFraction {
                    _ = "framerate".withCString { fraction(structure, $0, &numerator, &denominator) }
                }
            }
            (description.width, description.height) = (Int(width), Int(height))
            if numerator > 0, denominator > 0 { description.frameRate = Double(numerator) / Double(denominator) }
        }
        return description
    }

    /// The newest decoded frame, if one came since last asked, copied by
    /// `copy` (given its width, height, bytes and their count) while the
    /// frame is mapped.
    func pullFrame(_ copy: (Int, Int, UnsafeRawPointer, Int) -> Void) -> Bool {
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
        let count = Int(width) * 4 * Int(height)
        guard let data, length >= count else { return false }
        copy(Int(width), Int(height), data, count)
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

/// What a stream holds: its length in seconds, its video's size and
/// frames a second (zeros without video), and how many audio streams.
struct MediaDescription {
    var duration = 0.0
    var width = 0
    var height = 0
    var frameRate = 30.0
    var audioStreams = 0
}

/// A decoded video frame.
struct VideoFrame {
    var width = 0
    var height = 0
    var pixels: [UInt8] = []
    /// Counts the frames pulled, so a view can tell when there's a new one.
    var number: UInt = 0
}
