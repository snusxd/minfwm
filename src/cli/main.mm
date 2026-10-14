#import <Foundation/Foundation.h>
#include "CommandLine.hpp"
#include "DaemonControl.hpp"
#include "IPCClient.hpp"
#include "Protocol.hpp"

#include <csignal>
#include <iostream>
#include <string_view>

int runDaemon();

#ifndef MINFWM_BUILD_COMMIT
#define MINFWM_BUILD_COMMIT "unknown"
#endif

#ifndef MINFWM_BUILD_VERSION
#define MINFWM_BUILD_VERSION MINFWM_BUILD_COMMIT
#endif

#ifndef MINFWM_SOURCE_DIR
#define MINFWM_SOURCE_DIR "."
#endif

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
    std::cerr << "Usage: minfwm [daemon|start|stop|restart|dev-update|reload|enable|disable|status|version [--dev]] | camera move --x <value> --y <value>\n";
}

std::string latestLocalCommit() {
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    task.arguments = @[@"-C", [NSString stringWithUTF8String:MINFWM_SOURCE_DIR],
                       @"rev-parse", @"--short", @"HEAD"];
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    NSError* error = nil;
    if (![task launchAndReturnError:&error]) return "unknown";
    NSData* data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) return "unknown";
    NSString* output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    const char* commit = output.UTF8String;
    if (commit == nullptr) return "unknown";
    std::string result(commit);
    while (!result.empty() && (result.back() == '\n' || result.back() == '\r')) {
        result.pop_back();
    }
    return result.empty() ? "unknown" : result;
}

} // namespace

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        if (argc > 1 && argv[1] != nullptr && std::string_view(argv[1]) == "daemon") {
            if (argc != 2) {
                std::cerr << "minfwm: daemon does not accept arguments\n";
                return 2;
            }
            return runDaemon();
        }
        const auto parsed = minfwm::parseCommandLine(argc, argv);
        if (!parsed.command.has_value()) {
            std::cerr << "minfwm: " << parsed.error << '\n';
            printUsage();
            return 2;
        }

        const auto command = parsed.command->command;
        if (command == minfwm::ParsedCommandLine::Command::STATUS) {
            std::cout << "minfwm daemon: " << minfwm::daemonStatus() << '\n';
            return 0;
        }
        if (command == minfwm::ParsedCommandLine::Command::VERSION) {
            std::cout << "minfwm "
                      << (parsed.command->devVersion ? latestLocalCommit() : MINFWM_BUILD_VERSION)
                      << '\n';
            return 0;
        }
        if (command == minfwm::ParsedCommandLine::Command::DEV_UPDATE) {
            minfwm::IPCClient client;
            std::cout << "minfwm: saving daemon layout..." << std::endl;
            const auto result = client.sendMessage(minfwm::makeSaveLayoutRequest());
            if (!result.transportSucceeded) {
                std::cerr << "minfwm: could not save daemon layout: " << result.error << '\n';
                return 1;
            }
            if (result.response.status != minfwm::ResponseStatus::OK) {
                std::cerr << "minfwm: daemon could not save layout ("
                          << errorCodeName(result.response.error) << ")\n";
                return 1;
            }
            std::cout << "minfwm: daemon layout saved successfully" << std::endl;

            std::cout << "minfwm: restarting daemon..." << std::endl;
            std::string error;
            if (!minfwm::controlDaemon("restart", error)) {
                std::cerr << "minfwm: layout saved, but daemon restart failed: " << error << '\n';
                return 1;
            }
            std::cout << "minfwm: dev-update completed successfully (layout saved and daemon restart succeeded)\n";
            return 0;
        }
        if (command == minfwm::ParsedCommandLine::Command::START ||
            command == minfwm::ParsedCommandLine::Command::STOP ||
            command == minfwm::ParsedCommandLine::Command::RESTART ||
            command == minfwm::ParsedCommandLine::Command::ENABLE ||
            command == minfwm::ParsedCommandLine::Command::DISABLE) {
            const char* action = command == minfwm::ParsedCommandLine::Command::START ? "start" :
                                 command == minfwm::ParsedCommandLine::Command::STOP ? "stop" :
                                 command == minfwm::ParsedCommandLine::Command::RESTART ? "restart" :
                                 command == minfwm::ParsedCommandLine::Command::ENABLE ? "enable" : "disable";
            const char* progress = command == minfwm::ParsedCommandLine::Command::START ? "starting daemon..." :
                                   command == minfwm::ParsedCommandLine::Command::STOP ? "stopping daemon..." :
                                   command == minfwm::ParsedCommandLine::Command::RESTART ? "restarting daemon..." :
                                   command == minfwm::ParsedCommandLine::Command::ENABLE ? "enabling daemon..." :
                                                                                          "disabling daemon...";
            const char* success = command == minfwm::ParsedCommandLine::Command::START ? "daemon started successfully" :
                                  command == minfwm::ParsedCommandLine::Command::STOP ? "daemon stopped successfully" :
                                  command == minfwm::ParsedCommandLine::Command::RESTART ? "daemon restarted successfully" :
                                  command == minfwm::ParsedCommandLine::Command::ENABLE ? "daemon enabled successfully" :
                                                                                         "daemon disabled successfully";
            std::cout << "minfwm: " << progress << std::endl;
            std::string error;
            if (!minfwm::controlDaemon(action, error)) {
                std::cerr << "minfwm: " << error << '\n';
                return 1;
            }
            std::cout << "minfwm: " << success << '\n';
            return 0;
        }

        minfwm::Request request;
        const bool isReload = parsed.command->command == minfwm::ParsedCommandLine::Command::RELOAD;
        if (isReload) {
            request = minfwm::makeReloadRequest();
        } else {
            request = minfwm::makeCameraMoveRequest(parsed.command->x, parsed.command->y);
        }

        if (isReload) {
            std::cout << "minfwm: reloading daemon configuration..." << std::endl;
        } else {
            std::cout << "minfwm: moving camera (x=" << parsed.command->x
                      << ", y=" << parsed.command->y << ")..." << std::endl;
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
        std::cout << (isReload ? "minfwm: daemon configuration reloaded successfully\n"
                               : "minfwm: camera move completed successfully\n");
    }
    return 0;
}
