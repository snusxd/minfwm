#include "DisplayState.hpp"
#include <algorithm>
#include <cmath>

namespace minfwm::core {

bool DisplayState::setScaleAt(float scale, Point anchor) noexcept {
    if (!std::isfinite(scale) || scale < 0.2f || scale > 1 ||
        !std::isfinite(anchor.x) || !std::isfinite(anchor.y)) return false;
    const Point world = physicalToVirtual(anchor);
    const float x = world.x - (anchor.x - m_geometry.bounds.x) / scale;
    const float y = world.y - (anchor.y - m_geometry.bounds.y) / scale;
    if (!m_camera.setPosition(x, y)) return false;
    m_scale = scale;
    return true;
}

bool DisplayState::requestZoom(float delta, Point anchor) noexcept {
    if (!std::isfinite(delta) || !std::isfinite(anchor.x) || !std::isfinite(anchor.y)) return false;
    m_targetScale = std::clamp(m_targetScale * std::exp(std::clamp(delta * 0.015f, -10.0f, 10.0f)), 0.2f, 1.0f);
    m_zoomAnchor = anchor;
    return true;
}

void DisplayState::advanceZoom(double elapsed) noexcept {
    if (!std::isfinite(elapsed) || elapsed <= 0 || m_scale == m_targetScale) return;
    float next = m_targetScale + (m_scale - m_targetScale) * std::exp(-18.0 * elapsed);
    if (std::abs(next - m_targetScale) < 0.0001f) next = m_targetScale;
    if (!setScaleAt(next, m_zoomAnchor)) m_targetScale = m_scale;
}

void DisplayState::resetZoom(Point anchor) noexcept {
    if (setScaleAt(1, anchor)) m_targetScale = 1;
}

DisplayState::DisplayState(DisplayGeometry geometry) noexcept
    : m_geometry(geometry) {}

std::int64_t DisplayState::id() const noexcept {
    return m_geometry.id;
}

const DisplayGeometry& DisplayState::geometry() const noexcept {
    return m_geometry;
}

Camera& DisplayState::camera() noexcept {
    return m_camera;
}

const Camera& DisplayState::camera() const noexcept {
    return m_camera;
}

Rect DisplayState::viewport() const noexcept {
    const Point cameraPosition = m_camera.position();
    return { cameraPosition.x, cameraPosition.y, m_geometry.bounds.w / m_scale, m_geometry.bounds.h / m_scale };
}

Point DisplayState::virtualToPhysical(Point point) const noexcept {
    const Point cameraPosition = m_camera.position();
    return {
        m_geometry.bounds.x + (point.x - cameraPosition.x) * m_scale,
        m_geometry.bounds.y + (point.y - cameraPosition.y) * m_scale
    };
}

Point DisplayState::physicalToVirtual(Point point) const noexcept {
    const Point cameraPosition = m_camera.position();
    return {
        (point.x - m_geometry.bounds.x) / m_scale + cameraPosition.x,
        (point.y - m_geometry.bounds.y) / m_scale + cameraPosition.y
    };
}

Rect DisplayState::virtualToPhysical(Rect rect) const noexcept {
    const Point physicalOrigin = virtualToPhysical(Point{ rect.x, rect.y });
    return { physicalOrigin.x, physicalOrigin.y, rect.w * m_scale, rect.h * m_scale };
}

Rect DisplayState::physicalToVirtual(Rect rect) const noexcept {
    const Point virtualOrigin = physicalToVirtual(Point{ rect.x, rect.y });
    return { virtualOrigin.x, virtualOrigin.y, rect.w / m_scale, rect.h / m_scale };
}

void DisplayState::saveBookmark(int index) {
    m_bookmarks[index] = m_camera.position();
}

bool DisplayState::loadBookmark(int index) noexcept {
    const auto bookmark = m_bookmarks.find(index);
    if (bookmark == m_bookmarks.end()) return false;

    m_camera.setPosition(bookmark->second.x, bookmark->second.y);
    return true;
}

} // namespace minfwm::core
