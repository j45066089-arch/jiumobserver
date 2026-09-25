#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ============================================================
//  JumioObserver — observe-only KYC diagnostic for PaysafeCard
//
//  Dumps the FINAL images + metadata that reach Jumio, so the
//  user can see exactly what was sent (and whether the selfie is
//  mirrored / mis-rotated). NO bypass, NO mutation.
//
//  Design note: we do NOT hook the initWithData:...:iso: initializer
//  (unknown exact type encoding -> would break argument marshalling).
//  Instead we hook the -[JDAImage data] GETTER (trivial @: signature)
//  and read width/height/rotation via KVC (boxed -> no ambiguity).
//  Output dir: <app-data>/Documents/JumioObserver/
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
    return [NSString stringWithFormat:@"%lld",
            (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)];
}

// Write NSData to the dump dir. Returns path or nil.
static NSString *writeData(NSString *prefix, NSString *ext, NSData *data) {
    if (!data || data.length == 0) return nil;
    NSString *path = [dumpDir() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"%@_%@.%@", prefix, nowTag(), ext]];
    if ([data writeToFile:path atomically:YES]) return path;
    return nil;
}

// Pretty JSON from a small dict.
static NSString *jsonString(NSDictionary *d) {
    NSError *e = nil;
    NSData *j = [NSJSONSerialization dataWithJSONObject:d
                                               options:NSJSONWritingPrettyPrinted
                                                 error:&e];
    if (!j) return @"{}";
    return [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding];
}

// KVC-helper: read a numeric property from an object, tolerant of
// scalar (boxed by KVC) or object returns. Returns -1 on failure.
static long numProp(id obj, NSString *key) {
    @try {
        id v = [obj valueForKey:key];
        if (!v) return -1;
        if ([v respondsToSelector:@selector(longLongValue)])
            return [v longLongValue];
        if ([v respondsToSelector:@selector(longValue)])
            return [v longValue];
        return -1;
    } @catch (NSException *e) { return -1; }
}

static BOOL isJPEG(NSData *d) {
    const unsigned char *b = d.bytes;
    return d.length > 4 && b[0] == 0xFF && b[1] == 0xD8;
}

static void logMeta(NSString *kind, NSDictionary *extra) {
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:
                              @{@"kind": kind, @"ts": nowTag()}];
    if (extra) [m addEntriesFromDictionary:extra];
    NSString *mp = [dumpDir() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"meta_%@.json", nowTag()]];
    NSString *js = jsonString(m);
    [js writeToFile:mp atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// ============================================================
//  Hook 1: -[JDAImage data] getter — trivial signature.
//  Fires whenever Jumio reads the wrapped image bytes (i.e. right
//  before upload). self is the JDAImage, so we can read rotation etc.
// ============================================================
%hook JDAImage

- (id)data {
    id result = %orig;
    @try {
        if (result && [result isKindOfClass:[NSData class]]) {
            NSData *d = (NSData *)result;
            if (isJPEG(d)) {
                long w = numProp(self, @"width");
                long h = numProp(self, @"height");
                long rot = numProp(self, @"rotation");
                NSString *p = writeData(@"selfie", @"jpg", d);
                logMeta(@"selfie_image", @{
                    @"width": @(w), @"height": @(h), @"rotation": @(rot),
                    @"bytes": @(d.length), @"path": p ?: @"(none)"
                });
            }
        }
    } @catch (NSException *e) { }
    return result;
}

%end

// ============================================================
//  Hook 2: JDAClient image submission — attribute which image is the
//  live selfie. Known signatures (id image, NSInteger timestamp).
// ============================================================
%hook JDAClient

- (void)sendImage:(id)image timestamp:(NSInteger)timestamp {
    @try {
        if ([image isKindOfClass:NSClassFromString(@"JDAImage")]) {
            NSData *d = [image valueForKey:@"data"];
            if (d && [d isKindOfClass:[NSData class]] && isJPEG(d)) {
                NSString *p = writeData(@"selfie_live", @"jpg", d);
                logMeta(@"selfie_live_sendImage", @{
                    @"rotation": @(numProp(image, @"rotation")),
                    @"width": @(numProp(image, @"width")),
                    @"height": @(numProp(image, @"height")),
                    @"bytes": @(d.length), @"timestamp": @(timestamp),
                    @"path": p ?: @"(none)"
                });
            }
        }
    } @catch (NSException *e) { }
    %orig;
}

- (void)sendImage:(id)image depthImage:(id)depth timestamp:(NSInteger)timestamp {
    @try {
        if ([image isKindOfClass:NSClassFromString(@"JDAImage")]) {
            NSData *d = [image valueForKey:@"data"];
            if (d && [d isKindOfClass:[NSData class]] && isJPEG(d)) {
                NSString *p = writeData(@"selfie_depth", @"jpg", d);
                logMeta(@"selfie_depth_sendImage", @{
                    @"rotation": @(numProp(image, @"rotation")),
                    @"hasDepth": @(depth != nil),
                    @"bytes": @(d.length), @"timestamp": @(timestamp),
                    @"path": p ?: @"(none)"
                });
            }
        }
    } @catch (NSException *e) { }
    %orig;
}

%end

// ============================================================
//  Hook 3: NSURLSession upload catch-all — logs requests to *.jumio.ai
//  and dumps image-like bodies (captures ID front/back uploads even
//  if those never pass through JDAImage). Public, stable signatures.
// ============================================================
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    @try {
        NSString *url = request.URL.absoluteString;
        if (url && [url rangeOfString:@"jumio"].location != NSNotFound) {
            NSData *body = request.HTTPBody;
            if (body && [body isKindOfClass:[NSData class]] && isJPEG(body)) {
                writeData(@"uploadbody", @"jpg", body);
            }
            logMeta(@"upload_request", @{
                @"method": request.HTTPMethod ?: @"GET",
                @"url": url,
                @"contentLength": @(body.length),
                @"contentType": [request valueForHTTPHeaderField:@"Content-Type"] ?: @"-"
            });
        }
    } @catch (NSException *e) { }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    @try {
        NSString *url = request.URL.absoluteString;
        if (url && [url rangeOfString:@"jumio"].location != NSNotFound) {
            NSData *body = request.HTTPBody;
            if (body && [body isKindOfClass:[NSData class]] && isJPEG(body)) {
                writeData(@"uploadbody", @"jpg", body);
            }
            logMeta(@"upload_request", @{
                @"method": request.HTTPMethod ?: @"GET",
                @"url": url,
                @"contentLength": @(body.length),
                @"contentType": [request valueForHTTPHeaderField:@"Content-Type"] ?: @"-"
            });
        }
    } @catch (NSException *e) { }
    return %orig;
}

%end

%ctor {
    @autoreleasepool {
        NSString *marker = [dumpDir() stringByAppendingPathComponent:@"INJECTED.txt"];
        [[NSString stringWithFormat:@"JumioObserver loaded at %@\n", [NSDate date]]
         writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
