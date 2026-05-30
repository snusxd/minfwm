#include "DisplayManager.hpp"
#include <iostream>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <pwd.h>

struct __attribute__((packed)) YabaiMovePayload {
    int16_t length;
    uint8_t opcode;
    uint32_t wid;
    float x;
    float y;
};

struct __attribute__((packed)) YabaiResizePayload {
    int16_t length;
    uint8_t opcode;
    uint32_t wid;
    float w;
    float h;
};

struct __attribute__((packed)) YabaiLayerPayload {
    int16_t length;
    uint8_t opcode;
    uint32_t wid;
    int32_t layer;
};

DisplayManager::DisplayManager()
{
    TryInitializeYabaiSA();
}

void DisplayManager::TryInitializeYabaiSA()
{
    struct passwd *pw = getpwuid(getuid());
    if (pw) {
        snprintf(m_yabaiSocketPath, sizeof(m_yabaiSocketPath), "/tmp/yabai-sa_%s.socket", pw->pw_name);
        int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (sockfd >= 0) {
            struct sockaddr_un addr;
            memset(&addr, 0, sizeof(addr));
            addr.sun_family = AF_UNIX;
            strncpy(addr.sun_path, m_yabaiSocketPath, sizeof(addr.sun_path) - 1);
            if (connect(sockfd, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
                m_yabaiAvailable = true;
                std::cout << "[DisplayManager] SA Connected. Ready for smooth panning." << std::endl;
            }
            close(sockfd);
        }
    }
}

bool DisplayManager::MoveViaYabai(uint32_t wid, float x, float y)
{
    if (!m_yabaiAvailable) return false;
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd < 0) return false;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, m_yabaiSocketPath, sizeof(addr.sun_path) - 1);
    if (connect(sockfd, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
        YabaiMovePayload mp;
        mp.length = sizeof(YabaiMovePayload) - sizeof(int16_t);
        mp.opcode = 0x06; // SA_OPCODE_WINDOW_MOVE
        mp.wid = wid;
        mp.x = x;
        mp.y = y;
        send(sockfd, &mp, sizeof(mp), 0);
        char dummy; recv(sockfd, &dummy, 1, 0);
        close(sockfd);
        return true;
    }
    close(sockfd);
    return false;
}

bool DisplayManager::ResizeViaYabai(uint32_t wid, float w, float h)
{
    if (!m_yabaiAvailable) return false;
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd < 0) return false;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, m_yabaiSocketPath, sizeof(addr.sun_path) - 1);
    if (connect(sockfd, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
        YabaiResizePayload rp;
        rp.length = sizeof(YabaiResizePayload) - sizeof(int16_t);
        rp.opcode = 0x0d; // SA_OPCODE_WINDOW_SCALE (Resize)
        rp.wid = wid;
        rp.w = w;
        rp.h = h;
        send(sockfd, &rp, sizeof(rp), 0);
        char dummy; recv(sockfd, &dummy, 1, 0);
        close(sockfd);
        return true;
    }
    close(sockfd);
    return false;
}

bool DisplayManager::SetWindowLayerViaYabai(uint32_t wid, int layer)
{
    if (!m_yabaiAvailable) return false;
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd < 0) return false;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, m_yabaiSocketPath, sizeof(addr.sun_path) - 1);
    if (connect(sockfd, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
        YabaiLayerPayload lp;
        lp.length = sizeof(YabaiLayerPayload) - sizeof(int16_t);
        lp.opcode = 0x09; // WINDOW_LAYER
        lp.wid = wid;
        lp.layer = layer;
        send(sockfd, &lp, sizeof(lp), 0);
        char dummy; recv(sockfd, &dummy, 1, 0);
        close(sockfd);
        return true;
    }
    close(sockfd);
    return false;
}

bool DisplayManager::SetWindowOpacityViaYabai(uint32_t wid, float opacity)
{
    if (!m_yabaiAvailable) return false;
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd < 0) return false;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, m_yabaiSocketPath, sizeof(addr.sun_path) - 1);
    if (connect(sockfd, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
        struct __attribute__((packed)) {
            int16_t length;
            uint8_t opcode;
            uint32_t wid;
            float opacity;
        } lp;
        lp.length = sizeof(lp) - sizeof(int16_t);
        lp.opcode = 0x07; // SA_OPCODE_WINDOW_OPACITY
        lp.wid = wid;
        lp.opacity = opacity;
        send(sockfd, &lp, sizeof(lp), 0);
        char dummy; recv(sockfd, &dummy, 1, 0);
        close(sockfd);
        return true;
    }
    close(sockfd);
    return false;
}

void DisplayManager::UpdateWindowPositions(const std::vector<ClientWindow*>& windows, const Camera& camera)
{
    for (auto* window : windows) {
        float tx, ty;
        int32_t screenX, screenY;
        camera.WorldToScreen(window->absolute_x, window->absolute_y, screenX, screenY);
        tx = (float)screenX;
        ty = (float)screenY;
        
        float tw = (float)(window->width * camera.GetScale());
        float th = (float)(window->height * camera.GetScale());

        std::cout << "[DisplayManager] Window " << window->wid << " -> (" << tx << ", " << ty << ") " << tw << "x" << th << std::endl;

        bool moveSuccess = false;
        bool resizeSuccess = false;

        if (m_yabaiAvailable && window->wid != 0) {
            moveSuccess = MoveViaYabai(window->wid, tx, ty);
            resizeSuccess = ResizeViaYabai(window->wid, tw, th);
        }

        // Only fallback to AX if Yabai failed OR not available
        if (!moveSuccess) {
            CGPoint newPos = { (CGFloat)tx, (CGFloat)ty };
            AXValueRef posValue = AXValueCreate((AXValueType)kAXValueCGPointType, &newPos);
            if (posValue) {
                AXUIElementSetAttributeValue(window->GetRef(), kAXPositionAttribute, posValue);
                CFRelease(posValue);
            }
        }
        if (!resizeSuccess) {
            CGSize newSize = { (CGFloat)tw, (CGFloat)th };
            AXValueRef sizeValue = AXValueCreate((AXValueType)kAXValueCGSizeType, &newSize);
            if (sizeValue) {
                AXUIElementSetAttributeValue(window->GetRef(), kAXSizeAttribute, sizeValue);
                CFRelease(sizeValue);
            }
        }
    }
}

void DisplayManager::SetPanningMode(const std::vector<ClientWindow*>& windows, bool enabled)
{
    int layer = enabled ? 2 : 0;
    for (auto* window : windows) {
        if (window->wid != 0) {
            SetWindowLayerViaYabai(window->wid, layer);
            SetWindowOpacityViaYabai(window->wid, 1.0f);
        }
    }
}
