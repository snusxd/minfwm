#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <utility>

namespace minfwm {

template <typename T>
class CFRef {
public:
    CFRef() = default;
    explicit CFRef(T value) : m_value(value) {}
    CFRef(const CFRef&) = delete;
    CFRef& operator=(const CFRef&) = delete;

    CFRef(CFRef&& other) noexcept : m_value(std::exchange(other.m_value, nullptr)) {}
    CFRef& operator=(CFRef&& other) noexcept {
        if (this != &other) {
            reset();
            m_value = std::exchange(other.m_value, nullptr);
        }
        return *this;
    }

    ~CFRef() { reset(); }

    static CFRef adopt(T value) { return CFRef(value); }
    static CFRef retain(T value) {
        return CFRef(value ? static_cast<T>(CFRetain(value)) : nullptr);
    }

    T get() const { return m_value; }
    explicit operator bool() const { return m_value != nullptr; }
    T* put() {
        reset();
        return &m_value;
    }
    T release() { return std::exchange(m_value, nullptr); }
    void reset(T value = nullptr) {
        if (m_value) CFRelease(m_value);
        m_value = value;
    }

private:
    T m_value = nullptr;
};

} // namespace minfwm
