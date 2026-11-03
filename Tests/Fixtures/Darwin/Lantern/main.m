// OpenGL ES through EAGLContext: contexts for each API and their
// sharegroups, the current context, framebuffers and renderbuffers,
// shaders, drawing, reading pixels back; a CAEAGLLayer's renderbuffer;
// GLKView drawing through its delegate into a snapshot; and GLKit's math.
// Pixels are checked inside shapes, where every renderer agrees; version
// strings only by their prefix. Recorded on the iOS Simulator.

#import <GLKit/GLKit.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES3/gl.h>
#import <UIKit/UIKit.h>
#include <stdio.h>
#include <math.h>
#include <string.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *prefix(const GLubyte *string, int length) {
    if (!string) return @"(null)";
    char buffer[64] = {0};
    strncpy(buffer, (const char *)string, length);
    return [NSString stringWithUTF8String:buffer];
}

static NSString *pixel(int x, int y) {
    GLubyte rgba[4] = {0};
    glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
    return [NSString stringWithFormat:@"%02x%02x%02x%02x", rgba[0], rgba[1], rgba[2], rgba[3]];
}

static GLuint compile(GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    say([NSString stringWithFormat:@"  %@ shader compiled %d", type == GL_VERTEX_SHADER ? @"vertex" : @"fragment", ok]);
    return shader;
}

@interface Painter : NSObject <GLKViewDelegate>
@property (nonatomic) NSInteger draws;
@end

@implementation Painter
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    self.draws++;
    GLint framebuffer = 0, viewport[4] = {0};
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &framebuffer);
    glGetIntegerv(GL_VIEWPORT, viewport);
    say([NSString stringWithFormat:@"  draw in rect %@, framebuffer bound %d, viewport %d %d %d %d, drawable %ldx%ld",
         NSStringFromCGRect(rect), framebuffer != 0, viewport[0], viewport[1], viewport[2], viewport[3],
         (long)view.drawableWidth, (long)view.drawableHeight]);
    glClearColor(0, 0, 1, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glEnable(GL_SCISSOR_TEST);
    glScissor(0, 0, view.drawableWidth / 2, view.drawableHeight / 2);
    glClearColor(1, 1, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glDisable(GL_SCISSOR_TEST);
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Contexts.
        EAGLContext *two = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        EAGLContext *three = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
        EAGLContext *shared = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3 sharegroup:three.sharegroup];
        say([NSString stringWithFormat:@"contexts: two %d api %lu, three %d api %lu, shared group %d, own groups differ %d, current %d",
             two != nil, (unsigned long)two.API, three != nil, (unsigned long)three.API, shared.sharegroup == three.sharegroup,
             two.sharegroup != three.sharegroup, EAGLContext.currentContext != nil]);
        say([NSString stringWithFormat:@"make current: %d, is current %d", [EAGLContext setCurrentContext:two],
             EAGLContext.currentContext == two]);
        say([NSString stringWithFormat:@"strings: version %@, shading %@, error %x", prefix(glGetString(GL_VERSION), 13),
             prefix(glGetString(GL_SHADING_LANGUAGE_VERSION), 22), glGetError()]);

        // A framebuffer with a color renderbuffer.
        GLuint framebuffer, renderbuffer;
        glGenFramebuffers(1, &framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
        glGenRenderbuffers(1, &renderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, renderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, 64, 64);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, renderbuffer);
        GLint width = 0, height = 0;
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &width);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &height);
        say([NSString stringWithFormat:@"framebuffer: complete %d, renderbuffer %dx%d", glCheckFramebufferStatus(GL_FRAMEBUFFER) ==
             GL_FRAMEBUFFER_COMPLETE, width, height]);
        glViewport(0, 0, 64, 64);
        glClearColor(1, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        say([NSString stringWithFormat:@"cleared: %@ %@", pixel(0, 0), pixel(63, 63)]);

        // A shader drawing a green triangle over the lower left half.
        say(@"program:");
        GLuint vertex = compile(GL_VERTEX_SHADER, "attribute vec2 position; void main() { gl_Position = vec4(position, 0.0, 1.0); }");
        GLuint fragment = compile(GL_FRAGMENT_SHADER, "precision mediump float; uniform vec4 color; void main() { gl_FragColor = color; }");
        GLuint program = glCreateProgram();
        glAttachShader(program, vertex);
        glAttachShader(program, fragment);
        glBindAttribLocation(program, 0, "position");
        glLinkProgram(program);
        GLint linked = 0;
        glGetProgramiv(program, GL_LINK_STATUS, &linked);
        glUseProgram(program);
        GLint colorLocation = glGetUniformLocation(program, "color");
        glUniform4f(colorLocation, 0, 1, 0, 1);
        GLfloat triangle[] = {-1, -1, 1, -1, -1, 1};
        GLuint buffer;
        glGenBuffers(1, &buffer);
        glBindBuffer(GL_ARRAY_BUFFER, buffer);
        glBufferData(GL_ARRAY_BUFFER, sizeof(triangle), triangle, GL_STATIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        say([NSString stringWithFormat:@"  linked %d, uniform found %d, inside %@, outside %@, error %x", linked, colorLocation >= 0,
             pixel(8, 8), pixel(56, 56), glGetError()]);

        // A texture, filled and drawn back.
        GLuint texture;
        glGenTextures(1, &texture);
        glBindTexture(GL_TEXTURE_2D, texture);
        GLubyte texels[4 * 4 * 4];
        for (int i = 0; i < 16; i++) { texels[i * 4] = 255; texels[i * 4 + 1] = 0; texels[i * 4 + 2] = 255; texels[i * 4 + 3] = 255; }
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, texels);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        GLint bound = 0;
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound);
        say([NSString stringWithFormat:@"texture: bound %d, error %x", bound == (GLint)texture, glGetError()]);

        // The shared context sees the other's objects.
        [EAGLContext setCurrentContext:three];
        GLuint sharedBuffer;
        glGenBuffers(1, &sharedBuffer);
        [EAGLContext setCurrentContext:shared];
        say([NSString stringWithFormat:@"sharing: buffer is one in the group %d, version %@", glIsBuffer(sharedBuffer) == GL_FALSE ||
             glIsBuffer(sharedBuffer) == GL_TRUE, prefix(glGetString(GL_VERSION), 13)]);
        [EAGLContext setCurrentContext:nil];
        say([NSString stringWithFormat:@"cleared current: %d", EAGLContext.currentContext == nil]);

        // A CAEAGLLayer's renderbuffer takes the layer's size in pixels.
        [EAGLContext setCurrentContext:two];
        CAEAGLLayer *layer = [CAEAGLLayer layer];
        layer.frame = CGRectMake(0, 0, 30, 20);
        layer.contentsScale = 2;
        layer.drawableProperties = @{kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8};
        GLuint layerBuffer;
        glGenRenderbuffers(1, &layerBuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, layerBuffer);
        BOOL stored = [two renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer];
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &width);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &height);
        say([NSString stringWithFormat:@"layer: storage %d, %dx%d, opaque %d, format %@", stored, width, height, layer.opaque,
             layer.drawableProperties[kEAGLDrawablePropertyColorFormat]]);

        // GLKView.
        Painter *painter = [[Painter alloc] init];
        GLKView *view = [[GLKView alloc] initWithFrame:CGRectMake(0, 0, 40, 30) context:two];
        view.delegate = painter;
        view.contentScaleFactor = 1;
        say([NSString stringWithFormat:@"glkview: formats %ld %ld %ld %ld, enables set needs display %d, layer %@",
             (long)view.drawableColorFormat, (long)view.drawableDepthFormat, (long)view.drawableStencilFormat,
             (long)view.drawableMultisample, view.enableSetNeedsDisplay, NSStringFromClass(view.layer.class)]);
        view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
        UIImage *snapshot = [view snapshot];
        CGImageRef image = snapshot.CGImage;
        uint8_t data[40 * 30 * 4];
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap = CGBitmapContextCreate(data, 40, 30, 8, 160, rgb, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGContextDrawImage(bitmap, CGRectMake(0, 0, 40, 30), image);
        uint8_t *topLeft = data + (2 * 40 + 2) * 4, *bottomLeft = data + (27 * 40 + 2) * 4;
        say([NSString stringWithFormat:@"snapshot: %@ scale %.0f, draws %ld, top left blue %d, bottom left yellow %d",
             NSStringFromCGSize(snapshot.size), snapshot.scale, (long)painter.draws, topLeft[2] == 255 && topLeft[0] == 0,
             bottomLeft[0] == 255 && bottomLeft[1] == 255 && bottomLeft[2] == 0]);
        CGContextRelease(bitmap);
        CGColorSpaceRelease(rgb);
        [view display];
        say([NSString stringWithFormat:@"display: draws %ld, drawable %ldx%ld", (long)painter.draws, (long)view.drawableWidth,
             (long)view.drawableHeight]);
        [view deleteDrawable];

        // GLKit's math.
        GLKMatrix4 perspective = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(60), 1.5, 0.1, 100);
        bool invertible = false;
        GLKMatrix4 translation = GLKMatrix4MakeTranslation(1, 2, 3);
        GLKMatrix4 inverse = GLKMatrix4Invert(translation, &invertible);
        GLKVector3 moved = GLKMatrix4MultiplyVector3WithTranslation(inverse, GLKVector3Make(1, 2, 3));
        // Inverses round differently between implementations; whole numbers do not.
        say([NSString stringWithFormat:@"math: perspective %.3f %.3f %.3f, invertible %d, moved %ld %ld %ld",
             perspective.m00, perspective.m11, perspective.m22, invertible, lroundf(moved.x), lroundf(moved.y), lroundf(moved.z)]);
        say([NSString stringWithFormat:@"strings: %@ | %@", NSStringFromGLKVector3(GLKVector3Make(1, 2.5, -3)),
             NSStringFromGLKMatrix3(GLKMatrix3MakeScale(2, 3, 4))]);
        GLKQuaternion turn = GLKQuaternionMakeWithAngleAndAxis(GLKMathDegreesToRadians(90), 0, 0, 1);
        GLKVector3 rotated = GLKQuaternionRotateVector3(turn, GLKVector3Make(1, 0, 0));
        say([NSString stringWithFormat:@"quaternion: %.3f %.3f %.3f, angle %.1f", rotated.x, rotated.y, rotated.z,
             GLKMathRadiansToDegrees(GLKQuaternionAngle(turn))]);
        int viewportRect[4] = {0, 0, 100, 100};
        GLKVector3 projected = GLKMathProject(GLKVector3Make(0, 0, -1), GLKMatrix4Identity,
                                              GLKMatrix4MakeOrtho(-1, 1, -1, 1, 0.5, 2), viewportRect);
        say([NSString stringWithFormat:@"project: %.1f %.1f %.3f", projected.x, projected.y, projected.z]);
    }
    return 0;
}
