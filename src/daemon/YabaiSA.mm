#import "YabaiSA.hpp"
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <pwd.h>
#include <iostream>

extern "C" AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *wid);

namespace minfwm {

bool YabaiSA::moveWindow(uint32_t wid, int x, int y) {
    if (wid == 0) return false;

    static bool error_logged = false;
    static std::string socketPath = "";

    if (socketPath.empty()) {
        struct passwd *pw = getpwuid(getuid());
        if (pw) {
            socketPath = "/tmp/yabai-sa_" + std::string(pw->pw_name) + ".socket";
        } else {
            socketPath = "/tmp/yabai_sa";
        }
    }

    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd == -1) return false;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socketPath.c_str(), sizeof(addr.sun_path) - 1);

    if (connect(sockfd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        if (!error_logged) {
            std::cerr << "YabaiSA: Failed to connect to " << socketPath << std::endl;
            error_logged = true;
        }
        close(sockfd);
        return false;
    }

    error_logged = false;
    uint8_t opcode = 0x06;
    uint32_t message_length = sizeof(uint32_t) + sizeof(float) + sizeof(float);
    float fx = (float)x;
    float fy = (float)y;

    // Use MSG_NOSIGNAL to avoid SIGPIPE
    send(sockfd, &opcode, sizeof(opcode), 0);
    send(sockfd, &message_length, sizeof(message_length), 0);
    send(sockfd, &wid, sizeof(wid), 0);
    send(sockfd, &fx, sizeof(fx), 0);
    send(sockfd, &fy, sizeof(fy), 0);
    send(sockfd, &message_length, sizeof(message_length), MSG_NOSIGNAL);
    send(sockfd, &wid, sizeof(wid), MSG_NOSIGNAL);
    send(sockfd, &fx, sizeof(fx), MSG_NOSIGNAL);
    send(sockfd, &fy, sizeof(fy), MSG_NOSIGNAL);

    close(sockfd);
    return true;
}

bool YabaiSA::setWindowLayer(uint32_t wid, int layer) {
    return false;
}

} // namespace minfwm
