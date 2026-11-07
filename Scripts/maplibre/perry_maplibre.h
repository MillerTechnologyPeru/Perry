// A C interface to MapLibre Native for Perry's MapKit (perry_maplibre.cpp).
// Sizes are in points; frames are in pixels (points times the pixel ratio),
// RGBA with premultiplied alpha, rows top to bottom.

#ifndef PERRY_MAPLIBRE_H
#define PERRY_MAPLIBRE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PML_EXPORT __attribute__((visibility("default")))

typedef struct pml_map pml_map;

/// Called on the map's own thread when a newer frame is ready.
typedef void (*pml_frame_callback)(void *context);

/// A map of `style_url`'s style, `width` by `height` points, its tiles
/// cached in the database at `cache_path` (none if NULL).
PML_EXPORT pml_map *pml_map_create(int width, int height, float pixel_ratio, const char *style_url, const char *cache_path,
                        pml_frame_callback callback, void *context);
PML_EXPORT void pml_map_destroy(pml_map *map);

PML_EXPORT void pml_map_set_size(pml_map *map, int width, int height);

/// Centers the map, at a zoom level (0 the whole world in 512 points),
/// turned by `bearing` degrees clockwise from north and tilted by `pitch`.
PML_EXPORT void pml_map_set_camera(pml_map *map, double latitude, double longitude, double zoom, double bearing, double pitch);

/// Copies the newest frame if it is newer than `*generation`: 1 when it
/// did (`*generation` then the frame's), 0 when there is none newer, -1
/// when `capacity` is too small (`*width` and `*height` say how big it is).
PML_EXPORT int pml_map_copy_frame(pml_map *map, uint64_t *generation, uint8_t *buffer, size_t capacity, int *width, int *height);

#ifdef __cplusplus
}
#endif

#endif
