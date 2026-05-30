#include "ConfigManager.hpp"
#import <Foundation/Foundation.h>
#include <iostream>
#include <fstream>
#include <sstream>

namespace minfwm {

void ConfigManager::load() {
    NSString* home = NSHomeDirectory();
    NSString* path = [home stringByAppendingPathComponent:@".config/minfwm/minfwm.conf"];
    
    std::ifstream file([path UTF8String]);
    if (!file.is_open()) {
        std::cout << "ConfigManager: Config file not found at " << [path UTF8String] << ", using defaults." << std::endl;
        return;
    }

    std::string line;
    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#') continue;
        
        size_t delimiter = line.find('=');
        if (delimiter == std::string::npos) continue;
        
        std::string key = line.substr(0, delimiter);
        std::string value = line.substr(delimiter + 1);
        
        // Trim whitespace
        key.erase(0, key.find_first_not_of(" \t"));
        key.erase(key.find_last_not_of(" \t") + 1);
        value.erase(0, value.find_first_not_of(" \t"));
        value.erase(value.find_last_not_of(" \t") + 1);

        if (key == "overscan-buffer-px") {
            overscanBufferPx = std::stof(value);
        } else if (key == "enable-window-shadows") {
            enableWindowShadows = (value == "true");
        } else if (key == "whitelist") {
            // Simple comma-separated list
            whitelist.clear();
            std::stringstream ss(value);
            std::string item;
            while (std::getline(ss, item, ',')) {
                whitelist.push_back(item);
            }
        }
    }
    std::cout << "ConfigManager: Loaded config from " << [path UTF8String] << std::endl;
}

} // namespace minfwm
