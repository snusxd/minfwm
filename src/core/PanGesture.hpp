#pragma once

#include "Geometry.hpp"
#include <optional>

namespace minfwm::core {

enum class PanEvent { mouseDown, mouseDragged, mouseUp, modifiersChanged };

struct PanUpdate {
    bool consume = false;
    std::optional<std::int64_t> displayId;
    Point delta;
};

class PanGesture final {
public:
    PanUpdate handle(PanEvent event, bool modifiersHeld, std::int64_t displayId,
                     Point mouseDelta = {}) noexcept;
    void reset() noexcept;
    [[nodiscard]] bool isPanning() const noexcept;

private:
    std::optional<std::int64_t> m_displayId;
    bool m_dragEnabled = false;
};

} // namespace minfwm::core
