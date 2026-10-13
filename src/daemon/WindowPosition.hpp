#pragma once

#include <ApplicationServices/ApplicationServices.h>
#include <cstdint>
#include <functional>
#include <optional>
#include <unordered_set>

namespace minfwm {

using WindowPositionCheck = std::function<bool(AXUIElementRef, uint32_t, int, int)>;

// WindowServer bounds are authoritative after an SA move: the application's
// cached AX position may not have caught up with the server-side operation.
bool isWindowAtPosition(AXUIElementRef element, uint32_t wid, int x, int y);
bool readWindowPosition(AXUIElementRef element, uint32_t wid, CGPoint& point);
bool windowPositionMatches(CGPoint actual, int x, int y);
std::optional<std::unordered_set<uint32_t>> readOnscreenWindowIds();

} // namespace minfwm
