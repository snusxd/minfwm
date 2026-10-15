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
    expect(parsed.snapEnabled && parsed.snapThreshold == 32.0f,
           "snap defaults to enabled with a 32-point threshold");
    expect(parsed.snapHorizontalTuning == minfwm::core::SnapTuning::automatic &&
           parsed.snapVerticalTuning == minfwm::core::SnapTuning::automatic,
           "snap tuning defaults to automatic on both axes");
    expect(parsed.overscanBufferPx == 250.5f, "finite numeric value is parsed");
    expect(parsed.whitelist.size() == 2, "string array is parsed");
    expect(minfwm::ConfigManager::parseText(
               "[display]\nignored-displays = [\"Built-in Retina Display\", \"XV271 Z\"]\n",
               parsed, error) && parsed.ignoredDisplays.size() == 2 &&
           parsed.ignoredDisplays[0] == "Built-in Retina Display" &&
           parsed.ignoredDisplays[1] == "XV271 Z",
           "ignored display names are parsed without changing their order");
    const auto ignored = parsed.ignoredDisplays;
    for (const char* invalid : {
             "[display]\nignored-displays = \"Built-in Retina Display\"\n",
             "[display]\nignored-displays = [\"\"]\n",
             "[display]\nignored-displays = [\"XV271 Z\", \"XV271 Z\"]\n",
             "[display]\nignored-displays = [1]\n"}) {
        expect(!minfwm::ConfigManager::parseText(invalid, parsed, error) &&
               parsed.ignoredDisplays == ignored,
               "invalid ignored display config preserves the previous snapshot");
    }
    minfwm::ConfigSnapshot legacy;
    expect(minfwm::ConfigManager::parseText("enable-window-shadows = true\nwhitelist = [\"Terminal\"]\n", legacy, error) &&
           legacy.enableWindowShadows && legacy.whitelist.size() == 1,
           "previous root-level TOML remains supported");

    expect(!parsed.invertZoomScrollDirection, "zoom scroll inversion defaults to false");
    expect(minfwm::ConfigManager::parseText("[snap]\nenable = false\nthreshold = 64.5\n", parsed, error) &&
           !parsed.snapEnabled && parsed.snapThreshold == 64.5f,
           "snap options parse together from their own table");
    expect(minfwm::ConfigManager::parseText("[snap]\nenable = true\nthreshold = 96\n", parsed, error) &&
           parsed.snapEnabled && parsed.snapThreshold == 96.0f,
           "snap accepts a boolean and an integer threshold");
    expect(minfwm::ConfigManager::parseText(
               "[snap]\nhorizontal-tuning = \"right\"\nvertical-tuning = \"bottom\"\n",
               parsed, error) &&
           parsed.snapHorizontalTuning == minfwm::core::SnapTuning::trailing &&
           parsed.snapVerticalTuning == minfwm::core::SnapTuning::trailing,
           "snap parses horizontal and vertical tuning independently");
    for (const auto [horizontal, expected] : {
             std::pair{"left", minfwm::core::SnapTuning::leading},
             std::pair{"center", minfwm::core::SnapTuning::center},
             std::pair{"right", minfwm::core::SnapTuning::trailing},
             std::pair{"auto", minfwm::core::SnapTuning::automatic}}) {
        expect(minfwm::ConfigManager::parseText(
                   std::string("[snap]\nhorizontal-tuning = \"") + horizontal + "\"\n", parsed, error) &&
               parsed.snapHorizontalTuning == expected,
               "every horizontal tuning value parses");
    }
    for (const auto [vertical, expected] : {
             std::pair{"top", minfwm::core::SnapTuning::leading},
             std::pair{"center", minfwm::core::SnapTuning::center},
             std::pair{"bottom", minfwm::core::SnapTuning::trailing},
             std::pair{"auto", minfwm::core::SnapTuning::automatic}}) {
        expect(minfwm::ConfigManager::parseText(
                   std::string("[snap]\nvertical-tuning = \"") + vertical + "\"\n", parsed, error) &&
               parsed.snapVerticalTuning == expected,
               "every vertical tuning value parses");
    }
    minfwm::ConfigSnapshot thresholdLimits;
    expect(minfwm::ConfigManager::parseText("[snap]\nthreshold = 0\n", thresholdLimits, error) &&
           thresholdLimits.snapThreshold == 0.0f, "zero snap threshold is accepted");
    expect(minfwm::ConfigManager::parseText("[snap]\nthreshold = 1000\n", thresholdLimits, error) &&
           thresholdLimits.snapThreshold == 1000.0f, "maximum snap threshold is accepted");
    const auto snapSettings = parsed;
    for (const char* invalid : {
             "[snap]\nenable = \"true\"\n",
             "[snap]\nthreshold = \"64\"\n",
             "[snap]\nthreshold = -1\n",
             "[snap]\nthreshold = 1001\n",
             "[snap]\nthreshold = nan\n",
             "[snap]\nthreshold = inf\n",
             "[snap]\nunknown = 1\n",
             "[snap]\nhorizontal-tuning = \"top\"\n",
             "[snap]\nvertical-tuning = \"left\"\n",
             "[snap]\nhorizontal-tuning = 1\n",
             "[snap]\nvertical-tuning = \"Bottom\"\n",
             "snap = 42\n",
             "[camera]\nsnapping = true\n"}) {
        expect(!minfwm::ConfigManager::parseText(invalid, parsed, error) &&
               parsed.snapEnabled == snapSettings.snapEnabled &&
               parsed.snapThreshold == snapSettings.snapThreshold &&
               parsed.snapHorizontalTuning == snapSettings.snapHorizontalTuning &&
               parsed.snapVerticalTuning == snapSettings.snapVerticalTuning,
               "invalid snap settings preserve the previous snapshot");
    }
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
