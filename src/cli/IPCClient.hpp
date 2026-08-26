#pragma once
#include "Protocol.hpp"

namespace minfwm {

class IPCClient {
public:
    struct Result {
        bool transportSucceeded = false;
        Response response{};
        std::string error;
    };

    Result sendMessage(const Request& request);
};

} // namespace minfwm
