#pragma once

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <map>
#include <vector>
#include <unordered_set>
#include <optional>
#include "CFRAII.hpp"

namespace minfwm {

class AXObserver {
public:
    AXObserver();
    ~AXObserver();

    bool start();
    void stop();
    void reconcileWindows();

private:
    struct AppObserver {
        CFRef<AXObserverRef> observer;
        CFRef<AXUIElementRef> element;
        std::vector<CFRef<AXUIElementRef>> windows;
    };

    bool observeApplication(NSRunningApplication* app);
    bool observeWindow(AppObserver& app, AXUIElementRef element, bool center);
    bool refreshWindows(AppObserver& app, bool centerNewWindows);
    bool focusActivatedApplication(pid_t pid);
    void unobserveApplication(pid_t pid);
    
    static void axCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void* refcon);

    id m_launchObserver;
    id m_terminateObserver;
    id m_hideObserver = nil;
    id m_unhideObserver = nil;
    id m_activateObserver = nil;
    
    bool m_started = false;
    bool m_registrationSucceeded = false;
    std::map<pid_t, AppObserver> m_appObservers;
    std::optional<std::unordered_set<uint32_t>> m_sessionIds;
    double m_nextReconcileTime = 0;
    double m_nextAXRefreshTime = 0;
    bool m_refreshPending = false;
    std::optional<pid_t> m_pendingActivationPid;
};

} // namespace minfwm
