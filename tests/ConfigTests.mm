#import <Foundation/Foundation.h>

#include "ConfigManager.hpp"

#include <iostream>

namespace {

int failures = 0;

void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

std::string zoomConfig(const std::string& value) {
    return "[zoom]\ninvert-zoom-scroll-direction = " + value + "\n";
}

} // namespace

int main() {
    minfwm::ConfigSnapshot parsed;
    std::string error;
    const bool valid = minfwm::ConfigManager::parseText(
        "# TOML tables group related options.\n"
        "[window]\n"
        "enable-window-shadows = true\n"
        "overscan-buffer-px = 250.5 # trailing comment\n"
        "whitelist = [\"Terminal\", \"Music\",]\n"
        "spawn-behavior = \"center\"\n"
        "[display]\n"
        "multi-display-mode = \"isolated\"\n",
        parsed, error);
    expect(valid, "documented TOML config parses");
    expect(parsed.enableWindowShadows, "boolean value is parsed");
    expect(parsed.overscanBufferPx == 250.5f, "finite numeric value is parsed");
    expect(parsed.whitelist.size() == 2, "string array is parsed");
    minfwm::ConfigSnapshot legacy;
    expect(minfwm::ConfigManager::parseText("enable-window-shadows = true\nwhitelist = [\"Terminal\"]\n", legacy, error) &&
           legacy.enableWindowShadows && legacy.whitelist.size() == 1,
           "previous root-level TOML remains supported");

    expect(!parsed.invertZoomScrollDirection, "zoom scroll inversion defaults to false");
    expect(minfwm::ConfigManager::parseText(zoomConfig("true"), parsed, error) &&
           parsed.invertZoomScrollDirection, "boolean option accepts true");
    const auto inverted = parsed;
    for (const char* invalid : {"1", "\"true\"", "True", "false true"}) {
        expect(!minfwm::ConfigManager::parseText(zoomConfig(invalid), parsed, error),
               "zoom scroll inversion requires a TOML boolean");
        expect(parsed.invertZoomScrollDirection == inverted.invertZoomScrollDirection,
               "invalid config preserves the output snapshot");
    }
    expect(!minfwm::ConfigManager::parseText(
               "[zoom]\ninvert-zoom-scroll-direction = true\ninvert-zoom-scroll-direction = false\n", parsed, error),
           "duplicate TOML key is rejected");
    expect(minfwm::ConfigManager::parseText(zoomConfig("false"), parsed, error) &&
           !parsed.invertZoomScrollDirection, "boolean option accepts false");

    expect(parsed.zoomedEscCenter == "screen", "Escape anchor defaults to screen center");
    for (const char* mode : {"screen", "mouse", "focus"}) {
        expect(minfwm::ConfigManager::parseText(
                   std::string("[zoom]\nzoomed-esc-center = \"") + mode + "\"", parsed, error) &&
               parsed.zoomedEscCenter == mode, "all documented Escape anchor modes parse");
    }
    const auto focused = parsed;
    for (const char* invalid : {"true", "[\"screen\"]", "\"cursor\"", "\"\""}) {
        expect(!minfwm::ConfigManager::parseText(
                   std::string("[zoom]\nzoomed-esc-center = ") + invalid, parsed, error) &&
               parsed.zoomedEscCenter == focused.zoomedEscCenter,
               "invalid Escape anchors preserve the output snapshot");
    }

    const minfwm::ConfigSnapshot before = parsed;
    expect(!minfwm::ConfigManager::parseText("[window]\noverscan-buffer-px = nan\n", parsed, error),
           "non-finite number is rejected");
    expect(parsed.overscanBufferPx == before.overscanBufferPx,
           "failed parse does not mutate output snapshot");
    expect(!minfwm::ConfigManager::parseText("[window]\nunknown-key = true\n", parsed, error),
           "unknown key is rejected");
    expect(!minfwm::ConfigManager::parseText("[window]\nenable-window-shadows = maybe\n", parsed, error),
           "invalid boolean is rejected");
    expect(!minfwm::ConfigManager::parseText("[window]\nwhitelist = [\"\"]\n", parsed, error),
           "empty whitelist entry is rejected");
    expect(!minfwm::ConfigManager::parseText("[zoom\ninvert-zoom-scroll-direction = true", parsed, error),
           "malformed TOML is rejected");
    expect(minfwm::ConfigManager::parseText("[keybinds]\n", parsed, error),
           "document-only keybind category is accepted empty");
    expect(!minfwm::ConfigManager::parseText("[keybinds]\npan = \"cmd+option\"\n", parsed, error),
           "undocumented configurable keybinds are rejected");

    return failures == 0 ? 0 : 1;
}
