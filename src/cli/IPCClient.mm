#include "IPCClient.hpp"
#include <iostream>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace minfwm {

void IPCClient::sendMessage(const IPCMessage& msg) {
    int clientFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (clientFd == -1) {
        std::cerr << "IPCClient: Failed to create socket" << std::endl;
        return;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, "/tmp/minfwm.sock", sizeof(addr.sun_path) - 1);

    if (connect(clientFd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        std::cerr << "IPCClient: Failed to connect to daemon. Is minfwmd running?" << std::endl;
        close(clientFd);
        return;
    }

    if (write(clientFd, &msg, sizeof(msg)) == -1) {
        std::cerr << "IPCClient: Failed to send message" << std::endl;
    }

    close(clientFd);
}

} // namespace minfwm
