#pragma once

#include <string>
#include <vector>
#include <string_view>

namespace minfwm {

struct ConfigSnapshot {
    bool enableWindowShadows = false;
    std::string multiDisplayMode = "isolated";
    float overscanBufferPx = 500.0f;
    std::vector<std::string> whitelist = {"Terminal", "Music"};
    std::string spawnBehavior = "center";
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
