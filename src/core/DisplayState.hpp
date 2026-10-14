#pragma once

#include <map>

#include "Camera.hpp"

namespace minfwm::core {

class DisplayState final {
public:
    explicit DisplayState(DisplayGeometry geometry) noexcept;

    [[nodiscard]] std::int64_t id() const noexcept;
    [[nodiscard]] const DisplayGeometry& geometry() const noexcept;
    [[nodiscard]] bool updateGeometry(DisplayGeometry geometry) noexcept;

    [[nodiscard]] Camera& camera() noexcept;
    [[nodiscard]] const Camera& camera() const noexcept;
    [[nodiscard]] Rect viewport() const noexcept;
    [[nodiscard]] float scale() const noexcept { return m_scale; }
    [[nodiscard]] bool overviewActive() const noexcept { return m_return.has_value() || m_scale != 1 || m_targetScale != 1; }
    bool animateCameraTo(Point target) noexcept;
    void cancelCameraAnimation() noexcept;
    bool setScaleAt(float scale, Point physicalAnchor) noexcept;
    bool requestZoom(float scrollDelta, Point physicalAnchor) noexcept;
    void advanceZoom(double elapsedSeconds, float animationSpeed = 1.0f,
                     bool animationsEnabled = true) noexcept;
    void resetZoom(Point physicalAnchor) noexcept;
    bool beginReturn(std::optional<Point> targetCamera = {}, std::optional<Point> physicalAnchor = {}) noexcept;
    [[nodiscard]] bool returning() const noexcept { return m_return.has_value(); }

    // Both points use the same canonical physical coordinate system.
    // The physical display origin may be negative.
    [[nodiscard]] Point virtualToPhysical(Point point) const noexcept;
    [[nodiscard]] Point physicalToVirtual(Point point) const noexcept;
    [[nodiscard]] Rect virtualToPhysical(Rect rect) const noexcept;
    [[nodiscard]] Rect physicalToVirtual(Rect rect) const noexcept;

    void saveBookmark(int index);
    [[nodiscard]] bool loadBookmark(int index) noexcept;

private:
    DisplayGeometry m_geometry;
    Camera m_camera;
    float m_scale = 1;
    float m_targetScale = 1;
    Point m_zoomAnchor;
    struct ReturnTransition {
        Point fromCenter;
        Point physicalAnchor;
        Point targetCamera;
        float fromScale;
        double elapsed = 0;
    };
    std::optional<ReturnTransition> m_return;
    struct CameraTransition {
        Point from;
        Point target;
        double elapsed = 0;
    };
    std::optional<CameraTransition> m_cameraTransition;
    std::map<int, Point> m_bookmarks;
};

} // namespace minfwm::core
