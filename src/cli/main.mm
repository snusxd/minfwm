#import <Foundation/Foundation.h>
#include <iostream>
#include "IPCClient.hpp"
#include "Protocol.hpp"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            std::cout << "Usage: minfwmc <command> [args]" << std::endl;
            return 0;
        }

        std::string command = argv[1];
        minfwm::IPCClient client;

        if (command == "reload") {
            minfwm::IPCMessage msg;
            msg.type = minfwm::MessageType::RELOAD;
            client.sendMessage(msg);
        } else if (command == "camera") {
            if (argc < 5) {
                std::cout << "Usage: minfwmc camera move --x <x> --y <y>" << std::endl;
                return 1;
            }
            // Simple parsing for now
            float x = std::stof(argv[3]);
            float y = std::stof(argv[4]);
            
            minfwm::IPCMessage msg;
            msg.type = minfwm::MessageType::CAMERA_MOVE;
            msg.data.camera_move.x = x;
            msg.data.camera_move.y = y;
            client.sendMessage(msg);
        } else {
            std::cout << "Unknown command: " << command << std::endl;
        }
    }
    return 0;
}
