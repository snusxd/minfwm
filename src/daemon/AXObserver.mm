#import "AXObserver.hpp"
#import "WindowManager.hpp"
#import "ConfigManager.hpp"
#import <iostream>
#include <algorithm>
#import <QuartzCore/QuartzCore.h>

namespace minfwm {

AXObserver::AXObserver() : m_launchObserver(nil), m_terminateObserver(nil) {}

AXObserver::~AXObserver() {
    stop();
}

bool AXObserver::start() {
    if (m_started) return m_registrationSucceeded;
    m_started = true;
    std::cout << "AXObserver: Starting..." << std::endl;

    NSWorkspace* workspace = [NSWorkspace sharedWorkspace];
    NSNotificationCenter* center = [workspace notificationCenter];
    const auto applicationVisibilityChanged = ^(NSNotification* note) {
        NSRunningApplication* app = note.userInfo[NSWorkspaceApplicationKey];
        if (m_started && app) {
            const char* name = app.localizedName.UTF8String;
            WindowManager::instance().setApplicationState(app.processIdentifier, name ? name : "",
                [note.name isEqualToString:NSWorkspaceDidHideApplicationNotification]);
            if ([note.name isEqualToString:NSWorkspaceDidUnhideApplicationNotification]) {
                m_refreshPending = true;
                m_nextReconcileTime = 0;
            }
        }
    };
    m_hideObserver = [center addObserverForName:NSWorkspaceDidHideApplicationNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:applicationVisibilityChanged];
    m_unhideObserver = [center addObserverForName:NSWorkspaceDidUnhideApplicationNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:applicationVisibilityChanged];
    m_activateObserver = [center addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note) {
            if (!m_started) return;
            m_refreshPending = true;
            m_nextReconcileTime = 0;
            NSRunningApplication* app = note.userInfo[NSWorkspaceApplicationKey];
            if (!app || app.activationPolicy != NSApplicationActivationPolicyRegular) return;
            const pid_t pid = app.processIdentifier;
            (void)this->observeApplication(app);
            if (!this->focusActivatedApplication(pid)) {
                m_pendingActivationPid = pid;
            } else {
                m_pendingActivationPid.reset();
            }
        }];

    m_launchObserver = [center addObserverForName:NSWorkspaceDidLaunchApplicationNotification
                                           object:nil
                                            queue:[NSOperationQueue mainQueue]
                                       usingBlock:^(NSNotification* note) {
        NSRunningApplication* app = note.userInfo[NSWorkspaceApplicationKey];
        if (m_started && !this->observeApplication(app)) {
            std::cerr << "AXObserver: failed to observe launched application" << std::endl;
        }
    }];

    m_terminateObserver = [center addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                                              object:nil
                                               queue:[NSOperationQueue mainQueue]
                                          usingBlock:^(NSNotification* note) {
        NSRunningApplication* app = note.userInfo[NSWorkspaceApplicationKey];
        if (m_started) this->unobserveApplication(app.processIdentifier);
    }];

    bool registrationFailed = false;
    for (NSRunningApplication* app in [workspace runningApplications]) {
        if (app.activationPolicy == NSApplicationActivationPolicyRegular) {
            registrationFailed = !observeApplication(app) || registrationFailed;
        }
    }
    m_registrationSucceeded = !registrationFailed;
    WindowManager::instance().updateWindows();
    return m_registrationSucceeded;
}

void AXObserver::stop() {
    m_started = false;
    m_registrationSucceeded = false;
    for (id observer : {m_hideObserver, m_unhideObserver, m_activateObserver}) {
        if (observer) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
    }
    m_hideObserver = nil;
    m_unhideObserver = nil;
    m_activateObserver = nil;
    m_sessionIds.reset();
    m_nextReconcileTime = 0;
    m_nextAXRefreshTime = 0;
    m_refreshPending = false;
    m_pendingActivationPid.reset();
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
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(appObs.observer.get()), kCFRunLoopCommonModes);
        }
    }
    m_appObservers.clear();
}

bool AXObserver::observeApplication(NSRunningApplication* app) {
    auto& wm = WindowManager::instance();
    if (!app) return false;
    if (app.activationPolicy != NSApplicationActivationPolicyRegular) return true;
    pid_t pid = app.processIdentifier;
    const char* name = app.localizedName.UTF8String;
    wm.setApplicationState(pid, name ? name : "", app.hidden);
    if (auto existing = m_appObservers.find(pid); existing != m_appObservers.end()) return refreshWindows(existing->second, false);

    CFRef<AXUIElementRef> appElem = CFRef<AXUIElementRef>::adopt(AXUIElementCreateApplication(pid));
    if (!appElem) return false;

    AXObserverRef observerRaw = nullptr;
    if (AXObserverCreate(pid, axCallback, &observerRaw) != kAXErrorSuccess || !observerRaw) {
        return false;
    }
    CFRef<AXObserverRef> observer = CFRef<AXObserverRef>::adopt(observerRaw);

    const CFStringRef notifications[] = {
        kAXWindowCreatedNotification,
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
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer.get()), kCFRunLoopCommonModes);

    auto [entry, inserted] = m_appObservers.emplace(pid, AppObserver{std::move(observer), std::move(appElem), {}});

    return refreshWindows(entry->second, false) && !registrationFailed;
}

bool AXObserver::refreshWindows(AppObserver& app, bool centerNewWindows) {
    CFRef<CFTypeRef> windowValue;
    if (AXUIElementCopyAttributeValue(app.element.get(), kAXWindowsAttribute, windowValue.put()) != kAXErrorSuccess ||
        !windowValue || CFGetTypeID(windowValue.get()) != CFArrayGetTypeID()) return false;
    bool succeeded = true;
    const auto windowList = static_cast<CFArrayRef>(windowValue.get());
    std::vector<AXUIElementRef> liveWindows;
    for (CFIndex i = 0; i < CFArrayGetCount(windowList); ++i) {
        auto ref = static_cast<AXUIElementRef>(CFArrayGetValueAtIndex(windowList, i));
        if (ref && CFGetTypeID(ref) == AXUIElementGetTypeID()) liveWindows.push_back(ref);
        else return false; // A malformed snapshot is not a list of closed windows.
    }
    pid_t pid = 0;
    if (AXUIElementGetPid(app.element.get(), &pid) != kAXErrorSuccess || pid <= 0) return false;
    auto& wm = WindowManager::instance();
    wm.reconcileApplicationWindows(pid, liveWindows);
    std::erase_if(app.windows, [&](const auto& window) { return !wm.findWindow(window.get()); });
    for (CFIndex i = 0; i < CFArrayGetCount(windowList); ++i) {
        auto windowRef = static_cast<AXUIElementRef>(CFArrayGetValueAtIndex(windowList, i));
        succeeded = observeWindow(app, windowRef, centerNewWindows) && succeeded;
    }
    return succeeded;
}

void AXObserver::reconcileWindows() {
    if (!m_started) return;
    const double now = CACurrentMediaTime();
    if (now < m_nextReconcileTime) return;
    m_nextReconcileTime = now + 0.5;
    const auto session = readSessionWindowIds();
    if (session && (!m_sessionIds || *m_sessionIds != *session)) {
        m_refreshPending = true;
        m_sessionIds = session;
    }
    auto& wm = WindowManager::instance();
    for (auto& [pid, app] : m_appObservers) {
        // WindowServer reconciliation removes stale model records even if
        // the application never supports AX destruction notifications.
        std::erase_if(app.windows, [&](const auto& window) { return !wm.findWindow(window.get()); });
    }
    // Retained-but-closed windows need AX enumeration even if no WID was
    // destroyed. Defer these cross-process reads during camera gestures.
    if ((!m_refreshPending && now < m_nextAXRefreshTime) || wm.isPanning() || wm.overviewActive()) return;
    m_refreshPending = false;
    m_nextAXRefreshTime = now + 2;
    for (auto& [pid, app] : m_appObservers) (void)refreshWindows(app, false);
    if (m_pendingActivationPid && focusActivatedApplication(*m_pendingActivationPid)) {
        m_pendingActivationPid.reset();
    }
    wm.updateWindows();
}

bool AXObserver::focusActivatedApplication(pid_t pid) {
    const auto application = m_appObservers.find(pid);
    if (application == m_appObservers.end()) return false;

    CFRef<CFTypeRef> focusedValue;
    if (AXUIElementCopyAttributeValue(application->second.element.get(), kAXFocusedWindowAttribute,
                                      focusedValue.put()) != kAXErrorSuccess ||
        !focusedValue || CFGetTypeID(focusedValue.get()) != AXUIElementGetTypeID()) {
        return false;
    }

    const auto focused = static_cast<AXUIElementRef>(focusedValue.get());
    (void)observeWindow(application->second, focused, false);
    auto& wm = WindowManager::instance();
    const auto window = wm.findWindow(focused);
    if (!window || !window->virtualCoordinatesInitialized) return false;
    if (ConfigManager::instance().snapshot().rewindOnFocus) wm.centerCameraOnWindow(focused);
    return true;
}

bool AXObserver::observeWindow(AppObserver& app, AXUIElementRef element, bool center) {
    if (!element || CFGetTypeID(element) != AXUIElementGetTypeID()) return false;
    for (const auto& existing : app.windows) {
        if (CFEqual(existing.get(), element)) return true;
    }
    bool succeeded = true;
    const CFStringRef notifications[] = {
        kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
    };
    // Movement, resize and destruction belong to each window element. An app
    // may reject them on its application element while supporting them here.
    for (CFStringRef notification : notifications) {
        const AXError error = AXObserverAddNotification(app.observer.get(), element, notification, this);
        if (error != kAXErrorSuccess && error != kAXErrorNotificationAlreadyRegistered) {
            std::cerr << "AXObserver: failed to register window notification (error " << error << ")" << std::endl;
            succeeded = false;
        }
    }
    app.windows.push_back(CFRef<AXUIElementRef>::retain(element));
    auto& wm = WindowManager::instance();
    if (!wm.findWindow(element)) {
        Display& display = wm.displayForWindow(element);
        auto window = display.windowPool().addWindow(element);
        if (window) window->centerOnAdoption = center;
        wm.adoptWindow(display, window);
    }
    return succeeded;
}

void AXObserver::unobserveApplication(pid_t pid) {
    if (m_pendingActivationPid == pid) m_pendingActivationPid.reset();
    auto it = m_appObservers.find(pid);
    if (it != m_appObservers.end()) {
        if (it->second.observer) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(it->second.observer.get()), kCFRunLoopCommonModes);
        }
        m_appObservers.erase(it);
    }
    WindowManager::instance().removeWindowsForPid(pid);
}

void AXObserver::axCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void* refcon) {
    auto* self = static_cast<AXObserver*>(refcon);
    if (!self || !self->m_started || !element || !notification) return;
    const auto application = std::find_if(self->m_appObservers.begin(), self->m_appObservers.end(),
        [observer](const auto& entry) { return entry.second.observer.get() == observer; });
    if (application == self->m_appObservers.end()) return;
    AppObserver& app = application->second;
    auto& wm = WindowManager::instance();
    
    if (CFStringCompare(notification, kAXWindowCreatedNotification, 0) == kCFCompareEqualTo) {
        (void)self->observeWindow(app, element, true);
        wm.updateWindows();
    } else if (CFStringCompare(notification, kAXUIElementDestroyedNotification, 0) == kCFCompareEqualTo) {
        wm.removeWindow(element);
        std::erase_if(app.windows, [element](const auto& window) { return CFEqual(window.get(), element); });
    } else if (CFStringCompare(notification, kAXWindowMovedNotification, 0) == kCFCompareEqualTo ||
               CFStringCompare(notification, kAXWindowResizedNotification, 0) == kCFCompareEqualTo) {
        wm.syncPhysicalToVirtual(element);
    } else if (CFStringCompare(notification, kAXFocusedWindowChangedNotification, 0) == kCFCompareEqualTo) {
        CFRef<CFTypeRef> focusedValue;
        if (AXUIElementCopyAttributeValue(app.element.get(), kAXFocusedWindowAttribute, focusedValue.put()) == kAXErrorSuccess &&
            focusedValue && CFGetTypeID(focusedValue.get()) == AXUIElementGetTypeID()) {
            const auto focused = static_cast<AXUIElementRef>(focusedValue.get());
            (void)self->observeWindow(app, focused, false);
        }
    }
}

} // namespace minfwm
