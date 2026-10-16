#pragma once

#include <ApplicationServices/ApplicationServices.h>
#include "../core/Geometry.hpp"
#include <cstdint>
#include <functional>
#include <optional>
#include <unordered_set>
#include <vector>

namespace minfwm {

using WindowPositionCheck = std::function<bool(AXUIElementRef, uint32_t, int, int)>;

struct OnscreenWindowSnapshotEntry {
    uint32_t wid = 0;
    CGRect frame{};
};

// WindowServer bounds are authoritative after an SA move: the application's
// cached AX position may not have caught up with the server-side operation.
bool isWindowAtPosition(AXUIElementRef element, uint32_t wid, int x, int y);
bool readWindowPosition(AXUIElementRef element, uint32_t wid, CGPoint& point);
bool windowPositionMatches(CGPoint actual, int x, int y);
std::optional<std::unordered_set<uint32_t>> readOnscreenWindowIds();
std::optional<std::vector<OnscreenWindowSnapshotEntry>> readOnscreenWindowSnapshot();
std::optional<std::unordered_set<uint32_t>> readSessionWindowIds();

struct NativeWindowPresentation {
    CGRect frame;
    CGAffineTransform transform;
};
std::optional<NativeWindowPresentation> readNativeWindowPresentation(uint32_t wid);
bool nativePresentationMatches(const NativeWindowPresentation& presentation, core::Rect physical, float scale);
bool needsNativePresentationRecovery(const NativeWindowPresentation& presentation);

} // namespace minfwm
