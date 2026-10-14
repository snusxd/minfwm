#pragma once

#include "WindowBackend.hpp"
#include "WindowPool.hpp"
#include "WindowPosition.hpp"
#include "../core/DisplayState.hpp"
#include <optional>
#include <utility>

namespace minfwm {

// Backend operations are injected so partial failures exercise the same
// hide/show and restoration path as the daemon, without live AX windows.
class WindowRenderer final {
public:
    WindowRenderer(WindowBackend& ax, WindowBackend& yabai, WindowPositionCheck check = isWindowAtPosition)
        : m_ax(ax), m_yabai(yabai), m_checkPosition(std::move(check)) {}

    BackendResult render(ClientWindow& window, core::Rect physical, double now);
    BackendResult renderOverview(ClientWindow& window, core::Rect physical, float scale, double now);
    BackendResult suspend(ClientWindow& window, double now);
    BackendResult releaseToNative(ClientWindow& window, core::Rect physical, double now);
    BackendResult setPinnedLayer(ClientWindow& window, bool alwaysOnTop);
    BackendResult hide(ClientWindow& window, core::Rect physical, core::Rect displayBounds, double now,
                       std::optional<core::Point> parkingPosition = std::nullopt);
    BackendResult restore(ClientWindow& window, double now);
    bool acceptNativeGeometry(ClientWindow& window, core::Rect physical, const core::DisplayState& state);

private:
    BackendResult move(ClientWindow& window, int x, int y);
    BackendResult setLayer(ClientWindow& window, int layer);
    BackendResult restoreLayer(ClientWindow& window);
    BackendResult resetTransform(ClientWindow& window);

    WindowBackend& m_ax;
    WindowBackend& m_yabai;
    WindowPositionCheck m_checkPosition;
};

} // namespace minfwm
