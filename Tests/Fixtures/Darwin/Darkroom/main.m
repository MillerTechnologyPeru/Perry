// Images: CGImage from bytes, bitmap contexts with fills and drawn images,
// cropping, and ImageIO reading and writing PNG, JPEG and GIF with their
// properties and thumbnails. JPEG is lossy and its encoders differ, so its
// pixels are compared within a tolerance. Recorded on the iOS Simulator.

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#include <stdio.h>
#include <stdlib.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *describeImage(CGImageRef image) {
    CGColorSpaceRef space = CGImageGetColorSpace(image);
    return [NSString stringWithFormat:@"%zux%zu bpc %zu bpp %zu alpha %u info 0x%x space %zu/%d", CGImageGetWidth(image),
            CGImageGetHeight(image), CGImageGetBitsPerComponent(image), CGImageGetBitsPerPixel(image),
            CGImageGetAlphaInfo(image), CGImageGetBitmapInfo(image),
            space ? CGColorSpaceGetNumberOfComponents(space) : 0, space ? CGColorSpaceGetModel(space) : -1];
}

/// The image's pixel at x, y as RGBA, drawn into a known format.
static uint32_t pixel(CGImageRef image, size_t x, size_t y) {
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    uint8_t *buffer = calloc(width * height, 4);
    CGContextRef context = CGBitmapContextCreate(buffer, width, height, 8, width * 4, rgb,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    uint8_t *p = buffer + y * width * 4 + x * 4;
    uint32_t value = (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
    CGContextRelease(context);
    CGColorSpaceRelease(rgb);
    free(buffer);
    return value;
}

static BOOL near(uint32_t a, uint32_t b, int tolerance) {
    for (int shift = 0; shift < 32; shift += 8) {
        if (abs((int)((a >> shift) & 0xff) - (int)((b >> shift) & 0xff)) > tolerance) return NO;
    }
    return YES;
}

static NSString *properties(NSDictionary *props, NSArray *keys) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in keys) [parts addObject:[NSString stringWithFormat:@"%@=%@", key, props[key] ?: @"-"]];
    return [parts componentsJoinedByString:@" "];
}

static NSArray *commonKeys(void) {
    return @[(__bridge NSString *)kCGImagePropertyPixelWidth, (__bridge NSString *)kCGImagePropertyPixelHeight,
             (__bridge NSString *)kCGImagePropertyDepth, (__bridge NSString *)kCGImagePropertyColorModel,
             (__bridge NSString *)kCGImagePropertyHasAlpha, (__bridge NSString *)kCGImagePropertyOrientation];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // A 4x3 image from bytes: red, green, blue, white columns; the last
        // row half-transparent black.
        uint8_t bytes[4 * 3 * 4];
        const uint8_t colors[4][4] = {{255, 0, 0, 255}, {0, 255, 0, 255}, {0, 0, 255, 255}, {255, 255, 255, 255}};
        for (int y = 0; y < 3; y++) {
            for (int x = 0; x < 4; x++) {
                uint8_t *p = bytes + (y * 4 + x) * 4;
                if (y == 2) { p[0] = p[1] = p[2] = 0; p[3] = 128; }
                else memcpy(p, colors[x], 4);
            }
        }
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, bytes, sizeof(bytes), NULL);
        CGImageRef image = CGImageCreate(4, 3, 8, 32, 16, rgb, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big, provider,
                                         NULL, false, kCGRenderingIntentDefault);
        say([NSString stringWithFormat:@"image: %@ row %zu, type %d", describeImage(image), CGImageGetBytesPerRow(image),
             CFGetTypeID(image) == CGImageGetTypeID()]);
        say([NSString stringWithFormat:@"pixels: %08x %08x %08x %08x", pixel(image, 0, 0), pixel(image, 1, 0), pixel(image, 3, 1),
             pixel(image, 2, 2)]);
        CFDataRef copied = CGDataProviderCopyData(CGImageGetDataProvider(image));
        say([NSString stringWithFormat:@"provider: %ld bytes, first %d", (long)CFDataGetLength(copied), CFDataGetBytePtr(copied)[0]]);
        CFRelease(copied);
        say([NSString stringWithFormat:@"spaces: rgb %zu model %d, gray %zu model %d, srgb %zu", CGColorSpaceGetNumberOfComponents(rgb),
             CGColorSpaceGetModel(rgb), CGColorSpaceGetNumberOfComponents(CGColorSpaceCreateDeviceGray()),
             CGColorSpaceGetModel(CGColorSpaceCreateDeviceGray()),
             CGColorSpaceGetNumberOfComponents(CGColorSpaceCreateWithName(kCGColorSpaceSRGB))]);

        CGImageRef cropped = CGImageCreateWithImageInRect(image, CGRectMake(1, 0, 2, 2));
        say([NSString stringWithFormat:@"cropped: %zux%zu %08x %08x", CGImageGetWidth(cropped), CGImageGetHeight(cropped),
             pixel(cropped, 0, 0), pixel(cropped, 1, 1)]);

        // A bitmap context: filled, then the image drawn at an offset.
        CGContextRef context = CGBitmapContextCreate(NULL, 8, 6, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
        say([NSString stringWithFormat:@"context: %zux%zu row %zu bpc %zu bpp %zu alpha %u, data %d", CGBitmapContextGetWidth(context),
             CGBitmapContextGetHeight(context), CGBitmapContextGetBytesPerRow(context), CGBitmapContextGetBitsPerComponent(context),
             CGBitmapContextGetBitsPerPixel(context), CGBitmapContextGetAlphaInfo(context), CGBitmapContextGetData(context) != NULL]);
        CGContextSetRGBFillColor(context, 1, 1, 0, 1);
        CGContextFillRect(context, CGRectMake(0, 0, 8, 6));
        CGContextSetRGBFillColor(context, 0, 0, 1, 0.5);
        CGContextFillRect(context, CGRectMake(0, 0, 2, 2));
        CGContextDrawImage(context, CGRectMake(4, 3, 4, 3), image);
        CGImageRef snapshot = CGBitmapContextCreateImage(context);
        say([NSString stringWithFormat:@"drawn: %@ / %08x %08x %08x %08x %08x", describeImage(snapshot), pixel(snapshot, 0, 0),
             pixel(snapshot, 0, 5), pixel(snapshot, 4, 0), pixel(snapshot, 7, 1), pixel(snapshot, 5, 2)]);
        CGContextClearRect(context, CGRectMake(0, 0, 8, 6));
        say([NSString stringWithFormat:@"cleared: %08x", ((uint32_t *)CGBitmapContextGetData(context))[0]]);

        // PNG.
        say([NSString stringWithFormat:@"types: png %d jpeg %d gif %d heic %d", [(__bridge NSArray *)CGImageDestinationCopyTypeIdentifiers()
             containsObject:@"public.png"], [(__bridge NSArray *)CGImageSourceCopyTypeIdentifiers() containsObject:@"public.jpeg"],
             [(__bridge NSArray *)CGImageSourceCopyTypeIdentifiers() containsObject:@"com.compuserve.gif"],
             [(__bridge NSArray *)CGImageSourceCopyTypeIdentifiers() containsObject:@"public.heic"]]);
        NSMutableData *png = [NSMutableData data];
        CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, CFSTR("public.png"), 1, NULL);
        CGImageDestinationAddImage(destination, image, NULL);
        BOOL finalized = CGImageDestinationFinalize(destination);
        const uint8_t *signature = png.bytes;
        say([NSString stringWithFormat:@"png written: %d, signature %02x%02x%02x%02x", finalized, signature[0], signature[1], signature[2], signature[3]]);
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)png, NULL);
        NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
        say([NSString stringWithFormat:@"png read: type %@ count %zu status %d, %@", CGImageSourceGetType(source), CGImageSourceGetCount(source),
             CGImageSourceGetStatus(source), properties(props, commonKeys())]);
        CGImageRef decoded = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        say([NSString stringWithFormat:@"png image: %@ / %08x %08x %08x %08x", describeImage(decoded), pixel(decoded, 0, 0), pixel(decoded, 1, 0),
             pixel(decoded, 3, 1), pixel(decoded, 2, 2)]);

        // JPEG, with an orientation.
        NSMutableData *jpeg = [NSMutableData data];
        destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)jpeg, CFSTR("public.jpeg"), 1, NULL);
        CGImageRef solid = CGBitmapContextCreateImage(context);
        CGContextRef flat = CGBitmapContextCreate(NULL, 16, 16, 8, 0, rgb, kCGImageAlphaNoneSkipLast);
        CGContextSetRGBFillColor(flat, 0.2, 0.4, 0.8, 1);
        CGContextFillRect(flat, CGRectMake(0, 0, 16, 16));
        CGImageRef blue = CGBitmapContextCreateImage(flat);
        CGImageDestinationAddImage(destination, blue, (__bridge CFDictionaryRef)@{
            (__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @0.9,
            (__bridge NSString *)kCGImagePropertyOrientation: @6});
        say([NSString stringWithFormat:@"jpeg written: %d, starts %02x%02x", CGImageDestinationFinalize(destination),
             ((const uint8_t *)jpeg.bytes)[0], ((const uint8_t *)jpeg.bytes)[1]]);
        source = CGImageSourceCreateWithData((__bridge CFDataRef)jpeg, NULL);
        props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
        decoded = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        say([NSString stringWithFormat:@"jpeg read: type %@ count %zu, %@, image %zux%zu alpha %u, close %d", CGImageSourceGetType(source),
             CGImageSourceGetCount(source), properties(props, commonKeys()), CGImageGetWidth(decoded), CGImageGetHeight(decoded),
             CGImageGetAlphaInfo(decoded), near(pixel(decoded, 8, 8), pixel(blue, 8, 8), 6)]);

        // GIF, two frames with delays.
        NSMutableData *gif = [NSMutableData data];
        destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)gif, CFSTR("com.compuserve.gif"), 2, NULL);
        CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImagePropertyGIFDictionary:
            @{(__bridge NSString *)kCGImagePropertyGIFLoopCount: @0}});
        NSDictionary *frame = @{(__bridge NSString *)kCGImagePropertyGIFDictionary: @{(__bridge NSString *)kCGImagePropertyGIFDelayTime: @0.5}};
        CGImageDestinationAddImage(destination, blue, (__bridge CFDictionaryRef)frame);
        CGImageDestinationAddImage(destination, solid, (__bridge CFDictionaryRef)frame);
        say([NSString stringWithFormat:@"gif written: %d", CGImageDestinationFinalize(destination)]);
        source = CGImageSourceCreateWithData((__bridge CFDataRef)gif, NULL);
        NSDictionary *first = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
        NSDictionary *second = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 1, NULL));
        NSDictionary *container = CFBridgingRelease(CGImageSourceCopyProperties(source, NULL));
        say([NSString stringWithFormat:@"gif read: type %@ count %zu, sizes %@x%@ %@x%@, delay %@, loop %@, frame color %d",
             CGImageSourceGetType(source), CGImageSourceGetCount(source), first[(__bridge NSString *)kCGImagePropertyPixelWidth],
             first[(__bridge NSString *)kCGImagePropertyPixelHeight], second[(__bridge NSString *)kCGImagePropertyPixelWidth],
             second[(__bridge NSString *)kCGImagePropertyPixelHeight],
             first[(__bridge NSString *)kCGImagePropertyGIFDictionary][(__bridge NSString *)kCGImagePropertyGIFDelayTime],
             container[(__bridge NSString *)kCGImagePropertyGIFDictionary][(__bridge NSString *)kCGImagePropertyGIFLoopCount],
             near(pixel(CGImageSourceCreateImageAtIndex(source, 0, NULL), 3, 3), pixel(blue, 3, 3), 24)]);

        // Thumbnails.
        CGContextRef big = CGBitmapContextCreate(NULL, 40, 30, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
        CGContextSetRGBFillColor(big, 0, 1, 0, 1);
        CGContextFillRect(big, CGRectMake(0, 0, 40, 30));
        NSMutableData *bigPNG = [NSMutableData data];
        destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)bigPNG, CFSTR("public.png"), 1, NULL);
        CGImageDestinationAddImage(destination, CGBitmapContextCreateImage(big), NULL);
        CGImageDestinationFinalize(destination);
        source = CGImageSourceCreateWithData((__bridge CFDataRef)bigPNG, NULL);
        for (NSNumber *size in @[@10, @16, @100]) {
            CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
                (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: size});
            say([NSString stringWithFormat:@"thumbnail %@: %zux%zu %08x", size, CGImageGetWidth(thumbnail), CGImageGetHeight(thumbnail),
                 pixel(thumbnail, 0, 0)]);
        }
        CGImageRef none = CGImageSourceCreateThumbnailAtIndex(source, 0, NULL);
        say([NSString stringWithFormat:@"thumbnail without options: %d", none != NULL]);

        // Not an image.
        NSData *junk = [@"not an image at all" dataUsingEncoding:NSUTF8StringEncoding];
        CGImageSourceRef bad = CGImageSourceCreateWithData((__bridge CFDataRef)junk, NULL);
        say([NSString stringWithFormat:@"junk: source %d type %@ count %zu status %d image %d", bad != NULL, CGImageSourceGetType(bad),
             CGImageSourceGetCount(bad), CGImageSourceGetStatus(bad), CGImageSourceCreateImageAtIndex(bad, 0, NULL) != NULL]);
        say([NSString stringWithFormat:@"bad destination: %d", CGImageDestinationCreateWithData((__bridge CFMutableDataRef)[NSMutableData data],
             CFSTR("public.plain-text"), 1, NULL) != NULL]);
    }
    return 0;
}
