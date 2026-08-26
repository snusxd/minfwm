#pragma once

#import <ApplicationServices/ApplicationServices.h>
#include <cstdint>

namespace minfwm {

enum class BackendCode {
    ok,
    unavailable,
    unsupported,
    failed,
};

struct BackendResult {
    BackendCode code = BackendCode::failed;

    bool succeeded() const { return code == BackendCode::ok; }
};

class WindowBackend {
public:
    virtual ~WindowBackend() = default;

    virtual BackendResult move(AXUIElementRef element, uint32_t wid, int x, int y) = 0;
    virtual BackendResult resize(AXUIElementRef element, uint32_t wid, float width, float height) = 0;
    virtual BackendResult setLayer(AXUIElementRef element, uint32_t wid, int layer) = 0;
    virtual BackendResult setHidden(AXUIElementRef element, uint32_t wid, bool hidden) = 0;
    virtual BackendResult restore(AXUIElementRef element, uint32_t wid, int x, int y,
                                  float width, float height) = 0;
};

} // namespace minfwm
