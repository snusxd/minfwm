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
    bool supportsPinnedLevels() const { return m_compatible && m_pinnedLevelSupport; }
    bool supportsTransforms() const { return m_compatible && m_transformSupport; }
    bool supportsOverview() const { return supportsTransforms() && m_overviewSupport; }
    bool supportsNativeHandoff() const { return supportsOverview() && m_nativeHandoffSupport; }
    bool nativeHandoff(uint32_t wid, int x, int y) const;
    static std::vector<uint8_t> encodeNativeHandoffPacket(uint32_t wid, uint32_t owner, int x, int y);
    bool overviewWindow(uint32_t wid, int x, int y, uint32_t scalePermille) const;
    bool transformWindow(uint32_t wid, int x, int y) const;
    bool resetTransform(uint32_t wid) const;
    bool normalizeNativeWindow(uint32_t wid, CGRect nativeFrame) const;
    static std::vector<uint8_t> encodeNativeNormalizationPacket(uint32_t wid, CGRect nativeFrame);

    bool moveWindow(uint32_t wid, int x, int y) const;
    bool setWindowLayer(uint32_t wid, int layer) const;
    bool setWindowPinned(uint32_t wid, bool pinned) const;

    static std::vector<uint8_t> encodeMovePacket(uint32_t wid, int x, int y);
    static std::vector<uint8_t> encodeLayerPacket(uint32_t wid, int layer);
    static std::vector<uint8_t> encodePinnedPacket(uint32_t wid, uint32_t ownerPid, bool pinned);
    static std::vector<uint8_t> encodeHandshakePacket();
    static std::vector<uint8_t> encodeTransformPacket(uint32_t wid, uint32_t ownerPid, int x, int y);
    static std::vector<uint8_t> encodeResetTransformPacket(uint32_t wid, uint32_t ownerPid);
    static std::vector<uint8_t> encodeOverviewPacket(uint32_t wid, uint32_t ownerPid, int x, int y, uint32_t scalePermille);

private:
    bool sendPacket(const std::vector<uint8_t>& packet, bool explicitAck = false) const;
    bool isOwnedSocket() const;

    std::string m_socketPath;
    bool m_compatible = false;
    bool m_transformSupport = false;
    bool m_overviewSupport = false;
    bool m_nativeHandoffSupport = false;
    bool m_pinnedLevelSupport = false;
};

class YabaiSABackend final : public WindowBackend {
public:
    // Atomic handoff remains opt-in for isolated live fixtures: desktop
    // validation exposed a regression despite successful single-window checks.
    explicit YabaiSABackend(std::string socketPath = {}, WindowPositionCheck check = isWindowAtPosition,
                            bool experimentalNativeHandoff = false);
    ~YabaiSABackend() override;

    bool initialize(bool allowAdministratorLoad = false);
    bool available() const { return m_sa.compatible(); }
    bool supportsPinnedLevels() const { return m_sa.supportsPinnedLevels(); }
    bool usesTransforms() const override { return m_sa.supportsTransforms(); }
    bool supportsOverview() const override { return m_sa.supportsOverview(); }
    bool nativeMovePreservesLayer() const override { return m_experimentalNativeHandoff && m_sa.supportsNativeHandoff(); }
    BackendResult presentOverview(AXUIElementRef element, uint32_t wid, int x, int y, float scale) override;
    BackendResult resetTransform(uint32_t wid) override;
    BackendResult recoverNativePresentation(uint32_t wid, CGRect nativeFrame);

    BackendResult move(AXUIElementRef element, uint32_t wid, int x, int y) override;
    BackendResult moveNative(AXUIElementRef element, uint32_t wid, int x, int y) override;
    bool hasTransform(uint32_t wid) const override { return m_transformed.contains(wid); }
    BackendResult resize(AXUIElementRef element, uint32_t wid, float width, float height) override;
    BackendResult setLayer(AXUIElementRef element, uint32_t wid, int layer) override;
    BackendResult setPinnedLayer(AXUIElementRef element, uint32_t wid, bool alwaysOnTop) override;
    BackendResult setHidden(AXUIElementRef element, uint32_t wid, bool hidden) override;
    BackendResult restore(AXUIElementRef element, uint32_t wid, int x, int y,
                          float width, float height) override;

private:
    YabaiSA m_sa;
    WindowPositionCheck m_checkPosition;
    bool m_experimentalNativeHandoff = false;
    std::unordered_set<uint32_t> m_transformed;
    std::unordered_set<uint32_t> m_transformOwners;
};

} // namespace minfwm
