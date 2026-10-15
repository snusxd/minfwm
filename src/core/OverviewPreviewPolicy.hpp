#pragma once

#include <cmath>

namespace minfwm::core {

// Keep directly interactive windows live. Adapters provide focus and drag state.
struct OverviewPreviewInteraction {
    bool focused = false;
    bool whitelisted = false;
    bool pinned = false;
    bool dragged = false;
    bool auxiliary = false;
};

[[nodiscard]] inline bool overviewPreviewEligible(OverviewPreviewInteraction interaction) noexcept {
    return !interaction.focused && !interaction.whitelisted && !interaction.pinned &&
           !interaction.dragged && !interaction.auxiliary;
}

[[nodiscard]] inline bool overviewPreviewActive(bool active, float scale, bool enabled,
                                                bool /*rewindOnFocus*/, bool permitted) noexcept {
    // Focus rewind controls selection behavior, not thumbnail availability.
    if (!enabled || !permitted || !std::isfinite(scale) || scale <= 0 || scale >= 1) {
        return false;
    }
    return active ? scale < .55f : scale <= .45f;
}

} // namespace minfwm::core
