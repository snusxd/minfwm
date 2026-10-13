#pragma once

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "CFRAII.hpp"
#include "../core/PanGesture.hpp"
#include <bitset>

namespace minfwm {

class InputInterceptor {
public:
    InputInterceptor();
    ~InputInterceptor();

    bool start();
    void stop();

private:
    static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon);
    
    CFRef<CFMachPortRef> m_eventTap;
    CFRef<CFRunLoopSourceRef> m_runLoopSource;
    core::PanGesture m_panGesture;
    uint64_t m_overviewButtons = 0;
    std::bitset<256> m_overviewKeys;
    bool m_zoomScrollCaptured = false;
};

} // namespace minfwm
