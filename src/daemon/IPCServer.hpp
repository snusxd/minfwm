#pragma once

#include <string>
#include <thread>
#include <atomic>

namespace minfwm {

class IPCServer {
public:
    IPCServer();
    ~IPCServer();

    void start();
    void stop();

private:
    void run();
    void handleClient(int clientSocket);

    std::string m_socketPath;
    std::thread m_serverThread;
    std::atomic<bool> m_running;
    int m_serverFd;
};

} // namespace minfwm
