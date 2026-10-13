#pragma once

#include "WindowBackend.hpp"
#include "WindowPosition.hpp"
#include <cstdint>
#include <string>
#include <vector>
#include <unordered_set>

namespace minfwm {

class YabaiSA {
public:
    struct Handshake {
        std::string version;
        uint32_t attributes = 0;
    };

    explicit YabaiSA(std::string socketPath = {});

    bool handshake();
    bool compatible() const { return m_compatible; }
    bool supportsTransforms() const { return m_compatible && m_transformSupport; }
    bool transformWindow(uint32_t wid, int x, int y) const;
    bool resetTransform(uint32_t wid) const;

    bool moveWindow(uint32_t wid, int x, int y) const;
    bool setWindowLayer(uint32_t wid, int layer) const;

    static std::vector<uint8_t> encodeMovePacket(uint32_t wid, int x, int y);
    static std::vector<uint8_t> encodeLayerPacket(uint32_t wid, int layer);
    static std::vector<uint8_t> encodeHandshakePacket();
    static std::vector<uint8_t> encodeTransformPacket(uint32_t wid, uint32_t ownerPid, int x, int y);
    static std::vector<uint8_t> encodeResetTransformPacket(uint32_t wid, uint32_t ownerPid);

private:
    bool sendPacket(const std::vector<uint8_t>& packet, bool explicitAck = false) const;
    bool isOwnedSocket() const;

    std::string m_socketPath;
    bool m_compatible = false;
    bool m_transformSupport = false;
};

class YabaiSABackend final : public WindowBackend {
public:
    explicit YabaiSABackend(std::string socketPath = {}, WindowPositionCheck check = isWindowAtPosition);
    ~YabaiSABackend() override;

    bool initialize(bool enableTransforms = false);
    bool available() const { return m_sa.compatible(); }
    bool usesTransforms() const override { return m_transformsEnabled && m_sa.supportsTransforms(); }
    BackendResult resetTransform(uint32_t wid) override;

    BackendResult move(AXUIElementRef element, uint32_t wid, int x, int y) override;
    BackendResult resize(AXUIElementRef element, uint32_t wid, float width, float height) override;
    BackendResult setLayer(AXUIElementRef element, uint32_t wid, int layer) override;
    BackendResult setHidden(AXUIElementRef element, uint32_t wid, bool hidden) override;
    BackendResult restore(AXUIElementRef element, uint32_t wid, int x, int y,
                          float width, float height) override;

private:
    YabaiSA m_sa;
    WindowPositionCheck m_checkPosition;
    std::unordered_set<uint32_t> m_transformed;
    bool m_transformsEnabled = false;
};

} // namespace minfwm
