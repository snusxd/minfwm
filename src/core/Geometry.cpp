#include "Geometry.hpp"

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

} // namespace minfwm::core
