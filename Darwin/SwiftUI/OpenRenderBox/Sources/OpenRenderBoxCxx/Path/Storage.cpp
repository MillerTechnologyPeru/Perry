//
//  Storage.cpp
//  OpenRenderBox

#if OPENRENDERBOX_CF_CGTYPES

#include <OpenRenderBox/ORBPath.h>
#include <OpenRenderBox/ORBPathCallbacks.h>
#include <OpenRenderBoxCxx/Path/Storage.hpp>
#include <OpenRenderBoxCxx/Util/assert.hpp>

#if ORB_TARGET_OS_DARWIN
#include <CoreGraphics/CoreGraphics.h>
#endif
#include <stdlib.h>
#include <string.h>

namespace ORB {
namespace Path {
atomic_uint Storage::_last_identifier;

// FIXME: Elements are kept in a heap buffer, as bytes: the element, then
// its points. RenderBox keeps small paths inline after the header.
int32_t Storage::point_count(ORBPathElement element) ORB_NOEXCEPT {
    switch (element) {
        case ORBPathElementMoveToPoint:
        case ORBPathElementAddLineToPoint:
            return 2;
        case ORBPathElementAddQuadCurveToPoint:
            return 4;
        case ORBPathElementAddCurveToPoint:
            return 6;
        case ORBPathElementCloseSubpath:
            return 0;
        case ORBPathElementRect:
            return 4;
        case ORBPathElementRoundedRect:
        case ORBPathElementFixedRoundedRectCircular:
        case ORBPathElementFixedRoundedRectContinuous:
            return 6;
        default:
            return -1;
    }
}

Storage::Storage(uint32_t capacity) {
    _unknown = nullptr;
    _external_storage = nullptr;
    _external_size = 0;
    _reserved1 = nullptr;
    _reserved2 = nullptr;
    _reserved3 = nullptr;
    #if ORB_TARGET_OS_DARWIN
    _cached_cgPath = nullptr;
    #endif
    if (capacity <= 63) {
        precondition_failure("invalid capacity");
    }
    uint32_t cappedCapacity = fmin(capacity - 16, 4095);
    _flags = StorageFlags().withCapacity(cappedCapacity);
    _identifier = get_identifier();
}

Storage::Storage(uint32_t capacity, const Storage &storage): Storage(capacity) {
    if (storage.flags().isExternal() && storage.external_size() > 0) {
        reserve(storage.external_size());
        memcpy(buffer(), storage.buffer(), storage.external_size());
        _external_size = storage.external_size();
    }
    _flags = _flags
        .withQuadBezierOrder(storage.flags().isQuadBezierOrder())
        .withCubicBezierOrder(storage.flags().isCubicBezierOrder())
        .withSingleElement(storage.flags().isSingleElement());
}

Storage::~Storage() {
    if (_unknown != nullptr) {
        auto oldValue = _unknown;
        _unknown = nullptr;
        // TODO
    }
    // TODO: MapCache
    #if ORB_TARGET_OS_DARWIN
    if (cachedCGPath() != nullptr) {
        auto oldCache = cachedCGPath();
        _cached_cgPath = nullptr;
        CFRelease(oldCache);
    }
    #endif
    if (flags().isExternal()) {
        free((void *)external_storage());
    }
}

bool Storage::operator==(const Storage &other) const ORB_NOEXCEPT {
    if (actual_size() != other.actual_size()) {
        return false;
    }
    if (actual_size() == 0) {
        return true;
    }
    return memcmp(buffer(), other.buffer(), actual_size()) == 0;
}

void Storage::clear() {
    _external_size = 0;
    _element_count() = 0;
    _flags = _flags.withQuadBezierOrder(false).withCubicBezierOrder(false).withSingleElement(false);
    #if ORB_TARGET_OS_DARWIN
    if (_cached_cgPath != nullptr) {
        CFRelease(_cached_cgPath);
        _cached_cgPath = nullptr;
    }
    #endif
}

void Storage::reserve(uint64_t size) {
    uint64_t capacity = reinterpret_cast<uint64_t>(_reserved1);
    if (flags().isExternal() && size <= capacity) {
        return;
    }
    uint64_t newCapacity = capacity < 64 ? 64 : capacity;
    while (newCapacity < size) {
        newCapacity *= 2;
    }
    void *newBuffer = realloc(flags().isExternal() ? (void *)_external_storage : nullptr, newCapacity);
    _external_storage = reinterpret_cast<Storage *>(newBuffer);
    _reserved1 = reinterpret_cast<void *>(newCapacity);
    _flags = _flags.withExternal(true);
}

bool Storage::append_element(ORBPathElement element, const CGFloat *points, const void *info) {
    if (element >= ORBPathElementInvalid) {
        precondition_failure("invalid path element: %d", element);
    }
    int32_t count = point_count(element);
    if (count < 0) {
        // FIXME: Elements this storage doesn't know yet.
        return false;
    }
    uint64_t size = sizeof(int32_t) + sizeof(CGFloat) * count;
    reserve(_external_size + size);
    uint8_t *end = reinterpret_cast<uint8_t *>(buffer()) + _external_size;
    int32_t value = element;
    memcpy(end, &value, sizeof(int32_t));
    if (count > 0) {
        memcpy(end + sizeof(int32_t), points, sizeof(CGFloat) * count);
    }
    _external_size += size;
    _element_count() += 1;
    _flags = _flags
        .withSingleElement(_element_count() == 1)
        .withQuadBezierOrder(flags().isQuadBezierOrder() || element == ORBPathElementAddQuadCurveToPoint)
        .withCubicBezierOrder(flags().isCubicBezierOrder() || element == ORBPathElementAddCurveToPoint);
    #if ORB_TARGET_OS_DARWIN
    if (_cached_cgPath != nullptr) {
        CFRelease(_cached_cgPath);
        _cached_cgPath = nullptr;
    }
    #endif
    return true;
}

bool Storage::apply_elements(void *info, ORBPathApplyCallback callback) const ORB_NOEXCEPT {
    // TODO: Add fast-path checks for special callbacks:
    // - append_element_callback → append_storage(info, this)
    // - NestedCallbacks::apply_elements_callback → apply_elements_fast
    // - NestedCallbacks::single_element_callback → single_element_fast
    // - Mapper::apply_callback with flags check → MapCache::apply
    return apply_elements_(info, callback);
}

bool Storage::apply_elements_(void *info, ORBPathApplyCallback callback) const ORB_NOEXCEPT {
    if (!flags().isExternal()) {
        return true;
    }
    const uint8_t *cursor = reinterpret_cast<const uint8_t *>(buffer());
    const uint8_t *end = cursor + _external_size;
    while (cursor < end) {
        int32_t value;
        memcpy(&value, cursor, sizeof(int32_t));
        auto element = static_cast<ORBPathElement>(value);
        int32_t count = point_count(element);
        // Points are copied out, as the buffer may not be aligned for them.
        CGFloat points[8] = {};
        if (count > 0) {
            memcpy(points, cursor + sizeof(int32_t), sizeof(CGFloat) * count);
        }
        if (!callback(info, element, points, nullptr)) {
            return false;
        }
        cursor += sizeof(int32_t) + sizeof(CGFloat) * count;
    }
    return true;
}

#if ORB_TARGET_OS_DARWIN
CGPathRef Storage::cgpath() const ORB_NOEXCEPT {
    CGPathRef cached = __atomic_load_n(&_cached_cgPath, __ATOMIC_SEQ_CST);
    if (cached != nullptr) {
        return cached;
    }
    static const ORBPathCallbacks callbacks = {
        {},
        nullptr,
        nullptr,
        .apply = +[](const void *object, void *info, ORBPathApplyCallback callback) -> bool {
            auto storage = reinterpret_cast<const ORB::Path::Storage *>(object);
            return storage->apply_elements(info, callback);
        },
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
    };
    ORBPath path = {
        const_cast<ORBPathStorage *>(reinterpret_cast<const ORBPathStorage *>(this)),
        &callbacks
    };
    CGPathRef new_path = ORBPathCopyCGPath(path);
    CGPathRef expected = nullptr;
    if (__atomic_compare_exchange_n(&_cached_cgPath, &expected, new_path,
                                     false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        return new_path;
    } else {
        CGPathRelease(new_path);
        return expected;
    }
}
#endif

} /* Path */
} /* ORB */

#endif /* OPENRENDERBOX_CF_CGTYPES */
