#include "Application.hpp"
#include "WindowManager.hpp"
#include <iostream>
#include <algorithm>

Application::Application(pid_t pid)
    : m_pid(pid), m_appRef(nullptr), m_observerRef(nullptr)
{
    // Create AXUIElement for the application (Needs CFRelease later)
    m_appRef = AXUIElementCreateApplication(pid);
}

Application::~Application()
{
    if (m_observerRef)
    {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(m_observerRef), kCFRunLoopDefaultMode);
        CFRelease(m_observerRef);
        m_observerRef = nullptr;
    }

    if (m_appRef)
    {
        CFRelease(m_appRef);
        m_appRef = nullptr;
    }
}

bool Application::InitializeObserver()
{
    if (!m_appRef) return false;

    // Create the observer (Needs CFRelease later)
    AXError error = AXObserverCreate(m_pid, ObserverCallback, &m_observerRef);
    if (error != kAXErrorSuccess || !m_observerRef)
    {
        std::cerr << "Failed to create AXObserver for PID: " << m_pid << std::endl;
        return false;
    }

    // Add observer to RunLoop
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(m_observerRef), kCFRunLoopDefaultMode);

    // Add notifications
    AXObserverAddNotification(m_observerRef, m_appRef, kAXWindowCreatedNotification, this);
    AXObserverAddNotification(m_observerRef, m_appRef, kAXUIElementDestroyedNotification, this);
    AXObserverAddNotification(m_observerRef, m_appRef, kAXFocusedWindowChangedNotification, this);
    AXObserverAddNotification(m_observerRef, m_appRef, kAXWindowMovedNotification, this);
    AXObserverAddNotification(m_observerRef, m_appRef, kAXWindowResizedNotification, this);

    return true;
}

void Application::RegisterExistingWindows()
{
    if (!m_appRef) return;

    CFTypeRef windowsRef = nullptr;
    if (AXUIElementCopyAttributeValue(m_appRef, kAXWindowsAttribute, &windowsRef) == kAXErrorSuccess && windowsRef)
    {
        CFArrayRef windowsArray = (CFArrayRef)windowsRef;
        CFIndex count = CFArrayGetCount(windowsArray);
        for (CFIndex i = 0; i < count; ++i)
        {
            AXUIElementRef windowRef = (AXUIElementRef)CFArrayGetValueAtIndex(windowsArray, i);
            AddWindow(windowRef);
        }
        CFRelease(windowsRef); // Cleanup CFArray
    }
}

void Application::AddWindow(AXUIElementRef windowRef)
{
    // Check if it's actually a window
    CFTypeRef roleRef = nullptr;
    if (AXUIElementCopyAttributeValue(windowRef, kAXRoleAttribute, &roleRef) == kAXErrorSuccess)
    {
        if (CFStringCompare((CFStringRef)roleRef, kAXWindowRole, 0) == kCFCompareEqualTo)
        {
            auto newWindow = std::make_unique<ClientWindow>(windowRef);
            bool isStandard = !newWindow->is_floating;
            m_windows.push_back(std::move(newWindow));
            
            std::cout << "Added window to PID " << m_pid << " (Total windows: " << m_windows.size() << ")" << std::endl;
            
            if (isStandard) {
                WindowManager::GetInstance().ScheduleLayout();
            }
        }
        CFRelease(roleRef); // Cleanup CFTypeRef
    }
}

void Application::RemoveWindow(AXUIElementRef windowRef)
{
    size_t beforeCount = m_windows.size();
    m_windows.erase(std::remove_if(m_windows.begin(), m_windows.end(),
        [windowRef](const std::unique_ptr<ClientWindow>& window) {
            return CFEqual(window->GetRef(), windowRef);
        }), m_windows.end());
        
    if (m_windows.size() != beforeCount)
    {
        std::cout << "Removed window from PID " << m_pid << " (Remaining windows: " << m_windows.size() << ")" << std::endl;
        WindowManager::GetInstance().ScheduleLayout();
    }
}

void Application::ObserverCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void* refcon)
{
    Application* app = static_cast<Application*>(refcon);
    if (!app) return;

    if (CFStringCompare(notification, kAXWindowCreatedNotification, 0) == kCFCompareEqualTo)
    {
        app->AddWindow(element);
    }
    else if (CFStringCompare(notification, kAXUIElementDestroyedNotification, 0) == kCFCompareEqualTo)
    {
        app->RemoveWindow(element);
    }
    else if (CFStringCompare(notification, kAXFocusedWindowChangedNotification, 0) == kCFCompareEqualTo)
    {
        std::cout << "Focused window changed for PID " << app->GetPID() << std::endl;
    }
    else if (CFStringCompare(notification, kAXWindowMovedNotification, 0) == kCFCompareEqualTo ||
             CFStringCompare(notification, kAXWindowResizedNotification, 0) == kCFCompareEqualTo)
    {
        WindowManager::GetInstance().UpdateAbsolutePosition(element);
    }
}
