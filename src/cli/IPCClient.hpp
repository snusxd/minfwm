#pragma once
#include "Protocol.hpp"
#include <sys/types.h>

namespace minfwm {

class IPCClient {
public:
    struct Result {
        bool transportSucceeded = false;
        Response response{};
        std::string error;
        pid_t peerPid = 0;
    };

    Result sendMessage(const Request& request, pid_t expectedPeerPid = 0);
};

} // namespace minfwm
