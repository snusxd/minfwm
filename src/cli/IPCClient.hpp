#pragma once
#include "Protocol.hpp"

namespace minfwm {

class IPCClient {
public:
    void sendMessage(const IPCMessage& msg);
};

} // namespace minfwm
