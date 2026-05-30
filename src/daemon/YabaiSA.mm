#import "YabaiSA.hpp"
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <iostream>

extern "C" AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *wid);

namespace minfwm {

bool YabaiSA::moveWindow(uint32_t wid, int x, int y) {
    static bool error_logged = false;
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd == -1) return false;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, "/tmp/yabai_sa", sizeof(addr.sun_path) - 1);

    if (connect(sockfd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        if (!error_logged) {
            std::cerr << "YabaiSA: Failed to connect to /tmp/yabai_sa. Is 'sudo yabai --load-sa' running?" << std::endl;
            error_logged = true;
        }
        close(sockfd);
        return false;
    }

    error_logged = false; // Reset if connection succeeds
    uint8_t opcode = 0x06; // SA_WINDOW_MOVE
    uint32_t message_length = sizeof(uint32_t) + sizeof(float) + sizeof(float);
    float fx = (float)x;
    float fy = (float)y;

    write(sockfd, &opcode, sizeof(opcode));
    write(sockfd, &message_length, sizeof(message_length));
    write(sockfd, &wid, sizeof(wid));
    write(sockfd, &fx, sizeof(fx));
    write(sockfd, &fy, sizeof(fy));

    close(sockfd);
    return true;
}

bool YabaiSA::setWindowLayer(uint32_t wid, int layer) {
    return false;
}

} // namespace minfwm
