#pragma once

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "CFRAII.hpp"
#include "../core/PanGesture.hpp"
#include "TrackpadInput.hpp"
#include <bitset>
#include <atomic>
#include <memory>

@class NSPanel;
@class NSImageView;
@class NSTimer;

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
    void handleTrackpadPan(bool active, core::Point delta, float zoomDelta);
    void applyTrackpadPanDelta(core::Point delta);
    void advanceTrackpadMomentum();
    void finishTrackpadPan(bool snap = true);
    
    CFRef<CFMachPortRef> m_eventTap;
    CFRef<CFRunLoopSourceRef> m_runLoopSource;
    CFRef<CFMachPortRef> m_scrollEventTap;
    CFRef<CFRunLoopSourceRef> m_scrollRunLoopSource;
    core::PanGesture m_panGesture;
    std::optional<std::int64_t> m_mousePanDisplayId;
    TrackpadInput m_trackpadInput;
    std::shared_ptr<std::atomic_bool> m_trackpadCallbackEnabled;
    std::atomic_bool m_trackpadTouchActive{false};
    bool m_trackpadScrollCaptured = false;
    std::optional<std::int64_t> m_trackpadPanDisplayId;
    core::Point m_trackpadPanVelocity{};
    double m_trackpadLastEventTime = 0.0;
    double m_trackpadLastMovementTime = 0.0;
    double m_trackpadMomentumLastTick = 0.0;
    NSTimer* m_trackpadMomentumTimer = nil;
    bool m_trackpadGestureActive = false;
    bool m_trackpadDragEverywhereActive = false;
    core::Point m_trackpadDragPointer{};
    bool m_trackpadZoomGestureActive = false;
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
