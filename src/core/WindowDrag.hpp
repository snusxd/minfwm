#pragma once

#include "DisplayState.hpp"

namespace minfwm::core {

// Derive the drag offset from the model's projected frame. The OS-reported
// frame can be clamped at a display edge and is not a reliable model origin.
[[nodiscard]] inline Point dragPointerOffset(Point pointer, Rect projectedFrame) noexcept {
    return {pointer.x - projectedFrame.x, pointer.y - projectedFrame.y};
}

[[nodiscard]] inline Point draggedVirtualOrigin(const DisplayState& display, Point pointer,
                                                Point pointerOffset) noexcept {
    return display.physicalToVirtual(
        Point{pointer.x - pointerOffset.x, pointer.y - pointerOffset.y});
}

} // namespace minfwm::core
