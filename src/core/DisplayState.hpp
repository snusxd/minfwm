#pragma once

#include <map>

#include "Camera.hpp"

namespace minfwm::core {

class DisplayState final {
public:
    explicit DisplayState(DisplayGeometry geometry) noexcept;

    [[nodiscard]] std::int64_t id() const noexcept;
    [[nodiscard]] const DisplayGeometry& geometry() const noexcept;

    [[nodiscard]] Camera& camera() noexcept;
    [[nodiscard]] const Camera& camera() const noexcept;
    [[nodiscard]] Rect viewport() const noexcept;

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
    std::map<int, Point> m_bookmarks;
};

} // namespace minfwm::core
