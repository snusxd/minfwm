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

} // namespace

int main() {
    minfwm::ConfigSnapshot parsed;
    std::string error;
    const bool valid = minfwm::ConfigManager::parseText(
        "enable-window-shadows = true\n"
        "multi-display-mode = \"isolated\"\n"
        "overscan-buffer-px = 250.5\n"
        "whitelist = [\"Terminal\", \"Music\"]\n"
        "spawn-behavior = \"center\"\n",
        parsed, error);
    expect(valid, "documented config subset parses");
    expect(parsed.enableWindowShadows, "boolean value is parsed");
    expect(parsed.overscanBufferPx == 250.5f, "finite numeric value is parsed");
    expect(parsed.whitelist.size() == 2, "string array is parsed");

    expect(!parsed.invertZoomScrollDirection, "zoom scroll inversion defaults to false");
    expect(minfwm::ConfigManager::parseText("invert-zoom-scroll-direction = true\n", parsed, error) &&
           parsed.invertZoomScrollDirection, "zoom scroll inversion accepts true");
    const auto inverted = parsed;
    for (const char* invalid : {"1", "\"true\"", "True", "false true"}) {
        expect(!minfwm::ConfigManager::parseText(std::string("invert-zoom-scroll-direction = ") + invalid, parsed, error),
               "zoom scroll inversion requires an actual TOML boolean");
        expect(parsed.invertZoomScrollDirection == inverted.invertZoomScrollDirection, "invalid inversion preserves the previous snapshot");
    }
    expect(!minfwm::ConfigManager::parseText("invert-zoom-scroll-direction = true\ninvert-zoom-scroll-direction = false\n", parsed, error),
           "duplicate zoom scroll inversion is rejected atomically");
    expect(minfwm::ConfigManager::parseText("invert-zoom-scroll-direction = false\n", parsed, error) &&
           !parsed.invertZoomScrollDirection, "zoom scroll inversion accepts false");
    expect(parsed.zoomedEscCenter == "screen", "Escape anchor defaults to screen center");
    for (const char* mode : {"screen", "mouse", "focus"}) {
        expect(minfwm::ConfigManager::parseText(std::string("zoomed-esc-center = \"") + mode + "\"", parsed, error) &&
               parsed.zoomedEscCenter == mode, "all documented Escape anchor modes parse");
    }
    const auto focused = parsed;
    for (const char* invalid : {"true", "[\"screen\"]", "\"cursor\"", "\"\""}) {
        expect(!minfwm::ConfigManager::parseText(std::string("zoomed-esc-center = ") + invalid, parsed, error) &&
               parsed.zoomedEscCenter == focused.zoomedEscCenter, "invalid Escape anchors preserve the previous snapshot");
    }
    const minfwm::ConfigSnapshot before = parsed;
    expect(!minfwm::ConfigManager::parseText("overscan-buffer-px = nan\n", parsed, error),
           "non-finite number is rejected");
    expect(parsed.overscanBufferPx == before.overscanBufferPx,
           "failed parse does not mutate output snapshot");
    expect(!minfwm::ConfigManager::parseText("unknown-key = true\n", parsed, error),
           "unknown key is rejected");
    expect(!minfwm::ConfigManager::parseText("enable-window-shadows = maybe\n", parsed, error),
           "invalid boolean is rejected");
    expect(!minfwm::ConfigManager::parseText("whitelist = [\"\"]\n", parsed, error),
           "empty whitelist entry is rejected");

    return failures == 0 ? 0 : 1;
}
