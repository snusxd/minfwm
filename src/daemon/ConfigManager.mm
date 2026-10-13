#include "ConfigManager.hpp"
#import <Foundation/Foundation.h>
#include <iostream>
#include <fstream>
#include <sstream>
#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <set>

namespace {

std::string trim(std::string value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return {};
    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

std::string stripComment(std::string value) {
    bool quoted = false;
    bool escaped = false;
    for (size_t i = 0; i < value.size(); ++i) {
        const char ch = value[i];
        if (escaped) {
            escaped = false;
        } else if (ch == '\\' && quoted) {
            escaped = true;
        } else if (ch == '"') {
            quoted = !quoted;
        } else if (ch == '#' && !quoted) {
            value.resize(i);
            break;
        }
    }
    return trim(value);
}

bool parseString(const std::string& input, std::string& output) {
    if (input.size() < 2 || input.front() != '"' || input.back() != '"') return false;
    output.clear();
    bool escaped = false;
    for (size_t i = 1; i + 1 < input.size(); ++i) {
        const char ch = input[i];
        if (escaped) {
            if (ch != '"' && ch != '\\') return false;
            output.push_back(ch);
            escaped = false;
        } else if (ch == '\\') {
            escaped = true;
        } else {
            output.push_back(ch);
        }
    }
    return !escaped;
}

bool parseBool(const std::string& input, bool& output) {
    if (input == "true") {
        output = true;
        return true;
    }
    if (input == "false") {
        output = false;
        return true;
    }
    return false;
}

bool parseFloat(const std::string& input, float& output) {
    errno = 0;
    char* end = nullptr;
    const float parsed = std::strtof(input.c_str(), &end);
    if (errno == ERANGE || end == input.c_str() || *end != '\0' || !std::isfinite(parsed)) return false;
    if (parsed < 0.0f || parsed > 100000.0f) return false;
    output = parsed;
    return true;
}

bool parseStringArray(const std::string& input, std::vector<std::string>& output) {
    if (input.size() < 2 || input.front() != '[' || input.back() != ']') return false;
    const std::string body = trim(input.substr(1, input.size() - 2));
    output.clear();
    if (body.empty()) return true;

    size_t start = 0;
    bool quoted = false;
    bool escaped = false;
    for (size_t i = 0; i <= body.size(); ++i) {
        const char ch = i < body.size() ? body[i] : ',';
        if (escaped) {
            escaped = false;
        } else if (ch == '\\' && quoted) {
            escaped = true;
        } else if (ch == '"') {
            quoted = !quoted;
        } else if (ch == ',' && !quoted) {
            std::string item;
            if (!parseString(trim(body.substr(start, i - start)), item)) return false;
            if (item.empty()) return false;
            output.push_back(std::move(item));
            start = i + 1;
        }
    }
    return !quoted && !escaped;
}

} // namespace

namespace minfwm {

bool ConfigManager::parseText(std::string_view text, ConfigSnapshot& out, std::string& error) {
    ConfigSnapshot candidate;
    std::set<std::string> seen;
    size_t lineNumber = 0;
    size_t lineStart = 0;

    while (lineStart <= text.size()) {
        ++lineNumber;
        const size_t lineEnd = text.find('\n', lineStart);
        const size_t length = lineEnd == std::string_view::npos ? text.size() - lineStart : lineEnd - lineStart;
        const std::string line = stripComment(std::string(text.substr(lineStart, length)));
        if (!line.empty()) {
            const size_t delimiter = line.find('=');
            if (delimiter == std::string::npos) {
                error = "line " + std::to_string(lineNumber) + ": expected key = value";
                return false;
            }
            const std::string key = trim(line.substr(0, delimiter));
            const std::string value = trim(line.substr(delimiter + 1));
            if (key.empty() || value.empty() || !seen.insert(key).second) {
                error = "line " + std::to_string(lineNumber) + ": invalid or duplicate key";
                return false;
            }

            if (key == "enable-window-shadows") {
                if (!parseBool(value, candidate.enableWindowShadows)) {
                    error = "line " + std::to_string(lineNumber) + ": expected true or false";
                    return false;
                }
            } else if (key == "multi-display-mode") {
                if (!parseString(value, candidate.multiDisplayMode) || candidate.multiDisplayMode != "isolated") {
                    error = "line " + std::to_string(lineNumber) + ": multi-display-mode must be \"isolated\"";
                    return false;
                }
            } else if (key == "overscan-buffer-px") {
                if (!parseFloat(value, candidate.overscanBufferPx)) {
                    error = "line " + std::to_string(lineNumber) + ": overscan-buffer-px must be a finite number from 0 to 100000";
                    return false;
                }
            } else if (key == "whitelist") {
                if (!parseStringArray(value, candidate.whitelist)) {
                    error = "line " + std::to_string(lineNumber) + ": whitelist must be an array of non-empty strings";
                    return false;
                }
            } else if (key == "spawn-behavior") {
                if (!parseString(value, candidate.spawnBehavior) || candidate.spawnBehavior != "center") {
                    error = "line " + std::to_string(lineNumber) + ": spawn-behavior must be \"center\"";
                    return false;
                }
            } else {
                error = "line " + std::to_string(lineNumber) + ": unsupported key \"" + key + "\"";
                return false;
            }
        }

        if (lineEnd == std::string_view::npos) break;
        lineStart = lineEnd + 1;
    }

    out = std::move(candidate);
    return true;
}

ConfigSnapshot ConfigManager::snapshot() const {
    return m_snapshot;
}

bool ConfigManager::load(std::string* error) {
    NSString* home = NSHomeDirectory();
    NSString* path = [home stringByAppendingPathComponent:@".config/minfwm/minfwm.toml"];

    std::ifstream file([path UTF8String]);
    if (!file.is_open()) {
        const std::string message = "config file not found: " + std::string([path UTF8String]);
        if (error) *error = message;
        std::cerr << "ConfigManager: " << message << "; keeping current snapshot." << std::endl;
        return false;
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    ConfigSnapshot candidate;
    std::string parseError;
    if (!parseText(buffer.str(), candidate, parseError)) {
        if (error) *error = parseError;
        std::cerr << "ConfigManager: invalid config: " << parseError << "; keeping current snapshot." << std::endl;
        return false;
    }

    m_snapshot = std::move(candidate);
    std::cout << "ConfigManager: Loaded config from " << [path UTF8String] << std::endl;
    return true;
}

} // namespace minfwm
