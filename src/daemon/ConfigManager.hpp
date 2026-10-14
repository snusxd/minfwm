#pragma once

#include <string>
#include <vector>
#include <string_view>

namespace minfwm {

struct ConfigSnapshot {
    bool enableWindowShadows = false;
    bool invertZoomScrollDirection = false;
    bool rewindOnFocus = true;
    std::string zoomedEscCenter = "screen";
    std::string multiDisplayMode = "isolated";
    float mouseMovementMultiplier = 1.0f;
    float overscanBufferPx = 500.0f;
    std::vector<std::string> whitelist = {"Terminal", "Music"};
    std::string spawnBehavior = "center";
    bool pinsAlwaysOnTop = true;
    std::vector<std::string> superModifiers = {"Cmd", "Alt"};
    std::vector<std::string> centerCameraToFocus = {"Super", "F"};
    std::vector<std::string> centerFocusToCamera = {"Super", "S"};
    std::vector<std::string> dragEverywhereModifiers = {"Super", "Ctrl"};
    std::vector<std::string> bookmarksAddModifiers = {"Super"};
    std::vector<std::string> bookmarksGotoModifiers = {"Super", "Shift"};
};

class ConfigManager {
public:
    static ConfigManager& instance() {
        static ConfigManager instance;
        return instance;
    }

    bool load(std::string* error = nullptr);
    ConfigSnapshot snapshot() const;

    static bool parseText(std::string_view text, ConfigSnapshot& out, std::string& error);

private:
    ConfigManager() = default;

    ConfigSnapshot m_snapshot;
};

} // namespace minfwm
