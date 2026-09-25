#import <Foundation/Foundation.h>

// Minimal-injection probe. Writes a heartbeat to an ABSOLUTE path that
// SSH can read. No class hooks, no frameworks — just proves the ctor runs.
%ctor {
    @autoreleasepool {
        NSString *p = @"/var/mobile/Documents/jumioobserver_inject_probe.txt";
        NSString *s = [NSString stringWithFormat:
            @"%lld ctor ran, bundle=%@\n",
            (long long)([[NSDate date] timeIntervalSince1970] * 1000.0),
            [[NSBundle mainBundle] bundleIdentifier]];
        [s writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
