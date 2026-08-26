#pragma once

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <map>
#include "CFRAII.hpp"

namespace minfwm {

class AXObserver {
public:
    AXObserver();
    ~AXObserver();

    bool start();
    void stop();

private:
    bool observeApplication(NSRunningApplication* app);
    void unobserveApplication(pid_t pid);
    
    static void axCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void* refcon);

    id m_launchObserver;
    id m_terminateObserver;
    
    struct AppObserver {
        CFRef<AXObserverRef> observer;
        CFRef<AXUIElementRef> element;
    };
    std::map<pid_t, AppObserver> m_appObservers;
};

} // namespace minfwm
