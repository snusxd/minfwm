#include "WindowPosition.hpp"
#include "CFRAII.hpp"

#include <cmath>

namespace minfwm {

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
        if (!windows || CFArrayGetCount(windows.get()) != 1) return false;
        const auto info = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(windows.get(), 0));
        if (!info || CFGetTypeID(info) != CFDictionaryGetTypeID()) return false;
        const auto bounds = static_cast<CFDictionaryRef>(CFDictionaryGetValue(info, kCGWindowBounds));
        CGRect frame{};
        if (!bounds || CFGetTypeID(bounds) != CFDictionaryGetTypeID() ||
            !CGRectMakeWithDictionaryRepresentation(bounds, &frame)) return false;
        point = frame.origin;
        return std::isfinite(point.x) && std::isfinite(point.y);
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
