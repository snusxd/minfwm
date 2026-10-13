#include "DisplayFrameClock.hpp"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <vector>

@interface MinfwmFrameTarget : NSObject {
@public
    std::function<void(int64_t)> callback;
    int64_t displayId;
}
- (void)tick:(CADisplayLink*)link;
@end

@implementation MinfwmFrameTarget
- (void)tick:(CADisplayLink*)link {
    @autoreleasepool {
        if (callback) callback(displayId);
    }
}
@end

namespace minfwm {

struct DisplayFrameClock::Impl {
    struct Entry { CADisplayLink* link; MinfwmFrameTarget* target; };
    std::vector<Entry> entries;
    id screenObserver = nil;
    std::function<void(int64_t)> callback;
};

DisplayFrameClock::DisplayFrameClock() : m_impl(std::make_unique<Impl>()) {}
DisplayFrameClock::~DisplayFrameClock() { stop(); }

bool DisplayFrameClock::start(std::function<void(int64_t)> callback) {
    stop();
    m_impl->callback = std::move(callback);
    for (NSScreen* screen in NSScreen.screens) {
        NSNumber* number = screen.deviceDescription[@"NSScreenNumber"];
        if (!number) continue;
        auto* target = [[MinfwmFrameTarget alloc] init];
        target->displayId = number.longLongValue;
        target->callback = m_impl->callback;
        CADisplayLink* link = [[screen displayLinkWithTarget:target selector:@selector(tick:)] retain];
        if (!link) { [target release]; continue; }
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        m_impl->entries.push_back({link, target});
    }
    // A new display link must follow mode/refresh-rate changes on the same
    // display. The callback does not mutate WindowManager's display ownership.
    m_impl->screenObserver = [[NSNotificationCenter.defaultCenter
        addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*) {
            const auto callbackCopy = m_impl->callback;
            (void)start(callbackCopy);
        }] retain];
    return !m_impl->entries.empty();
}

void DisplayFrameClock::stop() {
    if (m_impl->screenObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:m_impl->screenObserver];
        [m_impl->screenObserver release];
        m_impl->screenObserver = nil;
    }
    for (const auto& entry : m_impl->entries) {
        [entry.link invalidate];
        [entry.link release];
        [entry.target release];
    }
    m_impl->entries.clear();
    m_impl->callback = {};
}

}
