#import "YabaiSA.hpp"
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <pwd.h>
#include <iostream>
#include <vector>

extern "C" AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *wid);

namespace minfwm {

static bool sendToSA(const void* data, size_t size) {
    static std::string socketPath = "";
    if (socketPath.empty()) {
        NSString* userName = NSUserName();
        socketPath = "/tmp/yabai-sa_" + std::string([userName UTF8String]) + ".socket";
    }

    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd == -1) return false;

    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = 50000;
    setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof(tv));
    setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof(tv));

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socketPath.c_str(), sizeof(addr.sun_path) - 1);

    if (connect(sockfd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        close(sockfd);
        return false;
    }

    // Packet structure: [int16_t total_length_excluding_this_field] [uint8_t opcode] [data...]
    int16_t payload_len = (int16_t)size; 
    send(sockfd, &payload_len, sizeof(int16_t), MSG_NOSIGNAL);
    send(sockfd, data, size, MSG_NOSIGNAL);

    // Wait for 1-byte ACK
    char ack = 0;
    recv(sockfd, &ack, 1, 0);

    close(sockfd);
    return true;
}

bool YabaiSA::moveWindow(uint32_t wid, int x, int y) {
    if (wid == 0) return false;

    struct {
        uint8_t opcode;
        uint32_t wid;
        float x;
        float y;
    } __attribute__((packed)) pkg;

    pkg.opcode = 0x06; // SA_WINDOW_MOVE
    pkg.wid = wid;
    pkg.x = (float)x;
    pkg.y = (float)y;

    return sendToSA(&pkg, sizeof(pkg));
}

bool YabaiSA::setWindowLayer(uint32_t wid, int layer) {
    if (wid == 0) return false;

    struct {
        uint8_t opcode;
        uint32_t wid;
        int32_t layer;
    } __attribute__((packed)) pkg;

    pkg.opcode = 0x07; // SA_WINDOW_LAYER
    pkg.wid = wid;
    pkg.layer = (int32_t)layer;

    return sendToSA(&pkg, sizeof(pkg));
}

} // namespace minfwm
