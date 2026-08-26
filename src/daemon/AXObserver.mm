#import "AXObserver.hpp"
#import "WindowManager.hpp"
#import <iostream>

namespace minfwm {

AXObserver::AXObserver() : m_launchObserver(nil), m_terminateObserver(nil) {}

AXObserver::~AXObserver() {
    stop();
}

bool AXObserver::start() {
    if (m_launchObserver || m_terminateObserver || !m_appObservers.empty()) return true;
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

    bool registrationFailed = false;
    for (NSRunningApplication* app in [workspace runningApplications]) {
        if (app.activationPolicy == NSApplicationActivationPolicyRegular) {
            registrationFailed = !observeApplication(app) || registrationFailed;
        }
    }
    return !registrationFailed;
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
        if (appObs.observer) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(appObs.observer.get()), kCFRunLoopDefaultMode);
        }
    }
    m_appObservers.clear();
}

bool AXObserver::observeApplication(NSRunningApplication* app) {
    auto& wm = WindowManager::instance();
    if (!app) return false;
    pid_t pid = app.processIdentifier;
    if (m_appObservers.find(pid) != m_appObservers.end()) return true;

    CFRef<AXUIElementRef> appElem = CFRef<AXUIElementRef>::adopt(AXUIElementCreateApplication(pid));
    if (!appElem) return false;

    AXObserverRef observerRaw = nullptr;
    if (AXObserverCreate(pid, axCallback, &observerRaw) != kAXErrorSuccess || !observerRaw) {
        return false;
    }
    CFRef<AXObserverRef> observer = CFRef<AXObserverRef>::adopt(observerRaw);

    const CFStringRef notifications[] = {
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXFocusedWindowChangedNotification,
    };
    bool registrationFailed = false;
    for (const CFStringRef notification : notifications) {
        const AXError error = AXObserverAddNotification(observer.get(), appElem.get(), notification, this);
        if (error != kAXErrorSuccess && error != kAXErrorNotificationAlreadyRegistered) {
            std::cerr << "AXObserver: failed to register notification for pid " << pid
                      << " (error " << error << ")" << std::endl;
            registrationFailed = true;
        }
    }
    if (registrationFailed) {
        return false;
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer.get()), kCFRunLoopDefaultMode);

    m_appObservers.emplace(pid, AppObserver{std::move(observer), std::move(appElem)});

    // Add existing windows
    CFRef<CFTypeRef> windowValue;
    if (AXUIElementCopyAttributeValue(m_appObservers.at(pid).element.get(), kAXWindowsAttribute,
                                      windowValue.put()) == kAXErrorSuccess && windowValue) {
        const CFArrayRef windowList = static_cast<CFArrayRef>(windowValue.get());
        if (CFGetTypeID(windowList) != CFArrayGetTypeID()) return true;
        CFIndex count = CFArrayGetCount(windowList);
        for (CFIndex i = 0; i < count; ++i) {
            AXUIElementRef windowRef = (AXUIElementRef)CFArrayGetValueAtIndex(windowList, i);
            Display& display = wm.displayForWindow(windowRef);
            wm.adoptWindow(display, display.windowPool().addWindow(windowRef));
        }
        wm.updateWindows();
    }
    return true;
}

void AXObserver::unobserveApplication(pid_t pid) {
    auto it = m_appObservers.find(pid);
    if (it != m_appObservers.end()) {
        if (it->second.observer) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(it->second.observer.get()), kCFRunLoopDefaultMode);
        }
        m_appObservers.erase(it);
    }
}

void AXObserver::axCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void* refcon) {
    auto* self = static_cast<AXObserver*>(refcon);
    if (!self || !element || !notification) return;
    auto& wm = WindowManager::instance();
    
    if (CFStringCompare(notification, kAXWindowCreatedNotification, 0) == kCFCompareEqualTo) {
        Display& display = wm.displayForWindow(element);
        auto window = display.windowPool().addWindow(element);
        wm.adoptWindow(display, window);
        wm.centerWindow(window);
        wm.updateWindows();
    } else if (CFStringCompare(notification, kAXUIElementDestroyedNotification, 0) == kCFCompareEqualTo) {
        wm.removeWindow(element);
    } else if (CFStringCompare(notification, kAXWindowMovedNotification, 0) == kCFCompareEqualTo ||
               CFStringCompare(notification, kAXWindowResizedNotification, 0) == kCFCompareEqualTo) {
        wm.syncPhysicalToVirtual(element);
    } else if (CFStringCompare(notification, kAXFocusedWindowChangedNotification, 0) == kCFCompareEqualTo) {
        CFRef<CFTypeRef> focusedValue;
        if (AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute, focusedValue.put()) == kAXErrorSuccess &&
            focusedValue) {
            wm.centerCameraOnWindow(static_cast<AXUIElementRef>(focusedValue.get()));
        }
    }
}

} // namespace minfwm
