#pragma once

#include <ApplicationServices/ApplicationServices.h>
#include <sys/types.h>
#include <vector>
#include "ClientWindow.hpp"
#include "Camera.hpp"

class DisplayManager
{
public:
    DisplayManager();
    ~DisplayManager() = default;

    void UpdateWindowPositions(const std::vector<ClientWindow*>& windows, const Camera& camera);
    void SetPanningMode(const std::vector<ClientWindow*>& windows, bool enabled);

    bool MoveViaYabai(uint32_t wid, float x, float y);
    bool ResizeViaYabai(uint32_t wid, float w, float h);
    bool SetWindowLayerViaYabai(uint32_t wid, int layer);
    bool SetWindowOpacityViaYabai(uint32_t wid, float opacity);

private:
    void TryInitializeYabaiSA();

    bool m_yabaiAvailable = false;
    char m_yabaiSocketPath[256];
};
