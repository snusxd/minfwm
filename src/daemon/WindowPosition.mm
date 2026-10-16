#include "WindowTrace.hpp"
#include "WindowPosition.hpp"
#include "CFRAII.hpp"

#include <cmath>
#include <dlfcn.h>

namespace minfwm {
namespace {
std::optional<std::unordered_set<uint32_t>> readWindowIds(CGWindowListOption option) {
    auto windows = CFRef<CFArrayRef>::adopt(CGWindowListCopyWindowInfo(option, kCGNullWindowID));
    if (!windows) return {};
    std::unordered_set<uint32_t> result;
    for (CFIndex i = 0; i < CFArrayGetCount(windows.get()); ++i) {
        auto info = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(windows.get(), i));
        if (!info || CFGetTypeID(info) != CFDictionaryGetTypeID()) continue;
        auto number = static_cast<CFNumberRef>(CFDictionaryGetValue(info, kCGWindowNumber));
        uint32_t wid = 0;
        if (number && CFGetTypeID(number) == CFNumberGetTypeID() &&
            CFNumberGetValue(number, kCGWindowIDCFNumberType, &wid) && wid) result.insert(wid);
    }
    return result;
}
}
std::optional<std::unordered_set<uint32_t>> readOnscreenWindowIds() {
    return readWindowIds(kCGWindowListOptionOnScreenOnly);
}
std::optional<std::vector<OnscreenWindowSnapshotEntry>> readOnscreenWindowSnapshot() {
    auto windows = CFRef<CFArrayRef>::adopt(
        CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    if (!windows) return {};
    std::vector<OnscreenWindowSnapshotEntry> result;
    result.reserve(static_cast<size_t>(CFArrayGetCount(windows.get())));
    for (CFIndex i = 0; i < CFArrayGetCount(windows.get()); ++i) {
        auto info = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(windows.get(), i));
        if (!info || CFGetTypeID(info) != CFDictionaryGetTypeID()) continue;
        auto number = static_cast<CFNumberRef>(CFDictionaryGetValue(info, kCGWindowNumber));
        auto bounds = static_cast<CFDictionaryRef>(CFDictionaryGetValue(info, kCGWindowBounds));
        uint32_t wid = 0;
        CGRect frame{};
        if (!number || CFGetTypeID(number) != CFNumberGetTypeID() ||
            !CFNumberGetValue(number, kCGWindowIDCFNumberType, &wid) || !wid || !bounds ||
            CFGetTypeID(bounds) != CFDictionaryGetTypeID() ||
            !CGRectMakeWithDictionaryRepresentation(bounds, &frame)) continue;
        result.push_back({wid, frame});
    }
    return result;
}
std::optional<std::unordered_set<uint32_t>> readSessionWindowIds() {
    return readWindowIds(kCGWindowListOptionAll);
}

std::optional<NativeWindowPresentation> readNativeWindowPresentation(uint32_t wid) {
    // Selected-window native observations and optional SA recovery; no AX calls.
    static void* sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    static auto connection = sky ? reinterpret_cast<int (*)()>(dlsym(sky, "SLSMainConnectionID")) : nullptr;
    static auto bounds = sky ? reinterpret_cast<CGError (*)(int, uint32_t, CGRect*)>(dlsym(sky, "SLSGetWindowBounds")) : nullptr;
    static auto transform = sky ? reinterpret_cast<CGError (*)(int, uint32_t, CGAffineTransform*)>(dlsym(sky, "SLSGetWindowTransform")) : nullptr;
    NativeWindowPresentation result{};
    if (!wid || !connection || !bounds || !transform ||
        bounds(connection(), wid, &result.frame) != kCGErrorSuccess ||
        transform(connection(), wid, &result.transform) != kCGErrorSuccess) return {};
    return result;
}

bool nativePresentationMatches(const NativeWindowPresentation& presentation, core::Rect physical, float scale) {
    if (!std::isfinite(physical.x) || !std::isfinite(physical.y) || !std::isfinite(scale) || scale < .2f || scale > 1) return false;
    const double quantized = std::round(scale * 1000) / 1000;
    const double inverse = 1 / quantized;
    const auto transform = presentation.transform;
    return std::isfinite(transform.a) && std::isfinite(transform.b) && std::isfinite(transform.c) &&
        std::isfinite(transform.d) && std::isfinite(transform.tx) && std::isfinite(transform.ty) &&
        std::abs(transform.a - inverse) <= .001 && std::abs(transform.d - inverse) <= .001 &&
        std::abs(transform.b) <= .001 && std::abs(transform.c) <= .001 &&
        std::abs(transform.tx + std::round(physical.x) * inverse) <= .5 * inverse &&
        std::abs(transform.ty + std::round(physical.y) * inverse) <= .5 * inverse;
}

bool needsNativePresentationRecovery(const NativeWindowPresentation& presentation) {
    const CGRect frame = presentation.frame;
    return std::isfinite(frame.origin.x) && std::isfinite(frame.origin.y) &&
        std::isfinite(frame.size.width) && std::isfinite(frame.size.height) &&
        frame.size.width > 0 && frame.size.height > 0 &&
        (frame.origin.x != 0 || frame.origin.y != 0) &&
        CGAffineTransformEqualToTransform(presentation.transform, CGAffineTransformIdentity);
}
namespace {

bool positionInList(CFArrayRef windows, uint32_t wid, CGPoint& point) {
    if (!windows) return false;
    for (CFIndex index = 0; index < CFArrayGetCount(windows); ++index) {
        const auto info = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(windows, index));
        if (!info || CFGetTypeID(info) != CFDictionaryGetTypeID()) continue;
        const auto number = static_cast<CFNumberRef>(CFDictionaryGetValue(info, kCGWindowNumber));
        uint32_t found = 0;
        if (!number || CFGetTypeID(number) != CFNumberGetTypeID() ||
            !CFNumberGetValue(number, kCGWindowIDCFNumberType, &found) || found != wid) continue;
        const auto bounds = static_cast<CFDictionaryRef>(CFDictionaryGetValue(info, kCGWindowBounds));
        CGRect frame{};
        if (!bounds || CFGetTypeID(bounds) != CFDictionaryGetTypeID() ||
            !CGRectMakeWithDictionaryRepresentation(bounds, &frame) ||
            !std::isfinite(frame.origin.x) || !std::isfinite(frame.origin.y)) return false;
        point = frame.origin;
        return true;
    }
    return false;
}

}

bool windowPositionMatches(CGPoint actual, int x, int y) {
    // Coordinates are logical screen points, including on Retina displays.
    constexpr double tolerance = 0.5;
    return std::isfinite(actual.x) && std::isfinite(actual.y) &&
        std::abs(actual.x - x) <= tolerance && std::abs(actual.y - y) <= tolerance;
}

bool readWindowPosition(AXUIElementRef element, uint32_t wid, CGPoint& point) {
    if (wid != 0) {
        CFRef<CFArrayRef> windows = CFRef<CFArrayRef>::adopt(
            CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, wid));
        if (positionInList(windows.get(), wid, point)) return true;
        // Some real windows (observed with Discord on macOS 27) are absent
        // from the selected-window query but present in the full session list.
        windows = CFRef<CFArrayRef>::adopt(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
        return positionInList(windows.get(), wid, point);
    }

    // The public AX-only path does not resolve private WindowServer IDs.
    CFRef<CFTypeRef> value;
    if (!element || AXUIElementCopyAttributeValue(element, kAXPositionAttribute, value.put()) != kAXErrorSuccess ||
        !value || CFGetTypeID(value.get()) != AXValueGetTypeID()) return false;
    const auto position = static_cast<AXValueRef>(value.get());
    return AXValueGetType(position) == kAXValueTypeCGPoint &&
        AXValueGetValue(position, kAXValueTypeCGPoint, &point) && std::isfinite(point.x) && std::isfinite(point.y);
}

bool isWindowAtPosition(AXUIElementRef element, uint32_t wid, int x, int y) {
    CGPoint point{};
    return readWindowPosition(element, wid, point) && windowPositionMatches(point, x, y);
}

} // namespace minfwm
