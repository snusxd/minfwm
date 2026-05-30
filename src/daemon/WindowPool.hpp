#pragma once

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#include <vector>
#include <memory>

extern "C" AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *wid);

namespace minfwm {

struct VirtualRect {
    float x, y, w, h;
};

class ClientWindow {
public:
    ClientWindow(AXUIElementRef windowRef);
    ~ClientWindow();

    AXUIElementRef ref() const { return m_windowRef; }
    uint32_t wid() const { return m_wid; }

    VirtualRect virtualRect;
    float lastRenderedX = -99999.0f;
    float lastRenderedY = -99999.0f;
    double lastProgrammaticMoveTime = 0.0;
    bool isHidden = false;

private:
    AXUIElementRef m_windowRef;
    uint32_t m_wid;
    CFTypeRef m_lastPositionValue;
    CFTypeRef m_lastSizeValue;
};

class WindowPool {
public:
    std::shared_ptr<ClientWindow> addWindow(AXUIElementRef windowRef);
    void removeWindow(AXUIElementRef windowRef);
    
    std::vector<std::shared_ptr<ClientWindow>>& windows() { return m_windows; }

private:
    std::vector<std::shared_ptr<ClientWindow>> m_windows;
};

} // namespace minfwm
