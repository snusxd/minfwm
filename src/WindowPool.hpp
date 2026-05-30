#pragma once

#include <vector>
#include <memory>
#include <sys/types.h>
#include "Application.hpp"

class WindowPool
{
public:
    WindowPool() = default;
    ~WindowPool() = default;

    void HandleAppLaunched(pid_t pid);
    void HandleAppTerminated(pid_t pid);
    
    void AddApplication(std::unique_ptr<Application> app);
    
    const std::vector<std::unique_ptr<Application>>& GetApplications() const { return m_applications; }
    
    // Helper to get all windows across all apps
    std::vector<ClientWindow*> GetAllWindows() const;

private:
    std::vector<std::unique_ptr<Application>> m_applications;
};
