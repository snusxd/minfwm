#import "AXBackend.hpp"
#include "CFRAII.hpp"
#include <cmath>
#include <vector>

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
    if (!element || !std::isfinite(width) || !std::isfinite(height) ||
        width <= 0.0f || height <= 0.0f) return {BackendCode::failed};
    const CGSize size = CGSizeMake(width, height);
    CFRef<AXValueRef> value = CFRef<AXValueRef>::adopt(AXValueCreate(kAXValueTypeCGSize, &size));
    if (!value) return {BackendCode::failed};
    const AXError error = AXUIElementSetAttributeValue(element, kAXSizeAttribute, value.get());
    return {error == kAXErrorSuccess ? BackendCode::ok : BackendCode::failed};
}

} // namespace

BackendResult AXBackend::move(AXUIElementRef element, uint32_t wid, int x, int y) {
    const BackendResult result = setPosition(element, x, y);
    if (!result.succeeded()) return result;
    return {m_checkPosition && m_checkPosition(element, wid, x, y) ? BackendCode::ok : BackendCode::failed};
}

BackendResult AXBackend::restore(AXUIElementRef element, uint32_t wid, int x, int y,
                                float width, float height) {
    // A resize can constrain the frame again. Position and verify afterwards,
    // and attempt both operations even if either one fails.
    const BackendResult resized = resize(element, wid, width, height);
    const BackendResult moved = move(element, wid, x, y);
    return resized.succeeded() ? moved : resized;
}

BackendResult AXBackend::maximize(AXUIElementRef element) {
    pid_t pid = 0;
    if (!element || AXUIElementGetPid(element, &pid) != kAXErrorSuccess || pid <= 0) {
        return {BackendCode::failed};
    }
    auto application = CFRef<AXUIElementRef>::adopt(AXUIElementCreateApplication(pid));
    CFRef<CFTypeRef> focused;
    CFRef<CFTypeRef> menu;
    if (!application ||
        AXUIElementCopyAttributeValue(application.get(), kAXFocusedWindowAttribute, focused.put()) != kAXErrorSuccess ||
        !focused || !CFEqual(focused.get(), element) ||
        AXUIElementCopyAttributeValue(application.get(), kAXMenuBarAttribute, menu.put()) != kAXErrorSuccess ||
        !menu || CFGetTypeID(menu.get()) != AXUIElementGetTypeID()) return {BackendCode::failed};

    // Match the system Fill shortcut rather than its localized menu title.
    // macOS exposes Fn as bit 4 in AXMenuItemCmdModifiers (not named in the SDK).
    constexpr int functionModifier = 1 << 4;
    constexpr int fillModifiers = functionModifier | kAXMenuItemModifierControl | kAXMenuItemModifierNoCommand;
    struct Entry { CFRef<AXUIElementRef> element; int depth; };
    std::vector<Entry> pending;
    pending.push_back({CFRef<AXUIElementRef>::retain(static_cast<AXUIElementRef>(menu.get())), 0});
    for (int visited = 0; !pending.empty() && visited < 512; ++visited) {
        auto entry = std::move(pending.back());
        pending.pop_back();
        CFRef<CFTypeRef> key;
        CFRef<CFTypeRef> modifiers;
        int mask = 0;
        if (AXUIElementCopyAttributeValue(entry.element.get(), kAXMenuItemCmdCharAttribute, key.put()) == kAXErrorSuccess &&
            key && CFGetTypeID(key.get()) == CFStringGetTypeID() &&
            CFStringCompare(static_cast<CFStringRef>(key.get()), CFSTR("F"), kCFCompareCaseInsensitive) == kCFCompareEqualTo &&
            AXUIElementCopyAttributeValue(entry.element.get(), kAXMenuItemCmdModifiersAttribute, modifiers.put()) == kAXErrorSuccess &&
            modifiers && CFGetTypeID(modifiers.get()) == CFNumberGetTypeID() &&
            CFNumberGetValue(static_cast<CFNumberRef>(modifiers.get()), kCFNumberIntType, &mask) && mask == fillModifiers) {
            CFRef<CFTypeRef> enabled;
            if (AXUIElementCopyAttributeValue(entry.element.get(), kAXEnabledAttribute, enabled.put()) != kAXErrorSuccess ||
                !enabled || CFGetTypeID(enabled.get()) != CFBooleanGetTypeID() ||
                !CFBooleanGetValue(static_cast<CFBooleanRef>(enabled.get()))) return {BackendCode::failed};
            return {AXUIElementPerformAction(entry.element.get(), kAXPressAction) == kAXErrorSuccess
                ? BackendCode::ok : BackendCode::failed};
        }
        if (entry.depth >= 8) continue;
        CFRef<CFTypeRef> children;
        if (AXUIElementCopyAttributeValue(entry.element.get(), kAXChildrenAttribute, children.put()) != kAXErrorSuccess ||
            !children || CFGetTypeID(children.get()) != CFArrayGetTypeID()) continue;
        auto array = static_cast<CFArrayRef>(children.get());
        for (CFIndex index = CFArrayGetCount(array); index > 0 && pending.size() < 512; --index) {
            auto child = static_cast<AXUIElementRef>(CFArrayGetValueAtIndex(array, index - 1));
            if (child && CFGetTypeID(child) == AXUIElementGetTypeID()) {
                pending.push_back({CFRef<AXUIElementRef>::retain(child), entry.depth + 1});
            }
        }
    }
    return {BackendCode::unsupported};
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

} // namespace minfwm
