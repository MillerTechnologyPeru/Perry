// Layer trees for the compositor: each scene is one still frame of a
// 480x360 tree that uses one family of CALayer features (masks, shadows,
// gradients, text, image contents, transforms, ordering and opacity,
// corners, shapes, replicators). Perry's tests composite each and check
// the frame.
//
// PRISM_SCENE names the scene to show (default basics); PRISM_SECONDS, when
// set, is how long it stays up before the app exits. A class or method the
// scene needs that is not there is named on standard error and left out.
//
// It also builds for macOS, hosted by AppKit, to run on machines that run
// Mac slices; there the tree's origin is at the bottom left, so the frame is
// the iOS one upside down.
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#else
#import <UIKit/UIKit.h>
#endif
#import <QuartzCore/QuartzCore.h>

static CGColorRef rgba(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    static CGColorSpaceRef space;
    if (!space) space = CGColorSpaceCreateDeviceRGB();
    CGFloat components[] = {r, g, b, a};
    return CGColorCreate(space, components);
}
static CGColorRef rgb(CGFloat r, CGFloat g, CGFloat b) { return rgba(r, g, b, 1); }

static CALayer *box(CGRect frame, CGColorRef color) {
    CALayer *l = [CALayer layer];
    l.frame = frame;
    l.backgroundColor = color;
    return l;
}

static CGPathRef ellipse(CGRect rect) {
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddEllipseInRect(path, NULL, rect);
    return path;
}

static CGPathRef star(CGPoint c, CGFloat outer, CGFloat inner) {
    CGMutablePathRef path = CGPathCreateMutable();
    for (int i = 0; i < 10; i++) {
        CGFloat r = i % 2 ? inner : outer, a = M_PI / 5 * i - M_PI / 2;
        CGPoint p = CGPointMake(c.x + r * cos(a), c.y + r * sin(a));
        if (i) CGPathAddLineToPoint(path, NULL, p.x, p.y); else CGPathMoveToPoint(path, NULL, p.x, p.y);
    }
    CGPathCloseSubpath(path);
    return path;
}

/// A checkerboard with a red corner, so scaling, cropping and flips show.
static CGImageRef checker(size_t side, size_t cell) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, side, side, 8, side * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    for (size_t y = 0; y < side; y += cell)
        for (size_t x = 0; x < side; x += cell) {
            BOOL dark = ((x / cell) + (y / cell)) % 2;
            CGContextSetRGBFillColor(context, dark ? 0.15 : 0.9, dark ? 0.3 : 0.9, dark ? 0.6 : 0.85, 1);
            CGContextFillRect(context, CGRectMake(x, y, cell, cell));
        }
    CGContextSetRGBFillColor(context, 0.9, 0.1, 0.1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, cell * 2, cell));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return image;
}

// MARK: Scenes

static void basics(CALayer *root) {
    [root addSublayer:box(CGRectMake(20, 20, 120, 80), rgb(0.9, 0.2, 0.2))];
    CALayer *faded = box(CGRectMake(80, 60, 120, 80), rgb(0.1, 0.3, 0.9));
    faded.opacity = 0.5;
    [root addSublayer:faded];
    CALayer *rounded = box(CGRectMake(240, 20, 140, 90), rgb(0.2, 0.7, 0.3));
    rounded.cornerRadius = 20;
    rounded.borderWidth = 4;
    rounded.borderColor = rgb(0, 0, 0);
    [root addSublayer:rounded];
    CALayer *clipper = box(CGRectMake(20, 180, 140, 100), rgb(0.8, 0.8, 0.2));
    clipper.masksToBounds = YES;
    [clipper addSublayer:box(CGRectMake(90, 50, 120, 120), rgb(0.5, 0.1, 0.6))];
    [root addSublayer:clipper];
    CALayer *pill = box(CGRectMake(200, 180, 120, 100), rgb(0.2, 0.6, 0.8));
    pill.masksToBounds = YES;
    pill.cornerRadius = 30;
    [pill addSublayer:box(CGRectMake(60, 40, 120, 120), rgb(1, 0.5, 0))];
    [root addSublayer:pill];
    CALayer *turned = box(CGRectMake(350, 190, 90, 90), rgb(0.1, 0.1, 0.1));
    turned.affineTransform = CGAffineTransformMakeRotation(M_PI / 6);
    [root addSublayer:turned];
    CAShapeLayer *shape = [CAShapeLayer layer];
    shape.frame = CGRectMake(380, 20, 80, 80);
    shape.path = ellipse(CGRectMake(5, 5, 70, 70));
    shape.fillColor = rgb(1, 1, 1);
    shape.strokeColor = rgb(0.8, 0, 0.4);
    shape.lineWidth = 6;
    [root addSublayer:shape];
}

static void masks(CALayer *root) {
    // A shape as a mask, over sublayers.
    CALayer *starred = box(CGRectMake(20, 20, 140, 140), rgb(0.9, 0.3, 0.2));
    [starred addSublayer:box(CGRectMake(0, 70, 140, 70), rgb(0.2, 0.3, 0.9))];
    CAShapeLayer *starMask = [CAShapeLayer layer];
    starMask.frame = starred.bounds;
    starMask.path = star(CGPointMake(70, 70), 68, 30);
    starred.mask = starMask;
    [root addSublayer:starred];
    // A rounded layer as a mask.
    CALayer *rounded = box(CGRectMake(180, 20, 140, 140), rgb(0.2, 0.7, 0.4));
    CALayer *roundMask = box(CGRectMake(15, 15, 110, 110), rgb(0, 0, 0));
    roundMask.cornerRadius = 40;
    rounded.mask = roundMask;
    [root addSublayer:rounded];
    // A mask whose alpha fades the layer.
    CALayer *fading = box(CGRectMake(340, 20, 120, 140), rgb(0.1, 0.1, 0.1));
    CAGradientLayer *fade = [CAGradientLayer layer];
    fade.frame = fading.bounds;
    fade.colors = @[(__bridge id)rgba(0, 0, 0, 1), (__bridge id)rgba(0, 0, 0, 0)];
    fading.mask = fade;
    [root addSublayer:fading];
    // A masked layer that is turned, and one inside a clip.
    CALayer *turned = box(CGRectMake(40, 200, 120, 120), rgb(0.7, 0.2, 0.7));
    CAShapeLayer *circle = [CAShapeLayer layer];
    circle.frame = turned.bounds;
    circle.path = ellipse(CGRectMake(10, 30, 100, 60));
    turned.mask = circle;
    turned.affineTransform = CGAffineTransformMakeRotation(M_PI / 5);
    [root addSublayer:turned];
    CALayer *clip = box(CGRectMake(220, 200, 200, 120), rgb(0.85, 0.85, 0.6));
    clip.masksToBounds = YES;
    CALayer *inner = box(CGRectMake(100, 30, 160, 160), rgb(0.1, 0.5, 0.6));
    CAShapeLayer *innerMask = [CAShapeLayer layer];
    innerMask.frame = inner.bounds;
    innerMask.path = star(CGPointMake(80, 80), 78, 40);
    inner.mask = innerMask;
    [clip addSublayer:inner];
    [root addSublayer:clip];
}

static void shadows(CALayer *root) {
    CALayer *soft = box(CGRectMake(30, 30, 110, 80), rgb(1, 1, 1));
    soft.shadowOpacity = 0.5;
    soft.shadowRadius = 8;
    soft.shadowOffset = CGSizeMake(0, -6);
    [root addSublayer:soft];
    CALayer *hard = box(CGRectMake(180, 30, 110, 80), rgb(0.95, 0.8, 0.2));
    hard.shadowOpacity = 1;
    hard.shadowRadius = 0;
    hard.shadowOffset = CGSizeMake(10, -10);
    hard.shadowColor = rgb(0.2, 0.2, 0.6);
    [root addSublayer:hard];
    CALayer *rounded = box(CGRectMake(330, 30, 110, 80), rgb(0.3, 0.7, 0.9));
    rounded.cornerRadius = 24;
    rounded.shadowOpacity = 0.7;
    rounded.shadowRadius = 12;
    rounded.shadowOffset = CGSizeZero;
    [root addSublayer:rounded];
    // A shadow path of its own.
    CALayer *pathed = box(CGRectMake(40, 190, 120, 90), rgb(0.9, 0.4, 0.4));
    pathed.shadowOpacity = 0.6;
    pathed.shadowRadius = 4;
    pathed.shadowOffset = CGSizeZero;
    pathed.shadowPath = ellipse(CGRectMake(-10, -30, 140, 40));
    [root addSublayer:pathed];
    // A shape's shadow follows the shape; a faded layer's fades.
    CAShapeLayer *shape = [CAShapeLayer layer];
    shape.frame = CGRectMake(200, 180, 110, 110);
    shape.path = star(CGPointMake(55, 55), 52, 22);
    shape.fillColor = rgb(1, 0.8, 0);
    shape.shadowOpacity = 0.8;
    shape.shadowRadius = 6;
    shape.shadowOffset = CGSizeMake(4, -4);
    [root addSublayer:shape];
    CALayer *faded = box(CGRectMake(340, 190, 100, 90), rgb(0.2, 0.2, 0.2));
    faded.opacity = 0.4;
    faded.shadowOpacity = 1;
    faded.shadowRadius = 6;
    faded.shadowOffset = CGSizeMake(8, -8);
    [root addSublayer:faded];
}

static void gradients(CALayer *root) {
    NSArray *warm = @[(__bridge id)rgb(1, 0.9, 0.2), (__bridge id)rgb(0.9, 0.2, 0.1), (__bridge id)rgb(0.3, 0, 0.4)];
    CAGradientLayer *down = [CAGradientLayer layer];
    down.frame = CGRectMake(20, 20, 130, 140);
    down.colors = warm;
    [root addSublayer:down];
    CAGradientLayer *across = [CAGradientLayer layer];
    across.frame = CGRectMake(170, 20, 130, 140);
    across.colors = warm;
    across.startPoint = CGPointMake(0, 0.5);
    across.endPoint = CGPointMake(1, 0.5);
    across.locations = @[@0, @0.2, @1];
    [root addSublayer:across];
    CAGradientLayer *diagonal = [CAGradientLayer layer];
    diagonal.frame = CGRectMake(320, 20, 140, 140);
    diagonal.colors = @[(__bridge id)rgb(0.1, 0.6, 0.9), (__bridge id)rgba(0.1, 0.6, 0.9, 0)];
    diagonal.startPoint = CGPointMake(0, 0);
    diagonal.endPoint = CGPointMake(1, 1);
    diagonal.cornerRadius = 30;
    diagonal.borderWidth = 2;
    diagonal.borderColor = rgb(0, 0, 0);
    [root addSublayer:diagonal];
    CAGradientLayer *radial = [CAGradientLayer layer];
    radial.frame = CGRectMake(20, 190, 150, 150);
    radial.type = kCAGradientLayerRadial;
    radial.colors = @[(__bridge id)rgb(1, 1, 1), (__bridge id)rgb(0.1, 0.4, 0.2)];
    radial.startPoint = CGPointMake(0.5, 0.5);
    radial.endPoint = CGPointMake(1, 1);
    [root addSublayer:radial];
    CAGradientLayer *turned = [CAGradientLayer layer];
    turned.frame = CGRectMake(220, 210, 110, 110);
    turned.colors = warm;
    turned.affineTransform = CGAffineTransformMakeRotation(M_PI / 4);
    turned.opacity = 0.7;
    [root addSublayer:turned];
    CAGradientLayer *masked = [CAGradientLayer layer];
    masked.frame = CGRectMake(350, 200, 110, 130);
    masked.colors = warm;
    masked.cornerRadius = 55;
    masked.masksToBounds = YES;
    [masked addSublayer:box(CGRectMake(0, 0, 110, 30), rgb(0, 0, 0))];
    [root addSublayer:masked];
}

static CATextLayer *text(NSString *string, CGRect frame, CGFloat size) {
    CATextLayer *l = [CATextLayer layer];
    l.frame = frame;
    l.string = string;
    l.fontSize = size;
    l.foregroundColor = rgb(0.1, 0.1, 0.1);
    l.contentsScale = 1;
    return l;
}

static void texts(CALayer *root) {
    if (!NSClassFromString(@"CATextLayer")) { fprintf(stderr, "prism: no CATextLayer\n"); return; }
    [root addSublayer:text(@"Plain text layer", CGRectMake(20, 300, 220, 30), 20)];
    CATextLayer *centered = text(@"Centered", CGRectMake(20, 250, 220, 30), 20);
    centered.alignmentMode = kCAAlignmentCenter;
    centered.backgroundColor = rgb(0.9, 0.9, 0.6);
    [root addSublayer:centered];
    CATextLayer *right = text(@"Right, in red", CGRectMake(20, 200, 220, 30), 20);
    right.alignmentMode = kCAAlignmentRight;
    right.foregroundColor = rgb(0.8, 0.1, 0.1);
    [root addSublayer:right];
    CATextLayer *wrapped = text(@"Wrapped text that runs over more than one line of its layer", CGRectMake(20, 90, 200, 90), 16);
    wrapped.wrapped = YES;
    wrapped.backgroundColor = rgb(0.8, 0.9, 1);
    [root addSublayer:wrapped];
    CATextLayer *cut = text(@"Truncated at the end of the layer", CGRectMake(20, 40, 200, 26), 16);
    cut.truncationMode = kCATruncationEnd;
    [root addSublayer:cut];
    CATextLayer *big = text(@"Big", CGRectMake(260, 230, 200, 100), 72);
    big.foregroundColor = rgb(0.2, 0.3, 0.7);
    [root addSublayer:big];
    CATextLayer *turned = text(@"Turned", CGRectMake(280, 120, 160, 40), 28);
    turned.affineTransform = CGAffineTransformMakeRotation(-M_PI / 8);
    turned.backgroundColor = rgb(1, 0.85, 0.3);
    [root addSublayer:turned];
    CATextLayer *faded = text(@"Faded, on a rounded tile", CGRectMake(250, 30, 210, 40), 16);
    faded.opacity = 0.5;
    faded.cornerRadius = 12;
    faded.backgroundColor = rgb(0.2, 0.2, 0.2);
    faded.foregroundColor = rgb(1, 1, 1);
    [root addSublayer:faded];
}

static void contents(CALayer *root) {
    CGImageRef image = checker(64, 8);
    NSArray *gravities = @[kCAGravityResize, kCAGravityResizeAspect, kCAGravityResizeAspectFill, kCAGravityCenter,
                           kCAGravityTopLeft, kCAGravityBottomRight, kCAGravityLeft, kCAGravityTop];
    for (NSUInteger i = 0; i < gravities.count; i++) {
        CALayer *l = box(CGRectMake(15 + (i % 4) * 116, 200 - (i / 4) * 100, 104, 84), rgb(0.8, 0.8, 0.8));
        l.contents = (__bridge id)image;
        l.contentsGravity = gravities[i];
        l.masksToBounds = i % 2;
        l.magnificationFilter = kCAFilterNearest;
        [root addSublayer:l];
    }
    // A part of the image, flipped contents, and contents under corners.
    CALayer *part = box(CGRectMake(15, 290, 104, 60), rgb(0.8, 0.8, 0.8));
    part.contents = (__bridge id)image;
    part.contentsRect = CGRectMake(0, 0, 0.5, 0.25);
    part.magnificationFilter = kCAFilterNearest;
    [root addSublayer:part];
    CALayer *flipped = box(CGRectMake(131, 290, 104, 60), rgb(0.8, 0.8, 0.8));
    flipped.contents = (__bridge id)image;
    flipped.contentsGravity = kCAGravityResizeAspect;
    if ([flipped respondsToSelector:@selector(setGeometryFlipped:)]) flipped.geometryFlipped = YES;
    else fprintf(stderr, "prism: no -[CALayer setGeometryFlipped:]\n");
    flipped.magnificationFilter = kCAFilterNearest;
    [root addSublayer:flipped];
    CALayer *cornered = box(CGRectMake(247, 290, 104, 60), rgb(0.8, 0.8, 0.8));
    cornered.contents = (__bridge id)image;
    cornered.cornerRadius = 20;
    cornered.masksToBounds = YES;
    cornered.borderWidth = 3;
    cornered.borderColor = rgb(0, 0, 0);
    cornered.magnificationFilter = kCAFilterNearest;
    [root addSublayer:cornered];
    CALayer *smooth = box(CGRectMake(363, 290, 104, 60), rgb(0.8, 0.8, 0.8));
    smooth.contents = (__bridge id)image;
    smooth.opacity = 0.6;
    [root addSublayer:smooth];
    CGImageRelease(image);
}

static void transforms(CALayer *root) {
    CALayer *scaled = box(CGRectMake(30, 250, 80, 60), rgb(0.9, 0.3, 0.3));
    scaled.affineTransform = CGAffineTransformMakeScale(1.4, 0.6);
    [root addSublayer:scaled];
    // Turned about a corner, with a child that turns again.
    CALayer *anchored = box(CGRectMake(170, 240, 100, 70), rgb(0.3, 0.6, 0.9));
    anchored.anchorPoint = CGPointMake(0, 0);
    anchored.position = CGPointMake(170, 240);
    anchored.affineTransform = CGAffineTransformMakeRotation(M_PI / 10);
    CALayer *child = box(CGRectMake(50, 20, 50, 50), rgb(1, 0.9, 0.2));
    child.affineTransform = CGAffineTransformMakeRotation(M_PI / 4);
    [anchored addSublayer:child];
    [root addSublayer:anchored];
    // A skew, and a mirror.
    CALayer *skewed = box(CGRectMake(330, 250, 90, 60), rgb(0.3, 0.8, 0.4));
    skewed.affineTransform = CGAffineTransformMake(1, 0, 0.5, 1, 0, 0);
    skewed.borderWidth = 3;
    skewed.borderColor = rgb(0, 0, 0);
    [root addSublayer:skewed];
    // A sublayer transform moves the children, not the layer.
    CALayer *parent = box(CGRectMake(30, 110, 140, 100), rgb(0.85, 0.85, 0.85));
    parent.sublayerTransform = CATransform3DMakeAffineTransform(CGAffineTransformMakeRotation(M_PI / 12));
    [parent addSublayer:box(CGRectMake(20, 20, 50, 40), rgb(0.6, 0.2, 0.7))];
    [parent addSublayer:box(CGRectMake(80, 40, 50, 40), rgb(0.9, 0.5, 0.1))];
    [root addSublayer:parent];
    // A clip that is turned, with a child past its edge.
    CALayer *clip = box(CGRectMake(210, 110, 110, 90), rgb(0.95, 0.9, 0.6));
    clip.masksToBounds = YES;
    clip.affineTransform = CGAffineTransformMakeRotation(-M_PI / 9);
    [clip addSublayer:box(CGRectMake(60, 40, 100, 100), rgb(0.1, 0.4, 0.5))];
    [root addSublayer:clip];
    // Perspective: turned about the vertical axis.
    CALayer *deep = box(CGRectMake(350, 110, 100, 90), rgb(0.2, 0.2, 0.25));
    CATransform3D perspective = CATransform3DIdentity;
    perspective.m34 = -1.0 / 300;
    deep.transform = CATransform3DRotate(perspective, M_PI / 4, 0, 1, 0);
    [deep addSublayer:box(CGRectMake(10, 10, 40, 40), rgb(1, 1, 1))];
    [root addSublayer:deep];
    // Turned about the depth axis by a 3D transform, and scaled down.
    CALayer *spun = box(CGRectMake(40, 20, 90, 60), rgb(0.8, 0.2, 0.5));
    spun.transform = CATransform3DConcat(CATransform3DMakeRotation(M_PI / 7, 0, 0, 1), CATransform3DMakeScale(0.8, 0.8, 1));
    [root addSublayer:spun];
    CALayer *moved = box(CGRectMake(200, 20, 90, 60), rgb(0.2, 0.5, 0.3));
    moved.transform = CATransform3DMakeTranslation(40, 10, 0);
    moved.cornerRadius = 12;
    [root addSublayer:moved];
}

static void ordering(CALayer *root) {
    // zPosition reorders siblings; equal ones keep their order.
    CALayer *back = box(CGRectMake(20, 220, 100, 100), rgb(0.9, 0.2, 0.2));
    CALayer *middle = box(CGRectMake(60, 190, 100, 100), rgb(0.2, 0.8, 0.3));
    CALayer *front = box(CGRectMake(100, 160, 100, 100), rgb(0.2, 0.3, 0.9));
    back.zPosition = 2;
    front.zPosition = -1;
    [root addSublayer:back];
    [root addSublayer:middle];
    [root addSublayer:front];
    // Hidden layers and their children draw nothing.
    CALayer *hidden = box(CGRectMake(240, 220, 100, 100), rgb(0, 0, 0));
    hidden.hidden = YES;
    [hidden addSublayer:box(CGRectMake(20, 20, 60, 60), rgb(1, 0, 0))];
    [root addSublayer:hidden];
    // Inserted below and above.
    CALayer *first = box(CGRectMake(240, 230, 90, 90), rgb(0.95, 0.75, 0.1));
    [root addSublayer:first];
    [root insertSublayer:box(CGRectMake(280, 200, 90, 90), rgb(0.5, 0.1, 0.6)) below:first];
    [root insertSublayer:box(CGRectMake(320, 250, 90, 60), rgb(0.1, 0.6, 0.6)) above:first];
    // A faded parent fades its overlapping children as one.
    CALayer *group = box(CGRectMake(20, 20, 200, 110), rgba(0, 0, 0, 0));
    group.opacity = 0.5;
    [group addSublayer:box(CGRectMake(0, 0, 120, 80), rgb(0.9, 0.1, 0.1))];
    [group addSublayer:box(CGRectMake(70, 30, 120, 80), rgb(0.1, 0.1, 0.9))];
    [root addSublayer:group];
    // Faded twice, and a faded border.
    CALayer *outer = box(CGRectMake(250, 20, 200, 110), rgb(0.2, 0.2, 0.2));
    outer.opacity = 0.6;
    CALayer *inner = box(CGRectMake(20, 20, 160, 70), rgb(1, 1, 1));
    inner.opacity = 0.5;
    inner.borderWidth = 6;
    inner.borderColor = rgba(0.9, 0.2, 0.2, 0.5);
    [outer addSublayer:inner];
    [root addSublayer:outer];
}

static void corners(CALayer *root) {
    NSArray *masks = @[@(kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner), @(kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner),
                       @(kCALayerMinXMinYCorner | kCALayerMaxXMaxYCorner), @(kCALayerMaxXMinYCorner)];
    for (NSUInteger i = 0; i < masks.count; i++) {
        CALayer *l = box(CGRectMake(20 + i * 115, 250, 100, 80), rgb(0.2, 0.5 + i * 0.1, 0.8 - i * 0.15));
        l.cornerRadius = 24;
        l.maskedCorners = [masks[i] unsignedIntegerValue];
        l.borderWidth = i % 2 ? 4 : 0;
        l.borderColor = rgb(0, 0, 0);
        l.masksToBounds = i >= 2;
        if (i >= 2) [l addSublayer:box(CGRectMake(50, -10, 70, 50), rgb(1, 0.6, 0.1))];
        [root addSublayer:l];
    }
    // A circle, a continuous curve, and a radius past half the side.
    CALayer *circle = box(CGRectMake(20, 130, 90, 90), rgb(0.9, 0.3, 0.4));
    circle.cornerRadius = 45;
    circle.borderWidth = 8;
    circle.borderColor = rgba(0, 0, 0, 0.4);
    [root addSublayer:circle];
    CALayer *smooth = box(CGRectMake(135, 130, 90, 90), rgb(0.3, 0.7, 0.5));
    smooth.cornerRadius = 30;
    smooth.cornerCurve = kCACornerCurveContinuous;
    [root addSublayer:smooth];
    CALayer *over = box(CGRectMake(250, 150, 110, 50), rgb(0.6, 0.4, 0.9));
    over.cornerRadius = 80;
    [root addSublayer:over];
    // Rounded clips nested in each other, and one that is turned.
    CALayer *outer = box(CGRectMake(20, 20, 160, 90), rgb(0.2, 0.2, 0.2));
    outer.cornerRadius = 28;
    outer.masksToBounds = YES;
    CALayer *inner = box(CGRectMake(40, -20, 160, 90), rgb(0.9, 0.9, 0.3));
    inner.cornerRadius = 28;
    inner.masksToBounds = YES;
    [inner addSublayer:box(CGRectMake(60, 30, 120, 90), rgb(0.9, 0.2, 0.2))];
    [outer addSublayer:inner];
    [root addSublayer:outer];
    CALayer *turned = box(CGRectMake(240, 30, 110, 70), rgb(0.1, 0.5, 0.7));
    turned.cornerRadius = 20;
    turned.masksToBounds = YES;
    turned.affineTransform = CGAffineTransformMakeRotation(M_PI / 8);
    [turned addSublayer:box(CGRectMake(55, 0, 80, 35), rgb(1, 1, 1))];
    [root addSublayer:turned];
    CALayer *bordered = box(CGRectMake(380, 130, 80, 90), rgba(0, 0, 0, 0));
    bordered.cornerRadius = 16;
    bordered.borderWidth = 10;
    bordered.borderColor = rgb(0.9, 0.5, 0.1);
    [root addSublayer:bordered];
}

static CAShapeLayer *stroke(CGPathRef path, CGRect frame, CGFloat width) {
    CAShapeLayer *l = [CAShapeLayer layer];
    l.frame = frame;
    l.path = path;
    l.fillColor = NULL;
    l.strokeColor = rgb(0.1, 0.2, 0.6);
    l.lineWidth = width;
    return l;
}

static void shapes(CALayer *root) {
    CAShapeLayer *dashed = stroke(ellipse(CGRectMake(10, 10, 100, 80)), CGRectMake(20, 240, 120, 100), 5);
    dashed.lineDashPattern = @[@12, @6];
    [root addSublayer:dashed];
    CAShapeLayer *partial = stroke(ellipse(CGRectMake(10, 10, 100, 80)), CGRectMake(170, 240, 120, 100), 10);
    partial.strokeStart = 0.1;
    partial.strokeEnd = 0.7;
    partial.lineCap = kCALineCapRound;
    partial.strokeColor = rgb(0.9, 0.3, 0.1);
    [root addSublayer:partial];
    CAShapeLayer *evenOdd = [CAShapeLayer layer];
    evenOdd.frame = CGRectMake(320, 230, 130, 120);
    evenOdd.path = star(CGPointMake(65, 60), 58, 22);
    CGMutablePathRef pentagram = CGPathCreateMutable();
    for (int i = 0; i < 5; i++) {
        CGFloat a = M_PI * 4 / 5 * i - M_PI / 2;
        CGPoint p = CGPointMake(65 + 58 * cos(a), 60 + 58 * sin(a));
        if (i) CGPathAddLineToPoint(pentagram, NULL, p.x, p.y); else CGPathMoveToPoint(pentagram, NULL, p.x, p.y);
    }
    CGPathCloseSubpath(pentagram);
    evenOdd.path = pentagram;
    evenOdd.fillRule = kCAFillRuleEvenOdd;
    evenOdd.fillColor = rgb(0.6, 0.2, 0.7);
    [root addSublayer:evenOdd];
    // Joins and caps on an open path.
    CGMutablePathRef zigzag = CGPathCreateMutable();
    CGPathMoveToPoint(zigzag, NULL, 10, 20);
    CGPathAddLineToPoint(zigzag, NULL, 45, 80);
    CGPathAddLineToPoint(zigzag, NULL, 80, 20);
    CGPathAddLineToPoint(zigzag, NULL, 115, 80);
    NSArray *joins = @[kCALineJoinMiter, kCALineJoinRound, kCALineJoinBevel];
    NSArray *caps = @[kCALineCapButt, kCALineCapRound, kCALineCapSquare];
    for (NSUInteger i = 0; i < 3; i++) {
        CAShapeLayer *l = stroke(zigzag, CGRectMake(20 + i * 150, 120, 130, 100), 14);
        l.lineJoin = joins[i];
        l.lineCap = caps[i];
        l.strokeColor = rgb(0.2, 0.6 - i * 0.2, 0.3 + i * 0.3);
        [root addSublayer:l];
    }
    // Curves, filled and stroked, faded; and a shape under a transform.
    CGMutablePathRef curve = CGPathCreateMutable();
    CGPathMoveToPoint(curve, NULL, 10, 10);
    CGPathAddCurveToPoint(curve, NULL, 60, 110, 120, -40, 190, 60);
    CGPathAddQuadCurveToPoint(curve, NULL, 120, 100, 10, 10);
    CAShapeLayer *filled = [CAShapeLayer layer];
    filled.frame = CGRectMake(20, 20, 200, 90);
    filled.path = curve;
    filled.fillColor = rgba(0.95, 0.7, 0.1, 0.8);
    filled.strokeColor = rgb(0.4, 0.2, 0);
    filled.lineWidth = 3;
    filled.opacity = 0.8;
    [root addSublayer:filled];
    CAShapeLayer *turned = stroke(star(CGPointMake(50, 45), 44, 18), CGRectMake(280, 20, 100, 90), 4);
    turned.fillColor = rgb(0.9, 0.9, 0.9);
    turned.affineTransform = CGAffineTransformMakeRotation(M_PI / 10);
    turned.backgroundColor = rgb(0.75, 0.85, 1);
    [root addSublayer:turned];
}

static void replicated(CALayer *root) {
    CAReplicatorLayer *row = [CAReplicatorLayer layer];
    row.frame = CGRectMake(20, 240, 440, 100);
    row.instanceCount = 8;
    row.instanceTransform = CATransform3DMakeTranslation(52, 0, 0);
    row.instanceAlphaOffset = -0.11;
    [row addSublayer:box(CGRectMake(0, 20, 44, 60), rgb(0.2, 0.5, 0.9))];
    [root addSublayer:row];
    CAReplicatorLayer *ring = [CAReplicatorLayer layer];
    ring.frame = CGRectMake(40, 30, 180, 180);
    ring.instanceCount = 12;
    ring.instanceTransform = CATransform3DMakeRotation(M_PI / 6, 0, 0, 1);
    ring.instanceColor = rgb(1, 1, 1);
    ring.instanceRedOffset = -0.07;
    CALayer *dot = box(CGRectMake(80, 150, 20, 20), rgb(1, 0.8, 0.2));
    dot.cornerRadius = 10;
    [ring addSublayer:dot];
    [root addSublayer:ring];
    // A layer that draws itself through its delegate-less display: tiled
    // children in a scroll layer's clip.
    if (!NSClassFromString(@"CAScrollLayer")) { fprintf(stderr, "prism: no CAScrollLayer\n"); return; }
    CAScrollLayer *scroll = [CAScrollLayer layer];
    scroll.frame = CGRectMake(260, 40, 190, 160);
    scroll.backgroundColor = rgb(0.9, 0.9, 0.9);
    for (int i = 0; i < 6; i++)
        [scroll addSublayer:box(CGRectMake(i * 50, i * 40, 90, 60), rgb(0.9 - i * 0.12, 0.3, 0.2 + i * 0.12))];
    [scroll scrollToPoint:CGPointMake(60, 50)];
    [root addSublayer:scroll];
}

// MARK: Hosts

/// Builds the named scene in `root`; NO when there is no such scene.
static BOOL build(NSString *name, CALayer *root) {
    NSDictionary<NSString *, void (^)(CALayer *)> *scenes = @{
        @"basics": ^(CALayer *l) { basics(l); }, @"masks": ^(CALayer *l) { masks(l); },
        @"shadows": ^(CALayer *l) { shadows(l); }, @"gradients": ^(CALayer *l) { gradients(l); },
        @"texts": ^(CALayer *l) { texts(l); }, @"contents": ^(CALayer *l) { contents(l); },
        @"transforms": ^(CALayer *l) { transforms(l); }, @"ordering": ^(CALayer *l) { ordering(l); },
        @"corners": ^(CALayer *l) { corners(l); }, @"shapes": ^(CALayer *l) { shapes(l); },
        @"replicated": ^(CALayer *l) { replicated(l); },
    };
    void (^scene)(CALayer *) = scenes[name];
    if (!scene) {
        fprintf(stderr, "prism: no scene %s; scenes: %s\n", name.UTF8String,
                [[scenes.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "].UTF8String);
        return NO;
    }
    root.backgroundColor = rgb(0.95, 0.95, 0.9);
    scene(root);
    printf("scene %s\n", name.UTF8String);
    fflush(stdout);
    const char *seconds = getenv("PRISM_SECONDS");
    if (seconds) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(atof(seconds) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            exit(0);
        });
    }
    return YES;
}

static NSString *sceneName(void) {
    const char *named = getenv("PRISM_SCENE");
    return named ? @(named) : @"basics";
}

#if TARGET_OS_OSX

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 480, 360)
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                         backing:NSBackingStoreBuffered defer:NO];
        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 360)];
        view.wantsLayer = YES;
        if (!build(sceneName(), view.layer)) return 2;
        window.contentView = view;
        [window makeKeyAndOrderFront:nil];
        [app run];
    }
    return 0;
}

#else

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.blackColor;
    // The scene keeps its size whatever the screen's, at the top left.
    CALayer *root = [CALayer layer];
    root.frame = CGRectMake(0, 0, 480, 360);
    [controller.view.layer addSublayer:root];
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    if (!build(sceneName(), root)) exit(2);
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}

#endif
