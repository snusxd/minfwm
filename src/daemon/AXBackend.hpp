#pragma once

#include "WindowBackend.hpp"

namespace minfwm {

class AXBackend final : public WindowBackend {
public:
    BackendResult move(AXUIElementRef element, uint32_t wid, int x, int y) override;
    BackendResult resize(AXUIElementRef element, uint32_t wid, float width, float height) override;
    BackendResult setLayer(AXUIElementRef element, uint32_t wid, int layer) override;
    BackendResult setHidden(AXUIElementRef element, uint32_t wid, bool hidden) override;
    BackendResult restore(AXUIElementRef element, uint32_t wid, int x, int y,
                          float width, float height) override;
};

} // namespace minfwm
