#import <Foundation/Foundation.h>

#include "DaemonControl.hpp"
#include "IPCClient.hpp"

#include <mach-o/dyld.h>
#include <libproc.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <charconv>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <thread>
#include <vector>

#ifndef MINFWM_BUILD_DIR
#define MINFWM_BUILD_DIR "."
#endif

namespace minfwm {
namespace {

constexpr const char* kLabel = "com.minfwm.daemon";

struct LaunchctlResult {
    int status = -1;
    std::string output;
};

LaunchctlResult runLaunchctl(const std::vector<std::string>& arguments) {
    @autoreleasepool {
        NSTask* task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
        NSMutableArray<NSString*>* taskArguments = [NSMutableArray arrayWithCapacity:arguments.size()];
        for (const auto& argument : arguments) {
            NSString* value = [NSString stringWithUTF8String:argument.c_str()];
            if (value == nil) return {};
            [taskArguments addObject:value];
        }
        task.arguments = taskArguments;

        NSPipe* pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = pipe;
        NSError* launchError = nil;
        if (![task launchAndReturnError:&launchError]) {
            const char* description = launchError.localizedDescription.UTF8String;
            return {-1, description == nullptr ? "could not launch launchctl" : description};
        }
        NSData* data = [[pipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        NSString* output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        const char* text = output.UTF8String;
        return {task.terminationStatus, text == nullptr ? std::string{} : std::string(text)};
    }
}

std::string serviceTarget() {
    return "gui/" + std::to_string(static_cast<unsigned long>(getuid())) + "/" + kLabel;
}

bool executablePaths(std::filesystem::path& executablePath,
                     std::filesystem::path& plistPath,
                     std::string& error) {
    std::array<char, MAXPATHLEN> executableBuffer{};
    uint32_t size = static_cast<uint32_t>(executableBuffer.size());
    if (_NSGetExecutablePath(executableBuffer.data(), &size) != 0) {
        error = "could not determine the minfwm executable path";
        return false;
    }
    // Keep the invocation path's symlinks. Homebrew's stable bin links point
    // into versioned Cellar directories; resolving them here would bake the
    // current version into the LaunchAgent and make macOS treat each upgrade
    // as a different Accessibility client.
    std::error_code pathError;
    executablePath = std::filesystem::absolute(executableBuffer.data(), pathError);
    if (pathError) {
        error = "could not make the minfwm executable path absolute";
        return false;
    }
    executablePath = executablePath.lexically_normal();
    if (access(executablePath.c_str(), X_OK) != 0) {
        error = "minfwm is not executable (expected " + executablePath.string() + ")";
        return false;
    }

    const char* home = std::getenv("HOME");
    if (home == nullptr || home[0] == '\0') {
        error = "HOME is not set; cannot install the LaunchAgent";
        return false;
    }
    plistPath = std::filesystem::path(home) / "Library/LaunchAgents" / (std::string(kLabel) + ".plist");
    return true;
}

bool installLaunchAgent(const std::filesystem::path& executablePath,
                        const std::filesystem::path& plistPath,
                        std::string& error) {
    @autoreleasepool {
        NSDictionary* plist = @{
            @"Label": [NSString stringWithUTF8String:kLabel],
            @"ProgramArguments": @[[NSString stringWithUTF8String:executablePath.c_str()], @"daemon"],
            @"RunAtLoad": @YES,
            // Restart after unexpected failures, but don't loop on setup
            // failures such as missing Accessibility permission or SA support.
            @"KeepAlive": @{ @"SuccessfulExit": @NO },
            @"StandardOutPath": [NSString stringWithFormat:@"%@/Library/Logs/minfwm.log",
                                                            NSHomeDirectory()],
            @"StandardErrorPath": [NSString stringWithFormat:@"%@/Library/Logs/minfwm.log",
                                                             NSHomeDirectory()]
        };
        NSError* directoryError = nil;
        NSString* directory = [NSString stringWithUTF8String:plistPath.parent_path().c_str()];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&directoryError]) {
            const char* message = directoryError.localizedDescription.UTF8String;
            error = message == nullptr ? "could not create ~/Library/LaunchAgents" : message;
            return false;
        }
        NSString* logDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs"];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:logDirectory
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&directoryError]) {
            const char* message = directoryError.localizedDescription.UTF8String;
            error = message == nullptr ? "could not create ~/Library/Logs" : message;
            return false;
        }
        NSData* data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:&directoryError];
        if (data == nil || ![data writeToFile:[NSString stringWithUTF8String:plistPath.c_str()]
                                      options:NSDataWritingAtomic
                                        error:&directoryError]) {
            const char* message = directoryError.localizedDescription.UTF8String;
            error = message == nullptr ? "could not write the LaunchAgent plist" : message;
            return false;
        }
        return true;
    }
}

bool isLoaded(const std::string& target) {
    return runLaunchctl({"print", target}).status == 0;
}

bool kickstart(const std::string& target, std::string& error) {
    const auto result = runLaunchctl({"kickstart", target});
    if (result.status == 0) return true;
    error = result.output.empty() ? "launchctl kickstart failed" : result.output;
    return false;
}

bool isDisabled(const std::string& domain) {
    const auto result = runLaunchctl({"print-disabled", domain});
    const std::string marker = std::string("\"") + kLabel + "\" => disabled";
    return result.status == 0 && result.output.find(marker) != std::string::npos;
}

bool bootstrap(const std::string& target, const std::filesystem::path& plistPath,
               std::string& error) {
    const auto result = runLaunchctl({"bootstrap", target.substr(0, target.rfind('/')),
                                      plistPath.string()});
    if (result.status == 0) return true;
    error = result.output.empty() ? "launchctl bootstrap failed" : result.output;
    return false;
}

bool bootout(const std::string& target, std::string& error) {
    const auto result = runLaunchctl({"bootout", target});
    if (result.status == 0) return true;
    error = result.output.empty() ? "launchctl bootout failed" : result.output;
    return false;
}

} // namespace

bool controlDaemon(std::string_view action, std::string& error) {
    std::filesystem::path executablePath;
    std::filesystem::path plistPath;
    const bool needsAgent = action == "start" || action == "restart" || action == "enable";
    if (needsAgent && !executablePaths(executablePath, plistPath, error)) return false;
    if (needsAgent && !installLaunchAgent(executablePath, plistPath, error)) return false;

    const std::string target = serviceTarget();
    if (action == "stop") {
        if (!isLoaded(target)) return true;
        return bootout(target, error);
    }
    if (action == "disable") {
        const auto disabled = runLaunchctl({"disable", target});
        if (disabled.status != 0) {
            error = disabled.output.empty() ? "launchctl disable failed" : disabled.output;
            return false;
        }
        if (isLoaded(target)) return bootout(target, error);
        return true;
    }
    if (action == "enable") {
        const auto enabled = runLaunchctl({"enable", target});
        if (enabled.status != 0) {
            error = enabled.output.empty() ? "launchctl enable failed" : enabled.output;
            return false;
        }
        if (isLoaded(target)) return kickstart(target, error);
        return bootstrap(target, plistPath, error);
    }
    if (action == "start") {
        if (isLoaded(target)) return kickstart(target, error);
        const std::string domain = target.substr(0, target.rfind('/'));
        const bool wasDisabled = isDisabled(domain);
        if (wasDisabled && runLaunchctl({"enable", target}).status != 0) {
            error = "launchctl could not temporarily enable the service";
            return false;
        }
        const bool started = bootstrap(target, plistPath, error);
        if (wasDisabled) {
            const auto restored = runLaunchctl({"disable", target});
            if (restored.status != 0) {
                if (started) error = "daemon started, but its disabled-at-login setting could not be restored";
                else error += "; could not restore disabled-at-login setting";
                return false;
            }
        }
        return started;
    }
    if (action == "restart") {
        if (isLoaded(target) && !bootout(target, error)) return false;
        const std::string domain = target.substr(0, target.rfind('/'));
        const bool wasDisabled = isDisabled(domain);
        if (wasDisabled && runLaunchctl({"enable", target}).status != 0) {
            error = "launchctl could not temporarily enable the service";
            return false;
        }
        const bool started = bootstrap(target, plistPath, error);
        if (wasDisabled) {
            const auto restored = runLaunchctl({"disable", target});
            if (restored.status != 0) {
                if (started) error = "daemon restarted, but its disabled-at-login setting could not be restored";
                else error += "; could not restore disabled-at-login setting";
                return false;
            }
        }
        return started;
    }

    error = "unsupported daemon action";
    return false;
}

std::optional<pid_t> parseLaunchAgentPid(const std::string& output) {
    constexpr std::string_view marker = "\n\tpid = ";
    const auto position = output.find(marker);
    if (position == std::string::npos) return std::nullopt;
    const char* begin = output.data() + position + marker.size();
    pid_t pid = 0;
    const auto parsed = std::from_chars(begin, output.data() + output.size(), pid);
    return parsed.ec == std::errc{} && pid > 0 ? std::optional<pid_t>(pid) : std::nullopt;
}

std::optional<pid_t> daemonPid() {
    const auto result = runLaunchctl({"print", serviceTarget()});
    if (result.status != 0 || result.output.find("state = running") == std::string::npos) {
        return std::nullopt;
    }
    return parseLaunchAgentPid(result.output);
}

std::string daemonStatus() {
    const auto launchAgent = runLaunchctl({"print", serviceTarget()});
    IPCClient client;
    if (launchAgent.status == 0 &&
        launchAgent.output.find("state = running") != std::string::npos) {
        const auto pid = parseLaunchAgentPid(launchAgent.output);
        if (pid.has_value()) {
            const auto ping = client.sendMessage(makePingRequest(), *pid);
            if (ping.transportSucceeded && ping.response.status == ResponseStatus::OK) {
                return "running (LaunchAgent PID " + std::to_string(*pid) + ")";
            }
        }
        return "loaded, not ready";
    }
    const auto ping = client.sendMessage(makePingRequest());
    if (ping.transportSucceeded && ping.response.status == ResponseStatus::OK &&
        isForegroundDaemon(ping.peerPid)) {
        return "running (foreground PID " + std::to_string(ping.peerPid) + ")";
    }
    return launchAgent.status == 0 ? "loaded, not running" : "stopped";
}

bool isForegroundDaemon(pid_t pid) {
    if (pid <= 0 || pid == getpid()) return false;
    std::array<char, PROC_PIDPATHINFO_MAXSIZE> processPath{};
    if (::proc_pidpath(pid, processPath.data(), static_cast<uint32_t>(processPath.size())) <= 0) {
        return false;
    }
    std::error_code pathError;
    return std::filesystem::equivalent(processPath.data(),
                                       std::filesystem::path(MINFWM_BUILD_DIR) / "minfwm",
                                       pathError) && !pathError;
}

bool stopForegroundDaemon(pid_t pid, std::string& error) {
    if (!isForegroundDaemon(pid)) {
        error = "socket owner is not the current minfwm build; refusing to stop PID " +
                std::to_string(pid);
        return false;
    }
    if (::kill(pid, SIGTERM) != 0 && errno != ESRCH) {
        error = "could not stop foreground daemon PID " + std::to_string(pid);
        return false;
    }
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    do {
        if (::kill(pid, 0) != 0 && errno == ESRCH) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    } while (std::chrono::steady_clock::now() < deadline);
    error = "foreground daemon PID " + std::to_string(pid) + " did not exit within 10 seconds";
    return false;
}

bool startForegroundDaemon(pid_t& pid, std::string& error) {
    @autoreleasepool {
        const auto executable = std::filesystem::path(MINFWM_BUILD_DIR) / "minfwm";
        NSString* logDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs"];
        NSError* fileError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:logDirectory
                                       withIntermediateDirectories:YES
                                                        attributes:nil error:&fileError]) {
            error = "could not create daemon log directory";
            return false;
        }
        NSString* logPath = [logDirectory stringByAppendingPathComponent:@"minfwm.log"];
        const int logFd = ::open(logPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (logFd < 0) {
            error = "could not open daemon log file";
            return false;
        }
        NSFileHandle* logHandle = [[NSFileHandle alloc] initWithFileDescriptor:logFd closeOnDealloc:YES];
        NSTask* task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:executable.c_str()]];
        task.arguments = @[@"daemon"];
        task.standardInput = [NSFileHandle fileHandleWithNullDevice];
        task.standardOutput = logHandle;
        task.standardError = logHandle;
        NSError* launchError = nil;
        if (![task launchAndReturnError:&launchError]) {
            const char* description = launchError.localizedDescription.UTF8String;
            error = description == nullptr ? "could not launch foreground daemon" : description;
            [logHandle closeFile];
            return false;
        }
        pid = task.processIdentifier;
        [logHandle closeFile];
        return true;
    }
}

} // namespace minfwm
