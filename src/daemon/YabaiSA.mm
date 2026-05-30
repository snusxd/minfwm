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

    static std::string socketPath = "";
    if (socketPath.empty()) {
        NSString* userName = NSUserName();
        socketPath = "/tmp/yabai-sa_" + std::string([userName UTF8String]) + ".socket";
    }

    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd == -1) return false;

    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = 50000; // 50ms timeout
    setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof(tv));

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socketPath.c_str(), sizeof(addr.sun_path) - 1);

    if (connect(sockfd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        close(sockfd);
        return false;
    }

    // Standard Yabai SA protocol: 1 byte opcode, 4 bytes length, then data
    uint8_t opcode = 0x06;
    uint32_t length = 12; // 4 (wid) + 4 (x) + 4 (y)
    float fx = (float)x;
    float fy = (float)y;

    send(sockfd, &opcode, sizeof(opcode), MSG_NOSIGNAL);
    send(sockfd, &length, sizeof(length), MSG_NOSIGNAL);
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
