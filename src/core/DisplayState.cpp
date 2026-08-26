#include "DisplayState.hpp"

namespace minfwm::core {

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
    return { cameraPosition.x, cameraPosition.y, m_geometry.bounds.w, m_geometry.bounds.h };
}

Point DisplayState::virtualToPhysical(Point point) const noexcept {
    const Point cameraPosition = m_camera.position();
    return {
        m_geometry.bounds.x + point.x - cameraPosition.x,
        m_geometry.bounds.y + point.y - cameraPosition.y
    };
}

Point DisplayState::physicalToVirtual(Point point) const noexcept {
    const Point cameraPosition = m_camera.position();
    return {
        point.x - m_geometry.bounds.x + cameraPosition.x,
        point.y - m_geometry.bounds.y + cameraPosition.y
    };
}

Rect DisplayState::virtualToPhysical(Rect rect) const noexcept {
    const Point physicalOrigin = virtualToPhysical(Point{ rect.x, rect.y });
    return { physicalOrigin.x, physicalOrigin.y, rect.w, rect.h };
}

Rect DisplayState::physicalToVirtual(Rect rect) const noexcept {
    const Point virtualOrigin = physicalToVirtual(Point{ rect.x, rect.y });
    return { virtualOrigin.x, virtualOrigin.y, rect.w, rect.h };
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
