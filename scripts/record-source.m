#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <signal.h>
#import <unistd.h>

static volatile sig_atomic_t KeepRunning = 1;

static void StopRecording(int signal) {
    (void)signal;
    KeepRunning = 0;
}

static NSString *CurrentSourceID(void) {
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    if (!source) return @"?";
    CFStringRef value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    NSString *result = value ? [(__bridge NSString *)value copy] : @"?";
    CFRelease(source);
    return result;
}

static NSString *FrontAppID(void) {
    return NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier ?: @"?";
}

static void Emit(NSString *message) {
    printf("[hal-record-source] %.6f %s\n",
           CFAbsoluteTimeGetCurrent(), message.UTF8String);
    fflush(stdout);
}

// Which app is in front and which input source is current, one line per change. Answers the
// question the §6.2 matrix keeps asking: did this app take the input source away from HAL?
int main(void) {
    @autoreleasepool {
        signal(SIGINT, StopRecording);
        signal(SIGTERM, StopRecording);

        NSString *source = CurrentSourceID();
        NSString *app = FrontAppID();
        Emit([NSString stringWithFormat:@"READY app=%@ source=%@", app, source]);

        while (KeepRunning) {
            @autoreleasepool {
                NSString *nextSource = CurrentSourceID();
                if (![nextSource isEqualToString:source]) {
                    Emit([NSString stringWithFormat:@"SOURCE %@ -> %@ app=%@", source, nextSource, app]);
                    source = nextSource;
                }

                NSString *nextApp = FrontAppID();
                if (![nextApp isEqualToString:app]) {
                    Emit([NSString stringWithFormat:@"APP %@ -> %@ source=%@", app, nextApp, source]);
                    app = nextApp;
                }
            }
            // TIS refreshes its cached current source on the run loop, so service one rather
            // than sleeping: with a bare usleep every SOURCE change goes unnoticed.
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.005, false);
        }

        Emit([NSString stringWithFormat:@"DONE app=%@ source=%@", app, source]);
    }
    return 0;
}
