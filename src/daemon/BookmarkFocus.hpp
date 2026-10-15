#pragma once

#import <ApplicationServices/ApplicationServices.h>

namespace minfwm {

enum class BookmarkFocusReadiness {
    unavailable,
    waitForPresentation,
    ready,
};

inline BookmarkFocusReadiness bookmarkFocusReadiness(bool managed, bool applicationHidden,
                                                     bool windowHidden, bool axHidden,
                                                     bool applicationSuspended) {
    if (!managed || applicationHidden) return BookmarkFocusReadiness::unavailable;
    if (windowHidden || axHidden || applicationSuspended) {
        return BookmarkFocusReadiness::waitForPresentation;
    }
    return BookmarkFocusReadiness::ready;
}

using AXPerformAction = AXError (*)(AXUIElementRef, CFStringRef);
using AXSetAttributeValue = AXError (*)(AXUIElementRef, CFStringRef, CFTypeRef);

// Raising changes z-order; AXFocused requests keyboard focus. Some apps expose
// the application-level focused-window attribute as a fallback instead.
inline bool focusBookmarkWindow(AXUIElementRef application, AXUIElementRef window,
                                AXPerformAction performAction = AXUIElementPerformAction,
                                AXSetAttributeValue setAttribute = AXUIElementSetAttributeValue) {
    if (!window) return false;
    (void)performAction(window, kAXRaiseAction);
    if (setAttribute(window, kAXFocusedAttribute, kCFBooleanTrue) == kAXErrorSuccess) return true;
    return application &&
        setAttribute(application, kAXFocusedWindowAttribute, window) == kAXErrorSuccess;
}

} // namespace minfwm
