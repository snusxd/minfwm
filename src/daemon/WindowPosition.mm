#include "WindowPosition.hpp"
#include "CFRAII.hpp"

#include <cmath>

namespace minfwm {
std::optional<std::unordered_set<uint32_t>> readOnscreenWindowIds() {
    auto windows = CFRef<CFArrayRef>::adopt(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
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
