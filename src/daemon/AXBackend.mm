#import "AXBackend.hpp"
#include "CFRAII.hpp"

namespace minfwm {

namespace {

BackendResult setPosition(AXUIElementRef element, int x, int y) {
    if (!element) return {BackendCode::failed};
    const CGPoint point = CGPointMake(x, y);
    CFRef<AXValueRef> value = CFRef<AXValueRef>::adopt(AXValueCreate(kAXValueTypeCGPoint, &point));
    if (!value) return {BackendCode::failed};
    const AXError error = AXUIElementSetAttributeValue(element, kAXPositionAttribute, value.get());
    return {error == kAXErrorSuccess ? BackendCode::ok : BackendCode::failed};
}

BackendResult setSize(AXUIElementRef element, float width, float height) {
    if (!element || width <= 0.0f || height <= 0.0f) return {BackendCode::failed};
    const CGSize size = CGSizeMake(width, height);
    CFRef<AXValueRef> value = CFRef<AXValueRef>::adopt(AXValueCreate(kAXValueTypeCGSize, &size));
    if (!value) return {BackendCode::failed};
    const AXError error = AXUIElementSetAttributeValue(element, kAXSizeAttribute, value.get());
    return {error == kAXErrorSuccess ? BackendCode::ok : BackendCode::failed};
}

} // namespace

BackendResult AXBackend::move(AXUIElementRef element, uint32_t, int x, int y) {
    return setPosition(element, x, y);
}

BackendResult AXBackend::resize(AXUIElementRef element, uint32_t, float width, float height) {
    return setSize(element, width, height);
}

BackendResult AXBackend::setLayer(AXUIElementRef, uint32_t, int) {
    return {BackendCode::unsupported};
}

BackendResult AXBackend::setHidden(AXUIElementRef element, uint32_t, bool hidden) {
    if (!element) return {BackendCode::failed};
    CFBooleanRef value = hidden ? kCFBooleanTrue : kCFBooleanFalse;
    const AXError error = AXUIElementSetAttributeValue(element, kAXHiddenAttribute, value);
    return {error == kAXErrorSuccess ? BackendCode::ok : BackendCode::failed};
}

BackendResult AXBackend::restore(AXUIElementRef element, uint32_t wid, int x, int y,
                                 float width, float height) {
    const BackendResult moved = move(element, wid, x, y);
    if (!moved.succeeded()) return moved;
    return resize(element, wid, width, height);
}

} // namespace minfwm
