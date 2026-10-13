#include "Geometry.hpp"
#include <cmath>
#include <limits>

namespace minfwm::core {

Rect Rect::expanded(float amount) const noexcept {
    return { x - amount, y - amount, w + (2.0f * amount), h + (2.0f * amount) };
}

Rect Rect::translated(Point delta) const noexcept {
    return { x + delta.x, y + delta.y, w, h };
}

bool Rect::intersects(const Rect& other) const noexcept {
    return right() > other.left() && left() < other.right() &&
           bottom() > other.top() && top() < other.bottom();
}

std::optional<std::int64_t> nearestDisplay(
    std::span<const DisplayGeometry> displays, Point point) noexcept {
    if (!std::isfinite(point.x) || !std::isfinite(point.y)) return std::nullopt;
    std::optional<std::int64_t> closest;
    double closestDistance = std::numeric_limits<double>::infinity();
    for (const auto& display : displays) {
        const Rect& bounds = display.bounds;
        if (!std::isfinite(bounds.x) || !std::isfinite(bounds.y) ||
            !std::isfinite(bounds.w) || !std::isfinite(bounds.h) ||
            !std::isfinite(bounds.right()) || !std::isfinite(bounds.bottom()) ||
            bounds.w <= 0 || bounds.h <= 0) continue;
        if (point.x >= bounds.left() && point.x < bounds.right() &&
            point.y >= bounds.top() && point.y < bounds.bottom()) return display.id;

        const double dx = point.x < bounds.left() ? double(bounds.left()) - point.x :
                          point.x > bounds.right() ? double(point.x) - bounds.right() : 0.0;
        const double dy = point.y < bounds.top() ? double(bounds.top()) - point.y :
                          point.y > bounds.bottom() ? double(point.y) - bounds.bottom() : 0.0;
        const double distance = dx * dx + dy * dy;
        if (distance < closestDistance) {
            closest = display.id;
            closestDistance = distance;
        }
    }
    return closest;
}

} // namespace minfwm::core
