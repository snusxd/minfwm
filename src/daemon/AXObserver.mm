#import "AXObserver.hpp"
#import "WindowManager.hpp"
#import <iostream>

namespace minfwm {

AXObserver::AXObserver() : m_launchObserver(nil), m_terminateObserver(nil) {}

AXObserver::~AXObserver() {
    stop();
}

void AXObserver::start() {
    std::cout << "AXObserver: Starting..." << std::endl;

    NSWorkspace* workspace = [NSWorkspace sharedWorkspace];
    NSNotificationCenter* center = [workspace notificationCenter];

    m_launchObserver = [center addObserverForName:NSWorkspaceDidLaunchApplicationNotification
                                           object:nil
                                            queue:[NSOperationQueue mainQueue]
                                       usingBlock:^(NSNotification* note) {
        NSRunningApplication* app = note.userInfo[NSWorkspaceApplicationKey];
        this->observeApplication(app);
    }];

    m_terminateObserver = [center addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                                              object:nil
                                               queue:[NSOperationQueue mainQueue]
                                          usingBlock:^(NSNotification* note) {
        NSRunningApplication* app = note.userInfo[NSWorkspaceApplicationKey];
        this->unobserveApplication(app.processIdentifier);
    }];

    for (NSRunningApplication* app in [workspace runningApplications]) {
        if (app.activationPolicy == NSApplicationActivationPolicyRegular) {
            observeApplication(app);
        }
    }
}

void AXObserver::stop() {
    if (m_launchObserver) {
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:m_launchObserver];
        m_launchObserver = nil;
    }
    if (m_terminateObserver) {
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:m_terminateObserver];
        m_terminateObserver = nil;
    }

    for (auto& [pid, appObs] : m_appObservers) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(appObs.observer), kCFRunLoopDefaultMode);
        CFRelease(appObs.observer);
        CFRelease(appObs.element);
    }
    m_appObservers.clear();
}

void AXObserver::observeApplication(NSRunningApplication* app) {
    auto& wm = WindowManager::instance();
    pid_t pid = app.processIdentifier;
    if (m_appObservers.find(pid) != m_appObservers.end()) return;

    AXUIElementRef appElem = AXUIElementCreateApplication(pid);
    if (!appElem) return;

    AXObserverRef observer;
    if (AXObserverCreate(pid, axCallback, &observer) != kAXErrorSuccess) {
        CFRelease(appElem);
        return;
    }

    AXObserverAddNotification(observer, appElem, kAXWindowCreatedNotification, this);
    AXObserverAddNotification(observer, appElem, kAXUIElementDestroyedNotification, this);
    AXObserverAddNotification(observer, appElem, kAXWindowMovedNotification, this);
    AXObserverAddNotification(observer, appElem, kAXWindowResizedNotification, this);
    AXObserverAddNotification(observer, appElem, kAXFocusedWindowChangedNotification, this);

    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), kCFRunLoopDefaultMode);

    m_appObservers[pid] = {observer, appElem};

    // Add existing windows
    CFArrayRef windowList = NULL;
    if (AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute, (CFTypeRef*)&windowList) == kAXErrorSuccess) {
        CFIndex count = CFArrayGetCount(windowList);
        for (CFIndex i = 0; i < count; ++i) {
            AXUIElementRef windowRef = (AXUIElementRef)CFArrayGetValueAtIndex(windowList, i);
            Display& display = wm.displayForWindow(windowRef);
            display.windowPool().addWindow(windowRef);
        }
        CFRelease(windowList);
        wm.updateWindows();
    }
}

void AXObserver::unobserveApplication(pid_t pid) {
    auto it = m_appObservers.find(pid);
    if (it != m_appObservers.end()) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(it->second.observer), kCFRunLoopDefaultMode);
        CFRelease(it->second.observer);
        CFRelease(it->second.element);
        m_appObservers.erase(it);
    }
}

void AXObserver::axCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void* refcon) {
    auto& wm = WindowManager::instance();
    
    if (CFStringCompare(notification, kAXWindowCreatedNotification, 0) == kCFCompareEqualTo) {
        Display& display = wm.displayForWindow(element);
        auto window = display.windowPool().addWindow(element);
        wm.centerWindow(window);
        wm.updateWindows();
    } else if (CFStringCompare(notification, kAXUIElementDestroyedNotification, 0) == kCFCompareEqualTo) {
        wm.removeWindow(element);
    } else if (CFStringCompare(notification, kAXWindowMovedNotification, 0) == kCFCompareEqualTo ||
               CFStringCompare(notification, kAXWindowResizedNotification, 0) == kCFCompareEqualTo) {
        wm.syncPhysicalToVirtual(element);
    } else if (CFStringCompare(notification, kAXFocusedWindowChangedNotification, 0) == kCFCompareEqualTo) {
        wm.centerCameraOnWindow(element);
    }
}

} // namespace minfwm
