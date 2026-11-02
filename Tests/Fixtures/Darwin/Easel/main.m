// UIKit drawing: colors, image renderers and image contexts at a scale,
// Bézier paths, images and their PNG data, and views rendered through
// their layers: backgrounds, corner radii, borders, opacity, hidden views,
// clipping to bounds and -drawRect:. Rendered pixels are checked inside
// shapes against expected colors within a tolerance; edges differ between
// renderers. Recorded on the iOS Simulator.

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

/// RGBA (premultiplied) at x, y in pixels from the image's top left.
static uint32_t pixel(UIImage *image, int x, int y) {
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    uint8_t *buffer = calloc(width * height, 4);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(buffer, width, height, 8, width * 4, rgb,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    uint8_t *p = buffer + (size_t)y * width * 4 + (size_t)x * 4;
    uint32_t value = (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
    CGContextRelease(context);
    CGColorSpaceRelease(rgb);
    free(buffer);
    return value;
}

static int is(UIImage *image, int x, int y, uint32_t want, int tolerance) {
    uint32_t got = pixel(image, x, y);
    for (int shift = 0; shift < 32; shift += 8)
        if (abs((int)((got >> shift) & 0xff) - (int)((want >> shift) & 0xff)) > tolerance) return 0;
    return 1;
}

@interface Circle : UIView
@end

@implementation Circle
- (void)drawRect:(CGRect)rect {
    [[UIColor redColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:self.bounds] fill];
    say([NSString stringWithFormat:@"drawRect: %@, context %d", NSStringFromCGRect(rect), UIGraphicsGetCurrentContext() != NULL]);
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Colors.
        CGFloat r, g, b, a, w;
        [[UIColor colorWithRed:0.25 green:0.5 blue:0.75 alpha:1] getRed:&r green:&g blue:&b alpha:&a];
        say([NSString stringWithFormat:@"rgba: %.2f %.2f %.2f %.2f", r, g, b, a]);
        [[UIColor colorWithWhite:0.5 alpha:0.25] getWhite:&w alpha:&a];
        say([NSString stringWithFormat:@"white: %.2f %.2f", w, a]);
        [[UIColor.redColor colorWithAlphaComponent:0.5] getRed:&r green:&g blue:&b alpha:&a];
        say([NSString stringWithFormat:@"alpha component: %.2f %.2f %.2f %.2f, equal %d %d", r, g, b, a,
             [UIColor.redColor isEqual:[UIColor colorWithRed:1 green:0 blue:0 alpha:1]], [UIColor.redColor isEqual:UIColor.blueColor]]);
        NSArray *named = @[UIColor.blackColor, UIColor.whiteColor, UIColor.grayColor, UIColor.greenColor, UIColor.orangeColor,
                           UIColor.clearColor, UIColor.darkGrayColor, UIColor.lightGrayColor, UIColor.purpleColor];
        NSMutableArray *parts = [NSMutableArray array];
        for (UIColor *color in named) {
            [color getRed:&r green:&g blue:&b alpha:&a];
            [parts addObject:[NSString stringWithFormat:@"%.3f/%.3f/%.3f/%.1f", r, g, b, a]];
        }
        say([@"named: " stringByAppendingString:[parts componentsJoinedByString:@" "]]);
        const CGFloat *components = CGColorGetComponents(UIColor.redColor.CGColor);
        say([NSString stringWithFormat:@"cgcolor: %zu components, %.0f %.0f %.0f %.0f", CGColorGetNumberOfComponents(UIColor.redColor.CGColor),
             components[0], components[1], components[2], components[3]]);

        // An image renderer at scale 1: UIKit's coordinates, origin at the top left.
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40, 30) format:format];
        UIImage *drawn = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.redColor setFill];
            UIRectFill(CGRectMake(0, 0, 40, 30));
            [UIColor.blueColor setFill];
            [[UIBezierPath bezierPathWithRect:CGRectMake(0, 0, 10, 10)] fill];
            [UIColor.greenColor setStroke];
            UIBezierPath *line = [UIBezierPath bezierPath];
            [line moveToPoint:CGPointMake(0, 25)];
            [line addLineToPoint:CGPointMake(40, 25)];
            line.lineWidth = 4;
            [line stroke];
            [context fillRect:CGRectMake(30, 0, 10, 5)];
        }];
        say([NSString stringWithFormat:@"renderer: %@ scale %.0f, cg %zux%zu, top left blue %d, middle red %d, line green %d, last fill blue %d",
             NSStringFromCGSize(drawn.size), drawn.scale, CGImageGetWidth(drawn.CGImage), CGImageGetHeight(drawn.CGImage),
             is(drawn, 2, 2, 0x0000ffff, 0), is(drawn, 20, 15, 0xff0000ff, 0), is(drawn, 20, 25, 0x00ff00ff, 0), is(drawn, 35, 2, 0x0000ffff, 0)]);

        // An image context at scale 2.
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(20, 20), NO, 2);
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGAffineTransform ctm = CGContextGetCTM(context);
        [UIColor.orangeColor setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 20, 20)] fill];
        UIImage *oval = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        say([NSString stringWithFormat:@"context: %@ scale %.0f, cg %zux%zu, ctm %.0f %.0f %.0f %.0f, center %d, corner clear %d, after end %d",
             NSStringFromCGSize(oval.size), oval.scale, CGImageGetWidth(oval.CGImage), CGImageGetHeight(oval.CGImage), ctm.a, ctm.d,
             ctm.tx, ctm.ty, is(oval, 20, 20, 0xff8000ff, 2), is(oval, 1, 1, 0, 0), UIGraphicsGetCurrentContext() == NULL]);

        // PNG data and back.
        NSData *png = UIImagePNGRepresentation(drawn);
        UIImage *loaded = [UIImage imageWithData:png];
        NSData *jpeg = UIImageJPEGRepresentation(drawn, 0.9);
        say([NSString stringWithFormat:@"png: signature %d, loaded %@ scale %.0f, pixel red %d; jpeg %d, from cg %@",
             ((const uint8_t *)png.bytes)[1] == 'P', NSStringFromCGSize(loaded.size), loaded.scale, is(loaded, 20, 15, 0xff0000ff, 0),
             ((const uint8_t *)jpeg.bytes)[0] == 0xff, NSStringFromCGSize([UIImage imageWithCGImage:drawn.CGImage scale:2
                                                                                     orientation:UIImageOrientationUp].size)]);

        // Paths.
        UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(10, 10, 40, 20) cornerRadius:5];
        UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:CGPointMake(0, 0) radius:10 startAngle:0 endAngle:M_PI clockwise:YES];
        say([NSString stringWithFormat:@"paths: rounded %@ contains %d %d, arc %@, empty %d, line width %.0f", NSStringFromCGRect(rounded.bounds),
             [rounded containsPoint:CGPointMake(30, 20)], [rounded containsPoint:CGPointMake(10.5, 10.5)], NSStringFromCGRect(CGRectIntegral(arc.bounds)),
             [UIBezierPath bezierPath].isEmpty, [UIBezierPath bezierPath].lineWidth]);

        // Views drawn through their layers.
        UIView *root = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
        root.backgroundColor = UIColor.whiteColor;
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(10, 10, 40, 40)];
        card.backgroundColor = UIColor.greenColor;
        card.layer.cornerRadius = 10;
        card.layer.borderWidth = 4;
        card.layer.borderColor = UIColor.blackColor.CGColor;
        [root addSubview:card];
        UIView *faded = [[UIView alloc] initWithFrame:CGRectMake(50, 50, 40, 40)];
        faded.backgroundColor = UIColor.blueColor;
        faded.alpha = 0.5;
        [root addSubview:faded];
        UIView *hidden = [[UIView alloc] initWithFrame:CGRectMake(0, 60, 30, 30)];
        hidden.backgroundColor = UIColor.blackColor;
        hidden.hidden = YES;
        [root addSubview:hidden];
        Circle *circle = [[Circle alloc] initWithFrame:CGRectMake(60, 10, 30, 30)];
        circle.backgroundColor = UIColor.clearColor;
        [root addSubview:circle];
        UIView *clip = [[UIView alloc] initWithFrame:CGRectMake(10, 60, 30, 30)];
        clip.clipsToBounds = YES;
        clip.backgroundColor = UIColor.yellowColor;
        UIView *overflow = [[UIView alloc] initWithFrame:CGRectMake(20, 20, 30, 30)];
        overflow.backgroundColor = UIColor.purpleColor;
        [clip addSubview:overflow];
        [root addSubview:clip];
        say([NSString stringWithFormat:@"layers: delegate %d, sublayers %lu, card frame %@ position %@ anchor %@, masks %d",
             root.layer.delegate == root, (unsigned long)root.layer.sublayers.count, NSStringFromCGRect(card.layer.frame),
             NSStringFromCGPoint(card.layer.position), NSStringFromCGPoint(card.layer.anchorPoint), clip.layer.masksToBounds]);

        UIImage *rendered = [renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(100, 100) format:format]
                             imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [root.layer renderInContext:context.CGContext];
        }];
        say([NSString stringWithFormat:@"render: background %d, card %d, card corner shows white %d, border %d, faded %d, hidden not drawn %d",
             is(rendered, 5, 5, 0xffffffff, 0), is(rendered, 30, 30, 0x00ff00ff, 0), is(rendered, 11, 11, 0xffffffff, 8),
             is(rendered, 30, 11, 0x000000ff, 8), is(rendered, 70, 70, 0x7f7fffff, 2), is(rendered, 5, 85, 0xffffffff, 0)]);
        say([NSString stringWithFormat:@"  circle %d, circle corner clear %d, clipped yellow %d, overflow inside %d, overflow outside clipped %d",
             is(rendered, 75, 25, 0xff0000ff, 0), is(rendered, 61, 11, 0xffffffff, 8), is(rendered, 15, 65, 0xffff00ff, 0),
             is(rendered, 35, 85, 0x800080ff, 0), is(rendered, 45, 85, 0xffffffff, 0)]);
    }
    return 0;
}
