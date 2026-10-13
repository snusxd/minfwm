// Included by the pinned Yabai payload. All state belongs to its socket thread.
#include <libproc.h>
#include <signal.h>
#include <time.h>
#include <sys/proc_info.h>
#include <math.h>
extern CGError SLSDisableUpdate(int cid);
extern CGError SLSReenableUpdate(int cid);

struct minfwm_transform_entry {
    uint32_t wid;
    pid_t owner;
    uint64_t start_sec, start_usec;
    bool transform_restored;
    int original_level;
};
static struct minfwm_transform_entry minfwm_transforms[4096];

static bool minfwm_process_identity(pid_t pid, uint64_t *sec, uint64_t *usec)
{
    struct proc_bsdinfo info = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) return false;
    *sec = info.pbi_start_tvsec;
    *usec = info.pbi_start_tvusec;
    return true;
}

static int minfwm_window_level(uint32_t wid)
{
    int level = 0;
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, wid);
    if (list && CFArrayGetCount(list) == 1) {
        CFDictionaryRef info = CFArrayGetValueAtIndex(list, 0);
        CFNumberRef number = CFDictionaryGetValue(info, kCGWindowLayer);
        if (number && CFGetTypeID(number) == CFNumberGetTypeID()) CFNumberGetValue(number, kCFNumberIntType, &level);
    }
    if (list) CFRelease(list);
    return level;
}

static bool minfwm_restore_entry(struct minfwm_transform_entry *entry)
{
    int cid = SLSMainConnectionID(), window_owner = 0;
    if (SLSGetWindowOwner(cid, entry->wid, &window_owner) != kCGErrorSuccess) {
        entry->wid = 0; // Destroyed windows need no restoration.
        return true;
    }
    if (!entry->transform_restored) {
        // A native drag/resize can change the frame while its presentation is
        // transformed. Replaying the first translation leaves a persistent
        // offset that survives daemon/Dock exit and breaks native dragging.
        CGRect native_frame;
        if (SLSGetWindowBounds(cid, entry->wid, &native_frame) != kCGErrorSuccess ||
            !isfinite(native_frame.origin.x) || !isfinite(native_frame.origin.y)) return false;
        if (SLSSetWindowTransform(cid, entry->wid,
                CGAffineTransformMakeTranslation(-native_frame.origin.x, -native_frame.origin.y)) != kCGErrorSuccess) return false;
        entry->transform_restored = true;
    }
    // Layer cleanup must not reapply a transform on every watchdog retry.
    bool restored = true;
    restored = (SLSSetWindowSubLevel(cid, entry->wid, entry->original_level) == kCGErrorSuccess) && restored;
    if (restored) entry->wid = 0;
    return restored;
}

static void minfwm_reap_transforms(void)
{
    static double last_check = 0;
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return;
    double time = now.tv_sec + now.tv_nsec / 1e9;
    if (time - last_check < 0.25) return;
    last_check = time;
    for (size_t i = 0; i < 4096; ++i) {
        struct minfwm_transform_entry *entry = &minfwm_transforms[i];
        if (!entry->wid) continue;
        uint64_t sec = 0, usec = 0;
        if (!minfwm_process_identity(entry->owner, &sec, &usec) ||
            sec != entry->start_sec || usec != entry->start_usec) {
            (void)minfwm_restore_entry(entry); // Retry on the next watchdog pass if it fails.
        }
    }
}

static bool minfwm_handle_transform(int sockfd, const char *message, int length)
{
    if (length < 1 || ((uint8_t)message[0] != 0x14 && (uint8_t)message[0] != 0x15 &&
        (uint8_t)message[0] != 0x16 && (uint8_t)message[0] != 0x17)) return false;
    uint8_t ack = 1;
    bool overview = (uint8_t)message[0] == 0x16;
    bool native = (uint8_t)message[0] == 0x17;
    bool apply = (uint8_t)message[0] != 0x15;
    if (length != (overview ? 21 : apply ? 17 : 9)) goto respond;
    uint32_t wid, owner;
    memcpy(&wid, message + 1, 4);
    memcpy(&owner, message + 5, 4);
    pid_t peer = 0;
    socklen_t peer_size = sizeof(peer);
    if (!wid || owner > INT_MAX ||
        getsockopt(sockfd, SOL_LOCAL, LOCAL_PEERPID, &peer, &peer_size) != 0 || (uint32_t)peer != owner) goto respond;
    struct minfwm_transform_entry *entry = NULL, *free_entry = NULL;
    for (size_t i = 0; i < 4096; ++i) {
        if (minfwm_transforms[i].wid == wid) entry = &minfwm_transforms[i];
        if (!minfwm_transforms[i].wid && !free_entry) free_entry = &minfwm_transforms[i];
    }
    if (entry && entry->owner != peer) goto respond;
    if (!apply) {
        ack = !entry || minfwm_restore_entry(entry) ? 0 : 1;
        goto respond;
    }
    int32_t x, y;
    memcpy(&x, message + 9, 4);
    memcpy(&y, message + 13, 4);
    // WindowServer's documented native coordinate range.
    if (x < -16000 || x > 16000 || y < -16000 || y > 16000) goto respond;
    if (native) {
        // Only a window already owned by this peer can be handed back.
        if (!entry) goto respond;
        int cid = SLSMainConnectionID();
        if (SLSDisableUpdate(cid) != kCGErrorSuccess) goto respond;
        entry->transform_restored = false;
        CGPoint point = CGPointMake(x, y);
        bool moved = SLSMoveWindowWithGroup(cid, wid, &point) == kCGErrorSuccess;
        CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt32Type, &wid);
        CFArrayRef windows = number ? CFArrayCreate(NULL, (const void **)&number, 1, &kCFTypeArrayCallBacks) : NULL;
        bool associated = moved && windows && SLSReassociateWindowsSpacesByGeometry(cid, windows) == kCGErrorSuccess;
        if (windows) CFRelease(windows);
        if (number) CFRelease(number);
        CGRect frame;
        bool normalized = moved && SLSGetWindowBounds(cid, wid, &frame) == kCGErrorSuccess &&
            isfinite(frame.origin.x) && isfinite(frame.origin.y) &&
            SLSSetWindowTransform(cid, wid, CGAffineTransformMakeTranslation(-frame.origin.x, -frame.origin.y)) == kCGErrorSuccess;
        if (normalized) entry->transform_restored = true;
        // No failure path may leave WindowServer presentation suspended.
        bool enabled = SLSReenableUpdate(cid) == kCGErrorSuccess;
        if (!enabled) (void)SLSReenableUpdate(cid);
        // Keep the captured level until final reset/process-death cleanup.
        ack = moved && associated && normalized && enabled ? 0 : 1;
        goto respond;
    }
    uint32_t scale = 1000;
    if (overview) memcpy(&scale, message + 17, 4);
    if (scale < 200 || scale > 1000) goto respond;
    if (!entry) {
        if (!free_entry) goto respond;
        CGAffineTransform original;
        CGRect native_frame;
        uint64_t sec, usec;
        if (!minfwm_process_identity(peer, &sec, &usec) ||
            SLSGetWindowTransform(SLSMainConnectionID(), wid, &original) != kCGErrorSuccess ||
            SLSGetWindowBounds(SLSMainConnectionID(), wid, &native_frame) != kCGErrorSuccess ||
            !CGAffineTransformEqualToTransform(original,
                CGAffineTransformMakeTranslation(-native_frame.origin.x, -native_frame.origin.y))) goto respond;
        entry = free_entry;
        *entry = (struct minfwm_transform_entry){wid, peer, sec, usec, false, minfwm_window_level(wid)};
    }
    entry->transform_restored = false;
    // WindowServer expects the inverse presentation transform: native local
    // coordinates = (screen coordinates - presentation origin) / scale.
    CGFloat inverse = 1000.0 / scale;
    CGAffineTransform transform = CGAffineTransformMake(inverse, 0, 0, inverse, -x * inverse, -y * inverse);
    ack = SLSSetWindowTransform(SLSMainConnectionID(), wid, transform) == kCGErrorSuccess ? 0 : 1;
respond:
    (void)send(sockfd, &ack, 1, MSG_NOSIGNAL);
    return true;
}
