#pragma once

#include <string>

namespace minfwm {

class YabaiSA {
public:
    static bool moveWindow(uint32_t wid, int x, int y);
    static bool setWindowLayer(uint32_t wid, int layer);

private:
    static bool sendCommand(const std::string& cmd);
};

} // namespace minfwm
