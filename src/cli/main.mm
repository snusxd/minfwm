#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include "CommandLine.hpp"
#include "DaemonControl.hpp"
#include "IPCClient.hpp"
#include "Protocol.hpp"

#include <mach-o/dyld.h>
#include <csignal>
#include <array>
#include <chrono>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string_view>
#include <thread>
#include <sys/stat.h>

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

#ifndef MINFWM_BUILD_DIR
#define MINFWM_BUILD_DIR "."
#endif

namespace {

volatile std::sig_atomic_t g_detachFromLogs = 0;

void requestLogDetach(int) {
    g_detachFromLogs = 1;
}

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
    std::cerr << "Usage: minfwm [daemon|start|stop|restart|dev-update|reload|enable|disable|status|list displays|version [--dev]] | camera move --x <value> --y <value>\n";
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

bool buildDevUpdate(std::string& error) {
    const std::filesystem::path buildDir(MINFWM_BUILD_DIR);
    if (!std::filesystem::exists(buildDir / "CMakeCache.txt")) {
        error = "CMake build directory is missing; configure it before dev-update: " + buildDir.string();
        return false;
    }
    std::array<char, MAXPATHLEN> executableBuffer{};
    uint32_t executableSize = static_cast<uint32_t>(executableBuffer.size());
    if (_NSGetExecutablePath(executableBuffer.data(), &executableSize) != 0) {
        error = "could not determine the current executable path";
        return false;
    }
    std::error_code pathError;
    const bool matchesBuild = std::filesystem::equivalent(
        executableBuffer.data(), buildDir / "minfwm", pathError);
    if (pathError || !matchesBuild) {
        error = "dev-update must run the executable from " + (buildDir / "minfwm").string();
        return false;
    }
    std::cout << "minfwm: building minfwm in " << buildDir << "..." << std::endl;
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
    task.arguments = @[@"cmake", @"--build", [NSString stringWithUTF8String:buildDir.c_str()],
                       @"--target", @"minfwm", @"--parallel"];
    NSError* launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        const char* description = launchError.localizedDescription.UTF8String;
        error = description == nullptr ? "could not start cmake" : description;
        return false;
    }
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        error = "build failed (exit " + std::to_string(task.terminationStatus) + ")";
        return false;
    }
    std::cout << "minfwm: build completed successfully" << std::endl;
    return true;
}

std::filesystem::path daemonLogPath() {
    return std::filesystem::path(NSHomeDirectory().UTF8String) / "Library/Logs/minfwm.log";
}

void attachToDaemonLogs() {
    const auto path = daemonLogPath();
    std::ifstream log(path);
    if (log) {
        std::deque<std::string> recentLines;
        std::string line;
        while (std::getline(log, line)) {
            recentLines.push_back(line);
            if (recentLines.size() > 20) recentLines.pop_front();
        }
        for (const auto& recentLine : recentLines) std::cout << recentLine << '\n';
    }

    std::error_code sizeError;
    std::uintmax_t offset = std::filesystem::file_size(path, sizeError);
    if (sizeError) offset = 0;
    struct stat logStat {};
    ino_t inode = ::stat(path.c_str(), &logStat) == 0 ? logStat.st_ino : 0;
    std::string pendingLine;

    g_detachFromLogs = 0;
    const auto previousHandler = std::signal(SIGINT, requestLogDetach);
    std::cout << "minfwm: attached to daemon logs; press Ctrl-C to detach (daemon keeps running)"
              << std::endl;
    while (g_detachFromLogs == 0) {
        std::error_code currentSizeError;
        const auto currentSize = std::filesystem::file_size(path, currentSizeError);
        struct stat currentStat {};
        const ino_t currentInode = ::stat(path.c_str(), &currentStat) == 0 ? currentStat.st_ino : 0;
        if (!currentSizeError && (currentInode != inode || currentSize < offset)) {
            offset = 0;
            inode = currentInode;
            pendingLine.clear();
        }
        if (!currentSizeError && currentSize > offset) {
            std::ifstream updates(path);
            updates.seekg(static_cast<std::streamoff>(offset));
            const std::string chunk((std::istreambuf_iterator<char>(updates)),
                                    std::istreambuf_iterator<char>());
            offset += chunk.size();
            pendingLine += chunk;
            std::size_t lineEnd = 0;
            while ((lineEnd = pendingLine.find('\n')) != std::string::npos) {
                std::cout << pendingLine.substr(0, lineEnd) << '\n';
                pendingLine.erase(0, lineEnd + 1);
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(150));
    }
    std::signal(SIGINT, previousHandler);
    std::cout << "minfwm: detached from daemon logs; daemon is still running" << std::endl;
}

std::uintmax_t daemonLogSize() {
    std::error_code fileError;
    const auto size = std::filesystem::file_size(daemonLogPath(), fileError);
    return fileError ? 0 : size;
}

std::string startupIssueSince(std::uintmax_t initialLogSize) {
    const auto size = daemonLogSize();
    std::ifstream log(daemonLogPath());
    if (!log) return {};
    log.seekg(static_cast<std::streamoff>(size < initialLogSize ? 0 : initialLogSize));
    std::string line;
    std::string failure;
    while (std::getline(log, line)) {
        if (line.find("minfwm daemon: Accessibility permission is not active") != std::string::npos ||
            line.find("minfwm daemon: waiting for Accessibility permission") != std::string::npos ||
            line.find("minfwm daemon: required Yabai Scripting Addition is unavailable") != std::string::npos ||
            line.find("minfwm daemon: failed to start IPC server") != std::string::npos ||
            line.find("minfwm daemon: failed to bound Accessibility messaging timeout") != std::string::npos) {
            failure = line;
        } else if (line.find("minfwm daemon: Accessibility permission is active") != std::string::npos) {
            failure.clear();
        }
    }
    return failure;
}

bool waitForDaemonReady(std::uintmax_t initialLogSize, std::optional<pid_t> foregroundPid,
                        std::string& error) {
    minfwm::IPCClient client;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    do {
        const auto expectedPid = foregroundPid.has_value() ? foregroundPid : minfwm::daemonPid();
        if (expectedPid.has_value()) {
            const auto result = client.sendMessage(minfwm::makePingRequest(), *expectedPid);
            if (result.transportSucceeded && result.response.status == minfwm::ResponseStatus::OK) {
                return true;
            }
            error = result.transportSucceeded ? "daemon is not ready yet" : result.error;
        } else {
            error = "LaunchAgent is not running";
        }
        const auto issue = startupIssueSince(initialLogSize);
        if (!issue.empty()) {
            if (issue.find("Accessibility permission") != std::string::npos) {
                error = std::string(foregroundPid.has_value() ? "foreground daemon" : "LaunchAgent") +
                        " needs Accessibility permission for " +
                        (std::filesystem::path(MINFWM_BUILD_DIR) / "minfwm").string() +
                        ". Add this executable in System Settings > Privacy & Security > "
                        "Accessibility, enable it, then rerun minfwm dev-update";
            } else {
                error = issue;
                error += " (log: ~/Library/Logs/minfwm.log)";
                return false;
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    } while (std::chrono::steady_clock::now() < deadline);
    if (error.find("needs Accessibility permission") == std::string::npos) {
        error = "daemon did not become ready within 10 seconds: " + error;
    }
    error += " (log: ~/Library/Logs/minfwm.log)";
    return false;
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
        if (command == minfwm::ParsedCommandLine::Command::LIST_DISPLAYS) {
            for (NSScreen* screen in NSScreen.screens) {
                NSDictionary* description = screen.deviceDescription;
                NSNumber* displayID = description[@"NSScreenNumber"];
                if (!displayID) continue;
                NSString* name = screen.localizedName;
                const char* utf8Name = name.UTF8String;
                std::cout << displayID.longLongValue << "\t"
                          << (utf8Name ? utf8Name : "") << '\n';
            }
            return 0;
        }
        if (command == minfwm::ParsedCommandLine::Command::VERSION) {
            std::cout << "minfwm "
                      << (parsed.command->devVersion ? latestLocalCommit() : MINFWM_BUILD_VERSION)
                      << '\n';
            return 0;
        }
        if (command == minfwm::ParsedCommandLine::Command::DEV_UPDATE) {
            std::string error;
            if (!buildDevUpdate(error)) {
                std::cerr << "minfwm: dev-update stopped: " << error << '\n';
                return 1;
            }

            bool layoutSaved = false;
            std::optional<pid_t> foregroundPid;
            const auto launchAgentPid = minfwm::daemonPid();
            minfwm::IPCClient client;
            std::cout << "minfwm: checking current daemon layout..." << std::endl;
            const auto result = client.sendMessage(minfwm::makeSaveLayoutRequest());
            if (result.transportSucceeded) {
                if (result.response.status != minfwm::ResponseStatus::OK) {
                    std::cerr << "minfwm: dev-update stopped: daemon could not save layout ("
                              << errorCodeName(result.response.error) << ")\n";
                    return 1;
                }
                layoutSaved = true;
                std::cout << "minfwm: daemon layout saved successfully" << std::endl;
                if (!launchAgentPid.has_value() || result.peerPid != *launchAgentPid) {
                    if (!minfwm::isForegroundDaemon(result.peerPid)) {
                        std::cerr << "minfwm: dev-update stopped: socket owner PID " << result.peerPid
                                  << " is not this build's daemon\n";
                        return 1;
                    }
                    foregroundPid = result.peerPid;
                    std::cout << "minfwm: foreground daemon PID " << *foregroundPid
                              << " owns the socket" << std::endl;
                }
            } else if (result.error == "daemon socket is missing or has unsafe ownership" ||
                       result.error == "failed to connect to daemon") {
                std::cout << "minfwm: no reachable daemon; no live layout to save" << std::endl;
            } else {
                std::cerr << "minfwm: dev-update stopped: could not save daemon layout: "
                          << result.error << '\n';
                return 1;
            }

            const auto initialLogSize = daemonLogSize();
            if (foregroundPid.has_value()) {
                std::cout << "minfwm: stopping LaunchAgent to avoid socket contention..." << std::endl;
                if (!minfwm::controlDaemon("stop", error)) {
                    std::cerr << "minfwm: dev-update stopped: " << error << '\n';
                    return 1;
                }
                std::cout << "minfwm: stopping foreground daemon PID " << *foregroundPid << "..." << std::endl;
                if (!minfwm::stopForegroundDaemon(*foregroundPid, error)) {
                    std::cerr << "minfwm: dev-update stopped: " << error << '\n';
                    return 1;
                }
                pid_t newPid = 0;
                std::cout << "minfwm: starting rebuilt foreground daemon..." << std::endl;
                if (!minfwm::startForegroundDaemon(newPid, error)) {
                    std::cerr << "minfwm: dev-update stopped: " << error << '\n';
                    return 1;
                }
                std::cout << "minfwm: foreground daemon started as PID " << newPid
                          << "; waiting for IPC readiness..." << std::endl;
                if (!waitForDaemonReady(initialLogSize, newPid, error)) {
                    std::cerr << "minfwm: dev-update stopped: " << error << '\n';
                    return 1;
                }
                std::cout << "minfwm: dev-update completed successfully: build succeeded, "
                          << "layout saved, foreground daemon PID " << newPid
                          << " confirmed ready via IPC" << std::endl;
                if (parsed.command->attachLogs) attachToDaemonLogs();
                return 0;
            }

            std::cout << "minfwm: restarting LaunchAgent daemon..." << std::endl;
            if (!minfwm::controlDaemon("restart", error)) {
                std::cerr << "minfwm: dev-update stopped: daemon restart failed: " << error << '\n';
                return 1;
            }
            std::cout << "minfwm: LaunchAgent restart completed; waiting for daemon readiness..." << std::endl;
            if (!waitForDaemonReady(initialLogSize, std::nullopt, error)) {
                std::cerr << "minfwm: dev-update stopped: " << error << '\n';
                return 1;
            }
            std::cout << "minfwm: dev-update completed successfully: build succeeded, "
                      << (layoutSaved ? "layout saved, " : "no running layout to save, ")
                      << "daemon restarted and confirmed ready via IPC" << std::endl;
            if (parsed.command->attachLogs) attachToDaemonLogs();
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
