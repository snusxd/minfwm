// Compile the native adapter here so its private coordinate and ownership boundaries are tested
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
static SCStreamConfiguration* lastCaptureConfiguration;
static CGRect filterContentRect = CGRectMake(0, 0, 100, 100);
@interface MinfwmFakeCaptureAPI : NSObject
@property(readonly) CGRect contentRect;
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
    lastCaptureConfiguration = configuration;
    pendingScreenshot = [completion copy];
}
- (instancetype)initWithDesktopIndependentWindow:(SCWindow*)window { return [super init]; }
- (CGRect)contentRect { return filterContentRect; }
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
void canvasFrameTests() {
    // The ordinary NSView owns an unflipped backing layer. Frame expectations
    // are in that bottom-left coordinate system, while input is top-left.
    const minfwm::core::Rect bounds{0, 0, 1920, 1080};
    auto top = minfwm::previewLayerFrame({100, 0, 200, 80}, bounds);
    auto bottom = minfwm::previewLayerFrame({100, 1000, 200, 80}, bounds);
    expect(top.origin.y == 1000 && bottom.origin.y == 0,
           "top and bottom previews occupy their matching screen edges");
    auto before = minfwm::previewLayerFrame({100, 300, 200, 80}, bounds);
    auto down = minfwm::previewLayerFrame({100, 340, 200, 80}, bounds);
    auto up = minfwm::previewLayerFrame({100, 260, 200, 80}, bounds);
    expect(before.origin.y == 700 && down.origin.y == 660 && up.origin.y == 740,
           "vertical camera movement preserves direction on the bottom-left canvas");
    auto negativeDisplay = minfwm::previewLayerFrame({-1100, -850, 200, 80}, {-1200, -900, 1200, 900});
    expect(negativeDisplay.origin.x == 100 && negativeDisplay.origin.y == 770 &&
           negativeDisplay.size.width == 200 && negativeDisplay.size.height == 80,
           "monitor origins and thumbnail size are respected");
    auto partiallyAbove = minfwm::previewLayerFrame({100, -30, 200, 80}, bounds);
    auto partiallyBelow = minfwm::previewLayerFrame({100, 1050, 200, 80}, bounds);
    expect(partiallyAbove.origin.y == 1030 && partiallyBelow.origin.y == -50,
           "offscreen previews remain positioned for canvas clipping");
}
void captureSizingTests() {
    // SCWindow.frame can describe an older scaled presentation. The capture
    // filter defines the source content, which must fill the requested bitmap.
    minfwm::ScreenshotProvider provider;
    filterContentRect = CGRectMake(-500, 120, 900, 600);
    provider.capture(42, 123, 512, [](auto) {});
    expect(lastCaptureConfiguration.width == 512 && lastCaptureConfiguration.height == 341,
           "capture dimensions use filter content rather than the scaled window frame");
    expect(lastCaptureConfiguration.scalesToFit && lastCaptureConfiguration.preservesAspectRatio,
           "smaller transformed window fills capture bounds with its aspect ratio intact");
    pendingScreenshot(nullptr, nil);
    pendingScreenshot = nil;
    filterContentRect = CGRectMake(0, 0, 150, 300);
    provider.capture(42, 123, 512, [](auto) {});
    expect(lastCaptureConfiguration.width == 150 && lastCaptureConfiguration.height == 300,
           "cached discovery respects current filter content and avoids unnecessary bitmap enlargement");
    pendingScreenshot(nullptr, nil);
    pendingScreenshot = nil;
    filterContentRect = CGRectMake(0, 0, 100, std::numeric_limits<double>::quiet_NaN());
    bool rejected = false;
    provider.capture(42, 123, 512, [&](auto image) { rejected = !image; });
    expect(rejected && pendingScreenshot == nil, "invalid filter content leaves the original live");
    filterContentRect = CGRectMake(0, 0, 100, 100);
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
        canvasFrameTests();
        ReplacedMethod discovery([SCShareableContent class],
            @selector(getShareableContentExcludingDesktopWindows:onScreenWindowsOnly:completionHandler:), true);
        ReplacedMethod screenshot([SCScreenshotManager class],
            @selector(captureImageWithFilter:configuration:completionHandler:), true);
        ReplacedMethod filter([SCContentFilter class], @selector(initWithDesktopIndependentWindow:), false);
        ReplacedMethod contentRect([SCContentFilter class], @selector(contentRect), false);
        captureSizingTests();
        deferredCapture(false, false, false);
        deferredCapture(false, false, true);
        deferredCapture(true, false, false);
        deferredCapture(false, true, false);
        deferredCapture(false, false, false, true);
    }
    if (!failures) std::cout << "native overview callback lifetime tests passed\n";
    return failures ? 1 : 0;
}
