#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

// ============================================================
//  JumioObserver — observe-only KYC diagnostic for PaysafeCard
//
//  Dumps the FINAL images + metadata that reach Jumio, so the
//  user can see exactly what was sent (and whether the selfie is
//  mirrored / mis-rotated). NO bypass, NO mutation.
//
//  Output dir: <app-data>/Documents/JumioObserver/
//    selfie_<ts>.jpg           final selfie as sent
//    image_<ts>.jpg            any JDAImage data (selfie/depth)
//    meta_<ts>.json            width/height/rotation/format/iso
//    upload_<ts>.txt           network upload target + headers
//    uploadbody_<ts>.bin       raw upload body (if image-like)
// ============================================================

static NSString *dumpDir(void) {
    static NSString *dir = nil;
    if (!dir) {
        NSString *base = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                             NSUserDomainMask, YES).firstObject;
        dir = [base stringByAppendingPathComponent:@"JumioObserver"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return dir;
}

static NSString *nowTag(void) {
    return [NSString stringWithFormat:@"%lld", (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)];
}

// Write NSData to the dump dir, return full path (or nil on failure).
static NSString *writeData(NSString *prefix, NSString *ext, NSData *data) {
    if (!data || data.length == 0) return nil;
    NSString *path = [[dumpDir() stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"%@_%@.%@", prefix, nowTag(), ext]];
    if ([data writeToFile:path atomically:YES]) return path;
    return nil;
}

// Serialize a small metadata dict as pretty JSON.
static NSString *jsonString(NSDictionary *d) {
    NSError *e = nil;
    NSData *j = [NSJSONSerialization dataWithJSONObject:d
                                               options:NSJSONWritingPrettyPrinted
                                                 error:&e];
    return j ? [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding] : @"{}";
}

// ---------- Hook 1: JDAImage construction chokepoint ----------
// Every image Jumio wraps (selfie, and depth frames) passes through
// initWithData:width:height:rotation:format:iso:. We capture the raw
// bytes + the rotation hint WITHOUT altering anything.
%hook JDAImage

- (id)initWithData:(id)data
             width:(long)width
            height:(long)height
          rotation:(long)rotation
            format:(long)format
               iso:(long)iso
{
    @try {
        if (data && [data isKindOfClass:[NSData class]]) {
            NSData *d = (NSData *)data;
            // JPEG magic 0xFFD8, PNG 0x8950, HEIC ftyp
            const unsigned char *b = d.bytes;
            BOOL isImage = d.length > 12 &&
                ((b[0]==0xFF && b[1]==0xD8) ||                     // JPEG
                 (b[0]==0x89 && b[1]==0x50) ||                     // PNG
                 (memcmp(b+4, "ftyp", 4)==0));                     // HEIC/BMFF
            NSString *ext = (b[0]==0xFF && b[1]==0xD8) ? @"jpg" :
                            (b[0]==0x89 && b[1]==0x50) ? @"png" : @"bin";
            NSString *tag = isImage ? @"selfie" : @"framedata";

            NSString *p = writeData(tag, ext, d);
            if (p) {
                NSDictionary *meta = @{
                    @"width": @(width),
                    @"height": @(height),
                    @"rotation": @(rotation),      // THE mirror/rotate hint
                    @"format": @(format),
                    @"iso": @(iso),
                    @"bytes": @(d.length),
                    @"path": p,
                    @"kind": tag,
                };
                NSString *mp = [[dumpDir() stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"meta_%@.json", nowTag()]];
                [jsonString(meta) writeToFile:mp atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
    } @catch (NSException *e) { /* never break the app */ }

    return %orig;
}

%end

// ---------- Hook 2: JDAClient sendImage attribution ----------
// Confirms which JDAImage is the actual face selfie vs. a depth frame.
%hook JDAClient

- (void)sendImage:(id)image timestamp:(long long)timestamp {
    @try {
        if ([image respondsToSelector:@selector(data)] &&
            [image respondsToSelector:@selector(width)]) {
            NSData *d = [image data];
            long w = [[image width] longValue];
            long h = [[image height] longValue];
            long rot = [image respondsToSelector:@selector(rotation)]
                         ? [[image rotation] longValue] : -1;
            const unsigned char *b = d.bytes;
            if (d.length > 4 && b[0]==0xFF && b[1]==0xD8) {
                NSString *p = writeData(@"selfie_live", @"jpg", d);
                (void)p;
                NSDictionary *m = @{@"kind":@"selfie_live_sendImage",
                                    @"width":@(w), @"height":@(h),
                                    @"rotation":@(rot), @"bytes":@(d.length),
                                    @"timestamp":@(timestamp)};
                NSString *mp = [[dumpDir() stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"meta_%@.json", nowTag()]];
                [jsonString(m) writeToFile:mp atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
    } @catch (NSException *e) { }
    %orig;
}

- (void)sendImage:(id)image depthImage:(id)depth timestamp:(long long)timestamp {
    @try {
        if ([image respondsToSelector:@selector(data)]) {
            NSData *d = [image data];
            const unsigned char *b = d.bytes;
            if (d.length > 4 && b[0]==0xFF && b[1]==0xD8) {
                NSString *p = writeData(@"selfie_depth", @"jpg", d);
                (void)p;
                NSDictionary *m = @{@"kind":@"selfie_depth_sendImage",
                                    @"rotation":@([image respondsToSelector:@selector(rotation)] ? [[image rotation] longValue] : -1),
                                    @"hasDepth":@(depth != nil),
                                    @"bytes":@(d.length)};
                NSString *mp = [[dumpDir() stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"meta_%@.json", nowTag()]];
                [jsonString(m) writeToFile:mp atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
    } @catch (NSException *e) { }
    %orig;
}

%end

// ---------- Hook 3: NSURLSession upload catch-all ----------
// Logs every upload/data request headed for jumio.ai and dumps the
// body if it looks like an image — captures the ID front/back even
// if those bypass JDAImage.
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    @try {
        NSString *url = request.URL.absoluteString;
        if ([url rangeOfString:@"jumio"].location != NSNotFound) {
            NSDictionary *m = @{@"method":request.HTTPMethod ?: @"GET",
                                @"url":url,
                                @"contentLength":@(request.HTTPBody.length),
                                @"contentType":[request valueForHTTPHeaderField:@"Content-Type"] ?: @"-"};
            NSString *mp = [[dumpDir() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"upload_%@.json", nowTag()]];
            [jsonString(m) writeToFile:mp atomically:YES encoding:NSUTF8StringEncoding error:nil];

            NSData *body = request.HTTPBody;
            const unsigned char *b = body.bytes;
            if (body.length > 12 && b[0]==0xFF && b[1]==0xD8) {
                writeData(@"uploadbody", @"jpg", body);
            } else if (body.length > 128) {
                writeData(@"uploadbody", @"bin", body);
            }
        }
    } @catch (NSException *e) { }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(id)handler {
    @try {
        NSString *url = request.URL.absoluteString;
        if ([url rangeOfString:@"jumio"].location != NSNotFound) {
            NSData *body = request.HTTPBody;
            const unsigned char *b = body.bytes;
            if (body.length > 12 && b[0]==0xFF && b[1]==0xD8) {
                writeData(@"uploadbody", @"jpg", body);
            } else if (body.length > 128) {
                writeData(@"uploadbody", @"bin", body);
            }
            NSDictionary *m = @{@"method":request.HTTPMethod ?: @"GET",
                                @"url":url,
                                @"contentLength":@(body.length),
                                @"contentType":[request valueForHTTPHeaderField:@"Content-Type"] ?: @"-"};
            NSString *mp = [[dumpDir() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"upload_%@.json", nowTag()]];
            [jsonString(m) writeToFile:mp atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    } @catch (NSException *e) { }
    return %orig;
}

%end

%ctor {
    // One-time marker so we can confirm injection from the dump dir.
    @autoreleasepool {
        NSString *marker = [dumpDir() stringByAppendingPathComponent:@"INJECTED.txt"];
        [[NSString stringWithFormat:@"JumioObserver loaded at %@\n",
          [NSDate date]] writeToFile:marker atomically:YES
                            encoding:NSUTF8StringEncoding error:nil];
    }
}
