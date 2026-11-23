// A C interface to MapLibre Native for Perry's MapKit: maps rendered
// offscreen through MapLibre's headless frontend (EGL and OpenGL ES), each
// one's newest frame kept for its map view to show.
//
// Every map lives on one thread, started with the first map, which runs
// MapLibre's run loop: the maps, their renderers and their GL contexts are
// made, used and let go there, as MapLibre expects of maps that are alive
// together. The caller's thread only posts changes (size, camera) to that
// loop and copies finished frames out.
// After each frame MapLibre renders, its pixels are read back and kept;
// the callback then tells the caller a newer frame is ready.
//
// Built against MapLibre Native (BSD 2-clause) by Scripts/build-maplibre.sh
// into libPerryMapLibre.so, which PerryMapKit loads at run time.

#include "perry_maplibre.h"

#include <mln/gfx/backend_scope.hpp>
#include <mln/gfx/headless_frontend.hpp>
#include <mln/map/map.hpp>
#include <mln/map/map_observer.hpp>
#include <mln/map/map_options.hpp>
#include <mln/storage/resource_options.hpp>
#include <mln/style/style.hpp>
#include <mln/util/image.hpp>
#include <mln/util/run_loop.hpp>

#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <future>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace {

/// Hears when a frame is done, to read it back once the renderer is out of
/// the way.
class FrameObserver : public mln::MapObserver {
public:
    explicit FrameObserver(pml_map *map) : map(map) {}
    void onDidFinishRenderingFrame(const RenderFrameStatus &) override;
    void onDidFailLoadingMap(mln::MapLoadError, const std::string &message) override;

private:
    pml_map *map;
};

/// The thread every map lives on, and its run loop; it lasts as long as the
/// program.
struct Host {
    std::mutex lock;
    std::condition_variable started;
    mln::util::RunLoop *loop = nullptr;

    // On the host's thread: the maps that are open, by their numbers. A
    // frame's read is posted to the loop and may come up after its map has
    // closed, so it finds its map here.
    std::unordered_map<uint64_t, pml_map *> maps;
    uint64_t lastNumber = 0;

    static Host &shared() {
        static Host *host = new Host();
        return *host;
    }

    Host() {
        std::thread([this] {
            mln::util::RunLoop runLoop;
            {
                std::lock_guard<std::mutex> guard(lock);
                loop = &runLoop;
            }
            started.notify_all();
            runLoop.run();
        }).detach();
        std::unique_lock<std::mutex> guard(lock);
        started.wait(guard, [this] { return loop != nullptr; });
    }

    /// Runs `work` on the host's thread and waits for it.
    template <typename Work>
    void perform(Work work) {
        std::promise<void> done;
        loop->invoke([&] {
            work();
            done.set_value();
        });
        done.get_future().wait();
    }
};

} // namespace

struct pml_map {
    // Set at creation, read on the host's thread.
    std::string style;
    std::string cache;
    float pixelRatio = 1;
    int width = 1, height = 1;
    pml_frame_callback callback = nullptr;
    void *context = nullptr;

    std::mutex lock;

    // On the host's thread.
    uint64_t number = 0;
    std::unique_ptr<mln::HeadlessFrontend> frontend;
    std::unique_ptr<mln::Map> map;
    std::unique_ptr<FrameObserver> observer;
    bool readPending = false;

    // The newest frame, under the lock.
    std::vector<uint8_t> pixels;
    int frameWidth = 0, frameHeight = 0;
    uint64_t generation = 0;

    void open();
    void close();
    void readFrame();
};

void FrameObserver::onDidFinishRenderingFrame(const RenderFrameStatus &) {
    if (map->readPending) return;
    map->readPending = true;
    Host &host = Host::shared();
    host.loop->invoke([&host, number = map->number] {
        auto found = host.maps.find(number);
        if (found != host.maps.end()) found->second->readFrame();
    });
}

void FrameObserver::onDidFailLoadingMap(mln::MapLoadError, const std::string &message) {
    fprintf(stderr, "perry: MapLibre: the map didn't load: %s\n", message.c_str());
}

void pml_map::readFrame() {
    readPending = false;
    // The frontend reads with its GL context current only while it renders.
    mln::gfx::BackendScope scope{*frontend->getBackend()};
    mln::PremultipliedImage image = frontend->readStillImage();
    if (!image.valid()) return;
    {
        std::lock_guard<std::mutex> guard(lock);
        pixels.assign(image.data.get(), image.data.get() + image.bytes());
        frameWidth = static_cast<int>(image.size.width);
        frameHeight = static_cast<int>(image.size.height);
        generation += 1;
    }
    if (callback) callback(context);
}

void pml_map::open() {
    Host &host = Host::shared();
    number = ++host.lastNumber;
    host.maps[number] = this;
    frontend = std::make_unique<mln::HeadlessFrontend>(
        mln::Size{static_cast<uint32_t>(width), static_cast<uint32_t>(height)}, pixelRatio);
    observer = std::make_unique<FrameObserver>(this);
    mln::ResourceOptions resources;
    if (!cache.empty()) resources.withCachePath(cache);
    map = std::make_unique<mln::Map>(*frontend, *observer,
                                     mln::MapOptions()
                                         .withMapMode(mln::MapMode::Continuous)
                                         .withSize(frontend->getSize())
                                         .withPixelRatio(pixelRatio),
                                     resources);
    map->getStyle().loadURL(style);
}

void pml_map::close() {
    Host::shared().maps.erase(number);
    map.reset();
    observer.reset();
    frontend.reset();
}

extern "C" {

pml_map *pml_map_create(int width, int height, float pixel_ratio, const char *style_url, const char *cache_path,
                        pml_frame_callback callback, void *context) {
    if (!style_url) return nullptr;
    // MapLibre's EGL display is eglGetDisplay(EGL_DEFAULT_DISPLAY), which on
    // Mesa without a window system's display (the program's windows are
    // SDL's) fails to initialize: it renders offscreen on Mesa's surfaceless
    // platform, as Perry's OpenGL ES contexts do, unless EGL_PLATFORM says
    // otherwise.
    setenv("EGL_PLATFORM", "surfaceless", 0);
    auto *map = new pml_map();
    map->style = style_url;
    map->cache = cache_path ? cache_path : "";
    map->width = width > 0 ? width : 1;
    map->height = height > 0 ? height : 1;
    map->pixelRatio = pixel_ratio > 0 ? pixel_ratio : 1;
    map->callback = callback;
    map->context = context;
    Host::shared().perform([map] { map->open(); });
    return map;
}

void pml_map_destroy(pml_map *map) {
    if (!map) return;
    // Changes posted before this run first, and find the map still open.
    Host::shared().perform([map] { map->close(); });
    delete map;
}

void pml_map_set_size(pml_map *map, int width, int height) {
    if (!map || width <= 0 || height <= 0) return;
    Host::shared().loop->invoke([map, width, height] {
        mln::Size size{static_cast<uint32_t>(width), static_cast<uint32_t>(height)};
        map->frontend->setSize(size);
        map->map->setSize(size);
    });
}

void pml_map_set_camera(pml_map *map, double latitude, double longitude, double zoom, double bearing, double pitch) {
    if (!map) return;
    Host::shared().loop->invoke([map, latitude, longitude, zoom, bearing, pitch] {
        map->map->jumpTo(mln::CameraOptions()
                             .withCenter(mln::LatLng(latitude, longitude))
                             .withZoom(zoom)
                             .withBearing(bearing)
                             .withPitch(pitch));
    });
}

int pml_map_copy_frame(pml_map *map, uint64_t *generation, uint8_t *buffer, size_t capacity, int *width, int *height) {
    if (!map) return 0;
    std::lock_guard<std::mutex> guard(map->lock);
    if (map->generation == 0 || (generation && *generation == map->generation)) return 0;
    if (width) *width = map->frameWidth;
    if (height) *height = map->frameHeight;
    size_t bytes = map->pixels.size();
    if (!buffer || capacity < bytes) return -1;
    std::memcpy(buffer, map->pixels.data(), bytes);
    if (generation) *generation = map->generation;
    return 1;
}

} // extern "C"
