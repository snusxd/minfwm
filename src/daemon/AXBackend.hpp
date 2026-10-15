#pragma once

#include "WindowBackend.hpp"
#include "WindowPosition.hpp"
#include <utility>

namespace minfwm {

class AXBackend final : public WindowBackend {
public:
    explicit AXBackend(WindowPositionCheck check = isWindowAtPosition) : m_checkPosition(std::move(check)) {}
    BackendResult move(AXUIElementRef element, uint32_t wid, int x, int y) override;
    BackendResult maximize(AXUIElementRef element);
    BackendResult resize(AXUIElementRef element, uint32_t wid, float width, float height) override;
    BackendResult setLayer(AXUIElementRef element, uint32_t wid, int layer) override;
    BackendResult setHidden(AXUIElementRef element, uint32_t wid, bool hidden) override;
    BackendResult restore(AXUIElementRef element, uint32_t wid, int x, int y,
                          float width, float height) override;

private:
    WindowPositionCheck m_checkPosition;
};

} // namespace minfwm
