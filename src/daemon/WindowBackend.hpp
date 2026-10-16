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
    // A native interaction must retain presentation even on an uncertain ACK.
    virtual BackendResult movePreservingTransform(AXUIElementRef, uint32_t, int, int) { return {BackendCode::unsupported}; }
    virtual BackendResult moveNative(AXUIElementRef, uint32_t, int, int) { return {BackendCode::unsupported}; }
    virtual bool hasTransform(uint32_t) const { return false; }
    virtual bool nativeMovePreservesLayer() const { return false; }
    virtual BackendResult resize(AXUIElementRef element, uint32_t wid, float width, float height) = 0;
    virtual BackendResult setLayer(AXUIElementRef element, uint32_t wid, int layer) = 0;
    virtual BackendResult setPinnedLayer(AXUIElementRef element, uint32_t wid, bool alwaysOnTop) {
        return setLayer(element, wid, alwaysOnTop ? kCGPopUpMenuWindowLevelKey : kCGNormalWindowLevelKey);
    }
    virtual BackendResult setHidden(AXUIElementRef element, uint32_t wid, bool hidden) = 0;
    virtual BackendResult resetTransform(uint32_t) { return {BackendCode::ok}; }
    virtual bool usesTransforms() const { return false; }
    virtual bool supportsOverview() const { return false; }
    virtual BackendResult presentOverview(AXUIElementRef, uint32_t, int, int, float) { return {BackendCode::unsupported}; }
    virtual BackendResult presentOverviewPreservingTransform(AXUIElementRef, uint32_t, int, int, float) { return {BackendCode::unsupported}; }
    virtual BackendResult restore(AXUIElementRef element, uint32_t wid, int x, int y,
                                  float width, float height) {
        const BackendResult moved = move(element, wid, x, y);
        const BackendResult resized = resize(element, wid, width, height);
        return moved.succeeded() ? resized : moved;
    }
};

} // namespace minfwm
