#pragma once

#include "Geometry.hpp"
#include <cmath>

namespace minfwm::core {

[[nodiscard]] inline bool userMovedWindow(bool windowDragged, bool cameraUnchanged,
                                          Rect start, Rect end) noexcept {
    return windowDragged && cameraUnchanged &&
        std::isfinite(start.x) && std::isfinite(start.y) &&
        std::isfinite(end.x) && std::isfinite(end.y) &&
        (std::abs(end.x - start.x) > 1.0f || std::abs(end.y - start.y) > 1.0f);
}

// Only an observed user drag may change the canvas that owns a window.
[[nodiscard]] inline bool shouldTransferWindow(bool windowDragged, bool cameraUnchanged,
                                                Rect start, Rect end, std::int64_t sourceDisplay,
                                                std::int64_t targetDisplay) noexcept {
    return sourceDisplay != targetDisplay && userMovedWindow(windowDragged, cameraUnchanged, start, end);
}

[[nodiscard]] inline bool shouldReleaseToIgnoredDisplay(bool windowDragged, bool cameraUnchanged,
                                                        Rect start, Rect end, bool targetIgnored) noexcept {
    return targetIgnored && userMovedWindow(windowDragged, cameraUnchanged, start, end);
}

[[nodiscard]] inline bool frameFitsDisplay(Rect frame, Rect bounds) noexcept {
    return std::isfinite(frame.x) && std::isfinite(frame.y) &&
        std::isfinite(frame.right()) && std::isfinite(frame.bottom()) &&
        frame.x >= bounds.x && frame.y >= bounds.y &&
        frame.right() <= bounds.right() && frame.bottom() <= bounds.bottom();
}

[[nodiscard]] inline bool shouldPreferNativePosition(Rect frame, Rect displayBounds,
                                                     Rect usableBounds) noexcept {
    // AppKit can clamp native frames at the menu bar or a display edge. Focus
    // cannot override those limits; such positions need a presentation transform.
    return frameFitsDisplay(frame, displayBounds) && canUseNativePosition(frame, usableBounds);
}

} // namespace minfwm::core
