#import <Foundation/Foundation.h>
#include "CommandLine.hpp"
#include "DaemonControl.hpp"
#include "IPCClient.hpp"
#include "Protocol.hpp"

#include <csignal>
#include <iostream>

namespace {

const char* errorCodeName(minfwm::ErrorCode error) {
    switch (error) {
        case minfwm::ErrorCode::MALFORMED:
            return "MALFORMED";
        case minfwm::ErrorCode::UNSUPPORTED:
            return "UNSUPPORTED";
        case minfwm::ErrorCode::INTERNAL:
            return "INTERNAL";
        case minfwm::ErrorCode::NONE:
            return "NONE";
    }
    return "UNKNOWN";
}

void printUsage() {
    std::cerr << "Usage: minfwm [start|stop|restart|reload|enable|disable] | camera move --x <value> --y <value>\n";
}

} // namespace

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        const auto parsed = minfwm::parseCommandLine(argc, argv);
        if (!parsed.command.has_value()) {
            std::cerr << "minfwm: " << parsed.error << '\n';
            printUsage();
            return 2;
        }

        const auto command = parsed.command->command;
        if (command == minfwm::ParsedCommandLine::Command::START ||
            command == minfwm::ParsedCommandLine::Command::STOP ||
            command == minfwm::ParsedCommandLine::Command::RESTART ||
            command == minfwm::ParsedCommandLine::Command::ENABLE ||
            command == minfwm::ParsedCommandLine::Command::DISABLE) {
            const char* action = command == minfwm::ParsedCommandLine::Command::START ? "start" :
                                 command == minfwm::ParsedCommandLine::Command::STOP ? "stop" :
                                 command == minfwm::ParsedCommandLine::Command::RESTART ? "restart" :
                                 command == minfwm::ParsedCommandLine::Command::ENABLE ? "enable" : "disable";
            std::string error;
            if (!minfwm::controlDaemon(action, error)) {
                std::cerr << "minfwm: " << error << '\n';
                return 1;
            }
            return 0;
        }

        minfwm::Request request;
        if (parsed.command->command == minfwm::ParsedCommandLine::Command::RELOAD) {
            request = minfwm::makeReloadRequest();
        } else {
            request = minfwm::makeCameraMoveRequest(parsed.command->x, parsed.command->y);
        }

        minfwm::IPCClient client;

        const auto result = client.sendMessage(request);
        if (!result.transportSucceeded) {
            std::cerr << "minfwm: " << result.error << '\n';
            return 1;
        }
        if (result.response.status != minfwm::ResponseStatus::OK) {
            std::cerr << "minfwm: daemon rejected request ("
                      << errorCodeName(result.response.error) << ")\n";
            return 1;
        }
    }
    return 0;
}
