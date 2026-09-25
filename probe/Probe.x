#import <Foundation/Foundation.h>

// Maximal-path probe: writes to MULTIPLE absolute paths so a roothide
// path-redirect can't hide the result. All readable via SSH scope.
%ctor {
    @autoreleasepool {
        NSString *bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"?";
        NSString *ts = [NSString stringWithFormat:@"%lld",
                        (long long)([[NSDate date] timeIntervalSince1970]*1000.0)];
        NSString *line = [NSString stringWithFormat:@"%@ bundle=%@\n", ts, bundle];

        NSArray *paths = @[
            @"/var/mobile/Documents/jumio_probe_hit.txt",
            @"/var/jb/jumio_probe_hit.txt",
            @"/var/tmp/jumio_probe_hit.txt",
            @"/tmp/jumio_probe_hit.txt"
        ];
        for (NSString *p in paths) {
            NSError *e = nil;
            BOOL ok = [line writeToFile:p atomically:YES
                               encoding:NSUTF8StringEncoding error:&e];
            // Log which path worked + errno-style reason
            if (!ok) {
                NSString *why = e ? e.localizedDescription : @"";
                [[NSString stringWithFormat:@"FAIL %@ %@\n", p, why]
                 writeToFile:@"/tmp/jumio_probe_fail.txt"
                  atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
        NSLog(@"[JumioProbe] ctor ran bundle=%@", bundle);
    }
}
