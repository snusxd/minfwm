#pragma once

#include <optional>
#include <string>

namespace minfwm {

struct ParsedCommandLine {
    enum class Command {
        RELOAD,
        CAMERA_MOVE
    };

    Command command = Command::RELOAD;
    float x = 0.0F;
    float y = 0.0F;
};

struct CommandLineParseResult {
    std::optional<ParsedCommandLine> command;
    std::string error;
};

CommandLineParseResult parseCommandLine(int argc, const char* const* argv);

} // namespace minfwm
