#pragma once

#include "Geometry.hpp"

namespace minfwm::core {

class VisibilityPolicy final {
public:
    explicit VisibilityPolicy(float overscanBuffer = 0.0f) noexcept;

    [[nodiscard]] float overscanBuffer() const noexcept;
    [[nodiscard]] bool intersectsViewport(const Rect& window, const Rect& viewport) const noexcept;
    [[nodiscard]] bool shouldRender(const Rect& window, const Rect& viewport, bool focused) const noexcept;

private:
    float m_overscanBuffer;
};

} // namespace minfwm::core
