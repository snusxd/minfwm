#pragma once

#include <string>
#include <string_view>

namespace minfwm {

bool controlDaemon(std::string_view action, std::string& error);

} // namespace minfwm
