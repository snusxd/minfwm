#include "DisplayState.hpp"
#include <algorithm>
#include <cmath>

namespace minfwm::core {
bool DisplayState::beginReturn(std::optional<Point> target, std::optional<Point> physicalAnchor) noexcept {
    const Point anchor = physicalAnchor.value_or(Point{m_geometry.bounds.x + m_geometry.bounds.w / 2,
                                                        m_geometry.bounds.y + m_geometry.bounds.h / 2});
    if (!std::isfinite(anchor.x) || !std::isfinite(anchor.y)) return false;
    const Point center = physicalToVirtual(anchor);
    const Point camera = target.value_or(Point{center.x - (anchor.x - m_geometry.bounds.x),
                                               center.y - (anchor.y - m_geometry.bounds.y)});
    if (!std::isfinite(center.x) || !std::isfinite(center.y) ||
        !std::isfinite(camera.x) || !std::isfinite(camera.y)) return false;
    m_return = ReturnTransition{center, anchor, camera, m_scale};
    m_cameraTransition.reset();
    m_targetScale = 1;
    return true;
}

bool DisplayState::animateCameraTo(Point target) noexcept {
    if (!std::isfinite(target.x) || !std::isfinite(target.y)) return false;
    m_cameraTransition = CameraTransition{m_camera.position(), target};
    return true;
}

void DisplayState::cancelCameraAnimation() noexcept {
    m_cameraTransition.reset();
}

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
    if (returning() || !std::isfinite(delta) || !std::isfinite(anchor.x) || !std::isfinite(anchor.y)) return false;
    m_cameraTransition.reset();
    m_targetScale = std::clamp(m_targetScale * std::exp(std::clamp(delta * 0.015f, -10.0f, 10.0f)), 0.2f, 1.0f);
    m_zoomAnchor = anchor;
    return true;
}

void DisplayState::advanceZoom(double elapsed, float animationSpeed, bool animationsEnabled) noexcept {
    if (!animationsEnabled) {
        if (m_return) {
            m_camera.setPosition(m_return->targetCamera.x, m_return->targetCamera.y);
            m_scale = 1;
            m_targetScale = 1;
            m_return.reset();
        } else if (m_cameraTransition) {
            m_camera.setPosition(m_cameraTransition->target.x, m_cameraTransition->target.y);
            m_cameraTransition.reset();
        }
        if (m_scale != m_targetScale) (void)setScaleAt(m_targetScale, m_zoomAnchor);
        return;
    }
    if (!std::isfinite(elapsed) || elapsed <= 0) return;
    if (!std::isfinite(animationSpeed) || animationSpeed <= 0) animationSpeed = 1;
    elapsed *= animationSpeed;
    if (m_return) {
        constexpr double duration = 0.36;
        auto& transition = *m_return;
        transition.elapsed = std::min(duration, transition.elapsed + elapsed);
        const double t = transition.elapsed / duration;
        const double progress = t * t * t * (10 + t * (-15 + t * 6));
        const double scale = std::exp(std::log(transition.fromScale) * (1 - progress));
        const double localX = double(transition.physicalAnchor.x) - m_geometry.bounds.x;
        const double localY = double(transition.physicalAnchor.y) - m_geometry.bounds.y;
        const double endX = double(transition.targetCamera.x) + localX;
        const double endY = double(transition.targetCamera.y) + localY;
        const double centerX = transition.fromCenter.x + (endX - transition.fromCenter.x) * progress;
        const double centerY = transition.fromCenter.y + (endY - transition.fromCenter.y) * progress;
        if (!m_camera.setPosition(centerX - localX / scale, centerY - localY / scale)) {
            m_return.reset();
            m_targetScale = m_scale;
            return;
        }
        m_scale = static_cast<float>(scale);
        if (transition.elapsed == duration) {
            m_camera.setPosition(transition.targetCamera.x, transition.targetCamera.y);
            m_scale = 1;
            m_return.reset();
        }
        return;
    }
    if (m_cameraTransition) {
        constexpr double duration = 0.36;
        auto& transition = *m_cameraTransition;
        transition.elapsed = std::min(duration, transition.elapsed + elapsed);
        const double t = transition.elapsed / duration;
        const double progress = t * t * t * (10 + t * (-15 + t * 6));
        const double x = transition.from.x + (transition.target.x - transition.from.x) * progress;
        const double y = transition.from.y + (transition.target.y - transition.from.y) * progress;
        if (!m_camera.setPosition(static_cast<float>(x), static_cast<float>(y))) {
            m_cameraTransition.reset();
            return;
        }
        if (transition.elapsed == duration) {
            m_camera.setPosition(transition.target.x, transition.target.y);
            m_cameraTransition.reset();
        }
        return;
    }
    if (m_scale == m_targetScale) return;
    float next = m_targetScale + (m_scale - m_targetScale) * std::exp(-18.0 * elapsed);
    if (std::abs(next - m_targetScale) < 0.0001f) next = m_targetScale;
    if (!setScaleAt(next, m_zoomAnchor)) m_targetScale = m_scale;
}

void DisplayState::resetZoom(Point anchor) noexcept {
    if (setScaleAt(1, anchor)) {
        m_targetScale = 1;
        m_return.reset();
        m_cameraTransition.reset();
    }
}

DisplayState::DisplayState(DisplayGeometry geometry) noexcept
    : m_geometry(geometry) {}

std::int64_t DisplayState::id() const noexcept {
    return m_geometry.id;
}

const DisplayGeometry& DisplayState::geometry() const noexcept {
    return m_geometry;
}

bool DisplayState::updateGeometry(DisplayGeometry geometry) noexcept {
    const Rect bounds = geometry.bounds;
    if (geometry.id != m_geometry.id || !std::isfinite(bounds.x) || !std::isfinite(bounds.y) ||
        !std::isfinite(bounds.w) || !std::isfinite(bounds.h) || bounds.w <= 0 || bounds.h <= 0) {
        return false;
    }
    if (bounds.x == m_geometry.bounds.x && bounds.y == m_geometry.bounds.y &&
        bounds.w == m_geometry.bounds.w && bounds.h == m_geometry.bounds.h) {
        return true;
    }
    m_geometry = geometry;
    m_return.reset();
    m_cameraTransition.reset();
    m_targetScale = m_scale;
    return true;
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

    return beginReturn(bookmark->second);
}

} // namespace minfwm::core
