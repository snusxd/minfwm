#pragma once

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "CFRAII.hpp"
#include "../core/PanGesture.hpp"
#include <bitset>

@class NSPanel;
@class NSImageView;

namespace minfwm {

class InputInterceptor {
public:
    InputInterceptor();
    ~InputInterceptor();

    bool start();
    void stop();

private:
    static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon);
    static CGEventRef scrollTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon);
    void updateCursor(bool superHeld, bool dragging, CGPoint pointer);
    
    CFRef<CFMachPortRef> m_eventTap;
    CFRef<CFRunLoopSourceRef> m_runLoopSource;
    CFRef<CFMachPortRef> m_scrollEventTap;
    CFRef<CFRunLoopSourceRef> m_scrollRunLoopSource;
    core::PanGesture m_panGesture;
    uint64_t m_overviewButtons = 0;
    std::bitset<256> m_overviewKeys;
    bool m_zoomScrollCaptured = false;
    bool m_dragEverywhereActive = false;
    NSPanel* m_cursorOverlay = nil;
    NSImageView* m_cursorImageView = nil;
    bool m_backgroundCursorHidingEnabled = false;
    bool m_systemCursorHidden = false;
    bool m_cursorUnavailableForHold = false;
    bool m_closedHandCursorActive = false;
};

} // namespace minfwm
