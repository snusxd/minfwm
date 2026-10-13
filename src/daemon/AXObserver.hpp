#pragma once

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <map>
#include <vector>
#include "CFRAII.hpp"

namespace minfwm {

class AXObserver {
public:
    AXObserver();
    ~AXObserver();

    bool start();
    void stop();

private:
    struct AppObserver {
        CFRef<AXObserverRef> observer;
        CFRef<AXUIElementRef> element;
        std::vector<CFRef<AXUIElementRef>> windows;
    };

    bool observeApplication(NSRunningApplication* app);
    bool observeWindow(AppObserver& app, AXUIElementRef element, bool center);
    void unobserveApplication(pid_t pid);
    
    static void axCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void* refcon);

    id m_launchObserver;
    id m_terminateObserver;
    
    bool m_started = false;
    bool m_registrationSucceeded = false;
    std::map<pid_t, AppObserver> m_appObservers;
};

} // namespace minfwm
