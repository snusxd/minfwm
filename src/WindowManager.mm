#include "WindowManager.hpp"
#include "GridLayout.hpp"
#import <Cocoa/Cocoa.h>
#include <iostream>

void WindowManager::Initialize()
{
    std::cout << "[WindowManager] Initializing..." << std::endl;
    m_isInitializing = true;
    m_currentLayout = std::make_unique<GridLayout>();
    
    // Initial application discovery
    for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if (app.activationPolicy == NSApplicationActivationPolicyRegular) {
            m_windowPool.HandleAppLaunched(app.processIdentifier);
        }
    }

    // Register for workspace notifications
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidLaunchApplicationNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        NSRunningApplication *app = n.userInfo[NSWorkspaceApplicationKey];
        if (app && app.activationPolicy == NSApplicationActivationPolicyRegular) {
            m_windowPool.HandleAppLaunched(app.processIdentifier);
        }
    }];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidTerminateApplicationNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        NSRunningApplication *app = n.userInfo[NSWorkspaceApplicationKey];
        if (app) {
            m_windowPool.HandleAppTerminated(app.processIdentifier);
        }
    }];

    m_isInitializing = false;
    m_displayManager.SetPanningMode(m_windowPool.GetAllWindows(), false);
    std::cout << "[WindowManager] Initialization complete. " << m_windowPool.GetAllWindows().size() << " windows tracked." << std::endl;
}

void WindowManager::UpdateAbsolutePosition(AXUIElementRef windowRef)
{
    if (m_isPanning || m_isZooming || m_isUpdating) return;
    
    CFTypeRef posRef = nullptr;
    CFTypeRef sizeRef = nullptr;
    
    if (AXUIElementCopyAttributeValue(windowRef, kAXPositionAttribute, &posRef) == kAXErrorSuccess &&
        AXUIElementCopyAttributeValue(windowRef, kAXSizeAttribute, &sizeRef) == kAXErrorSuccess) {
        
        CGPoint pos;
        CGSize size;
        
        if (AXValueGetValue((AXValueRef)posRef, (AXValueType)kAXValueCGPointType, &pos) &&
            AXValueGetValue((AXValueRef)sizeRef, (AXValueType)kAXValueCGSizeType, &size)) {
            
            for (auto* win : m_windowPool.GetAllWindows()) {
                if (CFEqual(win->GetRef(), windowRef)) {
                    double scale = m_camera.GetScale();
                    win->absolute_x = pos.x / scale + m_camera.GetX();
                    win->absolute_y = pos.y / scale + m_camera.GetY();
                    win->width = size.width / scale;
                    win->height = size.height / scale;
                    
                    CFRelease(posRef);
                    CFRelease(sizeRef);
                    return;
                }
            }
        }
        CFRelease(posRef);
        CFRelease(sizeRef);
    } else {
        if (posRef) CFRelease(posRef);
        if (sizeRef) CFRelease(sizeRef);
    }
}

void WindowManager::Pan(double dx, double dy)
{
    if (!m_isPanning && !m_isZooming) {
        m_isPanning = true;
        m_displayManager.SetPanningMode(m_windowPool.GetAllWindows(), true);
    }
    m_camera.Pan(dx, dy);
    ScheduleUpdate();
}

void WindowManager::Zoom(double delta, double centerX, double centerY)
{
    if (!m_isZooming && !m_isPanning) {
        m_isZooming = true;
        m_displayManager.SetPanningMode(m_windowPool.GetAllWindows(), true);
    }
    m_camera.Zoom(delta, centerX, centerY);
    ScheduleUpdate();
}

void WindowManager::ScheduleUpdate()
{
    if (m_updatePending) return;
    m_updatePending = true;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        UpdateWindowPositions();
        m_updatePending = false;
    });
}

void WindowManager::ForceUpdate()
{
    UpdateWindowPositions();
    m_displayManager.SetPanningMode(m_windowPool.GetAllWindows(), false);
    m_isPanning = false;
    m_isZooming = false;
}

void WindowManager::UpdateWindowPositions()
{
    m_isUpdating = true;
    m_displayManager.UpdateWindowPositions(m_windowPool.GetAllWindows(), m_camera);
    m_isUpdating = false;
}

void WindowManager::ScheduleLayout()
{
    if (m_layoutPending) return;
    m_layoutPending = true;
    
    // Debounce layout updates to 100ms
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_lastLayoutTime).count();
    
    int64_t delay = std::max(0LL, 100LL - (int64_t)elapsed);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        ApplyCurrentLayout();
        m_lastLayoutTime = std::chrono::steady_clock::now();
        m_layoutPending = false;
    });
}

void WindowManager::ApplyCurrentLayout()
{
    if (m_currentLayout) {
        m_currentLayout->ApplyLayout(m_windowPool.GetAllWindows());
        UpdateWindowPositions();
    }
}
