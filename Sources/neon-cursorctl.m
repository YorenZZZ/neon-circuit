// Copyright 2026 Yoren
// SPDX-License-Identifier: MIT
// Purpose-built local cursor controller. No reset, unregister, scale, color,
// preference, login-item or helper operations. Private cursor ABI is taken from
// Mousecape's CGSInternal/CGSCursor.h; callers must validate on their OS build.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <dlfcn.h>
#import <math.h>
#import <stdint.h>
#import <objc/message.h>

typedef int ConnectionID;
typedef ConnectionID (*MainConnectionFn)(void);
typedef CGError (*CopyNamedFn)(ConnectionID, char *, CGSize *, CGPoint *, NSUInteger *, CGFloat *, CFArrayRef *);
typedef CGError (*CopyCoreFn)(ConnectionID, int, CFArrayRef *, CGSize *, CGPoint *, NSUInteger *, CGFloat *);
typedef CGError (*RegisterFn)(ConnectionID, char *, bool, bool, CGSize, CGPoint, NSUInteger, CGFloat, CFArrayRef, int *);
static MainConnectionFn mainConnection;
static CopyNamedFn copyNamed;
static CopyCoreFn copyCore;
static RegisterFn registerImages;
static void *skyHandle, *hisHandle;
static NSString *lastError;

static void fail(NSString *message) { lastError = message; }
static void report(NSDictionary *value) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
    if (json) fprintf(stdout, "%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
}
static void *symbol(const char *a, const char *b) {
    for (int i = 0; i < 2; i++) {
        const char *name = i ? b : a;
        if (!name) continue;
        void *p = dlsym(RTLD_DEFAULT, name);
        if (!p && skyHandle) p = dlsym(skyHandle, name);
        if (!p && hisHandle) p = dlsym(hisHandle, name);
        if (p) return p;
    }
    return NULL;
}
static BOOL loadAPIs(BOOL writing) {
    skyHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
    hisHandle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY | RTLD_LOCAL);
    mainConnection = (MainConnectionFn)symbol("CGSMainConnectionID", "SLSMainConnectionID");
    copyNamed = (CopyNamedFn)symbol("CGSCopyRegisteredCursorImages", "SLSCopyRegisteredCursorImages");
    copyCore = (CopyCoreFn)symbol("CoreCursorCopyImages", NULL);
    registerImages = (RegisterFn)symbol("CGSRegisterCursorWithImages", "SLSRegisterCursorWithImages");
    if (!mainConnection || !copyNamed || !copyCore || (writing && !registerImages)) {
        fail(@"Required cursor symbols are unavailable"); return NO;
    }
    return YES;
}
static BOOL finiteNumber(id object, double *value) {
    if (![object isKindOfClass:NSNumber.class]) return NO;
    *value = [object doubleValue]; return isfinite(*value);
}
static BOOL validName(id name) {
    if (![name isKindOfClass:NSString.class] || [name length] == 0 || [name length] > 255) return NO;
    NSData *utf8 = [name dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8 || memchr(utf8.bytes, 0, utf8.length)) return NO;
    // Deliberately restrict this controller to the explicitly themed system names.
    return [name hasPrefix:@"com.apple.coregraphics."] || [name hasPrefix:@"com.apple.cursor."];
}
static BOOL coreID(NSString *name, int *number) {
    if (![name hasPrefix:@"com.apple.cursor."]) return NO;
    NSString *suffix = [name substringFromIndex:@"com.apple.cursor.".length];
    NSScanner *scanner = [NSScanner scannerWithString:suffix];
    scanner.charactersToBeSkipped = nil;
    long long value;
    if (![scanner scanLongLong:&value] || !scanner.isAtEnd || value < 0 || value > INT_MAX) return NO;
    *number = (int)value; return YES;
}
static NSDictionary *readCursor(NSString *name) {
    CGSize size = CGSizeZero; CGPoint hot = CGPointZero;
    NSUInteger frames = 0; CGFloat duration = 0; CFArrayRef images = NULL;
    int number;
    CGError error = coreID(name, &number)
        ? copyCore(mainConnection(), number, &images, &size, &hot, &frames, &duration)
        : copyNamed(mainConnection(), (char *)name.UTF8String, &size, &hot, &frames, &duration, &images);
    if (error || !images || CFGetTypeID(images) != CFArrayGetTypeID() || CFArrayGetCount(images) == 0) {
        if (images) CFRelease(images);
        fail([NSString stringWithFormat:@"Read failed for %@ (CGError %d)", name, error]); return nil;
    }
    NSMutableArray *array = [NSMutableArray array];
    for (CFIndex i = 0; i < CFArrayGetCount(images); i++) {
        CFTypeRef image = CFArrayGetValueAtIndex(images, i);
        if (!image || CFGetTypeID(image) != CGImageGetTypeID()) {
            CFRelease(images); fail([NSString stringWithFormat:@"Non-image representation for %@", name]); return nil;
        }
        [array addObject:(__bridge id)image];
    }
    CFRelease(images);
    return @{ @"PointsWide": @(size.width), @"PointsHigh": @(size.height),
              @"HotSpotX": @(hot.x), @"HotSpotY": @(hot.y),
              @"FrameCount": @(frames), @"FrameDuration": @(duration), @"Images": array };
}
static NSData *png(CGImageRef image) {
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    if (!dest) return nil;
    CGImageDestinationAddImage(dest, image, NULL);
    BOOL ok = CGImageDestinationFinalize(dest); CFRelease(dest);
    return ok ? data : nil;
}
static NSDictionary *rawRaster(CGImageRef image) {
    CGDataProviderRef provider = CGImageGetDataProvider(image);
    CFDataRef data = provider ? CGDataProviderCopyData(provider) : NULL;
    CGColorSpaceRef color = CGImageGetColorSpace(image);
    CFPropertyListRef colorProperty = color ? CGColorSpaceCopyPropertyList(color) : NULL;
    if (!data || (color && !colorProperty)) {
        if (data) CFRelease(data); if (colorProperty) CFRelease(colorProperty);
        fail(@"Cannot preserve the original image provider or color space"); return nil;
    }
    NSMutableDictionary *raster = [@{ @"Width": @(CGImageGetWidth(image)), @"Height": @(CGImageGetHeight(image)),
       @"BitsPerComponent": @(CGImageGetBitsPerComponent(image)), @"BitsPerPixel": @(CGImageGetBitsPerPixel(image)),
       @"BytesPerRow": @(CGImageGetBytesPerRow(image)), @"BitmapInfo": @(CGImageGetBitmapInfo(image)),
       @"IsMask": @(CGImageIsMask(image)), @"ShouldInterpolate": @(CGImageGetShouldInterpolate(image)),
       @"RenderingIntent": @(CGImageGetRenderingIntent(image)), @"Data": (__bridge NSData *)data } mutableCopy];
    if (colorProperty) { raster[@"ColorSpace"] = (__bridge id)colorProperty; CFRelease(colorProperty); }
    const CGFloat *decode = CGImageGetDecode(image);
    if (decode) {
        size_t components = CGImageIsMask(image) ? 1 : CGColorSpaceGetNumberOfComponents(color);
        NSMutableArray *values = [NSMutableArray array];
        for (size_t i = 0; i < components * 2; i++) [values addObject:@(decode[i])];
        raster[@"Decode"] = values;
    }
    CFRelease(data); return raster;
}
static CGImageRef decodeImage(NSData *data) {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return NULL;
    CGImageRef image = NULL;
    if (CGImageSourceGetCount(source) == 1)
        image = CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)@{ (id)kCGImageSourceShouldCache: @YES });
    CFRelease(source); return image;
}
static CGImageRef recreateRaw(NSDictionary *r) {
    if (![r isKindOfClass:NSDictionary.class] || ![r[@"Data"] isKindOfClass:NSData.class]) return NULL;
    const NSString *keys[] = {@"Width", @"Height", @"BitsPerComponent", @"BitsPerPixel", @"BytesPerRow", @"BitmapInfo", @"RenderingIntent"};
    double v[7];
    for (int i = 0; i < 7; i++) if (!finiteNumber(r[keys[i]], &v[i]) || v[i] < 0 || floor(v[i]) != v[i]) return NULL;
    if (v[0] < 1 || v[1] < 1 || v[0] > 8192 || v[1] > 33554432 || v[2] < 1 || v[2] > 32 || v[3] < 1 || v[3] > 128 || v[4] > 1073741824 || v[5] > UINT32_MAX || v[6] > kCGRenderingIntentAbsoluteColorimetric) return NULL;
    size_t width = v[0], height = v[1], bpc = v[2], bpp = v[3], row = v[4];
    if (row > SIZE_MAX / height || row < (width * bpp + 7) / 8 || [(NSData *)r[@"Data"] length] < row * height) return NULL;
    CGColorSpaceRef color = r[@"ColorSpace"] ? CGColorSpaceCreateWithPropertyList((__bridge CFPropertyListRef)r[@"ColorSpace"]) : NULL;
    BOOL mask = [r[@"IsMask"] boolValue];
    if (!mask && !color) return NULL;
    NSArray *values = r[@"Decode"]; CGFloat *decode = NULL;
    if (values) {
        NSUInteger count = (mask ? 1 : CGColorSpaceGetNumberOfComponents(color)) * 2;
        if (![values isKindOfClass:NSArray.class] || values.count != count) { if (color) CGColorSpaceRelease(color); return NULL; }
        decode = calloc(count, sizeof(CGFloat));
        if (!decode) { if (color) CGColorSpaceRelease(color); return NULL; }
        for (NSUInteger i = 0; i < count; i++) { double n; if (!finiteNumber(values[i], &n)) { free(decode); if (color) CGColorSpaceRelease(color); return NULL; } decode[i] = n; }
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)r[@"Data"]);
    CGImageRef image = mask ? CGImageMaskCreate(width, height, bpc, bpp, row, provider, decode, [r[@"ShouldInterpolate"] boolValue])
        : CGImageCreate(width, height, bpc, bpp, row, color, (CGBitmapInfo)(uint32_t)v[5], provider, decode, [r[@"ShouldInterpolate"] boolValue], (CGColorRenderingIntent)(int)v[6]);
    if (provider) CGDataProviderRelease(provider); if (color) CGColorSpaceRelease(color); free(decode);
    return image;
}
static NSData *rgba(CGImageRef image) {
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    if (!w || !h || w > SIZE_MAX / 4 || h > SIZE_MAX / (w * 4) || w * h * 4 > (size_t)512 * 1024 * 1024) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:w * h * 4];
    CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(data.mutableBytes, w, h, 8, w * 4, color, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(color); if (!ctx) return nil;
    CGContextSetBlendMode(ctx, kCGBlendModeCopy); CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image); CGContextRelease(ctx); return data;
}
static NSDictionary *loadCape(NSString *path) {
    NSError *error; NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    if (!data) { fail(error.localizedDescription); return nil; }
    id obj = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
    if (![obj isKindOfClass:NSDictionary.class] || ![obj[@"Cursors"] isKindOfClass:NSDictionary.class] || [obj[@"Cursors"] count] == 0) {
        fail(error.localizedDescription ?: @"Cape must contain a nonempty Cursors dictionary"); return nil;
    }
    return obj;
}
static NSDictionary *prepareCursor(NSString *name, NSDictionary *cursor, BOOL raw) {
    if (!validName(name) || ![cursor isKindOfClass:NSDictionary.class]) { fail(@"Invalid cursor name or value"); return nil; }
    if ([name hasPrefix:@"com.apple.cursor."]) { int n; if (!coreID(name, &n)) { fail(@"Invalid numeric cursor identifier"); return nil; } }
    const NSString *keys[] = {@"PointsWide", @"PointsHigh", @"HotSpotX", @"HotSpotY", @"FrameCount", @"FrameDuration"};
    double v[6]; for (int i = 0; i < 6; i++) if (!finiteNumber(cursor[keys[i]], &v[i])) { fail([NSString stringWithFormat:@"Invalid %@ in %@", keys[i], name]); return nil; }
    if (v[0] <= 0 || v[1] <= 0 || v[0] > 8192 || v[1] > 8192 || v[2] < 0 || v[3] < 0 || v[2] >= v[0] || v[3] >= v[1] || v[4] < 1 || v[4] > 4096 || floor(v[4]) != v[4] || v[5] < 0 || v[5] > 60) {
        fail([NSString stringWithFormat:@"Out-of-range cursor metadata in %@", name]); return nil;
    }
    NSArray *reps = raw ? cursor[@"RawRepresentations"] : cursor[@"Representations"];
    if (![reps isKindOfClass:NSArray.class] || reps.count == 0 || reps.count > 32) { fail([NSString stringWithFormat:@"Missing representations in %@", name]); return nil; }
    NSMutableArray *images = [NSMutableArray array]; NSMutableSet *dimensions = [NSMutableSet set];
    for (id rep in reps) {
        CGImageRef image = raw ? recreateRaw(rep) : ([rep isKindOfClass:NSData.class] ? decodeImage(rep) : NULL);
        if (!image) { fail([NSString stringWithFormat:@"Cannot decode a representation in %@", name]); return nil; }
        size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
        NSString *dim = [NSString stringWithFormat:@"%zux%zu", w, h];
        if (!w || !h || w > 8192 || h > (size_t)v[4] * 8192 || h % (NSUInteger)v[4] != 0 || [dimensions containsObject:dim]) {
            CGImageRelease(image); fail([NSString stringWithFormat:@"Invalid or duplicate representation dimensions in %@", name]); return nil;
        }
        double horizontalScale = w / v[0], verticalScale = h / (v[4] * v[1]);
        if (fabs(horizontalScale - verticalScale) > fmax(1.0 / v[0], 1.0 / v[1])) {
            CGImageRelease(image); fail([NSString stringWithFormat:@"Representation aspect ratio contradicts point size in %@", name]); return nil;
        }
        if (!rgba(image)) { CGImageRelease(image); fail(@"Representation exceeds comparison limits or cannot render"); return nil; }
        [dimensions addObject:dim]; [images addObject:(__bridge_transfer id)image];
    }
    NSMutableDictionary *result = [cursor mutableCopy]; result[@"Images"] = images;
    return result;
}
static NSDictionary *prepareCape(NSDictionary *cape, BOOL raw) {
    NSMutableDictionary *prepared = [NSMutableDictionary dictionary];
    for (NSString *name in [cape[@"Cursors"] allKeys]) {
        NSDictionary *entry = prepareCursor(name, cape[@"Cursors"][name], raw);
        if (!entry) return nil; prepared[name] = entry;
    }
    return prepared;
}
static NSDictionary *imageMap(NSArray *images) {
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (id object in images) {
        CGImageRef image = (__bridge CGImageRef)object;
        NSString *key = [NSString stringWithFormat:@"%zux%zu", CGImageGetWidth(image), CGImageGetHeight(image)];
        if (map[key]) return nil; map[key] = object;
    }
    return map;
}
static BOOL verifyCursor(NSString *name, NSDictionary *expected) {
    NSDictionary *actual = readCursor(name); if (!actual) return NO;
    for (NSString *key in @[@"PointsWide", @"PointsHigh", @"HotSpotX", @"HotSpotY", @"FrameCount", @"FrameDuration"]) {
        double a = [actual[key] doubleValue], e = [expected[key] doubleValue];
        // WindowServer stores cursor metadata as Float32. Accept its exact
        // representable value, rather than a broad numeric tolerance. Pixels
        // and frame counts remain exact.
        BOOL match = a == e || (![key isEqualToString:@"FrameCount"] && a == (double)(float)e);
        if (!isfinite(a) || !match) { fail([NSString stringWithFormat:@"%@ differs for %@ (expected %.17g, read %.17g)", key, name, e, a]); return NO; }
    }
    NSDictionary *em = imageMap(expected[@"Images"]), *am = imageMap(actual[@"Images"]);
    if (!em || !am || em.count != am.count || ![[NSSet setWithArray:em.allKeys] isEqualToSet:[NSSet setWithArray:am.allKeys]]) {
        fail([NSString stringWithFormat:@"Representation count or resolution differs for %@", name]); return NO;
    }
    for (NSString *key in em) {
        NSData *ep = rgba((__bridge CGImageRef)em[key]), *ap = rgba((__bridge CGImageRef)am[key]);
        if (!ep || !ap || ![ep isEqualToData:ap]) { fail([NSString stringWithFormat:@"RGBA pixels differ for %@ at %@", name, key]); return NO; }
    }
    return YES;
}
static int verifyAll(NSDictionary *prepared) {
    BOOL ok = YES;
    for (NSString *name in [prepared.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        BOOL match = verifyCursor(name, prepared[name]);
        report(match ? @{ @"cursor": name, @"verified": @YES } : @{ @"cursor": name, @"verified": @NO, @"error": lastError ?: @"Unknown error" });
        ok &= match;
    }
    return ok ? 0 : 1;
}
static NSArray *defaultNames(void) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *suffix in @[@"Arrow", @"IBeam", @"IBeamXOR", @"Alias", @"Copy", @"Move", @"ArrowCtx", @"ArrowS", @"IBeamS", @"Wait", @"Empty"])
        [names addObject:[@"com.apple.coregraphics." stringByAppendingString:suffix]];
    for (int i = 2; i <= 43; i++) if (i != 6) [names addObject:[NSString stringWithFormat:@"com.apple.cursor.%d", i]];
    return names;
}
static int snapshot(NSString *path, NSString *namesPath) {
    NSArray *names = defaultNames();
    if (namesPath) {
        NSData *data = [NSData dataWithContentsOfFile:namesPath]; NSError *error;
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
        if ([obj isKindOfClass:NSDictionary.class]) obj = obj[@"names"];
        if (![obj isKindOfClass:NSArray.class] || [obj count] == 0) { fail(@"names.json must contain a nonempty array of names"); return 1; }
        names = obj;
    }
    NSMutableSet *seen = [NSMutableSet set]; NSMutableDictionary *cursors = [NSMutableDictionary dictionary];
    for (NSString *name in names) {
        if (!validName(name) || [seen containsObject:name]) { fail(@"Invalid or duplicate snapshot name"); return 1; }
        [seen addObject:name]; NSDictionary *live = readCursor(name); if (!live) return 1;
        NSMutableDictionary *entry = [live mutableCopy]; [entry removeObjectForKey:@"Images"];
        NSMutableArray *encoded = [NSMutableArray array], *raw = [NSMutableArray array];
        for (id object in live[@"Images"]) {
            CGImageRef image = (__bridge CGImageRef)object;
            NSData *bytes = png(image); NSDictionary *raster = rawRaster(image);
            if (!bytes || !raster) { fail(lastError ?: @"Snapshot representation cannot be encoded"); return 1; }
            [encoded addObject:bytes]; [raw addObject:raster];
        }
        entry[@"Representations"] = encoded; entry[@"RawRepresentations"] = raw;
        if (!prepareCursor(name, entry, YES)) return 1;
        cursors[name] = entry;
    }
    NSDictionary *cape = @{ @"Version": @2.0, @"MinimumVersion": @2.0, @"Author": @"Local original system capture",
        @"CapeName": @"Unmodified cursor snapshot", @"CapeVersion": @1.0, @"Cloud": @NO, @"HiDPI": @YES,
        @"Identifier": @"local.neon-circuit.raw-original", @"NeonCursorctlRawVersion": @1, @"Cursors": cursors };
    NSError *error; NSData *data = [NSPropertyListSerialization dataWithPropertyList:cape format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) { fail(error.localizedDescription); return 1; }
    report(@{ @"snapshot": path, @"cursors": @(cursors.count), @"rawRasterPreserved": @YES }); return 0;
}
static NSArray *canonicalRaw(NSArray *raw) {
    return [raw sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult r = [a[@"Width"] compare:b[@"Width"]]; return r == NSOrderedSame ? [a[@"Height"] compare:b[@"Height"]] : r;
    }];
}
static int compareFiles(NSString *aPath, NSString *bPath) {
    NSDictionary *a = loadCape(aPath), *b = loadCape(bPath); if (!a || !b) return 1;
    NSDictionary *ac = a[@"Cursors"], *bc = b[@"Cursors"];
    BOOL rawComparison = [a[@"NeonCursorctlRawVersion"] isEqual:@1] && [b[@"NeonCursorctlRawVersion"] isEqual:@1];
    if (!prepareCape(a, rawComparison) || !prepareCape(b, rawComparison)) return 1;
    if (![[NSSet setWithArray:ac.allKeys] isEqualToSet:[NSSet setWithArray:bc.allKeys]]) { fail(@"Snapshot cursor key sets differ"); return 1; }
    BOOL ok = YES;
    for (NSString *name in [ac.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSMutableDictionary *ae = [ac[name] mutableCopy], *be = [bc[name] mutableCopy];
        // Raw snapshots compare provider bytes, format/color metadata and cursor
        // metadata; PNG is just the interoperable representation, not the oracle.
        if (ae[@"RawRepresentations"] && be[@"RawRepresentations"]) {
            if (!prepareCursor(name, ae, YES) || !prepareCursor(name, be, YES)) return 1;
            ae[@"RawRepresentations"] = canonicalRaw(ae[@"RawRepresentations"]);
            be[@"RawRepresentations"] = canonicalRaw(be[@"RawRepresentations"]);
            [ae removeObjectForKey:@"Representations"]; [be removeObjectForKey:@"Representations"];
        }
        BOOL equal = [ae isEqualToDictionary:be];
        report(@{ @"cursor": name, @"identical": @(equal), @"comparison": ae[@"RawRepresentations"] ? @"raw-provider-bytes-and-metadata" : @"encoded-representations-and-metadata" });
        ok &= equal;
    }
    if (!ok) fail(@"One or more snapshot entries differ"); return ok ? 0 : 1;
}
static int writeCape(NSDictionary *prepared) {
    BOOL ok = YES;
    for (NSString *name in [prepared.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *entry = prepared[name]; int seed = 0;
        // Preserve already-correct originals, including the native 30-frame
        // Wait that this OS refuses to register again. It is never themed.
        if (verifyCursor(name, entry)) {
            report(@{ @"cursor": name, @"alreadyMatched": @YES });
            continue;
        }
        CGError error = registerImages(mainConnection(), (char *)name.UTF8String, true, true,
            CGSizeMake([entry[@"PointsWide"] doubleValue], [entry[@"PointsHigh"] doubleValue]),
            CGPointMake([entry[@"HotSpotX"] doubleValue], [entry[@"HotSpotY"] doubleValue]),
            [entry[@"FrameCount"] unsignedIntegerValue], [entry[@"FrameDuration"] doubleValue],
            (__bridge CFArrayRef)entry[@"Images"], &seed);
        report(@{ @"cursor": name, @"registerError": @(error) }); ok &= (error == kCGErrorSuccess);
    }
    // Verify after all registrations, since Arrow and ArrowS can share readback.
    int checked = verifyAll(prepared); return ok && checked == 0 ? 0 : 1;
}
static NSString *architecture(void) {
#if defined(__arm64__)
    return @"arm64";
#elif defined(__x86_64__)
    return @"x86_64";
#else
    return @"unknown";
#endif
}
static NSDictionary *validationInfo(NSString *field, BOOL passed, NSUInteger keys, NSUInteger factories) {
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    NSMutableDictionary *info = [@{field: @(passed), @"keys": @(keys), @"publicFactoryCount": @(factories),
        @"operatingSystemVersion": [NSString stringWithFormat:@"%ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion],
        @"architecture": architecture()} mutableCopy];
    if (!passed) info[@"error"] = lastError ?: @"Validation failed";
    return info;
}
// Offline validation deliberately does not load SkyLight or cursor symbols.
// Snapshots must also retain valid PNGs, even though restoration uses raw data.
static int validateFile(NSString *path) {
    NSDictionary *cape = loadCape(path);
    NSUInteger keys = [cape[@"Cursors"] count];
    if (!cape) fail(@"Unable to read a valid cape file");
    BOOL ok = cape && prepareCape(cape, NO);
    if (ok && cape[@"NeonCursorctlRawVersion"]) {
        if (![cape[@"NeonCursorctlRawVersion"] isEqual:@1]) {
            fail(@"Unsupported raw snapshot version"); ok = NO;
        } else ok = prepareCape(cape, YES) != nil;
    } else if (ok) {
        // A raw section without its version marker must not silently pass.
        for (NSDictionary *cursor in [cape[@"Cursors"] allValues]) {
            if (cursor[@"RawRepresentations"]) {
                fail(@"Raw representations require the raw snapshot version marker"); ok = NO; break;
            }
        }
    }
    report(validationInfo(@"validated", ok, keys, 0)); return ok ? 0 : 1;
}
static BOOL validateLiveCursor(NSString *name) {
    NSDictionary *live = readCursor(name); if (!live) return NO;
    NSMutableDictionary *cursor = [live mutableCopy];
    NSMutableArray *representations = [NSMutableArray array];
    for (id object in live[@"Images"]) {
        NSData *data = png((__bridge CGImageRef)object);
        if (!data) { fail(@"A live cursor representation cannot be encoded"); return NO; }
        [representations addObject:data];
    }
    cursor[@"Representations"] = representations;
    // Reuse the same finite metadata, image dimensions and RGBA validation
    // required of a cape, while never registering or displaying this image.
    return prepareCursor(name, cursor, NO) != nil;
}
static BOOL checkFactory(NSCursor *cursor, NSInteger expected, NSString *state) {
    SEL selector = NSSelectorFromString(@"_coreCursorType");
    NSMethodSignature *signature = [cursor methodSignatureForSelector:selector];
    const char *type = signature.methodReturnType;
    while (type && type[0] && strchr("rnNoORV", type[0])) type++;
    if (!cursor || ![cursor respondsToSelector:selector] || !signature || signature.numberOfArguments != 2 ||
        signature.methodReturnLength != sizeof(NSInteger) || !type || strcmp(type, @encode(NSInteger)) != 0) {
        fail([NSString stringWithFormat:@"Cursor getter signature is unsupported for %@", state]); return NO;
    }
    NSInteger actual = ((NSInteger (*)(id, SEL))objc_msgSend)(cursor, selector);
    if (actual != expected) {
        fail([NSString stringWithFormat:@"Cursor mapping changed for %@ (expected %ld, read %ld)", state, (long)expected, (long)actual]); return NO;
    }
    return YES;
}
static BOOL validatePublicFactories(NSUInteger *checked) {
    *checked = 0;
    if (@available(macOS 15.0, *)) {
        // Profile observed on macOS 27.0 (26A428). Only factories and a getter
        // are called: no set, push, pop, hide, unhide or application activation.
        NSArray<NSCursor *> *everyday = @[
            NSCursor.arrowCursor, NSCursor.IBeamCursor, NSCursor.IBeamCursorForVerticalLayout,
            NSCursor.pointingHandCursor, NSCursor.openHandCursor, NSCursor.closedHandCursor,
            NSCursor.crosshairCursor, NSCursor.dragCopyCursor, NSCursor.dragLinkCursor,
            NSCursor.operationNotAllowedCursor, NSCursor.contextualMenuCursor, NSCursor.disappearingItemCursor];
        const NSInteger everydayTypes[] = {0, 1, 26, 13, 12, 11, 20, 5, 2, 3, 24, 25};
        for (NSUInteger i = 0; i < everyday.count; i++) {
            if (!checkFactory(everyday[i], everydayTypes[i], [NSString stringWithFormat:@"A%02lu", (unsigned long)i + 1])) return NO;
            (*checked)++;
        }
        NSArray<NSCursor *> *navigation = @[
            [NSCursor columnResizeCursorInDirections:NSHorizontalDirectionsAll],
            [NSCursor columnResizeCursorInDirections:NSHorizontalDirectionsLeft],
            [NSCursor columnResizeCursorInDirections:NSHorizontalDirectionsRight],
            [NSCursor rowResizeCursorInDirections:NSVerticalDirectionsAll],
            [NSCursor rowResizeCursorInDirections:NSVerticalDirectionsUp],
            [NSCursor rowResizeCursorInDirections:NSVerticalDirectionsDown], NSCursor.zoomInCursor, NSCursor.zoomOutCursor];
        const NSInteger navigationTypes[] = {19, 17, 18, 23, 21, 22, 42, 43};
        for (NSUInteger i = 0; i < navigation.count; i++) {
            if (!checkFactory(navigation[i], navigationTypes[i], [NSString stringWithFormat:@"B%02lu", (unsigned long)i + 1])) return NO;
            (*checked)++;
        }
        const NSCursorFrameResizePosition positions[] = {NSCursorFrameResizePositionTop, NSCursorFrameResizePositionLeft,
            NSCursorFrameResizePositionBottom, NSCursorFrameResizePositionRight, NSCursorFrameResizePositionTopLeft,
            NSCursorFrameResizePositionTopRight, NSCursorFrameResizePositionBottomLeft, NSCursorFrameResizePositionBottomRight};
        const NSCursorFrameResizeDirections directions[] = {NSCursorFrameResizeDirectionsAll, NSCursorFrameResizeDirectionsInward, NSCursorFrameResizeDirectionsOutward};
        const NSInteger expected[] = {32, 28, 32, 28, 34, 30, 30, 34, 36, 27, 31, 38, 35, 37, 29, 33, 31, 38, 36, 27, 33, 29, 37, 35};
        for (NSUInteger d = 0; d < 3; d++) for (NSUInteger p = 0; p < 8; p++) {
            NSUInteger index = d * 8 + p;
            NSString *state = index < 12 ? [NSString stringWithFormat:@"C%02lu", (unsigned long)index + 1]
                : [NSString stringWithFormat:@"D%02lu", (unsigned long)index - 11];
            NSCursor *cursor = [NSCursor frameResizeCursorFromPosition:positions[p] inDirections:directions[d]];
            if (!checkFactory(cursor, expected[index], state)) return NO;
            (*checked)++;
        }
        return *checked == 44;
    }
    fail(@"Required public cursor factories are unavailable"); return NO;
}
static int preflight(NSString *path) {
    NSUInteger keys = 0, factories = 0;
    BOOL ok = NO;
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    if (os.majorVersion != 27) fail(@"Supported cursor profile requires macOS 27; no cursor changes were made");
    else {
        NSDictionary *cape = loadCape(path);
        if (!cape) fail(@"Unable to read a valid cape file");
        NSDictionary *prepared = cape ? prepareCape(cape, NO) : nil;
        keys = prepared.count;
        if (prepared && loadAPIs(YES)) {
            @try {
                // AppKit requires an NSApplication instance to construct these
                // system cursors. Do not run or activate the application.
                [NSApplication sharedApplication];
                ok = validatePublicFactories(&factories);
                if (ok) for (NSString *name in [prepared.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                    if (!validateLiveCursor(name)) { ok = NO; break; }
                }
            } @catch (NSException *exception) {
                // Exception descriptions may contain paths or user content.
                fail(@"Public cursor factories could not be inspected safely"); ok = NO;
            }
        }
    }
    report(validationInfo(@"preflightPassed", ok, keys, factories)); return ok ? 0 : 1;
}
static void usage(void) {
    fprintf(stderr, "usage: neon-cursorctl snapshot DEST.cape [names.json]\n"
                    "       neon-cursorctl apply THEME.cape\n"
                    "       neon-cursorctl verify THEME.cape\n"
                    "       neon-cursorctl restore RAW-ORIGINAL.cape\n"
                    "       neon-cursorctl compare FIRST.cape SECOND.cape\n"
                    "       neon-cursorctl validate FILE.cape\n"
                    "       neon-cursorctl preflight THEME.cape\n");
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { usage(); return 2; }
        NSString *command = @(argv[1]), *path = @(argv[2]); int status = 2;
        if (([command isEqualToString:@"validate"] || [command isEqualToString:@"validate-file"]) && argc == 3) status = validateFile(path);
        else if ([command isEqualToString:@"preflight"] && argc == 3) status = preflight(path);
        else if ([command isEqualToString:@"compare"] && argc == 4) status = compareFiles(path, @(argv[3]));
        else if ([command isEqualToString:@"snapshot"] && (argc == 3 || argc == 4)) {
            if (loadAPIs(NO)) status = snapshot(path, argc == 4 ? @(argv[3]) : nil); else status = 1;
        } else if (([command isEqualToString:@"apply"] || [command isEqualToString:@"restore"] || [command isEqualToString:@"verify"]) && argc == 3) {
            BOOL restore = [command isEqualToString:@"restore"], writing = ![command isEqualToString:@"verify"];
            NSDictionary *cape = loadCape(path);
            // A restore must use a controller-produced raw snapshot, preventing
            // accidental use of Mousecape's downsampled/aliased dump as an original.
            if (restore && ![cape[@"NeonCursorctlRawVersion"] isEqual:@1]) { fail(@"restore requires an unmodified neon-cursorctl raw snapshot"); status = 1; }
            else {
                BOOL raw = restore || ([command isEqualToString:@"verify"] && [cape[@"NeonCursorctlRawVersion"] isEqual:@1]);
                NSDictionary *prepared = cape ? prepareCape(cape, raw) : nil;
                if (!prepared || !loadAPIs(writing)) status = 1;
                else status = writing ? writeCape(prepared) : verifyAll(prepared);
            }
        } else usage();
        if (status != 0 && lastError) fprintf(stderr, "%s\n", lastError.UTF8String);
        return status;
    }
}
