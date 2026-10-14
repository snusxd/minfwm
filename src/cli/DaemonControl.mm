#import <Foundation/Foundation.h>

#include "DaemonControl.hpp"

#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

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

bool executablePaths(std::filesystem::path& daemonPath,
                     std::filesystem::path& plistPath,
                     std::string& error) {
    std::array<char, MAXPATHLEN> executableBuffer{};
    uint32_t size = static_cast<uint32_t>(executableBuffer.size());
    if (_NSGetExecutablePath(executableBuffer.data(), &size) != 0) {
        error = "could not determine the minfwm executable path";
        return false;
    }
    char resolvedPath[PATH_MAX];
    if (realpath(executableBuffer.data(), resolvedPath) == nullptr) {
        error = "could not resolve the minfwm executable path";
        return false;
    }
    daemonPath = std::filesystem::path(resolvedPath).parent_path() / "minfwmd";
    if (access(daemonPath.c_str(), X_OK) != 0) {
        error = "minfwmd must be installed next to minfwm (expected " + daemonPath.string() + ")";
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

bool installLaunchAgent(const std::filesystem::path& daemonPath,
                        const std::filesystem::path& plistPath,
                        std::string& error) {
    @autoreleasepool {
        NSDictionary* plist = @{
            @"Label": [NSString stringWithUTF8String:kLabel],
            @"ProgramArguments": @[[NSString stringWithUTF8String:daemonPath.c_str()]],
            @"RunAtLoad": @YES,
            @"KeepAlive": @YES,
            @"StandardOutPath": [NSString stringWithFormat:@"%@/Library/Logs/minfwmd.log",
                                                            NSHomeDirectory()],
            @"StandardErrorPath": [NSString stringWithFormat:@"%@/Library/Logs/minfwmd.log",
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
    std::filesystem::path daemonPath;
    std::filesystem::path plistPath;
    const bool needsAgent = action == "start" || action == "restart" || action == "enable";
    if (needsAgent && !executablePaths(daemonPath, plistPath, error)) return false;
    if (needsAgent && !installLaunchAgent(daemonPath, plistPath, error)) return false;

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

} // namespace minfwm
