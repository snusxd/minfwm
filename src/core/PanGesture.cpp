#include "PanGesture.hpp"

namespace minfwm::core {

PanUpdate PanGesture::handle(PanEvent event, bool modifiersHeld, std::int64_t displayId,
                             Point mouseDelta) noexcept {
    if (event == PanEvent::mouseDown) {
        reset();
        if (modifiersHeld) {
            m_displayId = displayId;
            m_dragEnabled = true;
        }
    }
    if (!modifiersHeld) m_dragEnabled = false;

    PanUpdate update;
    update.consume = m_displayId.has_value() && event != PanEvent::modifiersChanged;
    update.displayId = m_displayId;
    if (event == PanEvent::mouseDragged && isPanning()) {
        update.delta = {-mouseDelta.x, -mouseDelta.y};
    }
    // Keep capture after modifier release so the matching mouse-up cannot
    // reach an application that never received the mouse-down.
    if (event == PanEvent::mouseUp) reset();
    return update;
}

void PanGesture::reset() noexcept {
    m_displayId.reset();
    m_dragEnabled = false;
}

bool PanGesture::isPanning() const noexcept {
    return m_displayId.has_value() && m_dragEnabled;
}

} // namespace minfwm::core
