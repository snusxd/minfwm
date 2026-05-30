#include "IPCServer.hpp"
#include "Protocol.hpp"
#include "WindowManager.hpp"
#include "ConfigManager.hpp"
#include <iostream>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <vector>

namespace minfwm {

IPCServer::IPCServer()
    : m_socketPath("/tmp/minfwm.sock"), m_running(false), m_serverFd(-1) {}

IPCServer::~IPCServer() {
    stop();
}

void IPCServer::start() {
    if (m_running) return;
    m_running = true;
    m_serverThread = std::thread(&IPCServer::run, this);
}

void IPCServer::stop() {
    m_running = false;
    if (m_serverFd != -1) {
        close(m_serverFd);
        m_serverFd = -1;
    }
    if (m_serverThread.joinable()) {
        m_serverThread.join();
    }
    unlink(m_socketPath.c_str());
}

void IPCServer::run() {
    m_serverFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (m_serverFd == -1) {
        std::cerr << "IPCServer: Failed to create socket" << std::endl;
        return;
    }

    unlink(m_socketPath.c_str());

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, m_socketPath.c_str(), sizeof(addr.sun_path) - 1);

    if (bind(m_serverFd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        std::cerr << "IPCServer: Failed to bind socket" << std::endl;
        return;
    }

    if (listen(m_serverFd, 5) == -1) {
        std::cerr << "IPCServer: Failed to listen on socket" << std::endl;
        return;
    }

    std::cout << "IPCServer: Listening on " << m_socketPath << std::endl;

    while (m_running) {
        int clientFd = accept(m_serverFd, NULL, NULL);
        if (clientFd == -1) {
            if (m_running) std::cerr << "IPCServer: Failed to accept connection" << std::endl;
            continue;
        }
        handleClient(clientFd);
    }
}

void IPCServer::handleClient(int clientFd) {
    IPCMessage msg;
    ssize_t bytesRead = read(clientFd, &msg, sizeof(msg));
    if (bytesRead == sizeof(msg)) {
        // Оборачиваем логику в блок GCD для безопасного выполнения на Main Thread
        dispatch_async(dispatch_get_main_queue(), ^{
            auto& wm = WindowManager::instance();
            switch (msg.type) {
                case MessageType::RELOAD:
                    std::cout << "IPCServer: Received RELOAD" << std::endl;
                    ConfigManager::instance().load(); // Можно сразу добавить перезагрузку конфига!
                    break;
                case MessageType::CAMERA_MOVE:
                    std::cout << "IPCServer: Received CAMERA_MOVE: " << msg.data.camera_move.x << ", " << msg.data.camera_move.y << std::endl;
                    wm.mainDisplay().camera().move(msg.data.camera_move.x, msg.data.camera_move.y);
                    wm.updateWindows();
                    break;
                default:
                    std::cout << "IPCServer: Received unknown message type" << std::endl;
                    break;
            }
        });
    }
    close(clientFd); // Закрываем сокет вне асинхронного блока (это потокобезопасно)
}

} // namespace minfwm
