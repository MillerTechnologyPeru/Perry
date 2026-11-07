import CPerryGeometry
import Glibc
import PerryObjCInterop

// The map itself, under an MKMapView: rendered by MapLibre Native through
// libPerryMapLibre.so (Scripts/build-maplibre.sh), which is loaded when the
// first map view is laid out, on either platform. Without the library a map view stays the
// color of land.
//
// MapLibre renders on a thread of its own; each finished frame is copied
// out on the main queue and shown as the map view's layer's pixels.
//
// PERRY_MAPLIBRE names the library (default libPerryMapLibre.so, found as
// dlopen finds libraries), PERRY_MAP_STYLE the style (default OpenFreeMap's
// Liberty, which needs no key). Tiles are cached in PERRY_CACHES.
// PERRY_MAP_TRACE=1 logs each camera, each frame shown (its size and
// middle pixel) and where each gesture ends.

enum MapLibre {
    typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Create = @convention(c) (Int32, Int32, Float, UnsafePointer<CChar>?, UnsafePointer<CChar>?, FrameCallback?,
                                       UnsafeMutableRawPointer?) -> OpaquePointer?
    typealias Destroy = @convention(c) (OpaquePointer?) -> Void
    typealias SetSize = @convention(c) (OpaquePointer?, Int32, Int32) -> Void
    typealias SetCamera = @convention(c) (OpaquePointer?, Double, Double, Double, Double, Double) -> Void
    typealias CopyFrame = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt64>?, UnsafeMutablePointer<UInt8>?, Int,
                                          UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Int32

    struct Functions {
        let create: Create
        let destroy: Destroy
        let setSize: SetSize
        let setCamera: SetCamera
        let copyFrame: CopyFrame
    }

    /// The library's functions, loaded once; nil without it.
    nonisolated(unsafe) static let functions: Functions? = {
        let name = getenv("PERRY_MAPLIBRE").map { String(cString: $0) } ?? "libPerryMapLibre.so"
        guard let library = dlopen(name, RTLD_NOW) else {
            let reason = dlerror().map { String(cString: $0) } ?? name
            let line = "perry: MapKit: no map tiles, as MapLibre isn't available (\(reason))\n"
            line.withCString { _ = write(2, $0, strlen($0)) }
            return nil
        }
        func symbol<T>(_ name: String, _ type: T.Type) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: type) } }
        guard let create = symbol("pml_map_create", Create.self), let destroy = symbol("pml_map_destroy", Destroy.self),
              let setSize = symbol("pml_map_set_size", SetSize.self), let setCamera = symbol("pml_map_set_camera", SetCamera.self),
              let copyFrame = symbol("pml_map_copy_frame", CopyFrame.self) else { return nil }
        return Functions(create: create, destroy: destroy, setSize: setSize, setCamera: setCamera, copyFrame: copyFrame)
    }()

    static var style: String {
        getenv("PERRY_MAP_STYLE").map { String(cString: $0) } ?? "https://tiles.openfreemap.org/styles/liberty"
    }

    static let tracing = getenv("PERRY_MAP_TRACE") != nil

    static func trace(_ message: String) {
        guard tracing else { return }
        let line = "perry: MapKit: \(message)\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }

    static var cachePath: String? {
        getenv("PERRY_CACHES").map { String(cString: $0) + "/maplibre.db" }
    }

    /// MapLibre's zoom for a region shown in `size` points: the closest that
    /// fits both its spans, the world being 512 points across at zoom 0.
    static func zoom(for region: MKCoordinateRegion, in size: CGSize) -> Double {
        let span = region.span
        let longitude = max(span.longitudeDelta, 1e-9)
        let zoomAcross = log2(360 * Double(size.width) / (512 * longitude))
        func mercator(_ latitude: Double) -> Double {
            let clamped = min(max(latitude, -85.0511), 85.0511) * .pi / 180
            return log(tan(.pi / 4 + clamped / 2))
        }
        let top = mercator(region.center.latitude + span.latitudeDelta / 2)
        let bottom = mercator(region.center.latitude - span.latitudeDelta / 2)
        let height = max(abs(top - bottom), 1e-9)
        let zoomDown = log2(Double(size.height) * 2 * .pi / (512 * height))
        return max(0, min(zoomAcross, zoomDown, 22))
    }
}

/// The CALayer message a map view's frames are shown through.
@ObjCWrapper("CALayer")
class MapLayer: NSObject {
    /// RGBA, rows top first (layout 2), alpha premultiplied.
    @ObjCMethod("_perrySetPixels:width:height:opaque:layout:")
    func setPixels(_ pixels: UnsafeRawPointer?, width: Int, height: Int, opaque: Bool, layout: Int)
}

extension NSObject {
    @ObjCMethod("layer") func sendLayer() -> MapLayer
}

/// One map view's MapLibre map.
final class MapTiles: @unchecked Sendable {
    private let functions: MapLibre.Functions
    private let handle: OpaquePointer
    /// The map view, which owns this; weakly, as frames arrive later.
    private let view: WeakObject
    private let lock = Lock()
    private var scheduled = false
    private var generation: UInt64 = 0
    private var buffer: [UInt8] = []
    private var size = CGSize(width: 0, height: 0)
    private var camera: (Double, Double, Double)?

    /// A map for `view`, `size` points; nil without MapLibre.
    init?(view: UnsafeMutableRawPointer, size: CGSize, scale: Float) {
        guard let functions = MapLibre.functions else { return nil }
        self.functions = functions
        self.view = WeakObject(view)
        self.size = size
        guard let handle = MapLibre.style.withCString({ style in
            (MapLibre.cachePath ?? "").withCString { cache in
                functions.create(Int32(max(size.width, 1)), Int32(max(size.height, 1)), scale, style,
                                 MapLibre.cachePath == nil ? nil : cache, nil, nil)
            }
        }) else { return nil }
        self.handle = handle
    }

    deinit { functions.destroy(handle) }

    func resize(to size: CGSize) {
        guard size.width != self.size.width || size.height != self.size.height, size.width >= 1, size.height >= 1 else { return }
        self.size = size
        functions.setSize(handle, Int32(size.width), Int32(size.height))
    }

    /// Centers the map on the region, zoomed to fit it.
    func show(_ region: MKCoordinateRegion) {
        let zoom = MapLibre.zoom(for: region, in: size)
        let camera = (region.center.latitude, region.center.longitude, zoom)
        if let old = self.camera, old == camera { return }
        self.camera = camera
        functions.setCamera(handle, camera.0, camera.1, camera.2, 0, 0)
        MapLibre.trace("camera \(camera.0), \(camera.1), zoom \(camera.2) in \(size.width)x\(size.height)")
    }

    /// Shows the newest frame, if there is a newer one.
    func present() {
        guard let view = view.object else { return }
        var width: Int32 = 0, height: Int32 = 0
        var result = buffer.withUnsafeMutableBufferPointer {
            functions.copyFrame(handle, &generation, $0.baseAddress, $0.count, &width, &height)
        }
        if result < 0 {
            buffer = [UInt8](repeating: 0, count: Int(width) * Int(height) * 4)
            result = buffer.withUnsafeMutableBufferPointer {
                functions.copyFrame(handle, &generation, $0.baseAddress, $0.count, &width, &height)
            }
        }
        guard result > 0 else { return }
        if MapLibre.tracing {
            let middle = (Int(height) / 2 * Int(width) + Int(width) / 2) * 4
            let pixel = buffer.count >= middle + 4 ? buffer[middle..<middle + 4].map { String($0) }.joined(separator: ",") : "?"
            MapLibre.trace("frame \(generation), \(width)x\(height), middle \(pixel)")
        }
        let layer = NSObject(view).sendLayer()
        buffer.withUnsafeBytes {
            layer.setPixels($0.baseAddress, width: Int(width), height: Int(height), opaque: true, layout: 2)
        }
    }

    /// Polls for frames on the main queue until the map view goes: MapLibre
    /// renders continuously while tiles load and the camera moves.
    func startPresenting() {
        lock.withLock {
            guard !scheduled else { return }
            scheduled = true
        }
        tick()
    }

    private func tick() {
        Dispatch.onMain(after: 33) { [weak self] in
            guard let self, self.view.object != nil else { return }
            self.present()
            self.tick()
        }
    }
}
