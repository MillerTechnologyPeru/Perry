// A C interface to MapLibre Native for Perry's MapKit: one map per thread,
// rendered offscreen through MapLibre's headless frontend (EGL and OpenGL
// ES), its newest frame kept for the map view to show.
//
// Each map has a thread of its own running MapLibre's run loop, on which
// the map, its renderer and its GL context live. The caller's thread only
// posts changes (size, camera) to that loop and copies finished frames out.
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
#include <memory>
#include <mutex>
#include <string>
#include <thread>
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

} // namespace

struct pml_map {
    // Set at creation, read on the map's thread.
    std::string style;
    std::string cache;
    float pixelRatio = 1;
    int width = 1, height = 1;
    pml_frame_callback callback = nullptr;
    void *context = nullptr;

    std::thread thread;
    std::mutex lock;
    std::condition_variable started;
    mln::util::RunLoop *loop = nullptr;

    // On the map's thread.
    std::unique_ptr<mln::HeadlessFrontend> frontend;
    std::unique_ptr<mln::Map> map;
    std::unique_ptr<FrameObserver> observer;
    bool readPending = false;

    // The newest frame, under the lock.
    std::vector<uint8_t> pixels;
    int frameWidth = 0, frameHeight = 0;
    uint64_t generation = 0;

    void run();
    void readFrame();
};

void FrameObserver::onDidFinishRenderingFrame(const RenderFrameStatus &) {
    if (map->readPending) return;
    map->readPending = true;
    map->loop->invoke([map = map] { map->readFrame(); });
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

void pml_map::run() {
    mln::util::RunLoop runLoop;
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
    {
        std::lock_guard<std::mutex> guard(lock);
        loop = &runLoop;
    }
    started.notify_all();
    runLoop.run();
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
    map->thread = std::thread([map] { map->run(); });
    std::unique_lock<std::mutex> guard(map->lock);
    map->started.wait(guard, [map] { return map->loop != nullptr; });
    return map;
}

void pml_map_destroy(pml_map *map) {
    if (!map) return;
    map->loop->invoke([loop = map->loop] { loop->stop(); });
    map->thread.join();
    delete map;
}

void pml_map_set_size(pml_map *map, int width, int height) {
    if (!map || width <= 0 || height <= 0) return;
    map->loop->invoke([map, width, height] {
        mln::Size size{static_cast<uint32_t>(width), static_cast<uint32_t>(height)};
        map->frontend->setSize(size);
        map->map->setSize(size);
    });
}

void pml_map_set_camera(pml_map *map, double latitude, double longitude, double zoom, double bearing, double pitch) {
    if (!map) return;
    map->loop->invoke([map, latitude, longitude, zoom, bearing, pitch] {
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
