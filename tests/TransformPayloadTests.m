// Exercise the actual payload parser/state machine with fake WindowServer calls.
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

static CGAffineTransform current;
static int current_level = 0, transform_calls = 0, failures = 0;
static bool fail_transform = false;
static bool fail_level = false;
static CGRect native_frame = {{100, 200}, {640, 480}};
static int SLSMainConnectionID(void) { return 1; }
static CGError SLSGetWindowOwner(int cid, uint32_t wid, int *owner) { *owner = 2; return kCGErrorSuccess; }
static CGError SLSGetWindowTransform(int cid, uint32_t wid, CGAffineTransform *transform) {
    *transform = current; return kCGErrorSuccess;
}
static CGError SLSGetWindowBounds(int cid, uint32_t wid, CGRect *frame) { *frame = native_frame; return kCGErrorSuccess; }
static CGError SLSSetWindowTransform(int cid, uint32_t wid, CGAffineTransform transform) {
    ++transform_calls;
    if (fail_transform) return kCGErrorFailure;
    current = transform; return kCGErrorSuccess;
}
static CGError SLSSetWindowSubLevel(int cid, uint32_t wid, int level) {
    if (fail_level) return kCGErrorFailure;
    current_level = level; return kCGErrorSuccess;
}
static CFArrayRef fakeWindowInfo(CGWindowListOption options, CGWindowID wid) {
    CFNumberRef level = CFNumberCreate(NULL, kCFNumberIntType, &current_level);
    const void *keys[] = {kCGWindowLayer}, *values[] = {level};
    CFDictionaryRef info = CFDictionaryCreate(NULL, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    const void *items[] = {info};
    CFArrayRef array = CFArrayCreate(NULL, items, 1, &kCFTypeArrayCallBacks);
    CFRelease(level); CFRelease(info);
    return array;
}
#define CGWindowListCopyWindowInfo fakeWindowInfo
#include "../integrations/yabai/minfwm_transform.m"
#undef CGWindowListCopyWindowInfo

static void expect(bool value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); ++failures; }
}
static int scaledRequest(uint8_t op, uint32_t owner, int x, int y, int length, uint32_t scale) {
    int pair[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, pair) != 0) return -1;
    char message[21] = {op}; uint32_t wid = 42;
    memcpy(message + 1, &wid, 4); memcpy(message + 5, &owner, 4);
    memcpy(message + 9, &x, 4); memcpy(message + 13, &y, 4);
    memcpy(message + 17, &scale, 4);
    bool handled = minfwm_handle_transform(pair[0], message, length);
    uint8_t ack = 2;
    if (handled && read(pair[1], &ack, 1) != 1) ack = 2;
    close(pair[0]); close(pair[1]);
    return handled ? ack : -1;
}
static int request(uint8_t op, uint32_t owner, int x, int y, int length) {
    return scaledRequest(op, owner, x, y, length, 1000);
}
int main(void) {
    @autoreleasepool {
        current = CGAffineTransformMakeTranslation(-100, -200);
        uint32_t owner = (uint32_t)getpid();
        expect(request(0x14, owner, 100, -120, 16) == 1 && transform_calls == 0, "truncated command does not mutate state");
        expect(request(0x14, owner + 1, 100, -120, 17) == 1, "owner must match socket peer PID");
        expect(request(0x14, owner, 100, -16001, 17) == 1, "unsupported native coordinates are rejected");
        expect(request(0x14, owner, 100, -120, 17) == 0 && current.ty == 120, "translation applies without toggling");
        current_level = 101;
        expect(request(0x14, owner, -300, -200, 17) == 0 && current.tx == 300 && current.ty == 200, "second target is absolute");
        expect(request(0x15, owner, 0, 0, 9) == 0 && current.tx == -100 && current.ty == -200 && current_level == 0,
               "reset restores the native baseline and captured level");
        int count = transform_calls;
        expect(request(0x15, owner, 0, 0, 9) == 0 && transform_calls == count, "reset is idempotent");
        expect(request(0x14, owner, 100, -120, 17) == 0, "watchdog fixture applies");
        minfwm_transforms[0].start_sec++; // Model PID reuse/death without touching a real window.
        minfwm_reap_transforms();
        expect(current.ty == -200 && !minfwm_transforms[0].wid, "watchdog restores stale owner identity");
        current = CGAffineTransformMakeScale(2, 2);
        expect(request(0x14, owner, 100, -120, 17) == 1, "preexisting scaled window is not taken over");
        current = CGAffineTransformMakeTranslation(-50, -75);
        count = transform_calls;
        expect(request(0x14, owner, 100, -120, 17) == 1 && transform_calls == count && !minfwm_transforms[0].wid,
               "preexisting foreign translation is not taken over or changed");
        current = CGAffineTransformMakeTranslation(-100, -200);
        fail_transform = true;
        expect(request(0x14, owner, 100, -120, 17) == 1, "WindowServer failure is explicitly acknowledged");
        expect(minfwm_transforms[0].wid == 42, "failed operations retain a recovery snapshot");
        fail_transform = false;
        expect(request(0x15, owner, 0, 0, 9) == 0, "failed operation can subsequently be cleaned up");
        expect(request(0x14, owner, 100, -120, 17) == 0, "native-drag fixture applies");
        native_frame.origin = CGPointMake(418, 364);
        expect(request(0x15, owner, 0, 0, 9) == 0 && current.tx == -418 && current.ty == -364,
               "reset normalizes the current native frame after a user drag, not the stale snapshot");
        expect(request(0x14, owner, 100, -120, 17) == 0, "partial recovery fixture applies");
        fail_level = true;
        expect(request(0x15, owner, 0, 0, 9) == 1, "failed layer restore retains cleanup state");
        int recovered_calls = transform_calls;
        native_frame.origin = CGPointMake(500, 500);
        current = CGAffineTransformMakeTranslation(-500, -500); // Native drag after transform cleanup.
        expect(request(0x15, owner, 0, 0, 9) == 1 && transform_calls == recovered_calls && current.tx == -500,
               "layer retries must never replay an already-restored transform during native dragging");
        fail_level = false;
        expect(request(0x15, owner, 0, 0, 9) == 0, "layer-only retry completes cleanup");
        count = transform_calls;
        expect(scaledRequest(0x16, owner, 400, -100, 20, 500) == 1 && transform_calls == count,
               "truncated overview is rejected without mutation");
        expect(scaledRequest(0x16, owner, 400, -100, 21, 199) == 1 &&
               scaledRequest(0x16, owner, 400, -100, 21, 1001) == 1 && transform_calls == count,
               "overview scale is bounded before a recovery entry is acquired");
        expect(scaledRequest(0x16, owner + 1, 400, -100, 21, 500) == 1, "overview checks peer ownership");
        expect(scaledRequest(0x16, owner, 400, -100, 21, 500) == 0 &&
               current.a == 2 && current.d == 2 && current.tx == -800 && current.ty == 200,
               "overview uses inverse WindowServer scale and translation");
        native_frame.origin = CGPointMake(700, 600);
        expect(request(0x15, owner, 0, 0, 9) == 0 && current.a == 1 && current.d == 1 && current.tx == -700 && current.ty == -600,
               "overview cleanup restores unit scale at the current native frame");
        expect(scaledRequest(0x16, owner, 400, -100, 21, 250) == 0, "scaled crash fixture applies");
        minfwm_transforms[0].start_sec++;
        // Reap interval is monotonic; force the earlier test's owner check through the entry helper.
        expect(minfwm_restore_entry(&minfwm_transforms[0]) && current.a == 1 && !minfwm_transforms[0].wid,
               "scaled owner recovery uses the same idempotent cleanup");

    }
    return failures ? 1 : 0;
}
