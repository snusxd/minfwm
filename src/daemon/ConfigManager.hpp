#pragma once

#include <string>
#include <vector>
#include <map>

namespace minfwm {

class ConfigManager {
public:
    static ConfigManager& instance() {
        static ConfigManager instance;
        return instance;
    }

    void load();
    
    bool enableWindowShadows = false;
    std::string multiDisplayMode = "isolated";
    float overscanBufferPx = 500.0f;
    std::vector<std::string> whitelist = {"Terminal", "Music"};
    std::string spawnBehavior = "center";

private:
    ConfigManager() = default;
};

} // namespace minfwm
