#import "TrackpadInput.hpp"

#import <CoreGraphics/CoreGraphics.h>
#import <CoreFoundation/CoreFoundation.h>

#include <dlfcn.h>
#include <iostream>
#include <utility>

namespace minfwm {

namespace {

using MTDeviceRef = void*;

struct MTPoint {
    float x;
    float y;
};

struct MTVector {
    MTPoint position;
    MTPoint velocity;
};

struct MTTouch {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    int32_t state;
    int32_t fingerId;
    int32_t handId;
    MTVector normalized;
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;
    int32_t field14;
    int32_t field15;
    float zDensity;
};

using ContactCallback = void (*)(MTDeviceRef, MTTouch*, size_t, double, size_t, void*);
using CreateDeviceList = CFArrayRef (*)();
using RegisterCallback = void (*)(MTDeviceRef, ContactCallback, void*);
using UnregisterCallback = void (*)(MTDeviceRef, ContactCallback);
using StartDevice = int32_t (*)(MTDeviceRef, int32_t);
using StopDevice = int32_t (*)(MTDeviceRef);
using GetSensorDimensions = int32_t (*)(MTDeviceRef, int*, int*);

constexpr int32_t kTouchMake = 3;
constexpr int32_t kTouching = 4;

} // namespace

struct TrackpadInput::Impl {
    void* library = nullptr;
    CFArrayRef devices = nullptr;
    MTDeviceRef device = nullptr;
    RegisterCallback registerCallback = nullptr;
    UnregisterCallback unregisterCallback = nullptr;
    StopDevice stopDevice = nullptr;
    Handler handler;
    bool registered = false;
    bool active = false;
    MTPoint previousCentroid{};

    static void onContacts(MTDeviceRef, MTTouch* touches, size_t count, double, size_t, void* context) {
        auto* self = static_cast<Impl*>(context);
        if (!self || !self->handler) return;

        MTPoint centroid{};
        size_t activeCount = 0;
        for (size_t index = 0; index < count; ++index) {
            const MTTouch& touch = touches[index];
            if (touch.state != kTouchMake && touch.state != kTouching) continue;
            centroid.x += touch.normalized.position.x;
            centroid.y += touch.normalized.position.y;
            ++activeCount;
        }

        if (activeCount != 3) {
            if (self->active) {
                self->active = false;
                self->handler(false, {});
            }
            return;
        }

        centroid.x /= static_cast<float>(activeCount);
        centroid.y /= static_cast<float>(activeCount);
        if (!self->active) {
            self->active = true;
            self->previousCentroid = centroid;
            self->handler(true, {});
            return;
        }

        const MTPoint previous = self->previousCentroid;
        self->previousCentroid = centroid;
        const CGRect displayBounds = CGDisplayBounds(CGMainDisplayID());
        const core::Point delta{
            (centroid.x - previous.x) * static_cast<float>(displayBounds.size.width),
            (previous.y - centroid.y) * static_cast<float>(displayBounds.size.height),
        };
        if (delta.x != 0.0f || delta.y != 0.0f) self->handler(true, delta);
    }
};

TrackpadInput::TrackpadInput() : m_impl(std::make_unique<Impl>()) {}

TrackpadInput::~TrackpadInput() {
    stop();
}

bool TrackpadInput::start(Handler handler) {
    if (!m_impl || m_impl->device) return m_impl && m_impl->device;
    m_impl->handler = std::move(handler);
    m_impl->library = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
    if (!m_impl->library) {
        std::cerr << "TrackpadInput: MultitouchSupport unavailable; three-finger pan disabled" << std::endl;
        return false;
    }

    const auto createDeviceList = reinterpret_cast<CreateDeviceList>(dlsym(m_impl->library, "MTDeviceCreateList"));
    m_impl->registerCallback = reinterpret_cast<RegisterCallback>(
        dlsym(m_impl->library, "MTRegisterContactFrameCallbackWithRefcon"));
    m_impl->unregisterCallback = reinterpret_cast<UnregisterCallback>(
        dlsym(m_impl->library, "MTUnregisterContactFrameCallback"));
    const auto startDevice = reinterpret_cast<StartDevice>(dlsym(m_impl->library, "MTDeviceStart"));
    m_impl->stopDevice = reinterpret_cast<StopDevice>(dlsym(m_impl->library, "MTDeviceStop"));
    const auto getSensorDimensions = reinterpret_cast<GetSensorDimensions>(
        dlsym(m_impl->library, "MTDeviceGetSensorSurfaceDimensions"));
    if (!createDeviceList || !m_impl->registerCallback || !m_impl->unregisterCallback ||
        !startDevice || !m_impl->stopDevice) {
        std::cerr << "TrackpadInput: required MultitouchSupport symbols unavailable" << std::endl;
        stop();
        return false;
    }

    m_impl->devices = createDeviceList();
    if (!m_impl->devices) {
        std::cerr << "TrackpadInput: no multitouch devices found" << std::endl;
        stop();
        return false;
    }

    const CFIndex deviceCount = CFArrayGetCount(m_impl->devices);
    for (CFIndex index = 0; index < deviceCount; ++index) {
        auto candidate = const_cast<void*>(CFArrayGetValueAtIndex(m_impl->devices, index));
        if (!candidate) continue;
        if (getSensorDimensions) {
            int width = 0;
            int height = 0;
            if (getSensorDimensions(candidate, &width, &height) != 0 || width < 10 || height < 10) continue;
        }
        m_impl->device = candidate;
        break;
    }

    if (!m_impl->device) {
        std::cerr << "TrackpadInput: no trackpad device found" << std::endl;
        stop();
        return false;
    }

    m_impl->registerCallback(m_impl->device, Impl::onContacts, m_impl.get());
    m_impl->registered = true;
    if (startDevice(m_impl->device, 0) != 0) {
        std::cerr << "TrackpadInput: failed to start multitouch device" << std::endl;
        stop();
        return false;
    }
    std::cout << "TrackpadInput: listening for three-finger pan" << std::endl;
    return true;
}

void TrackpadInput::stop() {
    if (!m_impl) return;
    if (m_impl->device && m_impl->stopDevice) (void)m_impl->stopDevice(m_impl->device);
    if (m_impl->device && m_impl->registered && m_impl->unregisterCallback) {
        m_impl->unregisterCallback(m_impl->device, Impl::onContacts);
        m_impl->registered = false;
    }
    m_impl->device = nullptr;
    if (m_impl->devices) {
        CFRelease(m_impl->devices);
        m_impl->devices = nullptr;
    }
    if (m_impl->library) {
        dlclose(m_impl->library);
        m_impl->library = nullptr;
    }
    m_impl->handler = {};
    m_impl->active = false;
}

} // namespace minfwm
