// Compile the native provider here so its private callback ownership is tested
// without exposing a production API or requesting desktop permissions.
#include "../src/daemon/OverviewPreview.mm"
#import <objc/runtime.h>
#include <thread>

@interface MinfwmFakeCaptureWindow : NSObject
@property(readonly) CGWindowID windowID;
@property(readonly) id owningApplication;
@property(readonly) pid_t processID;
@property(readonly) CGRect frame;
@end
@implementation MinfwmFakeCaptureWindow
- (CGWindowID)windowID { return 42; }
- (id)owningApplication { return self; }
- (pid_t)processID { return 123; }
- (CGRect)frame { return CGRectMake(0, 0, 100, 100); }
@end

@interface MinfwmFakeCaptureContent : NSObject
@property(readonly) NSArray* windows;
@end
@implementation MinfwmFakeCaptureContent
- (NSArray*)windows { return @[[MinfwmFakeCaptureWindow new]]; }
@end

static void (^pendingScreenshot)(CGImageRef, NSError*);
@interface MinfwmFakeCaptureAPI : NSObject
+ (void)getShareableContentExcludingDesktopWindows:(BOOL)exclude
                              onScreenWindowsOnly:(BOOL)onScreen
                                completionHandler:(void (^)(SCShareableContent*, NSError*))completion;
+ (void)captureImageWithFilter:(SCContentFilter*)filter
                configuration:(SCStreamConfiguration*)configuration
            completionHandler:(void (^)(CGImageRef, NSError*))completion;
- (instancetype)initWithDesktopIndependentWindow:(SCWindow*)window;
@end
@implementation MinfwmFakeCaptureAPI
+ (void)getShareableContentExcludingDesktopWindows:(BOOL)exclude
                              onScreenWindowsOnly:(BOOL)onScreen
                                completionHandler:(void (^)(SCShareableContent*, NSError*))completion {
    completion((SCShareableContent*)(id)[MinfwmFakeCaptureContent new], nil);
}
+ (void)captureImageWithFilter:(SCContentFilter*)filter
                configuration:(SCStreamConfiguration*)configuration
            completionHandler:(void (^)(CGImageRef, NSError*))completion {
    pendingScreenshot = [completion copy];
}
- (instancetype)initWithDesktopIndependentWindow:(SCWindow*)window { return [super init]; }
@end

namespace {
class ReplacedMethod {
    Method m_method;
    IMP m_original;
public:
    ReplacedMethod(Class target, SEL selector, bool classMethod) {
        m_method = classMethod ? class_getClassMethod(target, selector) : class_getInstanceMethod(target, selector);
        Method fake = classMethod ? class_getClassMethod([MinfwmFakeCaptureAPI class], selector)
                                  : class_getInstanceMethod([MinfwmFakeCaptureAPI class], selector);
        m_original = method_setImplementation(m_method, method_getImplementation(fake));
    }
    ~ReplacedMethod() { method_setImplementation(m_method, m_original); }
};
int failures = 0;
void expect(bool condition, const char* message) {
    if (!condition) { std::cerr << "FAIL: " << message << '\n'; ++failures; }
}
void drainMainUntil(bool& completed) {
    const double deadline = CACurrentMediaTime() + 2;
    while (!completed && CACurrentMediaTime() < deadline)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, .01, true);
    expect(completed, "deferred native callback completes on main");
}
void deferredCapture(bool reset, bool destroy, bool cached, bool fail = false) {
    auto provider = std::make_unique<minfwm::ScreenshotProvider>();
    bool completed = false;
    // The first request exercises discovery. The second exercises cached content.
    if (cached) {
        provider->capture(42, 123, 512, [](auto) {});
        pendingScreenshot(nullptr, nil);
        pendingScreenshot = nil;
    }
    provider->capture(42, 123, 512, [&](auto result) {
        expect([NSThread isMainThread], "native completion is marshalled to main");
        expect(static_cast<bool>(result) == (!reset && !fail),
               "successful image survives callback; failed or stale capture stays live");
        if (result) expect(CGImageGetWidth(result->get()) == 8, "borrowed screenshot image is retained");
        completed = true;
    });
    expect(pendingScreenshot != nil, "native screenshot callback was intercepted");
    if (!pendingScreenshot) return;
    if (reset) provider->reset();
    if (destroy) provider.reset();
    auto callback = pendingScreenshot;
    pendingScreenshot = nil;
    // Invoke only after discovery and captureWindow have returned. No real
    // ScreenCaptureKit call or permission request is made by this test.
    std::thread background([callback, fail] {
        @autoreleasepool {
            auto color = CGColorSpaceCreateDeviceRGB();
            auto context = CGBitmapContextCreate(nullptr, 8, 8, 8, 32, color, kCGImageAlphaPremultipliedLast);
            auto image = CGBitmapContextCreateImage(context);
            callback(fail ? nullptr : image,
                     fail ? [NSError errorWithDomain:@"test.capture" code:1 userInfo:nil] : nil);
            CGImageRelease(image);
            CGContextRelease(context);
            CGColorSpaceRelease(color);
        }
    });
    background.join();
    drainMainUntil(completed);
}
}
int main() {
    @autoreleasepool {
        ReplacedMethod discovery([SCShareableContent class],
            @selector(getShareableContentExcludingDesktopWindows:onScreenWindowsOnly:completionHandler:), true);
        ReplacedMethod screenshot([SCScreenshotManager class],
            @selector(captureImageWithFilter:configuration:completionHandler:), true);
        ReplacedMethod filter([SCContentFilter class], @selector(initWithDesktopIndependentWindow:), false);
        deferredCapture(false, false, false);
        deferredCapture(false, false, true);
        deferredCapture(true, false, false);
        deferredCapture(false, true, false);
        deferredCapture(false, false, false, true);
    }
    if (!failures) std::cout << "native overview callback lifetime tests passed\n";
    return failures ? 1 : 0;
}
