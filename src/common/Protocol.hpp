#pragma once

#include <algorithm>
#include <array>
#include <bit>
#include <cerrno>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <optional>
#include <span>
#include <string>
#include <unistd.h>
#include <vector>

namespace minfwm {

inline constexpr std::array<std::uint8_t, 4> kProtocolMagic = {'M', 'F', 'W', 'M'};
inline constexpr std::uint8_t kProtocolVersion = 1;
inline constexpr std::uint32_t kMaxPayloadLength = 64;
inline constexpr std::uint32_t kMaxPayloadSize = kMaxPayloadLength;
inline constexpr std::size_t kRequestHeaderSize = 11;
inline constexpr std::size_t kResponseSize = 4;

enum class Command : std::uint16_t {
    RELOAD = 0,
    CAMERA_MOVE = 1
};

enum class ResponseStatus : std::uint16_t {
    OK = 0,
    ERROR = 1
};

enum class ErrorCode : std::uint16_t {
    NONE = 0,
    MALFORMED = 1,
    UNSUPPORTED = 2,
    INTERNAL = 3
};

struct Request {
    std::uint16_t command = 0;
    std::vector<std::uint8_t> payload;
};

struct Response {
    ResponseStatus status = ResponseStatus::ERROR;
    ErrorCode error = ErrorCode::INTERNAL;
};

inline std::string ipcSocketPath(const char* temporaryDirectory) {
    if (temporaryDirectory == nullptr || temporaryDirectory[0] == '\0') {
        return "/tmp/minfwm.sock";
    }

    std::string path(temporaryDirectory);
    while (path.size() > 1 && path.back() == '/') {
        path.pop_back();
    }
    path += "/minfwm.sock";
    return path;
}

inline std::string ipcSocketPath() {
    return ipcSocketPath(std::getenv("TMPDIR"));
}

inline bool readExact(int fileDescriptor, void* buffer, std::size_t length) {
    auto* bytes = static_cast<std::uint8_t*>(buffer);
    std::size_t offset = 0;
    while (offset < length) {
        const ssize_t result = ::read(fileDescriptor, bytes + offset, length - offset);
        if (result > 0) {
            offset += static_cast<std::size_t>(result);
            continue;
        }
        if (result == -1 && errno == EINTR) {
            continue;
        }
        return false;
    }
    return true;
}

inline bool writeAll(int fileDescriptor, const void* buffer, std::size_t length) {
    const auto* bytes = static_cast<const std::uint8_t*>(buffer);
    std::size_t offset = 0;
    while (offset < length) {
        const ssize_t result = ::write(fileDescriptor, bytes + offset, length - offset);
        if (result > 0) {
            offset += static_cast<std::size_t>(result);
            continue;
        }
        if (result == -1 && errno == EINTR) {
            continue;
        }
        return false;
    }
    return true;
}

inline void appendUInt16LE(std::vector<std::uint8_t>& output, std::uint16_t value) {
    output.push_back(static_cast<std::uint8_t>(value & 0xffU));
    output.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xffU));
}

inline void appendUInt32LE(std::vector<std::uint8_t>& output, std::uint32_t value) {
    output.push_back(static_cast<std::uint8_t>(value & 0xffU));
    output.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xffU));
    output.push_back(static_cast<std::uint8_t>((value >> 16U) & 0xffU));
    output.push_back(static_cast<std::uint8_t>((value >> 24U) & 0xffU));
}

inline std::uint16_t readUInt16LE(std::span<const std::uint8_t> bytes, std::size_t offset) {
    return static_cast<std::uint16_t>(bytes[offset]) |
           static_cast<std::uint16_t>(bytes[offset + 1]) << 8U;
}

inline std::uint32_t readUInt32LE(std::span<const std::uint8_t> bytes, std::size_t offset) {
    return static_cast<std::uint32_t>(bytes[offset]) |
           static_cast<std::uint32_t>(bytes[offset + 1]) << 8U |
           static_cast<std::uint32_t>(bytes[offset + 2]) << 16U |
           static_cast<std::uint32_t>(bytes[offset + 3]) << 24U;
}

inline void appendFloat32LE(std::vector<std::uint8_t>& output, float value) {
    appendUInt32LE(output, std::bit_cast<std::uint32_t>(value));
}

inline float readFloat32LE(std::span<const std::uint8_t> bytes, std::size_t offset) {
    return std::bit_cast<float>(readUInt32LE(bytes, offset));
}

inline Request makeReloadRequest() {
    return Request{static_cast<std::uint16_t>(Command::RELOAD), {}};
}

inline Request makeCameraMoveRequest(float x, float y) {
    Request request;
    request.command = static_cast<std::uint16_t>(Command::CAMERA_MOVE);
    request.payload.reserve(8);
    appendFloat32LE(request.payload, x);
    appendFloat32LE(request.payload, y);
    return request;
}

inline bool decodeCameraMove(const Request& request, float& x, float& y) {
    if (request.command != static_cast<std::uint16_t>(Command::CAMERA_MOVE) ||
        request.payload.size() != 8) {
        return false;
    }

    x = readFloat32LE(request.payload, 0);
    y = readFloat32LE(request.payload, 4);
    return std::isfinite(x) && std::isfinite(y);
}

inline std::optional<std::vector<std::uint8_t>> encodeRequestFrame(
    const Request& request, std::uint8_t version = kProtocolVersion) {
    if (request.payload.size() > kMaxPayloadLength) {
        return std::nullopt;
    }

    std::vector<std::uint8_t> frame;
    frame.reserve(kRequestHeaderSize + request.payload.size());
    frame.insert(frame.end(), kProtocolMagic.begin(), kProtocolMagic.end());
    frame.push_back(version);
    appendUInt16LE(frame, request.command);
    appendUInt32LE(frame, static_cast<std::uint32_t>(request.payload.size()));
    frame.insert(frame.end(), request.payload.begin(), request.payload.end());
    return frame;
}

inline ErrorCode decodeRequestFrame(std::span<const std::uint8_t> frame, Request& request) {
    if (frame.size() < kRequestHeaderSize ||
        !std::equal(kProtocolMagic.begin(), kProtocolMagic.end(), frame.begin())) {
        return ErrorCode::MALFORMED;
    }

    const std::uint32_t payloadLength = readUInt32LE(frame, 7);
    if (payloadLength > kMaxPayloadLength ||
        frame.size() != kRequestHeaderSize + payloadLength) {
        return ErrorCode::MALFORMED;
    }

    if (frame[4] != kProtocolVersion) {
        return ErrorCode::UNSUPPORTED;
    }

    request.command = readUInt16LE(frame, 5);
    request.payload.assign(frame.begin() + kRequestHeaderSize, frame.end());

    switch (static_cast<Command>(request.command)) {
        case Command::RELOAD:
            return request.payload.empty() ? ErrorCode::NONE : ErrorCode::MALFORMED;
        case Command::CAMERA_MOVE: {
            float x = 0.0F;
            float y = 0.0F;
            return decodeCameraMove(request, x, y) ? ErrorCode::NONE : ErrorCode::MALFORMED;
        }
        default:
            return ErrorCode::UNSUPPORTED;
    }
}

inline ErrorCode readRequestFrame(int fileDescriptor, Request& request) {
    std::array<std::uint8_t, kRequestHeaderSize> header = {};
    if (!readExact(fileDescriptor, header.data(), header.size())) {
        return ErrorCode::MALFORMED;
    }

    if (!std::equal(kProtocolMagic.begin(), kProtocolMagic.end(), header.begin())) {
        return ErrorCode::MALFORMED;
    }

    const std::span<const std::uint8_t> headerSpan(header);
    const std::uint32_t payloadLength = readUInt32LE(headerSpan, 7);
    if (payloadLength > kMaxPayloadLength) {
        return ErrorCode::MALFORMED;
    }

    std::vector<std::uint8_t> frame(header.begin(), header.end());
    frame.resize(kRequestHeaderSize + payloadLength);
    if (payloadLength > 0 &&
        !readExact(fileDescriptor, frame.data() + kRequestHeaderSize, payloadLength)) {
        return ErrorCode::MALFORMED;
    }
    return decodeRequestFrame(frame, request);
}

inline std::array<std::uint8_t, kResponseSize> encodeResponse(const Response& response) {
    return {
        static_cast<std::uint8_t>(static_cast<std::uint16_t>(response.status) & 0xffU),
        static_cast<std::uint8_t>(static_cast<std::uint16_t>(response.status) >> 8U),
        static_cast<std::uint8_t>(static_cast<std::uint16_t>(response.error) & 0xffU),
        static_cast<std::uint8_t>(static_cast<std::uint16_t>(response.error) >> 8U)
    };
}

inline bool isValidResponse(const Response& response) {
    if (response.status == ResponseStatus::OK) {
        return response.error == ErrorCode::NONE;
    }
    return response.status == ResponseStatus::ERROR && response.error != ErrorCode::NONE &&
           response.error <= ErrorCode::INTERNAL;
}

inline bool decodeResponse(std::span<const std::uint8_t> bytes, Response& response) {
    if (bytes.size() != kResponseSize) {
        return false;
    }

    response.status = static_cast<ResponseStatus>(readUInt16LE(bytes, 0));
    response.error = static_cast<ErrorCode>(readUInt16LE(bytes, 2));
    return isValidResponse(response);
}

inline Response makeSuccessResponse() {
    return Response{ResponseStatus::OK, ErrorCode::NONE};
}

inline Response makeErrorResponse(ErrorCode error) {
    if (error == ErrorCode::NONE) {
        error = ErrorCode::INTERNAL;
    }
    return Response{ResponseStatus::ERROR, error};
}

inline bool writeResponse(int fileDescriptor, const Response& response) {
    const auto bytes = encodeResponse(response);
    return writeAll(fileDescriptor, bytes.data(), bytes.size());
}

inline bool readResponse(int fileDescriptor, Response& response) {
    std::array<std::uint8_t, kResponseSize> bytes = {};
    return readExact(fileDescriptor, bytes.data(), bytes.size()) &&
           decodeResponse(bytes, response);
}

} // namespace minfwm
