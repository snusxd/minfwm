#pragma once

#include <string>
#include <string_view>
#include <optional>
#include <sys/types.h>

namespace minfwm {

bool controlDaemon(std::string_view action, std::string& error);
std::string daemonStatus();
std::optional<pid_t> daemonPid();
bool isForegroundDaemon(pid_t pid);
bool stopForegroundDaemon(pid_t pid, std::string& error);
bool startForegroundDaemon(pid_t& pid, std::string& error);

} // namespace minfwm
