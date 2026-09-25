#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <string.h>

// Socket-based injection probe. Binds a loopback TCP port in the ctor —
// sandbox-friendly, and unambiguous: if the port answers, the ctor RAN.
// (File writes can be swallowed by roothide's per-process path redirect.)
%ctor {
    @autoreleasepool {
        int s = socket(AF_INET, SOCK_STREAM, 0);
        if (s >= 0) {
            int one = 1;
            setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
            struct sockaddr_in a;
            memset(&a, 0, sizeof(a));
            a.sin_family = AF_INET;
            a.sin_port = htons(8799);
            a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            if (bind(s, (struct sockaddr*)&a, sizeof(a)) == 0) {
                listen(s, 5);
                dispatch_async(dispatch_get_global_queue(0,0), ^{
                    while (1) {
                        int c = accept(s, NULL, NULL);
                        if (c >= 0) {
                            const char *msg = "JumioProbe ctor ran OK\n";
                            write(c, msg, strlen(msg));
                            close(c);
                        }
                    }
                });
            }
        }
        // Fallback file write
        NSString *line = [NSString stringWithFormat:@"ctor@%lld bundle=%@\n",
                          (long long)([[NSDate date] timeIntervalSince1970]*1000.0),
                          [[NSBundle mainBundle] bundleIdentifier] ?: @"?"];
        [line writeToFile:@"/var/mobile/Documents/jumio_probe_hit.txt"
               atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
