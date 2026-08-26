#include "CommandLine.hpp"

#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <cctype>
#include <string_view>

namespace minfwm {
namespace {

CommandLineParseResult invalidArguments(const std::string& message) {
    return CommandLineParseResult{std::nullopt, message};
}

bool parseFiniteFloat(std::string_view text, float& value) {
    if (text.empty() || std::isspace(static_cast<unsigned char>(text.front())) != 0) {
        return false;
    }

    const std::string input(text);
    char* end = nullptr;
    errno = 0;
    const float parsed = std::strtof(input.c_str(), &end);
    if (errno == ERANGE || end == input.c_str() || *end != '\0' || !std::isfinite(parsed)) {
        return false;
    }

    value = parsed;
    return true;
}

bool consumeValue(int argc, const char* const* argv, int& index,
                  std::string_view inlineValue, float& destination,
                  const char* option, std::string& error) {
    std::string_view value = inlineValue;
    if (value.empty()) {
        if (index + 1 >= argc) {
            error = std::string("missing value for ") + option;
            return false;
        }
        if (argv[index + 1] == nullptr) {
            error = std::string("missing value for ") + option;
            return false;
        }
        value = argv[++index];
    }

    if (!parseFiniteFloat(value, destination)) {
        error = std::string("invalid value for ") + option;
        return false;
    }
    return true;
}

} // namespace

CommandLineParseResult parseCommandLine(int argc, const char* const* argv) {
    if (argc < 2 || argv == nullptr) {
        return invalidArguments("a command is required");
    }

    const std::string_view command(argv[1] == nullptr ? "" : argv[1]);
    if (command == "reload") {
        if (argc != 2) {
            return invalidArguments("reload does not accept arguments");
        }
        return CommandLineParseResult{
            ParsedCommandLine{ParsedCommandLine::Command::RELOAD, 0.0F, 0.0F}, {}};
    }

    if (command != "camera") {
        return invalidArguments("unknown command: " + std::string(command));
    }
    if (argc < 3 || argv[2] == nullptr || std::string_view(argv[2]) != "move") {
        return invalidArguments("expected: camera move --x <value> --y <value>");
    }

    ParsedCommandLine parsed;
    parsed.command = ParsedCommandLine::Command::CAMERA_MOVE;
    bool hasX = false;
    bool hasY = false;
    for (int index = 3; index < argc; ++index) {
        if (argv[index] == nullptr) {
            return invalidArguments("null argument");
        }

        const std::string_view argument(argv[index]);
        if (argument == "--x" || argument.starts_with("--x=")) {
            if (hasX) {
                return invalidArguments("duplicate --x");
            }
            hasX = true;
            const std::string_view inlineValue = argument == "--x"
                ? std::string_view{}
                : argument.substr(4);
            std::string error;
            if (!consumeValue(argc, argv, index, inlineValue, parsed.x, "--x", error)) {
                return invalidArguments(error);
            }
            continue;
        }

        if (argument == "--y" || argument.starts_with("--y=")) {
            if (hasY) {
                return invalidArguments("duplicate --y");
            }
            hasY = true;
            const std::string_view inlineValue = argument == "--y"
                ? std::string_view{}
                : argument.substr(4);
            std::string error;
            if (!consumeValue(argc, argv, index, inlineValue, parsed.y, "--y", error)) {
                return invalidArguments(error);
            }
            continue;
        }

        return invalidArguments("unknown argument: " + std::string(argument));
    }

    if (!hasX || !hasY) {
        return invalidArguments("camera move requires both --x and --y");
    }
    return CommandLineParseResult{parsed, {}};
}

} // namespace minfwm
