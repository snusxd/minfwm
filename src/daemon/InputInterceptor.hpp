#pragma once

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "CFRAII.hpp"

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
};

} // namespace minfwm
