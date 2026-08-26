#include "Visibility.hpp"

namespace minfwm::core {

VisibilityPolicy::VisibilityPolicy(float overscanBuffer) noexcept
    : m_overscanBuffer(overscanBuffer) {}

float VisibilityPolicy::overscanBuffer() const noexcept {
    return m_overscanBuffer;
}

bool VisibilityPolicy::intersectsViewport(const Rect& window, const Rect& viewport) const noexcept {
    return window.intersects(viewport.expanded(m_overscanBuffer));
}

bool VisibilityPolicy::shouldRender(const Rect& window, const Rect& viewport, bool focused) const noexcept {
    return focused || intersectsViewport(window, viewport);
}

} // namespace minfwm::core
