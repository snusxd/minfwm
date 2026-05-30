#pragma once

#include <ApplicationServices/ApplicationServices.h>
#include <vector>
#include <memory>
#include "ClientWindow.hpp"

class Application
{
public:
    explicit Application(pid_t pid);
    ~Application();

    // Prevent copying
    Application(const Application&) = delete;
    Application& operator=(const Application&) = delete;

    bool InitializeObserver();
    void RegisterExistingWindows();
    
    void AddWindow(AXUIElementRef windowRef);
    void RemoveWindow(AXUIElementRef windowRef);

    pid_t GetPID() const { return m_pid; }
    AXUIElementRef GetAppRef() const { return m_appRef; }
    
    const std::vector<std::unique_ptr<ClientWindow>>& GetWindows() const { return m_windows; }

private:
    pid_t m_pid;
    AXUIElementRef m_appRef;
    AXObserverRef m_observerRef;
    std::vector<std::unique_ptr<ClientWindow>> m_windows;

    static void ObserverCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void* refcon);
};
