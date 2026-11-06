// A spinning cube in OpenGL ES 1, as iOS 3's OpenGL template drew one: a
// view whose layer is a CAEAGLLayer, an EAGLContext for ES 1, a framebuffer
// whose color renderbuffer is the layer's and whose depth buffer is its
// own, the fixed-function matrices, lighting off, vertex and color arrays,
// and a timer that turns the cube and presents each frame. Its GL calls
// with floats (glClearColor, glFrustumf, glTranslatef, glRotatef) pass them
// as 32-bit Darwin does. Without arguments it draws 30 frames, reads back
// the middle pixel, which a face covers, and exits; with "stay" it keeps
// spinning. There is no armv7 SDK, so UIKit and OpenGL ES are declared here.
#include "darwin.h"
typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef signed char BOOL;
#define nil ((id)0)
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#if __LP64__
typedef double CGFloat;
typedef unsigned long NSUInteger;
#else
typedef float CGFloat;
typedef unsigned int NSUInteger;
#endif
typedef struct CGPoint { CGFloat x, y; } CGPoint;
typedef struct CGSize { CGFloat width, height; } CGSize;
typedef struct CGRect { CGPoint origin; CGSize size; } CGRect;

typedef unsigned int GLenum, GLuint, GLbitfield;
typedef int GLint, GLsizei;
typedef float GLfloat;
typedef unsigned char GLubyte;
enum {
    GL_DEPTH_BUFFER_BIT = 0x100, GL_COLOR_BUFFER_BIT = 0x4000, GL_TRIANGLES = 4, GL_DEPTH_TEST = 0x0B71,
    GL_CULL_FACE = 0x0B44, GL_UNSIGNED_BYTE = 0x1401, GL_FLOAT = 0x1406, GL_MODELVIEW = 0x1700,
    GL_PROJECTION = 0x1701, GL_RGBA = 0x1908, GL_VERTEX_ARRAY = 0x8074, GL_COLOR_ARRAY = 0x8076,
    GL_FRAMEBUFFER_OES = 0x8D40, GL_RENDERBUFFER_OES = 0x8D41, GL_RENDERBUFFER_WIDTH_OES = 0x8D42,
    GL_RENDERBUFFER_HEIGHT_OES = 0x8D43, GL_COLOR_ATTACHMENT0_OES = 0x8CE0, GL_DEPTH_ATTACHMENT_OES = 0x8D00,
    GL_DEPTH_COMPONENT16_OES = 0x81A5, GL_FRAMEBUFFER_COMPLETE_OES = 0x8CD5,
};
void glGenFramebuffersOES(GLsizei, GLuint *);
void glGenRenderbuffersOES(GLsizei, GLuint *);
void glBindFramebufferOES(GLenum, GLuint);
void glBindRenderbufferOES(GLenum, GLuint);
void glFramebufferRenderbufferOES(GLenum, GLenum, GLenum, GLuint);
void glRenderbufferStorageOES(GLenum, GLenum, GLsizei, GLsizei);
void glGetRenderbufferParameterivOES(GLenum, GLenum, GLint *);
GLenum glCheckFramebufferStatusOES(GLenum);
GLenum glGetError(void);
const GLubyte *glGetString(GLenum);
void glViewport(GLint, GLint, GLsizei, GLsizei);
void glClearColor(GLfloat, GLfloat, GLfloat, GLfloat);
void glClear(GLbitfield);
void glEnable(GLenum);
void glMatrixMode(GLenum);
void glLoadIdentity(void);
void glFrustumf(GLfloat, GLfloat, GLfloat, GLfloat, GLfloat, GLfloat);
void glTranslatef(GLfloat, GLfloat, GLfloat);
void glRotatef(GLfloat, GLfloat, GLfloat, GLfloat);
void glEnableClientState(GLenum);
void glVertexPointer(GLint, GLenum, GLsizei, const void *);
void glColorPointer(GLint, GLenum, GLsizei, const void *);
void glDrawElements(GLenum, GLsizei, GLenum, const void *);
void glReadPixels(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *);

@class NSString, NSDictionary, UIWindow, UIViewController, UIApplication, CALayer;

__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)alloc;
- (instancetype)init;
+ (Class)class;
@end

@interface NSTimer : NSObject
+ (NSTimer *)scheduledTimerWithTimeInterval:(double)seconds target:(id)target selector:(SEL)selector
                                   userInfo:(id)userInfo repeats:(BOOL)repeats;
@end

@interface CALayer : NSObject
@property (getter=isOpaque) BOOL opaque;
@end

@interface CAEAGLLayer : CALayer
@end

@interface EAGLContext : NSObject
- (instancetype)initWithAPI:(NSUInteger)api;
+ (BOOL)setCurrentContext:(EAGLContext *)context;
- (BOOL)renderbufferStorage:(NSUInteger)target fromDrawable:(CAEAGLLayer *)drawable;
- (BOOL)presentRenderbuffer:(NSUInteger)target;
@end

@interface UIResponder : NSObject
@end

@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
@property (readonly) CGRect bounds;
@end

@interface UIView : UIResponder
- (instancetype)initWithFrame:(CGRect)frame;
@property (readonly) CALayer *layer;
@property CGRect bounds;
@property NSUInteger autoresizingMask;
@end

@interface UIWindow : UIView
@property (retain) UIViewController *rootViewController;
- (void)makeKeyAndVisible;
@end

@interface UIViewController : UIResponder
@property (retain) UIView *view;
- (void)loadView;
@end

int UIApplicationMain(int argc, char *argv[], NSString *principal, NSString *delegate);

static BOOL stay;

// A cube's eight corners, each its own color, and its twelve triangles,
// counterclockwise seen from outside.
static const GLfloat corners[] = {
    -1, -1, -1,   1, -1, -1,   1, 1, -1,   -1, 1, -1,
    -1, -1, 1,    1, -1, 1,    1, 1, 1,    -1, 1, 1,
};
static const GLubyte colors[] = {
    40, 40, 40, 255,     255, 60, 60, 255,    255, 220, 60, 255,   60, 220, 90, 255,
    60, 90, 255, 255,    230, 80, 255, 255,   255, 255, 255, 255,  60, 230, 240, 255,
};
static const GLubyte triangles[] = {
    4, 5, 6,  4, 6, 7,    1, 0, 3,  1, 3, 2,    5, 1, 2,  5, 2, 6,
    0, 4, 7,  0, 7, 3,    7, 6, 2,  7, 2, 3,    0, 1, 5,  0, 5, 4,
};

@interface CubeView : UIView
@property (nonatomic, retain) EAGLContext *context;
@property (nonatomic) int frames;
@end

@implementation CubeView {
    GLuint framebuffer, colorBuffer, depthBuffer;
    GLint width, height;
}

+ (Class)layerClass { return [CAEAGLLayer class]; }

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
    self.layer.opaque = YES;
    self.context = [[EAGLContext alloc] initWithAPI:1];
    printf("context %d current %d\n", self.context != nil, [EAGLContext setCurrentContext:self.context]);

    glGenFramebuffersOES(1, &framebuffer);
    glGenRenderbuffersOES(1, &colorBuffer);
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, framebuffer);
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorBuffer);
    BOOL storage = [self.context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer *)self.layer];
    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, colorBuffer);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &width);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &height);

    glGenRenderbuffersOES(1, &depthBuffer);
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthBuffer);
    glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, width, height);
    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthBuffer);
    printf("storage %d size %d complete %d\n", storage, width > 0 && height > 0,
           glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) == GL_FRAMEBUFFER_COMPLETE_OES);
    fflush(stdout);

    [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 target:self selector:@selector(draw:) userInfo:nil repeats:YES];
    return self;
}

- (void)draw:(NSTimer *)timer {
    [EAGLContext setCurrentContext:self.context];
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, framebuffer);
    glViewport(0, 0, width, height);
    glClearColor(0.08f, 0.1f, 0.16f, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);

    // A frustum as wide as the view is, so the cube stays a cube.
    GLfloat aspect = (GLfloat)width / (GLfloat)height;
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glFrustumf(-aspect, aspect, -1, 1, 2, 20);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glTranslatef(0, 0, -6);
    glRotatef(30 + self.frames * 1.5f, 1, 0, 0);
    glRotatef(self.frames * 2.0f, 0, 1, 0);

    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
    glVertexPointer(3, GL_FLOAT, 0, corners);
    glColorPointer(4, GL_UNSIGNED_BYTE, 0, colors);
    glDrawElements(GL_TRIANGLES, 36, GL_UNSIGNED_BYTE, triangles);

    self.frames++;
    if (!stay && self.frames == 30) {
        // The cube covers the middle of the view; the background is dark.
        GLubyte pixel[4] = { 0, 0, 0, 0 };
        glReadPixels(width >> 1, height >> 1, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        GLubyte corner[4] = { 0, 0, 0, 0 };
        glReadPixels(2, 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, corner);
        printf("frames %d error %d\n", self.frames, glGetError());
        printf("middle is the cube %d, corner is the background %d\n", pixel[0] + pixel[1] + pixel[2] > 120,
               corner[0] == 20 && corner[1] == 26 && corner[2] == 41);
    }
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorBuffer);
    BOOL presented = [self.context presentRenderbuffer:GL_RENDERBUFFER_OES];
    if (!stay && self.frames == 30) {
        printf("presented %d\n", presented);
        exit(0);
    }
}

@end

@interface CubeController : UIViewController
@end

@implementation CubeController
- (void)loadView {
    CubeView *view = [[CubeView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    view.autoresizingMask = 18;
    self.view = view;
}
@end

@interface AppDelegate : UIResponder
@property (nonatomic, retain) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[CubeController alloc] init];
    [self.window makeKeyAndVisible];
    printf("launched\n");
    fflush(stdout);
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        stay = argc > 1 && strcmp(argv[1], "stay") == 0;
        return UIApplicationMain(argc, argv, nil, @"AppDelegate");
    }
}
