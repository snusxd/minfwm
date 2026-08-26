#include "CommandLine.hpp"
#include "Protocol.hpp"

#include <array>
#include <cassert>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <thread>
#include <unistd.h>
#include <vector>

namespace {

using minfwm::Command;
using minfwm::ErrorCode;
using minfwm::ParsedCommandLine;
using minfwm::Request;
using minfwm::Response;
using minfwm::ResponseStatus;

void assertBytes(const std::vector<std::uint8_t>& actual,
                 std::initializer_list<std::uint8_t> expected) {
    assert(actual == std::vector<std::uint8_t>(expected));
}

Request requestFromFrame(const std::vector<std::uint8_t>& frame,
                         ErrorCode expectedResult = ErrorCode::NONE) {
    Request request;
    const ErrorCode result = minfwm::decodeRequestFrame(frame, request);
    assert(result == expectedResult);
    return request;
}

void testRequestEncodingAndDecoding() {
    const Request reload = minfwm::makeReloadRequest();
    const auto reloadFrame = minfwm::encodeRequestFrame(reload);
    assert(reloadFrame.has_value());
    assertBytes(*reloadFrame, {'M', 'F', 'W', 'M', 1, 0, 0, 0, 0, 0, 0});
    assert(requestFromFrame(*reloadFrame).command ==
           static_cast<std::uint16_t>(Command::RELOAD));
    assert(requestFromFrame(*reloadFrame).payload.empty());

    const Request camera = minfwm::makeCameraMoveRequest(1.5F, -2.25F);
    const auto cameraFrame = minfwm::encodeRequestFrame(camera);
    assert(cameraFrame.has_value());
    assert(cameraFrame->size() == minfwm::kRequestHeaderSize + 8);
    assert((*cameraFrame)[5] == 1);
    assert((*cameraFrame)[6] == 0);
    assert((*cameraFrame)[7] == 8);
    assert((*cameraFrame)[8] == 0);
    const Request decodedCamera = requestFromFrame(*cameraFrame);
    assert(decodedCamera.command == static_cast<std::uint16_t>(Command::CAMERA_MOVE));
    assert(decodedCamera.payload == camera.payload);

    float x = 0.0F;
    float y = 0.0F;
    assert(minfwm::decodeCameraMove(decodedCamera, x, y));
    assert(x == 1.5F);
    assert(y == -2.25F);
}

void testMalformedAndUnsupportedFrames() {
    const Request reload = minfwm::makeReloadRequest();
    const auto encodedReload = minfwm::encodeRequestFrame(reload);
    assert(encodedReload.has_value());

    std::vector<std::uint8_t> wrongMagic = *encodedReload;
    wrongMagic[0] = 'X';
    requestFromFrame(wrongMagic, ErrorCode::MALFORMED);

    std::vector<std::uint8_t> unsupportedVersion = *encodedReload;
    unsupportedVersion[4] = 2;
    requestFromFrame(unsupportedVersion, ErrorCode::UNSUPPORTED);

    std::vector<std::uint8_t> truncated = *encodedReload;
    truncated.pop_back();
    requestFromFrame(truncated, ErrorCode::MALFORMED);

    std::vector<std::uint8_t> oversized = *encodedReload;
    oversized[9] = 65;
    oversized.resize(minfwm::kRequestHeaderSize + 65, 0);
    requestFromFrame(oversized, ErrorCode::MALFORMED);

    Request invalidReload;
    invalidReload.command = static_cast<std::uint16_t>(Command::RELOAD);
    invalidReload.payload = {1};
    const auto invalidReloadFrame = minfwm::encodeRequestFrame(invalidReload);
    assert(invalidReloadFrame.has_value());
    requestFromFrame(*invalidReloadFrame, ErrorCode::MALFORMED);

    Request invalidCamera;
    invalidCamera.command = static_cast<std::uint16_t>(Command::CAMERA_MOVE);
    invalidCamera.payload = {0, 1, 2, 3};
    const auto invalidCameraFrame = minfwm::encodeRequestFrame(invalidCamera);
    assert(invalidCameraFrame.has_value());
    requestFromFrame(*invalidCameraFrame, ErrorCode::MALFORMED);

    Request nonFiniteCamera = minfwm::makeCameraMoveRequest(NAN, 0.0F);
    const auto nonFiniteFrame = minfwm::encodeRequestFrame(nonFiniteCamera);
    assert(nonFiniteFrame.has_value());
    requestFromFrame(*nonFiniteFrame, ErrorCode::MALFORMED);

    Request unknown;
    unknown.command = 99;
    const auto unknownFrame = minfwm::encodeRequestFrame(unknown);
    assert(unknownFrame.has_value());
    requestFromFrame(*unknownFrame, ErrorCode::UNSUPPORTED);
}

void testResponseEncodingAndDecoding() {
    const Response success{ResponseStatus::OK, ErrorCode::NONE};
    const auto successBytes = minfwm::encodeResponse(success);
    assertBytes(std::vector<std::uint8_t>(successBytes.begin(), successBytes.end()),
                {0, 0, 0, 0});

    Response decoded;
    assert(minfwm::decodeResponse(successBytes, decoded));
    assert(decoded.status == ResponseStatus::OK);
    assert(decoded.error == ErrorCode::NONE);

    const Response unsupported{ResponseStatus::ERROR, ErrorCode::UNSUPPORTED};
    const auto unsupportedBytes = minfwm::encodeResponse(unsupported);
    assertBytes(std::vector<std::uint8_t>(unsupportedBytes.begin(), unsupportedBytes.end()),
                {1, 0, 2, 0});
    assert(minfwm::decodeResponse(unsupportedBytes, decoded));
    assert(decoded.status == ResponseStatus::ERROR);
    assert(decoded.error == ErrorCode::UNSUPPORTED);

    const std::array<std::uint8_t, minfwm::kResponseSize> invalid = {0, 0, 1, 0};
    assert(!minfwm::decodeResponse(invalid, decoded));
}

void testExactIo() {
    int descriptors[2] = {-1, -1};
    assert(pipe(descriptors) == 0);

    const std::array<std::uint8_t, 5> expected = {1, 2, 3, 4, 5};
    std::thread writer([&]() {
        for (const std::uint8_t byte : expected) {
            assert(::write(descriptors[1], &byte, sizeof(byte)) == 1);
        }
        close(descriptors[1]);
    });

    std::array<std::uint8_t, 5> actual = {};
    assert(minfwm::readExact(descriptors[0], actual.data(), actual.size()));
    assert(actual == expected);
    close(descriptors[0]);
    writer.join();

    assert(pipe(descriptors) == 0);
    assert(minfwm::writeAll(descriptors[1], expected.data(), expected.size()));
    std::array<std::uint8_t, 5> written = {};
    assert(minfwm::readExact(descriptors[0], written.data(), written.size()));
    assert(written == expected);
    close(descriptors[0]);
    close(descriptors[1]);
}

void testCommandLineParsing() {
    {
        const char* argv[] = {"minfwmc", "reload"};
        const auto result = minfwm::parseCommandLine(2, argv);
        assert(result.command.has_value());
        assert(result.command->command == ParsedCommandLine::Command::RELOAD);
    }

    {
        const char* argv[] = {"minfwmc", "camera", "move", "--y", "-2.25", "--x", "1.5"};
        const auto result = minfwm::parseCommandLine(7, argv);
        assert(result.command.has_value());
        assert(result.command->command == ParsedCommandLine::Command::CAMERA_MOVE);
        assert(result.command->x == 1.5F);
        assert(result.command->y == -2.25F);
    }

    {
        const char* argv[] = {"minfwmc", "camera", "move", "--x=1", "--y=-2"};
        const auto result = minfwm::parseCommandLine(5, argv);
        assert(result.command.has_value());
        assert(result.command->x == 1.0F);
        assert(result.command->y == -2.0F);
    }

    const std::array<std::vector<const char*>, 7> invalidArguments = {
        std::vector<const char*> {"minfwmc"},
        std::vector<const char*> {"minfwmc", "reload", "extra"},
        std::vector<const char*> {"minfwmc", "camera", "move", "--x", "nan", "--y", "0"},
        std::vector<const char*> {"minfwmc", "camera", "move", "--x", "1", "--x", "2", "--y", "3"},
        std::vector<const char*> {"minfwmc", "camera", "move", "--x", "1", "--z", "2", "--y", "3"},
        std::vector<const char*> {"minfwmc", "camera", "move", "--x", "1", "--y"},
        std::vector<const char*> {"minfwmc", "camera", "move", "--x", "1.2oops", "--y", "3"}
    };
    for (const auto& arguments : invalidArguments) {
        const auto result = minfwm::parseCommandLine(
            static_cast<int>(arguments.size()), arguments.data());
        assert(!result.command.has_value());
        assert(!result.error.empty());
    }
}

} // namespace

int main() {
    testRequestEncodingAndDecoding();
    testMalformedAndUnsupportedFrames();
    testResponseEncodingAndDecoding();
    testExactIo();
    testCommandLineParsing();
    return 0;
}
