#include "WindowPool.hpp"
#include <algorithm>
#import <Cocoa/Cocoa.h>
#include <unistd.h>

void WindowPool::HandleAppLaunched(pid_t pid)
{
    NSRunningApplication *appInfo = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (appInfo && ([appInfo.bundleIdentifier isEqualToString:@"com.koekeishiya.yabai"] || pid == getpid())) return;
    
    auto app = std::make_unique<Application>(pid);
    if (app->InitializeObserver()) {
        app->RegisterExistingWindows();
        m_applications.push_back(std::move(app));
    }
}

void WindowPool::HandleAppTerminated(pid_t pid)
{
    m_applications.erase(std::remove_if(m_applications.begin(), m_applications.end(), 
        [pid](const auto& app) { return app->GetPID() == pid; }), m_applications.end());
}

void WindowPool::AddApplication(std::unique_ptr<Application> app)
{
    m_applications.push_back(std::move(app));
}

std::vector<ClientWindow*> WindowPool::GetAllWindows() const
{
    std::vector<ClientWindow*> allWindows;
    for (const auto& app : m_applications) {
        for (const auto& window : app->GetWindows()) {
            allWindows.push_back(window.get());
        }
    }
    return allWindows;
}
