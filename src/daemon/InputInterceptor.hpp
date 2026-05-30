#pragma once

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

namespace minfwm {

class InputInterceptor {
public:
    InputInterceptor();
    ~InputInterceptor();

    void start();
    void stop();

private:
    static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon);
    
    CFMachPortRef m_eventTap;
    CFRunLoopSourceRef m_runLoopSource;
};

} // namespace minfwm
