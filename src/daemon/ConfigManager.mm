#include "ConfigManager.hpp"

#import <Foundation/Foundation.h>

#include <toml.hpp>

#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <utility>

namespace {

using TomlTable = toml::table;
using TomlNode = toml::node;

const TomlTable* tableAt(const TomlTable& root, std::string_view name, std::string& error) {
    const TomlNode* node = root.get(name);
    if (!node) return nullptr;
    const TomlTable* table = node->as_table();
    if (!table) error = "[" + std::string(name) + "] must be a table";
    return table;
}

bool rejectUnknownKeys(const TomlTable& root, const std::vector<std::string_view>& allowedTables,
                       const std::vector<std::string_view>& legacyKeys, std::string& error) {
    for (const auto& [key, node] : root) {
        const bool isTable = std::find(allowedTables.begin(), allowedTables.end(), key) != allowedTables.end();
        const bool isLegacyKey = std::find(legacyKeys.begin(), legacyKeys.end(), key) != legacyKeys.end();
        if ((isTable && !node.is_table()) || (!isTable && !isLegacyKey)) {
            error = "unsupported key or table \"" + std::string(key) + "\"";
            return false;
        }
    }
    return true;
}

bool rejectUnknownKeys(const TomlTable& table, std::string_view section,
                       const std::vector<std::string_view>& allowedKeys, std::string& error) {
    for (const auto& [key, node] : table) {
        (void)node;
        if (std::find(allowedKeys.begin(), allowedKeys.end(), key) == allowedKeys.end()) {
            error = "unsupported key \"" + std::string(section) + "." + std::string(key) + "\"";
            return false;
        }
    }
    return true;
}

const TomlNode* get(const TomlTable& root, const TomlTable* table, std::string_view key,
                    std::string& error) {
    const TomlNode* nested = table ? table->get(key) : nullptr;
    const TomlNode* legacy = root.get(key);
    if (nested && legacy) {
        error = "option \"" + std::string(key) + "\" is defined both at the root and in its table";
        return nullptr;
    }
    return nested ? nested : legacy;
}

bool readBool(const TomlTable& root, const TomlTable* table, std::string_view key,
              bool& out, std::string& error) {
    const TomlNode* node = get(root, table, key, error);
    if (!error.empty()) return false;
    if (!node) return true;
    if (!node->is_boolean()) {
        error = std::string(key) + " must be a boolean";
        return false;
    }
    const auto value = node->value<bool>();
    if (!value) {
        error = std::string(key) + " must be a boolean";
        return false;
    }
    out = *value;
    return true;
}

bool readString(const TomlTable& root, const TomlTable* table, std::string_view key,
                std::string& out, std::string& error) {
    const TomlNode* node = get(root, table, key, error);
    if (!error.empty()) return false;
    if (!node) return true;
    const auto value = node->value<std::string>();
    if (!value) {
        error = std::string(key) + " must be a string";
        return false;
    }
    out = *value;
    return true;
}

bool readOverscan(const TomlTable& root, const TomlTable* table, float& out, std::string& error) {
    const TomlNode* node = get(root, table, "overscan-buffer-px", error);
    if (!error.empty()) return false;
    if (!node) return true;

    double value = 0.0;
    if (const auto floating = node->value<double>()) {
        value = *floating;
    } else if (const auto integer = node->value<std::int64_t>()) {
        value = static_cast<double>(*integer);
    } else {
        error = "overscan-buffer-px must be a number from 0 to 100000";
        return false;
    }

    if (!std::isfinite(value) || value < 0.0 || value > 100000.0) {
        error = "overscan-buffer-px must be a finite number from 0 to 100000";
        return false;
    }
    out = static_cast<float>(value);
    return true;
}

bool readWhitelist(const TomlTable& root, const TomlTable* table,
                   std::vector<std::string>& out, std::string& error) {
    const TomlNode* node = get(root, table, "whitelist", error);
    if (!error.empty()) return false;
    if (!node) return true;
    const toml::array* values = node->as_array();
    if (!values) {
        error = "whitelist must be an array of non-empty strings";
        return false;
    }

    std::vector<std::string> parsed;
    parsed.reserve(values->size());
    for (const TomlNode& item : *values) {
        const auto value = item.value<std::string>();
        if (!value || value->empty()) {
            error = "whitelist must be an array of non-empty strings";
            return false;
        }
        parsed.push_back(*value);
    }
    out = std::move(parsed);
    return true;
}

bool readSuperKey(const TomlTable* table, std::vector<std::string>& out, std::string& error) {
    if (!table) return true;
    const TomlNode* node = table->get("super");
    if (!node) return true;
    const toml::array* values = node->as_array();
    if (!values || values->empty()) {
        error = "keybinds.super must be a non-empty array of Cmd, Alt, Shift, or Ctrl strings";
        return false;
    }

    std::vector<std::string> parsed;
    parsed.reserve(values->size());
    for (const TomlNode& item : *values) {
        const auto value = item.value<std::string>();
        if (!value || (*value != "Cmd" && *value != "Alt" && *value != "Shift" && *value != "Ctrl") ||
            std::find(parsed.begin(), parsed.end(), *value) != parsed.end()) {
            error = "keybinds.super must contain unique Cmd, Alt, Shift, or Ctrl strings";
            return false;
        }
        parsed.push_back(*value);
    }
    out = std::move(parsed);
    return true;
}

bool readShortcut(const TomlTable* table, std::string_view name,
                  std::vector<std::string>& out, std::string& error) {
    if (!table) return true;
    const TomlNode* node = table->get(name);
    if (!node) return true;
    const toml::array* values = node->as_array();
    if (!values || values->size() != 2) {
        error = "keybinds." + std::string(name) + " must be [\"Super\", \"A-Z\"]";
        return false;
    }
    const auto modifier = (*values)[0].value<std::string>();
    const auto key = (*values)[1].value<std::string>();
    if (!modifier || *modifier != "Super" || !key || key->size() != 1 ||
        (*key)[0] < 'A' || (*key)[0] > 'Z') {
        error = "keybinds." + std::string(name) + " must be [\"Super\", \"A-Z\"]";
        return false;
    }
    out = {*modifier, *key};
    return true;
}

bool readBookmarkModifiers(const TomlTable* table, std::string_view name,
                           std::vector<std::string>& out, std::string& error) {
    if (!table) return true;
    const TomlNode* node = table->get(name);
    if (!node) return true;
    const toml::array* values = node->as_array();
    if (!values || values->empty()) {
        error = "keybinds." + std::string(name) + " must be a non-empty array of modifier names";
        return false;
    }

    std::vector<std::string> parsed;
    parsed.reserve(values->size());
    for (const TomlNode& item : *values) {
        const auto value = item.value<std::string>();
        if (!value || (*value != "Super" && *value != "Cmd" && *value != "Alt" &&
                       *value != "Shift" && *value != "Ctrl") ||
            std::find(parsed.begin(), parsed.end(), *value) != parsed.end()) {
            error = "keybinds." + std::string(name) +
                " must contain unique Super, Cmd, Alt, Shift, or Ctrl modifiers";
            return false;
        }
        parsed.push_back(*value);
    }
    out = std::move(parsed);
    return true;
}

unsigned bookmarkModifierMask(const std::vector<std::string>& modifiers,
                              const std::vector<std::string>& superModifiers) {
    unsigned mask = 0;
    const auto add = [&mask](const std::string& modifier) {
        if (modifier == "Cmd") mask |= 1u << 0;
        else if (modifier == "Alt") mask |= 1u << 1;
        else if (modifier == "Shift") mask |= 1u << 2;
        else if (modifier == "Ctrl") mask |= 1u << 3;
    };
    for (const std::string& modifier : modifiers) {
        if (modifier == "Super") {
            for (const std::string& superModifier : superModifiers) add(superModifier);
        } else {
            add(modifier);
        }
    }
    return mask;
}

bool readConfig(const TomlTable& root, minfwm::ConfigSnapshot& candidate, std::string& error) {
    if (!rejectUnknownKeys(root, {"window", "zoom", "display", "keybinds", "pins"},
                           {"enable-window-shadows", "invert-zoom-scroll-direction", "zoomed-esc-center",
                            "multi-display-mode", "overscan-buffer-px", "whitelist", "spawn-behavior",
                            "always-on-top"}, error)) return false;

    const TomlTable* window = tableAt(root, "window", error);
    const TomlTable* zoom = tableAt(root, "zoom", error);
    const TomlTable* display = tableAt(root, "display", error);
    const TomlTable* keybinds = tableAt(root, "keybinds", error);
    const TomlTable* pins = tableAt(root, "pins", error);
    if (!error.empty()) return false;

    if (window && !rejectUnknownKeys(*window, "window", {"enable-window-shadows", "overscan-buffer-px", "whitelist", "spawn-behavior"}, error)) return false;
    if (zoom && !rejectUnknownKeys(*zoom, "zoom", {"invert-zoom-scroll-direction", "zoomed-esc-center"}, error)) return false;
    if (display && !rejectUnknownKeys(*display, "display", {"multi-display-mode"}, error)) return false;
    if (keybinds && !rejectUnknownKeys(*keybinds, "keybinds",
                                       {"super", "center-camera-to-focus", "center-focus-to-camera",
                                        "bookmarks-add", "bookmarks-goto"}, error)) return false;
    if (pins && !rejectUnknownKeys(*pins, "pins", {"always-on-top"}, error)) return false;

    if (!readBool(root, window, "enable-window-shadows", candidate.enableWindowShadows, error) ||
        !readBool(root, zoom, "invert-zoom-scroll-direction", candidate.invertZoomScrollDirection, error) ||
        !readString(root, zoom, "zoomed-esc-center", candidate.zoomedEscCenter, error) ||
        !readString(root, display, "multi-display-mode", candidate.multiDisplayMode, error) ||
        !readOverscan(root, window, candidate.overscanBufferPx, error) ||
        !readWhitelist(root, window, candidate.whitelist, error) ||
        !readString(root, window, "spawn-behavior", candidate.spawnBehavior, error) ||
        !readBool(root, pins, "always-on-top", candidate.pinsAlwaysOnTop, error) ||
        !readSuperKey(keybinds, candidate.superModifiers, error) ||
        !readShortcut(keybinds, "center-camera-to-focus", candidate.centerCameraToFocus, error) ||
        !readShortcut(keybinds, "center-focus-to-camera", candidate.centerFocusToCamera, error) ||
        !readBookmarkModifiers(keybinds, "bookmarks-add", candidate.bookmarksAddModifiers, error) ||
        !readBookmarkModifiers(keybinds, "bookmarks-goto", candidate.bookmarksGotoModifiers, error)) {
        return false;
    }

    if (bookmarkModifierMask(candidate.bookmarksAddModifiers, candidate.superModifiers) ==
        bookmarkModifierMask(candidate.bookmarksGotoModifiers, candidate.superModifiers)) {
        error = "keybinds.bookmarks-add and keybinds.bookmarks-goto must resolve to different modifier chords";
        return false;
    }

    if (candidate.zoomedEscCenter != "screen" && candidate.zoomedEscCenter != "mouse" && candidate.zoomedEscCenter != "focus") {
        error = "zoomed-esc-center must be \"screen\", \"mouse\" or \"focus\"";
        return false;
    }
    if (candidate.multiDisplayMode != "isolated") {
        error = "multi-display-mode must be \"isolated\"";
        return false;
    }
    if (candidate.spawnBehavior != "center") {
        error = "spawn-behavior must be \"center\"";
        return false;
    }
    return true;
}

} // namespace

namespace minfwm {

bool ConfigManager::parseText(std::string_view text, ConfigSnapshot& out, std::string& error) {
    error.clear();
    try {
        const TomlTable root = toml::parse(text);
        ConfigSnapshot candidate;
        if (!readConfig(root, candidate, error)) return false;
        out = std::move(candidate);
        error.clear();
        return true;
    } catch (const toml::parse_error& parseError) {
        error = parseError.what();
        return false;
    }
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
