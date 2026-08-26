#pragma once

#include "Protocol.hpp"

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>

namespace minfwm {

class IPCServer {
public:
    IPCServer();
    ~IPCServer();

    bool start();
    void stop();
    std::string lastError() const;

private:
    void run();
    void handleClient(int clientSocket);
    ErrorCode dispatchRequest(const Request& request);
    void setStartupResult(bool succeeded, std::string error);

    std::string m_socketPath;
    std::thread m_serverThread;
    std::atomic<bool> m_running;
    int m_wakeupReadFd;
    int m_wakeupWriteFd;
    mutable std::mutex m_stateMutex;
    std::condition_variable m_startCondition;
    bool m_startComplete;
    bool m_startSucceeded;
    std::string m_startError;
};

} // namespace minfwm
