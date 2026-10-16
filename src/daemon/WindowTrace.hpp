#pragma once

#include "../core/Geometry.hpp"
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <sstream>
#include <thread>
#include <string_view>
#include <unistd.h>

namespace minfwm {

inline bool windowTraceEnabled() {
    const auto* value = std::getenv("MINFWM_TRACE_WINDOW_INPUT");
    return value && *value && std::string_view(value) != "0";
}
inline thread_local uint64_t windowTraceGesture = 0;
inline uint64_t beginWindowTraceGesture() {
    static std::atomic<uint64_t> next{0};
    return windowTraceGesture = windowTraceEnabled() ? ++next : 0;
}
class WindowTraceScope final {
public:
    explicit WindowTraceScope(uint64_t gesture) : m_previous(windowTraceGesture) { windowTraceGesture = gesture; }
    ~WindowTraceScope() { windowTraceGesture = m_previous; }
    WindowTraceScope(const WindowTraceScope&) = delete;
    WindowTraceScope& operator=(const WindowTraceScope&) = delete;
private:
    uint64_t m_previous;
};
inline void traceRect(std::ostream& out, const char* name, core::Rect rect) {
    out << ' ' << name << '=' << rect.x << ',' << rect.y << ',' << rect.w << ',' << rect.h;
}
inline void emitWindowTrace(const char* stage, uint32_t wid, const std::string& fields) {
    static std::mutex mutex;
    static uint64_t sequence = 0;
    const auto monotonic = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    std::lock_guard lock(mutex);
    std::ostringstream line;
    line << std::fixed << std::setprecision(3)
         << "WINDOW_TRACE seq=" << ++sequence << " mono_ms=" << monotonic
         << " pid=" << getpid() << " thread=" << std::this_thread::get_id()
         << " gesture=" << windowTraceGesture << " wid=" << wid << " stage=" << stage << fields << '\n';
    std::cerr << line.str();
}
// Build one complete line only while enabled. No AX/WindowServer calls belong
// here: callers log already-observed data, except the explicitly sampled probe.
template<class Write>
void traceWindow(const char* stage, uint32_t wid, Write&& write) {
    if (!windowTraceEnabled()) return;
    std::ostringstream line;
    line << std::fixed << std::setprecision(3);
    write(line);
    emitWindowTrace(stage, wid, line.str());
}

} // namespace minfwm
