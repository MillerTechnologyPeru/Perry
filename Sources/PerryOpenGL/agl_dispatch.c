// AGL's dispatch table: an AGLContext starts with its renderer and a
// GLIFunctionDispatch, OpenGL's functions in the order of OpenGL.framework's
// gliDispatch.h (Mac OS X 10.5), which programs built with AGL/aglMacro.h
// call through as ctx->disp.name(ctx->rend, ...) (Age of Empires III). Each
// entry here leaves the renderer out and calls the OpenGL function of its
// name, found through the loader the first time, on the current context;
// one the host lacks does nothing and answers zero. Generated from the
// header's list; its order is the ABI.

#include <stdint.h>
#include <stddef.h>

typedef unsigned int GLenum, GLuint, GLbitfield;
typedef int GLint, GLsizei;
typedef unsigned char GLboolean, GLubyte;
typedef signed char GLbyte;
typedef short GLshort;
typedef unsigned short GLushort;
typedef float GLfloat, GLclampf;
typedef double GLdouble, GLclampd;
typedef void GLvoid;
typedef char GLchar, GLcharARB;
typedef void *GLhandleARB;
typedef intptr_t GLintptr, GLintptrARB, GLsizeiptr, GLsizeiptrARB;
typedef void *GLIContext;

void *perry_opengl_lookup(const char *library, const char *name);

#define OPENGL "/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL"

/// The OpenGL function of a Mach-O name, looked up once.
static void *resolve(void **slot, int *looked, const char *name) {
    if (!*looked) {
        *slot = perry_opengl_lookup(OPENGL, name);
        *looked = 1;
    }
    return *slot;
}

static void d_accum(GLIContext ctx, GLenum op, GLfloat value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glAccum");
    if (found) ((void (*)(GLenum op, GLfloat value))found)(op, value);
}

static void d_alpha_func(GLIContext ctx, GLenum func, GLclampf ref) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glAlphaFunc");
    if (found) ((void (*)(GLenum func, GLclampf ref))found)(func, ref);
}

static GLboolean d_are_textures_resident(GLIContext ctx, GLsizei n, const GLuint *textures, GLboolean *residences) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glAreTexturesResident");
    return found ? ((GLboolean (*)(GLsizei n, const GLuint *textures, GLboolean *residences))found)(n, textures, residences) : 0;
}

static void d_array_element(GLIContext ctx, GLint i) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glArrayElement");
    if (found) ((void (*)(GLint i))found)(i);
}

static void d_begin(GLIContext ctx, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBegin");
    if (found) ((void (*)(GLenum mode))found)(mode);
}

static void d_bind_texture(GLIContext ctx, GLenum target, GLuint texture) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBindTexture");
    if (found) ((void (*)(GLenum target, GLuint texture))found)(target, texture);
}

static void d_bitmap(GLIContext ctx, GLsizei width, GLsizei height, GLfloat xorig, GLfloat yorig, GLfloat xmove, GLfloat ymove, const GLubyte *bitmap) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBitmap");
    if (found) ((void (*)(GLsizei width, GLsizei height, GLfloat xorig, GLfloat yorig, GLfloat xmove, GLfloat ymove, const GLubyte *bitmap))found)(width, height, xorig, yorig, xmove, ymove, bitmap);
}

static void d_blend_func(GLIContext ctx, GLenum sfactor, GLenum dfactor) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBlendFunc");
    if (found) ((void (*)(GLenum sfactor, GLenum dfactor))found)(sfactor, dfactor);
}

static void d_call_list(GLIContext ctx, GLuint list) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCallList");
    if (found) ((void (*)(GLuint list))found)(list);
}

static void d_call_lists(GLIContext ctx, GLsizei n, GLenum type, const GLvoid *lists) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCallLists");
    if (found) ((void (*)(GLsizei n, GLenum type, const GLvoid *lists))found)(n, type, lists);
}

static void d_clear(GLIContext ctx, GLbitfield mask) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glClear");
    if (found) ((void (*)(GLbitfield mask))found)(mask);
}

static void d_clear_accum(GLIContext ctx, GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glClearAccum");
    if (found) ((void (*)(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha))found)(red, green, blue, alpha);
}

static void d_clear_color(GLIContext ctx, GLclampf red, GLclampf green, GLclampf blue, GLclampf alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glClearColor");
    if (found) ((void (*)(GLclampf red, GLclampf green, GLclampf blue, GLclampf alpha))found)(red, green, blue, alpha);
}

static void d_clear_depth(GLIContext ctx, GLclampd depth) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glClearDepth");
    if (found) ((void (*)(GLclampd depth))found)(depth);
}

static void d_clear_index(GLIContext ctx, GLfloat c) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glClearIndex");
    if (found) ((void (*)(GLfloat c))found)(c);
}

static void d_clear_stencil(GLIContext ctx, GLint s) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glClearStencil");
    if (found) ((void (*)(GLint s))found)(s);
}

static void d_clip_plane(GLIContext ctx, GLenum plane, const GLdouble *equation) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glClipPlane");
    if (found) ((void (*)(GLenum plane, const GLdouble *equation))found)(plane, equation);
}

static void d_color3b(GLIContext ctx, GLbyte red, GLbyte green, GLbyte blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3b");
    if (found) ((void (*)(GLbyte red, GLbyte green, GLbyte blue))found)(red, green, blue);
}

static void d_color3bv(GLIContext ctx, const GLbyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3bv");
    if (found) ((void (*)(const GLbyte *v))found)(v);
}

static void d_color3d(GLIContext ctx, GLdouble red, GLdouble green, GLdouble blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3d");
    if (found) ((void (*)(GLdouble red, GLdouble green, GLdouble blue))found)(red, green, blue);
}

static void d_color3dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_color3f(GLIContext ctx, GLfloat red, GLfloat green, GLfloat blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3f");
    if (found) ((void (*)(GLfloat red, GLfloat green, GLfloat blue))found)(red, green, blue);
}

static void d_color3fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_color3i(GLIContext ctx, GLint red, GLint green, GLint blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3i");
    if (found) ((void (*)(GLint red, GLint green, GLint blue))found)(red, green, blue);
}

static void d_color3iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_color3s(GLIContext ctx, GLshort red, GLshort green, GLshort blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3s");
    if (found) ((void (*)(GLshort red, GLshort green, GLshort blue))found)(red, green, blue);
}

static void d_color3sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_color3ub(GLIContext ctx, GLubyte red, GLubyte green, GLubyte blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3ub");
    if (found) ((void (*)(GLubyte red, GLubyte green, GLubyte blue))found)(red, green, blue);
}

static void d_color3ubv(GLIContext ctx, const GLubyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3ubv");
    if (found) ((void (*)(const GLubyte *v))found)(v);
}

static void d_color3ui(GLIContext ctx, GLuint red, GLuint green, GLuint blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3ui");
    if (found) ((void (*)(GLuint red, GLuint green, GLuint blue))found)(red, green, blue);
}

static void d_color3uiv(GLIContext ctx, const GLuint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3uiv");
    if (found) ((void (*)(const GLuint *v))found)(v);
}

static void d_color3us(GLIContext ctx, GLushort red, GLushort green, GLushort blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3us");
    if (found) ((void (*)(GLushort red, GLushort green, GLushort blue))found)(red, green, blue);
}

static void d_color3usv(GLIContext ctx, const GLushort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor3usv");
    if (found) ((void (*)(const GLushort *v))found)(v);
}

static void d_color4b(GLIContext ctx, GLbyte red, GLbyte green, GLbyte blue, GLbyte alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4b");
    if (found) ((void (*)(GLbyte red, GLbyte green, GLbyte blue, GLbyte alpha))found)(red, green, blue, alpha);
}

static void d_color4bv(GLIContext ctx, const GLbyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4bv");
    if (found) ((void (*)(const GLbyte *v))found)(v);
}

static void d_color4d(GLIContext ctx, GLdouble red, GLdouble green, GLdouble blue, GLdouble alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4d");
    if (found) ((void (*)(GLdouble red, GLdouble green, GLdouble blue, GLdouble alpha))found)(red, green, blue, alpha);
}

static void d_color4dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_color4f(GLIContext ctx, GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4f");
    if (found) ((void (*)(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha))found)(red, green, blue, alpha);
}

static void d_color4fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_color4i(GLIContext ctx, GLint red, GLint green, GLint blue, GLint alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4i");
    if (found) ((void (*)(GLint red, GLint green, GLint blue, GLint alpha))found)(red, green, blue, alpha);
}

static void d_color4iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_color4s(GLIContext ctx, GLshort red, GLshort green, GLshort blue, GLshort alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4s");
    if (found) ((void (*)(GLshort red, GLshort green, GLshort blue, GLshort alpha))found)(red, green, blue, alpha);
}

static void d_color4sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_color4ub(GLIContext ctx, GLubyte red, GLubyte green, GLubyte blue, GLubyte alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4ub");
    if (found) ((void (*)(GLubyte red, GLubyte green, GLubyte blue, GLubyte alpha))found)(red, green, blue, alpha);
}

static void d_color4ubv(GLIContext ctx, const GLubyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4ubv");
    if (found) ((void (*)(const GLubyte *v))found)(v);
}

static void d_color4ui(GLIContext ctx, GLuint red, GLuint green, GLuint blue, GLuint alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4ui");
    if (found) ((void (*)(GLuint red, GLuint green, GLuint blue, GLuint alpha))found)(red, green, blue, alpha);
}

static void d_color4uiv(GLIContext ctx, const GLuint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4uiv");
    if (found) ((void (*)(const GLuint *v))found)(v);
}

static void d_color4us(GLIContext ctx, GLushort red, GLushort green, GLushort blue, GLushort alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4us");
    if (found) ((void (*)(GLushort red, GLushort green, GLushort blue, GLushort alpha))found)(red, green, blue, alpha);
}

static void d_color4usv(GLIContext ctx, const GLushort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColor4usv");
    if (found) ((void (*)(const GLushort *v))found)(v);
}

static void d_color_mask(GLIContext ctx, GLboolean red, GLboolean green, GLboolean blue, GLboolean alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColorMask");
    if (found) ((void (*)(GLboolean red, GLboolean green, GLboolean blue, GLboolean alpha))found)(red, green, blue, alpha);
}

static void d_color_material(GLIContext ctx, GLenum face, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColorMaterial");
    if (found) ((void (*)(GLenum face, GLenum mode))found)(face, mode);
}

static void d_color_pointer(GLIContext ctx, GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColorPointer");
    if (found) ((void (*)(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer))found)(size, type, stride, pointer);
}

static void d_copy_pixels(GLIContext ctx, GLint x, GLint y, GLsizei width, GLsizei height, GLenum type) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCopyPixels");
    if (found) ((void (*)(GLint x, GLint y, GLsizei width, GLsizei height, GLenum type))found)(x, y, width, height, type);
}

static void d_copy_tex_image1D(GLIContext ctx, GLenum target, GLint level, GLenum internalFormat, GLint x, GLint y, GLsizei width, GLint border) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCopyTexImage1D");
    if (found) ((void (*)(GLenum target, GLint level, GLenum internalFormat, GLint x, GLint y, GLsizei width, GLint border))found)(target, level, internalFormat, x, y, width, border);
}

static void d_copy_tex_image2D(GLIContext ctx, GLenum target, GLint level, GLenum internalFormat, GLint x, GLint y, GLsizei width, GLsizei height, GLint border) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCopyTexImage2D");
    if (found) ((void (*)(GLenum target, GLint level, GLenum internalFormat, GLint x, GLint y, GLsizei width, GLsizei height, GLint border))found)(target, level, internalFormat, x, y, width, height, border);
}

static void d_copy_tex_sub_image1D(GLIContext ctx, GLenum target, GLint level, GLint xoffset, GLint x, GLint y, GLsizei width) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCopyTexSubImage1D");
    if (found) ((void (*)(GLenum target, GLint level, GLint xoffset, GLint x, GLint y, GLsizei width))found)(target, level, xoffset, x, y, width);
}

static void d_copy_tex_sub_image2D(GLIContext ctx, GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint x, GLint y, GLsizei width, GLsizei height) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCopyTexSubImage2D");
    if (found) ((void (*)(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint x, GLint y, GLsizei width, GLsizei height))found)(target, level, xoffset, yoffset, x, y, width, height);
}

static void d_cull_face(GLIContext ctx, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCullFace");
    if (found) ((void (*)(GLenum mode))found)(mode);
}

static void d_delete_lists(GLIContext ctx, GLuint list, GLsizei range) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDeleteLists");
    if (found) ((void (*)(GLuint list, GLsizei range))found)(list, range);
}

static void d_delete_textures(GLIContext ctx, GLsizei n, const GLuint *textures) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDeleteTextures");
    if (found) ((void (*)(GLsizei n, const GLuint *textures))found)(n, textures);
}

static void d_depth_func(GLIContext ctx, GLenum func) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDepthFunc");
    if (found) ((void (*)(GLenum func))found)(func);
}

static void d_depth_mask(GLIContext ctx, GLboolean flag) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDepthMask");
    if (found) ((void (*)(GLboolean flag))found)(flag);
}

static void d_depth_range(GLIContext ctx, GLclampd zNear, GLclampd zFar) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDepthRange");
    if (found) ((void (*)(GLclampd zNear, GLclampd zFar))found)(zNear, zFar);
}

static void d_disable(GLIContext ctx, GLenum cap) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDisable");
    if (found) ((void (*)(GLenum cap))found)(cap);
}

static void d_disable_client_state(GLIContext ctx, GLenum array) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDisableClientState");
    if (found) ((void (*)(GLenum array))found)(array);
}

static void d_draw_arrays(GLIContext ctx, GLenum mode, GLint first, GLsizei count) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDrawArrays");
    if (found) ((void (*)(GLenum mode, GLint first, GLsizei count))found)(mode, first, count);
}

static void d_draw_buffer(GLIContext ctx, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDrawBuffer");
    if (found) ((void (*)(GLenum mode))found)(mode);
}

static void d_draw_elements(GLIContext ctx, GLenum mode, GLsizei count, GLenum type, const GLvoid *indices) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDrawElements");
    if (found) ((void (*)(GLenum mode, GLsizei count, GLenum type, const GLvoid *indices))found)(mode, count, type, indices);
}

static void d_draw_pixels(GLIContext ctx, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *pixels) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDrawPixels");
    if (found) ((void (*)(GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *pixels))found)(width, height, format, type, pixels);
}

static void d_edge_flag(GLIContext ctx, GLboolean flag) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEdgeFlag");
    if (found) ((void (*)(GLboolean flag))found)(flag);
}

static void d_edge_flag_pointer(GLIContext ctx, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEdgeFlagPointer");
    if (found) ((void (*)(GLsizei stride, const GLvoid *pointer))found)(stride, pointer);
}

static void d_edge_flagv(GLIContext ctx, const GLboolean *flag) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEdgeFlagv");
    if (found) ((void (*)(const GLboolean *flag))found)(flag);
}

static void d_enable(GLIContext ctx, GLenum cap) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEnable");
    if (found) ((void (*)(GLenum cap))found)(cap);
}

static void d_enable_client_state(GLIContext ctx, GLenum array) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEnableClientState");
    if (found) ((void (*)(GLenum array))found)(array);
}

static void d_end(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEnd");
    if (found) ((void (*)(void))found)();
}

static void d_end_list(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEndList");
    if (found) ((void (*)(void))found)();
}

static void d_eval_coord1d(GLIContext ctx, GLdouble u) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalCoord1d");
    if (found) ((void (*)(GLdouble u))found)(u);
}

static void d_eval_coord1dv(GLIContext ctx, const GLdouble *u) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalCoord1dv");
    if (found) ((void (*)(const GLdouble *u))found)(u);
}

static void d_eval_coord1f(GLIContext ctx, GLfloat u) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalCoord1f");
    if (found) ((void (*)(GLfloat u))found)(u);
}

static void d_eval_coord1fv(GLIContext ctx, const GLfloat *u) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalCoord1fv");
    if (found) ((void (*)(const GLfloat *u))found)(u);
}

static void d_eval_coord2d(GLIContext ctx, GLdouble u, GLdouble v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalCoord2d");
    if (found) ((void (*)(GLdouble u, GLdouble v))found)(u, v);
}

static void d_eval_coord2dv(GLIContext ctx, const GLdouble *u) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalCoord2dv");
    if (found) ((void (*)(const GLdouble *u))found)(u);
}

static void d_eval_coord2f(GLIContext ctx, GLfloat u, GLfloat v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalCoord2f");
    if (found) ((void (*)(GLfloat u, GLfloat v))found)(u, v);
}

static void d_eval_coord2fv(GLIContext ctx, const GLfloat *u) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalCoord2fv");
    if (found) ((void (*)(const GLfloat *u))found)(u);
}

static void d_eval_mesh1(GLIContext ctx, GLenum mode, GLint i1, GLint i2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalMesh1");
    if (found) ((void (*)(GLenum mode, GLint i1, GLint i2))found)(mode, i1, i2);
}

static void d_eval_mesh2(GLIContext ctx, GLenum mode, GLint i1, GLint i2, GLint j1, GLint j2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalMesh2");
    if (found) ((void (*)(GLenum mode, GLint i1, GLint i2, GLint j1, GLint j2))found)(mode, i1, i2, j1, j2);
}

static void d_eval_point1(GLIContext ctx, GLint i) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalPoint1");
    if (found) ((void (*)(GLint i))found)(i);
}

static void d_eval_point2(GLIContext ctx, GLint i, GLint j) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEvalPoint2");
    if (found) ((void (*)(GLint i, GLint j))found)(i, j);
}

static void d_feedback_buffer(GLIContext ctx, GLsizei size, GLenum type, GLfloat *buffer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFeedbackBuffer");
    if (found) ((void (*)(GLsizei size, GLenum type, GLfloat *buffer))found)(size, type, buffer);
}

static void d_finish(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFinish");
    if (found) ((void (*)(void))found)();
}

static void d_flush(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFlush");
    if (found) ((void (*)(void))found)();
}

static void d_fogf(GLIContext ctx, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFogf");
    if (found) ((void (*)(GLenum pname, GLfloat param))found)(pname, param);
}

static void d_fogfv(GLIContext ctx, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFogfv");
    if (found) ((void (*)(GLenum pname, const GLfloat *params))found)(pname, params);
}

static void d_fogi(GLIContext ctx, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFogi");
    if (found) ((void (*)(GLenum pname, GLint param))found)(pname, param);
}

static void d_fogiv(GLIContext ctx, GLenum pname, const GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFogiv");
    if (found) ((void (*)(GLenum pname, const GLint *params))found)(pname, params);
}

static void d_front_face(GLIContext ctx, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFrontFace");
    if (found) ((void (*)(GLenum mode))found)(mode);
}

static void d_frustum(GLIContext ctx, GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble zNear, GLdouble zFar) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFrustum");
    if (found) ((void (*)(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble zNear, GLdouble zFar))found)(left, right, bottom, top, zNear, zFar);
}

static GLuint d_gen_lists(GLIContext ctx, GLsizei range) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGenLists");
    return found ? ((GLuint (*)(GLsizei range))found)(range) : 0;
}

static void d_gen_textures(GLIContext ctx, GLsizei n, GLuint *textures) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGenTextures");
    if (found) ((void (*)(GLsizei n, GLuint *textures))found)(n, textures);
}

static void d_get_booleanv(GLIContext ctx, GLenum pname, GLboolean *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetBooleanv");
    if (found) ((void (*)(GLenum pname, GLboolean *params))found)(pname, params);
}

static void d_get_clip_plane(GLIContext ctx, GLenum plane, GLdouble *equation) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetClipPlane");
    if (found) ((void (*)(GLenum plane, GLdouble *equation))found)(plane, equation);
}

static void d_get_doublev(GLIContext ctx, GLenum pname, GLdouble *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetDoublev");
    if (found) ((void (*)(GLenum pname, GLdouble *params))found)(pname, params);
}

static GLenum d_get_error(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetError");
    return found ? ((GLenum (*)(void))found)() : 0;
}

static void d_get_floatv(GLIContext ctx, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetFloatv");
    if (found) ((void (*)(GLenum pname, GLfloat *params))found)(pname, params);
}

static void d_get_integerv(GLIContext ctx, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetIntegerv");
    if (found) ((void (*)(GLenum pname, GLint *params))found)(pname, params);
}

static void d_get_lightfv(GLIContext ctx, GLenum light, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetLightfv");
    if (found) ((void (*)(GLenum light, GLenum pname, GLfloat *params))found)(light, pname, params);
}

static void d_get_lightiv(GLIContext ctx, GLenum light, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetLightiv");
    if (found) ((void (*)(GLenum light, GLenum pname, GLint *params))found)(light, pname, params);
}

static void d_get_mapdv(GLIContext ctx, GLenum target, GLenum query, GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetMapdv");
    if (found) ((void (*)(GLenum target, GLenum query, GLdouble *v))found)(target, query, v);
}

static void d_get_mapfv(GLIContext ctx, GLenum target, GLenum query, GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetMapfv");
    if (found) ((void (*)(GLenum target, GLenum query, GLfloat *v))found)(target, query, v);
}

static void d_get_mapiv(GLIContext ctx, GLenum target, GLenum query, GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetMapiv");
    if (found) ((void (*)(GLenum target, GLenum query, GLint *v))found)(target, query, v);
}

static void d_get_materialfv(GLIContext ctx, GLenum face, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetMaterialfv");
    if (found) ((void (*)(GLenum face, GLenum pname, GLfloat *params))found)(face, pname, params);
}

static void d_get_materialiv(GLIContext ctx, GLenum face, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetMaterialiv");
    if (found) ((void (*)(GLenum face, GLenum pname, GLint *params))found)(face, pname, params);
}

static void d_get_pixel_mapfv(GLIContext ctx, GLenum map, GLfloat *values) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetPixelMapfv");
    if (found) ((void (*)(GLenum map, GLfloat *values))found)(map, values);
}

static void d_get_pixel_mapuiv(GLIContext ctx, GLenum map, GLuint *values) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetPixelMapuiv");
    if (found) ((void (*)(GLenum map, GLuint *values))found)(map, values);
}

static void d_get_pixel_mapusv(GLIContext ctx, GLenum map, GLushort *values) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetPixelMapusv");
    if (found) ((void (*)(GLenum map, GLushort *values))found)(map, values);
}

static void d_get_pointerv(GLIContext ctx, GLenum pname, GLvoid* *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetPointerv");
    if (found) ((void (*)(GLenum pname, GLvoid* *params))found)(pname, params);
}

static void d_get_polygon_stipple(GLIContext ctx, GLubyte *mask) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetPolygonStipple");
    if (found) ((void (*)(GLubyte *mask))found)(mask);
}

static const GLubyte* d_get_string(GLIContext ctx, GLenum name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetString");
    return found ? ((const GLubyte* (*)(GLenum name))found)(name) : 0;
}

static void d_get_tex_envfv(GLIContext ctx, GLenum target, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexEnvfv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLfloat *params))found)(target, pname, params);
}

static void d_get_tex_enviv(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexEnviv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static void d_get_tex_gendv(GLIContext ctx, GLenum coord, GLenum pname, GLdouble *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexGendv");
    if (found) ((void (*)(GLenum coord, GLenum pname, GLdouble *params))found)(coord, pname, params);
}

static void d_get_tex_genfv(GLIContext ctx, GLenum coord, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexGenfv");
    if (found) ((void (*)(GLenum coord, GLenum pname, GLfloat *params))found)(coord, pname, params);
}

static void d_get_tex_geniv(GLIContext ctx, GLenum coord, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexGeniv");
    if (found) ((void (*)(GLenum coord, GLenum pname, GLint *params))found)(coord, pname, params);
}

static void d_get_tex_image(GLIContext ctx, GLenum target, GLint level, GLenum format, GLenum type, GLvoid *pixels) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexImage");
    if (found) ((void (*)(GLenum target, GLint level, GLenum format, GLenum type, GLvoid *pixels))found)(target, level, format, type, pixels);
}

static void d_get_tex_level_parameterfv(GLIContext ctx, GLenum target, GLint level, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexLevelParameterfv");
    if (found) ((void (*)(GLenum target, GLint level, GLenum pname, GLfloat *params))found)(target, level, pname, params);
}

static void d_get_tex_level_parameteriv(GLIContext ctx, GLenum target, GLint level, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexLevelParameteriv");
    if (found) ((void (*)(GLenum target, GLint level, GLenum pname, GLint *params))found)(target, level, pname, params);
}

static void d_get_tex_parameterfv(GLIContext ctx, GLenum target, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexParameterfv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLfloat *params))found)(target, pname, params);
}

static void d_get_tex_parameteriv(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexParameteriv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static void d_hint(GLIContext ctx, GLenum target, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glHint");
    if (found) ((void (*)(GLenum target, GLenum mode))found)(target, mode);
}

static void d_index_mask(GLIContext ctx, GLuint mask) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexMask");
    if (found) ((void (*)(GLuint mask))found)(mask);
}

static void d_index_pointer(GLIContext ctx, GLenum type, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexPointer");
    if (found) ((void (*)(GLenum type, GLsizei stride, const GLvoid *pointer))found)(type, stride, pointer);
}

static void d_indexd(GLIContext ctx, GLdouble c) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexd");
    if (found) ((void (*)(GLdouble c))found)(c);
}

static void d_indexdv(GLIContext ctx, const GLdouble *c) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexdv");
    if (found) ((void (*)(const GLdouble *c))found)(c);
}

static void d_indexf(GLIContext ctx, GLfloat c) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexf");
    if (found) ((void (*)(GLfloat c))found)(c);
}

static void d_indexfv(GLIContext ctx, const GLfloat *c) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexfv");
    if (found) ((void (*)(const GLfloat *c))found)(c);
}

static void d_indexi(GLIContext ctx, GLint c) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexi");
    if (found) ((void (*)(GLint c))found)(c);
}

static void d_indexiv(GLIContext ctx, const GLint *c) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexiv");
    if (found) ((void (*)(const GLint *c))found)(c);
}

static void d_indexs(GLIContext ctx, GLshort c) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexs");
    if (found) ((void (*)(GLshort c))found)(c);
}

static void d_indexsv(GLIContext ctx, const GLshort *c) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexsv");
    if (found) ((void (*)(const GLshort *c))found)(c);
}

static void d_indexub(GLIContext ctx, GLubyte c) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexub");
    if (found) ((void (*)(GLubyte c))found)(c);
}

static void d_indexubv(GLIContext ctx, const GLubyte *c) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIndexubv");
    if (found) ((void (*)(const GLubyte *c))found)(c);
}

static void d_init_names(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glInitNames");
    if (found) ((void (*)(void))found)();
}

static void d_interleaved_arrays(GLIContext ctx, GLenum format, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glInterleavedArrays");
    if (found) ((void (*)(GLenum format, GLsizei stride, const GLvoid *pointer))found)(format, stride, pointer);
}

static GLboolean d_is_enabled(GLIContext ctx, GLenum cap) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsEnabled");
    return found ? ((GLboolean (*)(GLenum cap))found)(cap) : 0;
}

static GLboolean d_is_list(GLIContext ctx, GLuint list) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsList");
    return found ? ((GLboolean (*)(GLuint list))found)(list) : 0;
}

static GLboolean d_is_texture(GLIContext ctx, GLuint texture) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsTexture");
    return found ? ((GLboolean (*)(GLuint texture))found)(texture) : 0;
}

static void d_light_modelf(GLIContext ctx, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLightModelf");
    if (found) ((void (*)(GLenum pname, GLfloat param))found)(pname, param);
}

static void d_light_modelfv(GLIContext ctx, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLightModelfv");
    if (found) ((void (*)(GLenum pname, const GLfloat *params))found)(pname, params);
}

static void d_light_modeli(GLIContext ctx, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLightModeli");
    if (found) ((void (*)(GLenum pname, GLint param))found)(pname, param);
}

static void d_light_modeliv(GLIContext ctx, GLenum pname, const GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLightModeliv");
    if (found) ((void (*)(GLenum pname, const GLint *params))found)(pname, params);
}

static void d_lightf(GLIContext ctx, GLenum light, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLightf");
    if (found) ((void (*)(GLenum light, GLenum pname, GLfloat param))found)(light, pname, param);
}

static void d_lightfv(GLIContext ctx, GLenum light, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLightfv");
    if (found) ((void (*)(GLenum light, GLenum pname, const GLfloat *params))found)(light, pname, params);
}

static void d_lighti(GLIContext ctx, GLenum light, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLighti");
    if (found) ((void (*)(GLenum light, GLenum pname, GLint param))found)(light, pname, param);
}

static void d_lightiv(GLIContext ctx, GLenum light, GLenum pname, const GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLightiv");
    if (found) ((void (*)(GLenum light, GLenum pname, const GLint *params))found)(light, pname, params);
}

static void d_line_stipple(GLIContext ctx, GLint factor, GLushort pattern) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLineStipple");
    if (found) ((void (*)(GLint factor, GLushort pattern))found)(factor, pattern);
}

static void d_line_width(GLIContext ctx, GLfloat width) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLineWidth");
    if (found) ((void (*)(GLfloat width))found)(width);
}

static void d_list_base(GLIContext ctx, GLuint base) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glListBase");
    if (found) ((void (*)(GLuint base))found)(base);
}

static void d_load_identity(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLoadIdentity");
    if (found) ((void (*)(void))found)();
}

static void d_load_matrixd(GLIContext ctx, const GLdouble *m) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLoadMatrixd");
    if (found) ((void (*)(const GLdouble *m))found)(m);
}

static void d_load_matrixf(GLIContext ctx, const GLfloat *m) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLoadMatrixf");
    if (found) ((void (*)(const GLfloat *m))found)(m);
}

static void d_load_name(GLIContext ctx, GLuint name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLoadName");
    if (found) ((void (*)(GLuint name))found)(name);
}

static void d_logic_op(GLIContext ctx, GLenum opcode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLogicOp");
    if (found) ((void (*)(GLenum opcode))found)(opcode);
}

static void d_map1d(GLIContext ctx, GLenum target, GLdouble u1, GLdouble u2, GLint stride, GLint order, const GLdouble *points) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMap1d");
    if (found) ((void (*)(GLenum target, GLdouble u1, GLdouble u2, GLint stride, GLint order, const GLdouble *points))found)(target, u1, u2, stride, order, points);
}

static void d_map1f(GLIContext ctx, GLenum target, GLfloat u1, GLfloat u2, GLint stride, GLint order, const GLfloat *points) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMap1f");
    if (found) ((void (*)(GLenum target, GLfloat u1, GLfloat u2, GLint stride, GLint order, const GLfloat *points))found)(target, u1, u2, stride, order, points);
}

static void d_map2d(GLIContext ctx, GLenum target, GLdouble u1, GLdouble u2, GLint ustride, GLint uorder, GLdouble v1, GLdouble v2, GLint vstride, GLint vorder, const GLdouble *points) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMap2d");
    if (found) ((void (*)(GLenum target, GLdouble u1, GLdouble u2, GLint ustride, GLint uorder, GLdouble v1, GLdouble v2, GLint vstride, GLint vorder, const GLdouble *points))found)(target, u1, u2, ustride, uorder, v1, v2, vstride, vorder, points);
}

static void d_map2f(GLIContext ctx, GLenum target, GLfloat u1, GLfloat u2, GLint ustride, GLint uorder, GLfloat v1, GLfloat v2, GLint vstride, GLint vorder, const GLfloat *points) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMap2f");
    if (found) ((void (*)(GLenum target, GLfloat u1, GLfloat u2, GLint ustride, GLint uorder, GLfloat v1, GLfloat v2, GLint vstride, GLint vorder, const GLfloat *points))found)(target, u1, u2, ustride, uorder, v1, v2, vstride, vorder, points);
}

static void d_map_grid1d(GLIContext ctx, GLint un, GLdouble u1, GLdouble u2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMapGrid1d");
    if (found) ((void (*)(GLint un, GLdouble u1, GLdouble u2))found)(un, u1, u2);
}

static void d_map_grid1f(GLIContext ctx, GLint un, GLfloat u1, GLfloat u2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMapGrid1f");
    if (found) ((void (*)(GLint un, GLfloat u1, GLfloat u2))found)(un, u1, u2);
}

static void d_map_grid2d(GLIContext ctx, GLint un, GLdouble u1, GLdouble u2, GLint vn, GLdouble v1, GLdouble v2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMapGrid2d");
    if (found) ((void (*)(GLint un, GLdouble u1, GLdouble u2, GLint vn, GLdouble v1, GLdouble v2))found)(un, u1, u2, vn, v1, v2);
}

static void d_map_grid2f(GLIContext ctx, GLint un, GLfloat u1, GLfloat u2, GLint vn, GLfloat v1, GLfloat v2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMapGrid2f");
    if (found) ((void (*)(GLint un, GLfloat u1, GLfloat u2, GLint vn, GLfloat v1, GLfloat v2))found)(un, u1, u2, vn, v1, v2);
}

static void d_materialf(GLIContext ctx, GLenum face, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMaterialf");
    if (found) ((void (*)(GLenum face, GLenum pname, GLfloat param))found)(face, pname, param);
}

static void d_materialfv(GLIContext ctx, GLenum face, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMaterialfv");
    if (found) ((void (*)(GLenum face, GLenum pname, const GLfloat *params))found)(face, pname, params);
}

static void d_materiali(GLIContext ctx, GLenum face, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMateriali");
    if (found) ((void (*)(GLenum face, GLenum pname, GLint param))found)(face, pname, param);
}

static void d_materialiv(GLIContext ctx, GLenum face, GLenum pname, const GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMaterialiv");
    if (found) ((void (*)(GLenum face, GLenum pname, const GLint *params))found)(face, pname, params);
}

static void d_matrix_mode(GLIContext ctx, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMatrixMode");
    if (found) ((void (*)(GLenum mode))found)(mode);
}

static void d_mult_matrixd(GLIContext ctx, const GLdouble *m) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultMatrixd");
    if (found) ((void (*)(const GLdouble *m))found)(m);
}

static void d_mult_matrixf(GLIContext ctx, const GLfloat *m) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultMatrixf");
    if (found) ((void (*)(const GLfloat *m))found)(m);
}

static void d_new_list(GLIContext ctx, GLuint list, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNewList");
    if (found) ((void (*)(GLuint list, GLenum mode))found)(list, mode);
}

static void d_normal3b(GLIContext ctx, GLbyte nx, GLbyte ny, GLbyte nz) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNormal3b");
    if (found) ((void (*)(GLbyte nx, GLbyte ny, GLbyte nz))found)(nx, ny, nz);
}

static void d_normal3bv(GLIContext ctx, const GLbyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNormal3bv");
    if (found) ((void (*)(const GLbyte *v))found)(v);
}

static void d_normal3d(GLIContext ctx, GLdouble nx, GLdouble ny, GLdouble nz) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNormal3d");
    if (found) ((void (*)(GLdouble nx, GLdouble ny, GLdouble nz))found)(nx, ny, nz);
}

static void d_normal3dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNormal3dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_normal3f(GLIContext ctx, GLfloat nx, GLfloat ny, GLfloat nz) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNormal3f");
    if (found) ((void (*)(GLfloat nx, GLfloat ny, GLfloat nz))found)(nx, ny, nz);
}

static void d_normal3fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNormal3fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_normal3i(GLIContext ctx, GLint nx, GLint ny, GLint nz) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNormal3i");
    if (found) ((void (*)(GLint nx, GLint ny, GLint nz))found)(nx, ny, nz);
}

static void d_normal3iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNormal3iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_normal3s(GLIContext ctx, GLshort nx, GLshort ny, GLshort nz) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNormal3s");
    if (found) ((void (*)(GLshort nx, GLshort ny, GLshort nz))found)(nx, ny, nz);
}

static void d_normal3sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNormal3sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_normal_pointer(GLIContext ctx, GLenum type, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glNormalPointer");
    if (found) ((void (*)(GLenum type, GLsizei stride, const GLvoid *pointer))found)(type, stride, pointer);
}

static void d_ortho(GLIContext ctx, GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble zNear, GLdouble zFar) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glOrtho");
    if (found) ((void (*)(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble zNear, GLdouble zFar))found)(left, right, bottom, top, zNear, zFar);
}

static void d_pass_through(GLIContext ctx, GLfloat token) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPassThrough");
    if (found) ((void (*)(GLfloat token))found)(token);
}

static void d_pixel_mapfv(GLIContext ctx, GLenum map, GLsizei mapsize, const GLfloat *values) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPixelMapfv");
    if (found) ((void (*)(GLenum map, GLsizei mapsize, const GLfloat *values))found)(map, mapsize, values);
}

static void d_pixel_mapuiv(GLIContext ctx, GLenum map, GLsizei mapsize, const GLuint *values) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPixelMapuiv");
    if (found) ((void (*)(GLenum map, GLsizei mapsize, const GLuint *values))found)(map, mapsize, values);
}

static void d_pixel_mapusv(GLIContext ctx, GLenum map, GLsizei mapsize, const GLushort *values) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPixelMapusv");
    if (found) ((void (*)(GLenum map, GLsizei mapsize, const GLushort *values))found)(map, mapsize, values);
}

static void d_pixel_storef(GLIContext ctx, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPixelStoref");
    if (found) ((void (*)(GLenum pname, GLfloat param))found)(pname, param);
}

static void d_pixel_storei(GLIContext ctx, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPixelStorei");
    if (found) ((void (*)(GLenum pname, GLint param))found)(pname, param);
}

static void d_pixel_transferf(GLIContext ctx, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPixelTransferf");
    if (found) ((void (*)(GLenum pname, GLfloat param))found)(pname, param);
}

static void d_pixel_transferi(GLIContext ctx, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPixelTransferi");
    if (found) ((void (*)(GLenum pname, GLint param))found)(pname, param);
}

static void d_pixel_zoom(GLIContext ctx, GLfloat xfactor, GLfloat yfactor) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPixelZoom");
    if (found) ((void (*)(GLfloat xfactor, GLfloat yfactor))found)(xfactor, yfactor);
}

static void d_point_size(GLIContext ctx, GLfloat size) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPointSize");
    if (found) ((void (*)(GLfloat size))found)(size);
}

static void d_polygon_mode(GLIContext ctx, GLenum face, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPolygonMode");
    if (found) ((void (*)(GLenum face, GLenum mode))found)(face, mode);
}

static void d_polygon_offset(GLIContext ctx, GLfloat factor, GLfloat units) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPolygonOffset");
    if (found) ((void (*)(GLfloat factor, GLfloat units))found)(factor, units);
}

static void d_polygon_stipple(GLIContext ctx, const GLubyte *mask) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPolygonStipple");
    if (found) ((void (*)(const GLubyte *mask))found)(mask);
}

static void d_pop_attrib(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPopAttrib");
    if (found) ((void (*)(void))found)();
}

static void d_pop_client_attrib(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPopClientAttrib");
    if (found) ((void (*)(void))found)();
}

static void d_pop_matrix(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPopMatrix");
    if (found) ((void (*)(void))found)();
}

static void d_pop_name(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPopName");
    if (found) ((void (*)(void))found)();
}

static void d_prioritize_textures(GLIContext ctx, GLsizei n, const GLuint *textures, const GLclampf *priorities) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPrioritizeTextures");
    if (found) ((void (*)(GLsizei n, const GLuint *textures, const GLclampf *priorities))found)(n, textures, priorities);
}

static void d_push_attrib(GLIContext ctx, GLbitfield mask) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPushAttrib");
    if (found) ((void (*)(GLbitfield mask))found)(mask);
}

static void d_push_client_attrib(GLIContext ctx, GLbitfield mask) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPushClientAttrib");
    if (found) ((void (*)(GLbitfield mask))found)(mask);
}

static void d_push_matrix(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPushMatrix");
    if (found) ((void (*)(void))found)();
}

static void d_push_name(GLIContext ctx, GLuint name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPushName");
    if (found) ((void (*)(GLuint name))found)(name);
}

static void d_raster_pos2d(GLIContext ctx, GLdouble x, GLdouble y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos2d");
    if (found) ((void (*)(GLdouble x, GLdouble y))found)(x, y);
}

static void d_raster_pos2dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos2dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_raster_pos2f(GLIContext ctx, GLfloat x, GLfloat y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos2f");
    if (found) ((void (*)(GLfloat x, GLfloat y))found)(x, y);
}

static void d_raster_pos2fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos2fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_raster_pos2i(GLIContext ctx, GLint x, GLint y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos2i");
    if (found) ((void (*)(GLint x, GLint y))found)(x, y);
}

static void d_raster_pos2iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos2iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_raster_pos2s(GLIContext ctx, GLshort x, GLshort y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos2s");
    if (found) ((void (*)(GLshort x, GLshort y))found)(x, y);
}

static void d_raster_pos2sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos2sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_raster_pos3d(GLIContext ctx, GLdouble x, GLdouble y, GLdouble z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos3d");
    if (found) ((void (*)(GLdouble x, GLdouble y, GLdouble z))found)(x, y, z);
}

static void d_raster_pos3dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos3dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_raster_pos3f(GLIContext ctx, GLfloat x, GLfloat y, GLfloat z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos3f");
    if (found) ((void (*)(GLfloat x, GLfloat y, GLfloat z))found)(x, y, z);
}

static void d_raster_pos3fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos3fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_raster_pos3i(GLIContext ctx, GLint x, GLint y, GLint z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos3i");
    if (found) ((void (*)(GLint x, GLint y, GLint z))found)(x, y, z);
}

static void d_raster_pos3iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos3iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_raster_pos3s(GLIContext ctx, GLshort x, GLshort y, GLshort z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos3s");
    if (found) ((void (*)(GLshort x, GLshort y, GLshort z))found)(x, y, z);
}

static void d_raster_pos3sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos3sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_raster_pos4d(GLIContext ctx, GLdouble x, GLdouble y, GLdouble z, GLdouble w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos4d");
    if (found) ((void (*)(GLdouble x, GLdouble y, GLdouble z, GLdouble w))found)(x, y, z, w);
}

static void d_raster_pos4dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos4dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_raster_pos4f(GLIContext ctx, GLfloat x, GLfloat y, GLfloat z, GLfloat w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos4f");
    if (found) ((void (*)(GLfloat x, GLfloat y, GLfloat z, GLfloat w))found)(x, y, z, w);
}

static void d_raster_pos4fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos4fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_raster_pos4i(GLIContext ctx, GLint x, GLint y, GLint z, GLint w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos4i");
    if (found) ((void (*)(GLint x, GLint y, GLint z, GLint w))found)(x, y, z, w);
}

static void d_raster_pos4iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos4iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_raster_pos4s(GLIContext ctx, GLshort x, GLshort y, GLshort z, GLshort w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos4s");
    if (found) ((void (*)(GLshort x, GLshort y, GLshort z, GLshort w))found)(x, y, z, w);
}

static void d_raster_pos4sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRasterPos4sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_read_buffer(GLIContext ctx, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glReadBuffer");
    if (found) ((void (*)(GLenum mode))found)(mode);
}

static void d_read_pixels(GLIContext ctx, GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, GLvoid *pixels) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glReadPixels");
    if (found) ((void (*)(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, GLvoid *pixels))found)(x, y, width, height, format, type, pixels);
}

static void d_rectd(GLIContext ctx, GLdouble x1, GLdouble y1, GLdouble x2, GLdouble y2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRectd");
    if (found) ((void (*)(GLdouble x1, GLdouble y1, GLdouble x2, GLdouble y2))found)(x1, y1, x2, y2);
}

static void d_rectdv(GLIContext ctx, const GLdouble *v1, const GLdouble *v2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRectdv");
    if (found) ((void (*)(const GLdouble *v1, const GLdouble *v2))found)(v1, v2);
}

static void d_rectf(GLIContext ctx, GLfloat x1, GLfloat y1, GLfloat x2, GLfloat y2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRectf");
    if (found) ((void (*)(GLfloat x1, GLfloat y1, GLfloat x2, GLfloat y2))found)(x1, y1, x2, y2);
}

static void d_rectfv(GLIContext ctx, const GLfloat *v1, const GLfloat *v2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRectfv");
    if (found) ((void (*)(const GLfloat *v1, const GLfloat *v2))found)(v1, v2);
}

static void d_recti(GLIContext ctx, GLint x1, GLint y1, GLint x2, GLint y2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRecti");
    if (found) ((void (*)(GLint x1, GLint y1, GLint x2, GLint y2))found)(x1, y1, x2, y2);
}

static void d_rectiv(GLIContext ctx, const GLint *v1, const GLint *v2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRectiv");
    if (found) ((void (*)(const GLint *v1, const GLint *v2))found)(v1, v2);
}

static void d_rects(GLIContext ctx, GLshort x1, GLshort y1, GLshort x2, GLshort y2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRects");
    if (found) ((void (*)(GLshort x1, GLshort y1, GLshort x2, GLshort y2))found)(x1, y1, x2, y2);
}

static void d_rectsv(GLIContext ctx, const GLshort *v1, const GLshort *v2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRectsv");
    if (found) ((void (*)(const GLshort *v1, const GLshort *v2))found)(v1, v2);
}

static GLint d_render_mode(GLIContext ctx, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRenderMode");
    return found ? ((GLint (*)(GLenum mode))found)(mode) : 0;
}

static void d_rotated(GLIContext ctx, GLdouble angle, GLdouble x, GLdouble y, GLdouble z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRotated");
    if (found) ((void (*)(GLdouble angle, GLdouble x, GLdouble y, GLdouble z))found)(angle, x, y, z);
}

static void d_rotatef(GLIContext ctx, GLfloat angle, GLfloat x, GLfloat y, GLfloat z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRotatef");
    if (found) ((void (*)(GLfloat angle, GLfloat x, GLfloat y, GLfloat z))found)(angle, x, y, z);
}

static void d_scaled(GLIContext ctx, GLdouble x, GLdouble y, GLdouble z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glScaled");
    if (found) ((void (*)(GLdouble x, GLdouble y, GLdouble z))found)(x, y, z);
}

static void d_scalef(GLIContext ctx, GLfloat x, GLfloat y, GLfloat z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glScalef");
    if (found) ((void (*)(GLfloat x, GLfloat y, GLfloat z))found)(x, y, z);
}

static void d_scissor(GLIContext ctx, GLint x, GLint y, GLsizei width, GLsizei height) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glScissor");
    if (found) ((void (*)(GLint x, GLint y, GLsizei width, GLsizei height))found)(x, y, width, height);
}

static void d_select_buffer(GLIContext ctx, GLsizei size, GLuint *buffer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSelectBuffer");
    if (found) ((void (*)(GLsizei size, GLuint *buffer))found)(size, buffer);
}

static void d_shade_model(GLIContext ctx, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glShadeModel");
    if (found) ((void (*)(GLenum mode))found)(mode);
}

static void d_stencil_func(GLIContext ctx, GLenum func, GLint ref, GLuint mask) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glStencilFunc");
    if (found) ((void (*)(GLenum func, GLint ref, GLuint mask))found)(func, ref, mask);
}

static void d_stencil_mask(GLIContext ctx, GLuint mask) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glStencilMask");
    if (found) ((void (*)(GLuint mask))found)(mask);
}

static void d_stencil_op(GLIContext ctx, GLenum fail, GLenum zfail, GLenum zpass) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glStencilOp");
    if (found) ((void (*)(GLenum fail, GLenum zfail, GLenum zpass))found)(fail, zfail, zpass);
}

static void d_tex_coord1d(GLIContext ctx, GLdouble s) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord1d");
    if (found) ((void (*)(GLdouble s))found)(s);
}

static void d_tex_coord1dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord1dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_tex_coord1f(GLIContext ctx, GLfloat s) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord1f");
    if (found) ((void (*)(GLfloat s))found)(s);
}

static void d_tex_coord1fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord1fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_tex_coord1i(GLIContext ctx, GLint s) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord1i");
    if (found) ((void (*)(GLint s))found)(s);
}

static void d_tex_coord1iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord1iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_tex_coord1s(GLIContext ctx, GLshort s) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord1s");
    if (found) ((void (*)(GLshort s))found)(s);
}

static void d_tex_coord1sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord1sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_tex_coord2d(GLIContext ctx, GLdouble s, GLdouble t) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord2d");
    if (found) ((void (*)(GLdouble s, GLdouble t))found)(s, t);
}

static void d_tex_coord2dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord2dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_tex_coord2f(GLIContext ctx, GLfloat s, GLfloat t) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord2f");
    if (found) ((void (*)(GLfloat s, GLfloat t))found)(s, t);
}

static void d_tex_coord2fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord2fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_tex_coord2i(GLIContext ctx, GLint s, GLint t) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord2i");
    if (found) ((void (*)(GLint s, GLint t))found)(s, t);
}

static void d_tex_coord2iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord2iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_tex_coord2s(GLIContext ctx, GLshort s, GLshort t) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord2s");
    if (found) ((void (*)(GLshort s, GLshort t))found)(s, t);
}

static void d_tex_coord2sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord2sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_tex_coord3d(GLIContext ctx, GLdouble s, GLdouble t, GLdouble r) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord3d");
    if (found) ((void (*)(GLdouble s, GLdouble t, GLdouble r))found)(s, t, r);
}

static void d_tex_coord3dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord3dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_tex_coord3f(GLIContext ctx, GLfloat s, GLfloat t, GLfloat r) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord3f");
    if (found) ((void (*)(GLfloat s, GLfloat t, GLfloat r))found)(s, t, r);
}

static void d_tex_coord3fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord3fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_tex_coord3i(GLIContext ctx, GLint s, GLint t, GLint r) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord3i");
    if (found) ((void (*)(GLint s, GLint t, GLint r))found)(s, t, r);
}

static void d_tex_coord3iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord3iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_tex_coord3s(GLIContext ctx, GLshort s, GLshort t, GLshort r) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord3s");
    if (found) ((void (*)(GLshort s, GLshort t, GLshort r))found)(s, t, r);
}

static void d_tex_coord3sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord3sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_tex_coord4d(GLIContext ctx, GLdouble s, GLdouble t, GLdouble r, GLdouble q) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord4d");
    if (found) ((void (*)(GLdouble s, GLdouble t, GLdouble r, GLdouble q))found)(s, t, r, q);
}

static void d_tex_coord4dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord4dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_tex_coord4f(GLIContext ctx, GLfloat s, GLfloat t, GLfloat r, GLfloat q) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord4f");
    if (found) ((void (*)(GLfloat s, GLfloat t, GLfloat r, GLfloat q))found)(s, t, r, q);
}

static void d_tex_coord4fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord4fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_tex_coord4i(GLIContext ctx, GLint s, GLint t, GLint r, GLint q) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord4i");
    if (found) ((void (*)(GLint s, GLint t, GLint r, GLint q))found)(s, t, r, q);
}

static void d_tex_coord4iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord4iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_tex_coord4s(GLIContext ctx, GLshort s, GLshort t, GLshort r, GLshort q) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord4s");
    if (found) ((void (*)(GLshort s, GLshort t, GLshort r, GLshort q))found)(s, t, r, q);
}

static void d_tex_coord4sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoord4sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_tex_coord_pointer(GLIContext ctx, GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexCoordPointer");
    if (found) ((void (*)(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer))found)(size, type, stride, pointer);
}

static void d_tex_envf(GLIContext ctx, GLenum target, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexEnvf");
    if (found) ((void (*)(GLenum target, GLenum pname, GLfloat param))found)(target, pname, param);
}

static void d_tex_envfv(GLIContext ctx, GLenum target, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexEnvfv");
    if (found) ((void (*)(GLenum target, GLenum pname, const GLfloat *params))found)(target, pname, params);
}

static void d_tex_envi(GLIContext ctx, GLenum target, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexEnvi");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint param))found)(target, pname, param);
}

static void d_tex_enviv(GLIContext ctx, GLenum target, GLenum pname, const GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexEnviv");
    if (found) ((void (*)(GLenum target, GLenum pname, const GLint *params))found)(target, pname, params);
}

static void d_tex_gend(GLIContext ctx, GLenum coord, GLenum pname, GLdouble param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexGend");
    if (found) ((void (*)(GLenum coord, GLenum pname, GLdouble param))found)(coord, pname, param);
}

static void d_tex_gendv(GLIContext ctx, GLenum coord, GLenum pname, const GLdouble *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexGendv");
    if (found) ((void (*)(GLenum coord, GLenum pname, const GLdouble *params))found)(coord, pname, params);
}

static void d_tex_genf(GLIContext ctx, GLenum coord, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexGenf");
    if (found) ((void (*)(GLenum coord, GLenum pname, GLfloat param))found)(coord, pname, param);
}

static void d_tex_genfv(GLIContext ctx, GLenum coord, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexGenfv");
    if (found) ((void (*)(GLenum coord, GLenum pname, const GLfloat *params))found)(coord, pname, params);
}

static void d_tex_geni(GLIContext ctx, GLenum coord, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexGeni");
    if (found) ((void (*)(GLenum coord, GLenum pname, GLint param))found)(coord, pname, param);
}

static void d_tex_geniv(GLIContext ctx, GLenum coord, GLenum pname, const GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexGeniv");
    if (found) ((void (*)(GLenum coord, GLenum pname, const GLint *params))found)(coord, pname, params);
}

static void d_tex_image1D(GLIContext ctx, GLenum target, GLint level, GLenum internalformat, GLsizei width, GLint border, GLenum format, GLenum type, const GLvoid *pixels) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexImage1D");
    if (found) ((void (*)(GLenum target, GLint level, GLenum internalformat, GLsizei width, GLint border, GLenum format, GLenum type, const GLvoid *pixels))found)(target, level, internalformat, width, border, format, type, pixels);
}

static void d_tex_image2D(GLIContext ctx, GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const GLvoid *pixels) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexImage2D");
    if (found) ((void (*)(GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const GLvoid *pixels))found)(target, level, internalformat, width, height, border, format, type, pixels);
}

static void d_tex_parameterf(GLIContext ctx, GLenum target, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexParameterf");
    if (found) ((void (*)(GLenum target, GLenum pname, GLfloat param))found)(target, pname, param);
}

static void d_tex_parameterfv(GLIContext ctx, GLenum target, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexParameterfv");
    if (found) ((void (*)(GLenum target, GLenum pname, const GLfloat *params))found)(target, pname, params);
}

static void d_tex_parameteri(GLIContext ctx, GLenum target, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexParameteri");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint param))found)(target, pname, param);
}

static void d_tex_parameteriv(GLIContext ctx, GLenum target, GLenum pname, const GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexParameteriv");
    if (found) ((void (*)(GLenum target, GLenum pname, const GLint *params))found)(target, pname, params);
}

static void d_tex_sub_image1D(GLIContext ctx, GLenum target, GLint level, GLint xoffset, GLsizei width, GLenum format, GLenum type, const GLvoid *pixels) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexSubImage1D");
    if (found) ((void (*)(GLenum target, GLint level, GLint xoffset, GLsizei width, GLenum format, GLenum type, const GLvoid *pixels))found)(target, level, xoffset, width, format, type, pixels);
}

static void d_tex_sub_image2D(GLIContext ctx, GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *pixels) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexSubImage2D");
    if (found) ((void (*)(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *pixels))found)(target, level, xoffset, yoffset, width, height, format, type, pixels);
}

static void d_translated(GLIContext ctx, GLdouble x, GLdouble y, GLdouble z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTranslated");
    if (found) ((void (*)(GLdouble x, GLdouble y, GLdouble z))found)(x, y, z);
}

static void d_translatef(GLIContext ctx, GLfloat x, GLfloat y, GLfloat z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTranslatef");
    if (found) ((void (*)(GLfloat x, GLfloat y, GLfloat z))found)(x, y, z);
}

static void d_vertex2d(GLIContext ctx, GLdouble x, GLdouble y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex2d");
    if (found) ((void (*)(GLdouble x, GLdouble y))found)(x, y);
}

static void d_vertex2dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex2dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_vertex2f(GLIContext ctx, GLfloat x, GLfloat y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex2f");
    if (found) ((void (*)(GLfloat x, GLfloat y))found)(x, y);
}

static void d_vertex2fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex2fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_vertex2i(GLIContext ctx, GLint x, GLint y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex2i");
    if (found) ((void (*)(GLint x, GLint y))found)(x, y);
}

static void d_vertex2iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex2iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_vertex2s(GLIContext ctx, GLshort x, GLshort y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex2s");
    if (found) ((void (*)(GLshort x, GLshort y))found)(x, y);
}

static void d_vertex2sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex2sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_vertex3d(GLIContext ctx, GLdouble x, GLdouble y, GLdouble z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex3d");
    if (found) ((void (*)(GLdouble x, GLdouble y, GLdouble z))found)(x, y, z);
}

static void d_vertex3dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex3dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_vertex3f(GLIContext ctx, GLfloat x, GLfloat y, GLfloat z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex3f");
    if (found) ((void (*)(GLfloat x, GLfloat y, GLfloat z))found)(x, y, z);
}

static void d_vertex3fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex3fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_vertex3i(GLIContext ctx, GLint x, GLint y, GLint z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex3i");
    if (found) ((void (*)(GLint x, GLint y, GLint z))found)(x, y, z);
}

static void d_vertex3iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex3iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_vertex3s(GLIContext ctx, GLshort x, GLshort y, GLshort z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex3s");
    if (found) ((void (*)(GLshort x, GLshort y, GLshort z))found)(x, y, z);
}

static void d_vertex3sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex3sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_vertex4d(GLIContext ctx, GLdouble x, GLdouble y, GLdouble z, GLdouble w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex4d");
    if (found) ((void (*)(GLdouble x, GLdouble y, GLdouble z, GLdouble w))found)(x, y, z, w);
}

static void d_vertex4dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex4dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_vertex4f(GLIContext ctx, GLfloat x, GLfloat y, GLfloat z, GLfloat w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex4f");
    if (found) ((void (*)(GLfloat x, GLfloat y, GLfloat z, GLfloat w))found)(x, y, z, w);
}

static void d_vertex4fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex4fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_vertex4i(GLIContext ctx, GLint x, GLint y, GLint z, GLint w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex4i");
    if (found) ((void (*)(GLint x, GLint y, GLint z, GLint w))found)(x, y, z, w);
}

static void d_vertex4iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex4iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_vertex4s(GLIContext ctx, GLshort x, GLshort y, GLshort z, GLshort w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex4s");
    if (found) ((void (*)(GLshort x, GLshort y, GLshort z, GLshort w))found)(x, y, z, w);
}

static void d_vertex4sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertex4sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_vertex_pointer(GLIContext ctx, GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexPointer");
    if (found) ((void (*)(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer))found)(size, type, stride, pointer);
}

static void d_viewport(GLIContext ctx, GLint x, GLint y, GLsizei width, GLsizei height) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glViewport");
    if (found) ((void (*)(GLint x, GLint y, GLsizei width, GLsizei height))found)(x, y, width, height);
}

static void d_blend_func_separate(GLIContext ctx, GLenum sfactorRGB, GLenum dfactorRGB, GLenum sfactorAlpha, GLenum dfactorAlpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBlendFuncSeparate");
    if (found) ((void (*)(GLenum sfactorRGB, GLenum dfactorRGB, GLenum sfactorAlpha, GLenum dfactorAlpha))found)(sfactorRGB, dfactorRGB, sfactorAlpha, dfactorAlpha);
}

static void d_blend_color(GLIContext ctx, GLclampf red, GLclampf green, GLclampf blue, GLclampf alpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBlendColor");
    if (found) ((void (*)(GLclampf red, GLclampf green, GLclampf blue, GLclampf alpha))found)(red, green, blue, alpha);
}

static void d_blend_equation(GLIContext ctx, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBlendEquation");
    if (found) ((void (*)(GLenum mode))found)(mode);
}

static void d_lock_arrays_EXT(GLIContext ctx, GLint first, GLsizei count) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLockArraysEXT");
    if (found) ((void (*)(GLint first, GLsizei count))found)(first, count);
}

static void d_unlock_arrays_EXT(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUnlockArraysEXT");
    if (found) ((void (*)(void))found)();
}

static void d_client_active_texture(GLIContext ctx, GLenum target) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glClientActiveTexture");
    if (found) ((void (*)(GLenum target))found)(target);
}

static void d_active_texture(GLIContext ctx, GLenum target) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glActiveTexture");
    if (found) ((void (*)(GLenum target))found)(target);
}

static void d_multi_tex_coord1d(GLIContext ctx, GLenum target, GLdouble s) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord1d");
    if (found) ((void (*)(GLenum target, GLdouble s))found)(target, s);
}

static void d_multi_tex_coord1dv(GLIContext ctx, GLenum target, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord1dv");
    if (found) ((void (*)(GLenum target, const GLdouble *v))found)(target, v);
}

static void d_multi_tex_coord1f(GLIContext ctx, GLenum target, GLfloat s) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord1f");
    if (found) ((void (*)(GLenum target, GLfloat s))found)(target, s);
}

static void d_multi_tex_coord1fv(GLIContext ctx, GLenum target, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord1fv");
    if (found) ((void (*)(GLenum target, const GLfloat *v))found)(target, v);
}

static void d_multi_tex_coord1i(GLIContext ctx, GLenum target, GLint s) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord1i");
    if (found) ((void (*)(GLenum target, GLint s))found)(target, s);
}

static void d_multi_tex_coord1iv(GLIContext ctx, GLenum target, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord1iv");
    if (found) ((void (*)(GLenum target, const GLint *v))found)(target, v);
}

static void d_multi_tex_coord1s(GLIContext ctx, GLenum target, GLshort s) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord1s");
    if (found) ((void (*)(GLenum target, GLshort s))found)(target, s);
}

static void d_multi_tex_coord1sv(GLIContext ctx, GLenum target, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord1sv");
    if (found) ((void (*)(GLenum target, const GLshort *v))found)(target, v);
}

static void d_multi_tex_coord2d(GLIContext ctx, GLenum target, GLdouble s, GLdouble t) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord2d");
    if (found) ((void (*)(GLenum target, GLdouble s, GLdouble t))found)(target, s, t);
}

static void d_multi_tex_coord2dv(GLIContext ctx, GLenum target, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord2dv");
    if (found) ((void (*)(GLenum target, const GLdouble *v))found)(target, v);
}

static void d_multi_tex_coord2f(GLIContext ctx, GLenum target, GLfloat s, GLfloat t) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord2f");
    if (found) ((void (*)(GLenum target, GLfloat s, GLfloat t))found)(target, s, t);
}

static void d_multi_tex_coord2fv(GLIContext ctx, GLenum target, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord2fv");
    if (found) ((void (*)(GLenum target, const GLfloat *v))found)(target, v);
}

static void d_multi_tex_coord2i(GLIContext ctx, GLenum target, GLint s, GLint t) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord2i");
    if (found) ((void (*)(GLenum target, GLint s, GLint t))found)(target, s, t);
}

static void d_multi_tex_coord2iv(GLIContext ctx, GLenum target, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord2iv");
    if (found) ((void (*)(GLenum target, const GLint *v))found)(target, v);
}

static void d_multi_tex_coord2s(GLIContext ctx, GLenum target, GLshort s, GLshort t) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord2s");
    if (found) ((void (*)(GLenum target, GLshort s, GLshort t))found)(target, s, t);
}

static void d_multi_tex_coord2sv(GLIContext ctx, GLenum target, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord2sv");
    if (found) ((void (*)(GLenum target, const GLshort *v))found)(target, v);
}

static void d_multi_tex_coord3d(GLIContext ctx, GLenum target, GLdouble s, GLdouble t, GLdouble r) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord3d");
    if (found) ((void (*)(GLenum target, GLdouble s, GLdouble t, GLdouble r))found)(target, s, t, r);
}

static void d_multi_tex_coord3dv(GLIContext ctx, GLenum target, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord3dv");
    if (found) ((void (*)(GLenum target, const GLdouble *v))found)(target, v);
}

static void d_multi_tex_coord3f(GLIContext ctx, GLenum target, GLfloat s, GLfloat t, GLfloat r) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord3f");
    if (found) ((void (*)(GLenum target, GLfloat s, GLfloat t, GLfloat r))found)(target, s, t, r);
}

static void d_multi_tex_coord3fv(GLIContext ctx, GLenum target, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord3fv");
    if (found) ((void (*)(GLenum target, const GLfloat *v))found)(target, v);
}

static void d_multi_tex_coord3i(GLIContext ctx, GLenum target, GLint s, GLint t, GLint r) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord3i");
    if (found) ((void (*)(GLenum target, GLint s, GLint t, GLint r))found)(target, s, t, r);
}

static void d_multi_tex_coord3iv(GLIContext ctx, GLenum target, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord3iv");
    if (found) ((void (*)(GLenum target, const GLint *v))found)(target, v);
}

static void d_multi_tex_coord3s(GLIContext ctx, GLenum target, GLshort s, GLshort t, GLshort r) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord3s");
    if (found) ((void (*)(GLenum target, GLshort s, GLshort t, GLshort r))found)(target, s, t, r);
}

static void d_multi_tex_coord3sv(GLIContext ctx, GLenum target, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord3sv");
    if (found) ((void (*)(GLenum target, const GLshort *v))found)(target, v);
}

static void d_multi_tex_coord4d(GLIContext ctx, GLenum target, GLdouble s, GLdouble t, GLdouble r, GLdouble q) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord4d");
    if (found) ((void (*)(GLenum target, GLdouble s, GLdouble t, GLdouble r, GLdouble q))found)(target, s, t, r, q);
}

static void d_multi_tex_coord4dv(GLIContext ctx, GLenum target, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord4dv");
    if (found) ((void (*)(GLenum target, const GLdouble *v))found)(target, v);
}

static void d_multi_tex_coord4f(GLIContext ctx, GLenum target, GLfloat s, GLfloat t, GLfloat r, GLfloat q) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord4f");
    if (found) ((void (*)(GLenum target, GLfloat s, GLfloat t, GLfloat r, GLfloat q))found)(target, s, t, r, q);
}

static void d_multi_tex_coord4fv(GLIContext ctx, GLenum target, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord4fv");
    if (found) ((void (*)(GLenum target, const GLfloat *v))found)(target, v);
}

static void d_multi_tex_coord4i(GLIContext ctx, GLenum target, GLint s, GLint t, GLint r, GLint q) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord4i");
    if (found) ((void (*)(GLenum target, GLint s, GLint t, GLint r, GLint q))found)(target, s, t, r, q);
}

static void d_multi_tex_coord4iv(GLIContext ctx, GLenum target, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord4iv");
    if (found) ((void (*)(GLenum target, const GLint *v))found)(target, v);
}

static void d_multi_tex_coord4s(GLIContext ctx, GLenum target, GLshort s, GLshort t, GLshort r, GLshort q) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord4s");
    if (found) ((void (*)(GLenum target, GLshort s, GLshort t, GLshort r, GLshort q))found)(target, s, t, r, q);
}

static void d_multi_tex_coord4sv(GLIContext ctx, GLenum target, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiTexCoord4sv");
    if (found) ((void (*)(GLenum target, const GLshort *v))found)(target, v);
}

static void d_load_transpose_matrixd(GLIContext ctx, const GLdouble *m) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLoadTransposeMatrixd");
    if (found) ((void (*)(const GLdouble *m))found)(m);
}

static void d_load_transpose_matrixf(GLIContext ctx, const GLfloat *m) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLoadTransposeMatrixf");
    if (found) ((void (*)(const GLfloat *m))found)(m);
}

static void d_mult_transpose_matrixd(GLIContext ctx, const GLdouble *m) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultTransposeMatrixd");
    if (found) ((void (*)(const GLdouble *m))found)(m);
}

static void d_mult_transpose_matrixf(GLIContext ctx, const GLfloat *m) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultTransposeMatrixf");
    if (found) ((void (*)(const GLfloat *m))found)(m);
}

static void d_compressed_tex_image3D(GLIContext ctx, GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height, GLsizei depth, GLint border, GLsizei imageSize, const GLvoid *data) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCompressedTexImage3D");
    if (found) ((void (*)(GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height, GLsizei depth, GLint border, GLsizei imageSize, const GLvoid *data))found)(target, level, internalformat, width, height, depth, border, imageSize, data);
}

static void d_compressed_tex_image2D(GLIContext ctx, GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height, GLint border, GLsizei imageSize, const GLvoid *data) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCompressedTexImage2D");
    if (found) ((void (*)(GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height, GLint border, GLsizei imageSize, const GLvoid *data))found)(target, level, internalformat, width, height, border, imageSize, data);
}

static void d_compressed_tex_image1D(GLIContext ctx, GLenum target, GLint level, GLenum internalformat, GLsizei width, GLint border, GLsizei imageSize, const GLvoid *data) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCompressedTexImage1D");
    if (found) ((void (*)(GLenum target, GLint level, GLenum internalformat, GLsizei width, GLint border, GLsizei imageSize, const GLvoid *data))found)(target, level, internalformat, width, border, imageSize, data);
}

static void d_compressed_tex_sub_image3D(GLIContext ctx, GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLsizei width, GLsizei height, GLsizei depth, GLenum format, GLsizei imageSize, const GLvoid *data) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCompressedTexSubImage3D");
    if (found) ((void (*)(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLsizei width, GLsizei height, GLsizei depth, GLenum format, GLsizei imageSize, const GLvoid *data))found)(target, level, xoffset, yoffset, zoffset, width, height, depth, format, imageSize, data);
}

static void d_compressed_tex_sub_image2D(GLIContext ctx, GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLsizei imageSize, const GLvoid *data) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCompressedTexSubImage2D");
    if (found) ((void (*)(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLsizei imageSize, const GLvoid *data))found)(target, level, xoffset, yoffset, width, height, format, imageSize, data);
}

static void d_compressed_tex_sub_image1D(GLIContext ctx, GLenum target, GLint level, GLint xoffset, GLsizei width, GLenum format, GLsizei imageSize, const GLvoid *data) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCompressedTexSubImage1D");
    if (found) ((void (*)(GLenum target, GLint level, GLint xoffset, GLsizei width, GLenum format, GLsizei imageSize, const GLvoid *data))found)(target, level, xoffset, width, format, imageSize, data);
}

static void d_get_compressed_tex_image(GLIContext ctx, GLenum target, GLint level, GLvoid *img) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetCompressedTexImage");
    if (found) ((void (*)(GLenum target, GLint level, GLvoid *img))found)(target, level, img);
}

static void d_secondary_color3b(GLIContext ctx, GLbyte red, GLbyte green, GLbyte blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3b");
    if (found) ((void (*)(GLbyte red, GLbyte green, GLbyte blue))found)(red, green, blue);
}

static void d_secondary_color3bv(GLIContext ctx, const GLbyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3bv");
    if (found) ((void (*)(const GLbyte *v))found)(v);
}

static void d_secondary_color3d(GLIContext ctx, GLdouble red, GLdouble green, GLdouble blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3d");
    if (found) ((void (*)(GLdouble red, GLdouble green, GLdouble blue))found)(red, green, blue);
}

static void d_secondary_color3dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_secondary_color3f(GLIContext ctx, GLfloat red, GLfloat green, GLfloat blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3f");
    if (found) ((void (*)(GLfloat red, GLfloat green, GLfloat blue))found)(red, green, blue);
}

static void d_secondary_color3fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_secondary_color3i(GLIContext ctx, GLint red, GLint green, GLint blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3i");
    if (found) ((void (*)(GLint red, GLint green, GLint blue))found)(red, green, blue);
}

static void d_secondary_color3iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_secondary_color3s(GLIContext ctx, GLshort red, GLshort green, GLshort blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3s");
    if (found) ((void (*)(GLshort red, GLshort green, GLshort blue))found)(red, green, blue);
}

static void d_secondary_color3sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_secondary_color3ub(GLIContext ctx, GLubyte red, GLubyte green, GLubyte blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3ub");
    if (found) ((void (*)(GLubyte red, GLubyte green, GLubyte blue))found)(red, green, blue);
}

static void d_secondary_color3ubv(GLIContext ctx, const GLubyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3ubv");
    if (found) ((void (*)(const GLubyte *v))found)(v);
}

static void d_secondary_color3ui(GLIContext ctx, GLuint red, GLuint green, GLuint blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3ui");
    if (found) ((void (*)(GLuint red, GLuint green, GLuint blue))found)(red, green, blue);
}

static void d_secondary_color3uiv(GLIContext ctx, const GLuint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3uiv");
    if (found) ((void (*)(const GLuint *v))found)(v);
}

static void d_secondary_color3us(GLIContext ctx, GLushort red, GLushort green, GLushort blue) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3us");
    if (found) ((void (*)(GLushort red, GLushort green, GLushort blue))found)(red, green, blue);
}

static void d_secondary_color3usv(GLIContext ctx, const GLushort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColor3usv");
    if (found) ((void (*)(const GLushort *v))found)(v);
}

static void d_secondary_color_pointer(GLIContext ctx, GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSecondaryColorPointer");
    if (found) ((void (*)(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer))found)(size, type, stride, pointer);
}

static void d_vertex_array_range_EXT(GLIContext ctx, GLsizei count, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexArrayRangeEXT");
    if (found) ((void (*)(GLsizei count, const GLvoid *pointer))found)(count, pointer);
}

static void d_flush_vertex_array_range_EXT(GLIContext ctx, GLsizei count, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFlushVertexArrayRangeEXT");
    if (found) ((void (*)(GLsizei count, const GLvoid *pointer))found)(count, pointer);
}

static void d_draw_range_elements(GLIContext ctx, GLenum mode, GLuint start, GLuint end, GLsizei count, GLenum type, const GLvoid *indices) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDrawRangeElements");
    if (found) ((void (*)(GLenum mode, GLuint start, GLuint end, GLsizei count, GLenum type, const GLvoid *indices))found)(mode, start, end, count, type, indices);
}

static void d_color_table(GLIContext ctx, GLenum target, GLenum internalformat, GLsizei width, GLenum format, GLenum type, const GLvoid *table) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColorTable");
    if (found) ((void (*)(GLenum target, GLenum internalformat, GLsizei width, GLenum format, GLenum type, const GLvoid *table))found)(target, internalformat, width, format, type, table);
}

static void d_color_table_parameterfv(GLIContext ctx, GLenum target, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColorTableParameterfv");
    if (found) ((void (*)(GLenum target, GLenum pname, const GLfloat *params))found)(target, pname, params);
}

static void d_color_table_parameteriv(GLIContext ctx, GLenum target, GLenum pname, const GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColorTableParameteriv");
    if (found) ((void (*)(GLenum target, GLenum pname, const GLint *params))found)(target, pname, params);
}

static void d_copy_color_table(GLIContext ctx, GLenum target, GLenum internalformat, GLint x, GLint y, GLsizei width) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCopyColorTable");
    if (found) ((void (*)(GLenum target, GLenum internalformat, GLint x, GLint y, GLsizei width))found)(target, internalformat, x, y, width);
}

static void d_get_color_table(GLIContext ctx, GLenum target, GLenum format, GLenum type, GLvoid *table) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetColorTable");
    if (found) ((void (*)(GLenum target, GLenum format, GLenum type, GLvoid *table))found)(target, format, type, table);
}

static void d_get_color_table_parameterfv(GLIContext ctx, GLenum target, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetColorTableParameterfv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLfloat *params))found)(target, pname, params);
}

static void d_get_color_table_parameteriv(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetColorTableParameteriv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static void d_color_sub_table(GLIContext ctx, GLenum target, GLsizei start, GLsizei count, GLenum format, GLenum type, const GLvoid *data) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glColorSubTable");
    if (found) ((void (*)(GLenum target, GLsizei start, GLsizei count, GLenum format, GLenum type, const GLvoid *data))found)(target, start, count, format, type, data);
}

static void d_copy_color_sub_table(GLIContext ctx, GLenum target, GLsizei start, GLint x, GLint y, GLsizei width) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCopyColorSubTable");
    if (found) ((void (*)(GLenum target, GLsizei start, GLint x, GLint y, GLsizei width))found)(target, start, x, y, width);
}

static void d_convolution_filter1D(GLIContext ctx, GLenum target, GLenum internalformat, GLsizei width, GLenum format, GLenum type, const GLvoid *image) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glConvolutionFilter1D");
    if (found) ((void (*)(GLenum target, GLenum internalformat, GLsizei width, GLenum format, GLenum type, const GLvoid *image))found)(target, internalformat, width, format, type, image);
}

static void d_convolution_filter2D(GLIContext ctx, GLenum target, GLenum internalformat, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *image) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glConvolutionFilter2D");
    if (found) ((void (*)(GLenum target, GLenum internalformat, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *image))found)(target, internalformat, width, height, format, type, image);
}

static void d_convolution_parameterf(GLIContext ctx, GLenum target, GLenum pname, GLfloat params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glConvolutionParameterf");
    if (found) ((void (*)(GLenum target, GLenum pname, GLfloat params))found)(target, pname, params);
}

static void d_convolution_parameterfv(GLIContext ctx, GLenum target, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glConvolutionParameterfv");
    if (found) ((void (*)(GLenum target, GLenum pname, const GLfloat *params))found)(target, pname, params);
}

static void d_convolution_parameteri(GLIContext ctx, GLenum target, GLenum pname, GLint params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glConvolutionParameteri");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint params))found)(target, pname, params);
}

static void d_convolution_parameteriv(GLIContext ctx, GLenum target, GLenum pname, const GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glConvolutionParameteriv");
    if (found) ((void (*)(GLenum target, GLenum pname, const GLint *params))found)(target, pname, params);
}

static void d_copy_convolution_filter1D(GLIContext ctx, GLenum target, GLenum internalformat, GLint x, GLint y, GLsizei width) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCopyConvolutionFilter1D");
    if (found) ((void (*)(GLenum target, GLenum internalformat, GLint x, GLint y, GLsizei width))found)(target, internalformat, x, y, width);
}

static void d_copy_convolution_filter2D(GLIContext ctx, GLenum target, GLenum internalformat, GLint x, GLint y, GLsizei width, GLsizei height) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCopyConvolutionFilter2D");
    if (found) ((void (*)(GLenum target, GLenum internalformat, GLint x, GLint y, GLsizei width, GLsizei height))found)(target, internalformat, x, y, width, height);
}

static void d_get_convolution_filter(GLIContext ctx, GLenum target, GLenum format, GLenum type, GLvoid *image) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetConvolutionFilter");
    if (found) ((void (*)(GLenum target, GLenum format, GLenum type, GLvoid *image))found)(target, format, type, image);
}

static void d_get_convolution_parameterfv(GLIContext ctx, GLenum target, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetConvolutionParameterfv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLfloat *params))found)(target, pname, params);
}

static void d_get_convolution_parameteriv(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetConvolutionParameteriv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static void d_get_separable_filter(GLIContext ctx, GLenum target, GLenum format, GLenum type, GLvoid *row, GLvoid *column, GLvoid *span) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetSeparableFilter");
    if (found) ((void (*)(GLenum target, GLenum format, GLenum type, GLvoid *row, GLvoid *column, GLvoid *span))found)(target, format, type, row, column, span);
}

static void d_separable_filter2D(GLIContext ctx, GLenum target, GLenum internalformat, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *row, const GLvoid *column) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSeparableFilter2D");
    if (found) ((void (*)(GLenum target, GLenum internalformat, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *row, const GLvoid *column))found)(target, internalformat, width, height, format, type, row, column);
}

static void d_get_histogram(GLIContext ctx, GLenum target, GLboolean reset, GLenum format, GLenum type, GLvoid *values) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetHistogram");
    if (found) ((void (*)(GLenum target, GLboolean reset, GLenum format, GLenum type, GLvoid *values))found)(target, reset, format, type, values);
}

static void d_get_histogram_parameterfv(GLIContext ctx, GLenum target, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetHistogramParameterfv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLfloat *params))found)(target, pname, params);
}

static void d_get_histogram_parameteriv(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetHistogramParameteriv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static void d_get_minmax(GLIContext ctx, GLenum target, GLboolean reset, GLenum format, GLenum type, GLvoid *values) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetMinmax");
    if (found) ((void (*)(GLenum target, GLboolean reset, GLenum format, GLenum type, GLvoid *values))found)(target, reset, format, type, values);
}

static void d_get_minmax_parameterfv(GLIContext ctx, GLenum target, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetMinmaxParameterfv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLfloat *params))found)(target, pname, params);
}

static void d_get_minmax_parameteriv(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetMinmaxParameteriv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static void d_histogram(GLIContext ctx, GLenum target, GLsizei width, GLenum internalformat, GLboolean sink) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glHistogram");
    if (found) ((void (*)(GLenum target, GLsizei width, GLenum internalformat, GLboolean sink))found)(target, width, internalformat, sink);
}

static void d_minmax(GLIContext ctx, GLenum target, GLenum internalformat, GLboolean sink) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMinmax");
    if (found) ((void (*)(GLenum target, GLenum internalformat, GLboolean sink))found)(target, internalformat, sink);
}

static void d_reset_histogram(GLIContext ctx, GLenum target) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glResetHistogram");
    if (found) ((void (*)(GLenum target))found)(target);
}

static void d_reset_minmax(GLIContext ctx, GLenum target) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glResetMinmax");
    if (found) ((void (*)(GLenum target))found)(target);
}

static void d_tex_image3D(GLIContext ctx, GLenum target, GLint level, GLenum internalFormat, GLsizei width, GLsizei height, GLsizei depth, GLint border, GLenum format, GLenum type, const GLvoid *pixels) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexImage3D");
    if (found) ((void (*)(GLenum target, GLint level, GLenum internalFormat, GLsizei width, GLsizei height, GLsizei depth, GLint border, GLenum format, GLenum type, const GLvoid *pixels))found)(target, level, internalFormat, width, height, depth, border, format, type, pixels);
}

static void d_tex_sub_image3D(GLIContext ctx, GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLsizei width, GLsizei height, GLsizei depth, GLenum format, GLenum type, const GLvoid *pixels) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexSubImage3D");
    if (found) ((void (*)(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLsizei width, GLsizei height, GLsizei depth, GLenum format, GLenum type, const GLvoid *pixels))found)(target, level, xoffset, yoffset, zoffset, width, height, depth, format, type, pixels);
}

static void d_copy_tex_sub_image3D(GLIContext ctx, GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLint x, GLint y, GLsizei width, GLsizei height) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCopyTexSubImage3D");
    if (found) ((void (*)(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLint x, GLint y, GLsizei width, GLsizei height))found)(target, level, xoffset, yoffset, zoffset, x, y, width, height);
}

static void d_combiner_parameterfv_NV(GLIContext ctx, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCombinerParameterfvNV");
    if (found) ((void (*)(GLenum pname, const GLfloat *params))found)(pname, params);
}

static void d_combiner_parameterf_NV(GLIContext ctx, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCombinerParameterfNV");
    if (found) ((void (*)(GLenum pname, GLfloat param))found)(pname, param);
}

static void d_combiner_parameteriv_NV(GLIContext ctx, GLenum pname, const GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCombinerParameterivNV");
    if (found) ((void (*)(GLenum pname, const GLint *params))found)(pname, params);
}

static void d_combiner_parameteri_NV(GLIContext ctx, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCombinerParameteriNV");
    if (found) ((void (*)(GLenum pname, GLint param))found)(pname, param);
}

static void d_combiner_input_NV(GLIContext ctx, GLenum stage, GLenum portion, GLenum variable, GLenum input, GLenum mapping, GLenum componentUsage) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCombinerInputNV");
    if (found) ((void (*)(GLenum stage, GLenum portion, GLenum variable, GLenum input, GLenum mapping, GLenum componentUsage))found)(stage, portion, variable, input, mapping, componentUsage);
}

static void d_combiner_output_NV(GLIContext ctx, GLenum stage, GLenum portion, GLenum abOutput, GLenum cdOutput, GLenum sumOutput, GLenum scale, GLenum bias, GLboolean abDotProduct, GLboolean cdDotProduct, GLboolean muxSum) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCombinerOutputNV");
    if (found) ((void (*)(GLenum stage, GLenum portion, GLenum abOutput, GLenum cdOutput, GLenum sumOutput, GLenum scale, GLenum bias, GLboolean abDotProduct, GLboolean cdDotProduct, GLboolean muxSum))found)(stage, portion, abOutput, cdOutput, sumOutput, scale, bias, abDotProduct, cdDotProduct, muxSum);
}

static void d_final_combiner_input_NV(GLIContext ctx, GLenum variable, GLenum input, GLenum mapping, GLenum componentUsage) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFinalCombinerInputNV");
    if (found) ((void (*)(GLenum variable, GLenum input, GLenum mapping, GLenum componentUsage))found)(variable, input, mapping, componentUsage);
}

static void d_get_combiner_input_parameterfv_NV(GLIContext ctx, GLenum stage, GLenum portion, GLenum variable, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetCombinerInputParameterfvNV");
    if (found) ((void (*)(GLenum stage, GLenum portion, GLenum variable, GLenum pname, GLfloat *params))found)(stage, portion, variable, pname, params);
}

static void d_get_combiner_input_parameteriv_NV(GLIContext ctx, GLenum stage, GLenum portion, GLenum variable, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetCombinerInputParameterivNV");
    if (found) ((void (*)(GLenum stage, GLenum portion, GLenum variable, GLenum pname, GLint *params))found)(stage, portion, variable, pname, params);
}

static void d_get_combiner_output_parameterfv_NV(GLIContext ctx, GLenum stage, GLenum portion, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetCombinerOutputParameterfvNV");
    if (found) ((void (*)(GLenum stage, GLenum portion, GLenum pname, GLfloat *params))found)(stage, portion, pname, params);
}

static void d_get_combiner_output_parameteriv_NV(GLIContext ctx, GLenum stage, GLenum portion, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetCombinerOutputParameterivNV");
    if (found) ((void (*)(GLenum stage, GLenum portion, GLenum pname, GLint *params))found)(stage, portion, pname, params);
}

static void d_get_final_combiner_input_parameterfv_NV(GLIContext ctx, GLenum variable, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetFinalCombinerInputParameterfvNV");
    if (found) ((void (*)(GLenum variable, GLenum pname, GLfloat *params))found)(variable, pname, params);
}

static void d_get_final_combiner_input_parameteriv_NV(GLIContext ctx, GLenum variable, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetFinalCombinerInputParameterivNV");
    if (found) ((void (*)(GLenum variable, GLenum pname, GLint *params))found)(variable, pname, params);
}

static void d_combiner_stage_parameterfv_NV(GLIContext ctx, GLenum stage, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCombinerStageParameterfvNV");
    if (found) ((void (*)(GLenum stage, GLenum pname, const GLfloat *params))found)(stage, pname, params);
}

static void d_get_combiner_stage_parameterfv_NV(GLIContext ctx, GLenum stage, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetCombinerStageParameterfvNV");
    if (found) ((void (*)(GLenum stage, GLenum pname, GLfloat *params))found)(stage, pname, params);
}

static void d_texture_range_APPLE(GLIContext ctx, GLenum target, GLsizei length, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTextureRangeAPPLE");
    if (found) ((void (*)(GLenum target, GLsizei length, const GLvoid *pointer))found)(target, length, pointer);
}

static void d_get_tex_parameter_pointerv_APPLE(GLIContext ctx, GLenum target, GLenum pname, GLvoid **params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexParameterPointervAPPLE");
    if (found) ((void (*)(GLenum target, GLenum pname, GLvoid **params))found)(target, pname, params);
}

static void d_blend_equation_separate_EXT(GLIContext ctx, GLenum equationRGB, GLenum equationAlpha) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBlendEquationSeparateEXT");
    if (found) ((void (*)(GLenum equationRGB, GLenum equationAlpha))found)(equationRGB, equationAlpha);
}

static void d_sample_coverage(GLIContext ctx, GLclampf value, GLboolean invert) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSampleCoverage");
    if (found) ((void (*)(GLclampf value, GLboolean invert))found)(value, invert);
}

static void d_sample_pass(GLIContext ctx, GLenum mode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSamplePass");
    if (found) ((void (*)(GLenum mode))found)(mode);
}

static void d_pn_trianglesi_ATI(GLIContext ctx, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPnTrianglesiATI");
    if (found) ((void (*)(GLenum pname, GLint param))found)(pname, param);
}

static void d_pn_trianglesf_ATI(GLIContext ctx, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPnTrianglesfATI");
    if (found) ((void (*)(GLenum pname, GLfloat param))found)(pname, param);
}

static void d_gen_fences_APPLE(GLIContext ctx, GLsizei n, GLuint *fences) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGenFencesAPPLE");
    if (found) ((void (*)(GLsizei n, GLuint *fences))found)(n, fences);
}

static void d_delete_fences_APPLE(GLIContext ctx, GLsizei n, const GLuint *fences) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDeleteFencesAPPLE");
    if (found) ((void (*)(GLsizei n, const GLuint *fences))found)(n, fences);
}

static void d_set_fence_APPLE(GLIContext ctx, GLuint fence) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSetFenceAPPLE");
    if (found) ((void (*)(GLuint fence))found)(fence);
}

static GLboolean d_is_fence_APPLE(GLIContext ctx, GLuint fence) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsFenceAPPLE");
    return found ? ((GLboolean (*)(GLuint fence))found)(fence) : 0;
}

static GLboolean d_test_fence_APPLE(GLIContext ctx, GLuint fence) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTestFenceAPPLE");
    return found ? ((GLboolean (*)(GLuint fence))found)(fence) : 0;
}

static void d_finish_fence_APPLE(GLIContext ctx, GLuint fence) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFinishFenceAPPLE");
    if (found) ((void (*)(GLuint fence))found)(fence);
}

static GLboolean d_test_object_APPLE(GLIContext ctx, GLenum object, GLuint name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTestObjectAPPLE");
    return found ? ((GLboolean (*)(GLenum object, GLuint name))found)(object, name) : 0;
}

static void d_finish_object_APPLE(GLIContext ctx, GLenum object, GLuint name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFinishObjectAPPLE");
    if (found) ((void (*)(GLenum object, GLuint name))found)(object, name);
}

static void d_bind_program_ARB(GLIContext ctx, GLenum target, GLuint program) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBindProgramARB");
    if (found) ((void (*)(GLenum target, GLuint program))found)(target, program);
}

static void d_delete_programs_ARB(GLIContext ctx, GLsizei n, const GLuint *programs) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDeleteProgramsARB");
    if (found) ((void (*)(GLsizei n, const GLuint *programs))found)(n, programs);
}

static void d_gen_programs_ARB(GLIContext ctx, GLsizei n, GLuint *programs) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGenProgramsARB");
    if (found) ((void (*)(GLsizei n, GLuint *programs))found)(n, programs);
}

static GLboolean d_is_program_ARB(GLIContext ctx, GLuint program) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsProgramARB");
    return found ? ((GLboolean (*)(GLuint program))found)(program) : 0;
}

static void d_vertex_attrib1s_ARB(GLIContext ctx, GLuint index, GLshort x) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib1sARB");
    if (found) ((void (*)(GLuint index, GLshort x))found)(index, x);
}

static void d_vertex_attrib1f_ARB(GLIContext ctx, GLuint index, GLfloat x) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib1fARB");
    if (found) ((void (*)(GLuint index, GLfloat x))found)(index, x);
}

static void d_vertex_attrib1d_ARB(GLIContext ctx, GLuint index, GLdouble x) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib1dARB");
    if (found) ((void (*)(GLuint index, GLdouble x))found)(index, x);
}

static void d_vertex_attrib2s_ARB(GLIContext ctx, GLuint index, GLshort x, GLshort y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib2sARB");
    if (found) ((void (*)(GLuint index, GLshort x, GLshort y))found)(index, x, y);
}

static void d_vertex_attrib2f_ARB(GLIContext ctx, GLuint index, GLfloat x, GLfloat y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib2fARB");
    if (found) ((void (*)(GLuint index, GLfloat x, GLfloat y))found)(index, x, y);
}

static void d_vertex_attrib2d_ARB(GLIContext ctx, GLuint index, GLdouble x, GLdouble y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib2dARB");
    if (found) ((void (*)(GLuint index, GLdouble x, GLdouble y))found)(index, x, y);
}

static void d_vertex_attrib3s_ARB(GLIContext ctx, GLuint index, GLshort x, GLshort y, GLshort z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib3sARB");
    if (found) ((void (*)(GLuint index, GLshort x, GLshort y, GLshort z))found)(index, x, y, z);
}

static void d_vertex_attrib3f_ARB(GLIContext ctx, GLuint index, GLfloat x, GLfloat y, GLfloat z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib3fARB");
    if (found) ((void (*)(GLuint index, GLfloat x, GLfloat y, GLfloat z))found)(index, x, y, z);
}

static void d_vertex_attrib3d_ARB(GLIContext ctx, GLuint index, GLdouble x, GLdouble y, GLdouble z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib3dARB");
    if (found) ((void (*)(GLuint index, GLdouble x, GLdouble y, GLdouble z))found)(index, x, y, z);
}

static void d_vertex_attrib4s_ARB(GLIContext ctx, GLuint index, GLshort x, GLshort y, GLshort z, GLshort w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4sARB");
    if (found) ((void (*)(GLuint index, GLshort x, GLshort y, GLshort z, GLshort w))found)(index, x, y, z, w);
}

static void d_vertex_attrib4f_ARB(GLIContext ctx, GLuint index, GLfloat x, GLfloat y, GLfloat z, GLfloat w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4fARB");
    if (found) ((void (*)(GLuint index, GLfloat x, GLfloat y, GLfloat z, GLfloat w))found)(index, x, y, z, w);
}

static void d_vertex_attrib4d_ARB(GLIContext ctx, GLuint index, GLdouble x, GLdouble y, GLdouble z, GLdouble w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4dARB");
    if (found) ((void (*)(GLuint index, GLdouble x, GLdouble y, GLdouble z, GLdouble w))found)(index, x, y, z, w);
}

static void d_vertex_attrib4Nub_ARB(GLIContext ctx, GLuint index, GLubyte x, GLubyte y, GLubyte z, GLubyte w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4NubARB");
    if (found) ((void (*)(GLuint index, GLubyte x, GLubyte y, GLubyte z, GLubyte w))found)(index, x, y, z, w);
}

static void d_vertex_attrib1sv_ARB(GLIContext ctx, GLuint index, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib1svARB");
    if (found) ((void (*)(GLuint index, const GLshort *v))found)(index, v);
}

static void d_vertex_attrib1fv_ARB(GLIContext ctx, GLuint index, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib1fvARB");
    if (found) ((void (*)(GLuint index, const GLfloat *v))found)(index, v);
}

static void d_vertex_attrib1dv_ARB(GLIContext ctx, GLuint index, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib1dvARB");
    if (found) ((void (*)(GLuint index, const GLdouble *v))found)(index, v);
}

static void d_vertex_attrib2sv_ARB(GLIContext ctx, GLuint index, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib2svARB");
    if (found) ((void (*)(GLuint index, const GLshort *v))found)(index, v);
}

static void d_vertex_attrib2fv_ARB(GLIContext ctx, GLuint index, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib2fvARB");
    if (found) ((void (*)(GLuint index, const GLfloat *v))found)(index, v);
}

static void d_vertex_attrib2dv_ARB(GLIContext ctx, GLuint index, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib2dvARB");
    if (found) ((void (*)(GLuint index, const GLdouble *v))found)(index, v);
}

static void d_vertex_attrib3sv_ARB(GLIContext ctx, GLuint index, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib3svARB");
    if (found) ((void (*)(GLuint index, const GLshort *v))found)(index, v);
}

static void d_vertex_attrib3fv_ARB(GLIContext ctx, GLuint index, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib3fvARB");
    if (found) ((void (*)(GLuint index, const GLfloat *v))found)(index, v);
}

static void d_vertex_attrib3dv_ARB(GLIContext ctx, GLuint index, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib3dvARB");
    if (found) ((void (*)(GLuint index, const GLdouble *v))found)(index, v);
}

static void d_vertex_attrib4bv_ARB(GLIContext ctx, GLuint index, const GLbyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4bvARB");
    if (found) ((void (*)(GLuint index, const GLbyte *v))found)(index, v);
}

static void d_vertex_attrib4sv_ARB(GLIContext ctx, GLuint index, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4svARB");
    if (found) ((void (*)(GLuint index, const GLshort *v))found)(index, v);
}

static void d_vertex_attrib4iv_ARB(GLIContext ctx, GLuint index, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4ivARB");
    if (found) ((void (*)(GLuint index, const GLint *v))found)(index, v);
}

static void d_vertex_attrib4ubv_ARB(GLIContext ctx, GLuint index, const GLubyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4ubvARB");
    if (found) ((void (*)(GLuint index, const GLubyte *v))found)(index, v);
}

static void d_vertex_attrib4usv_ARB(GLIContext ctx, GLuint index, const GLushort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4usvARB");
    if (found) ((void (*)(GLuint index, const GLushort *v))found)(index, v);
}

static void d_vertex_attrib4uiv_ARB(GLIContext ctx, GLuint index, const GLuint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4uivARB");
    if (found) ((void (*)(GLuint index, const GLuint *v))found)(index, v);
}

static void d_vertex_attrib4fv_ARB(GLIContext ctx, GLuint index, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4fvARB");
    if (found) ((void (*)(GLuint index, const GLfloat *v))found)(index, v);
}

static void d_vertex_attrib4dv_ARB(GLIContext ctx, GLuint index, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4dvARB");
    if (found) ((void (*)(GLuint index, const GLdouble *v))found)(index, v);
}

static void d_vertex_attrib4Nbv_ARB(GLIContext ctx, GLuint index, const GLbyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4NbvARB");
    if (found) ((void (*)(GLuint index, const GLbyte *v))found)(index, v);
}

static void d_vertex_attrib4Nsv_ARB(GLIContext ctx, GLuint index, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4NsvARB");
    if (found) ((void (*)(GLuint index, const GLshort *v))found)(index, v);
}

static void d_vertex_attrib4Niv_ARB(GLIContext ctx, GLuint index, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4NivARB");
    if (found) ((void (*)(GLuint index, const GLint *v))found)(index, v);
}

static void d_vertex_attrib4Nubv_ARB(GLIContext ctx, GLuint index, const GLubyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4NubvARB");
    if (found) ((void (*)(GLuint index, const GLubyte *v))found)(index, v);
}

static void d_vertex_attrib4Nusv_ARB(GLIContext ctx, GLuint index, const GLushort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4NusvARB");
    if (found) ((void (*)(GLuint index, const GLushort *v))found)(index, v);
}

static void d_vertex_attrib4Nuiv_ARB(GLIContext ctx, GLuint index, const GLuint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttrib4NuivARB");
    if (found) ((void (*)(GLuint index, const GLuint *v))found)(index, v);
}

static void d_vertex_attrib_pointer_ARB(GLIContext ctx, GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribPointerARB");
    if (found) ((void (*)(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid *pointer))found)(index, size, type, normalized, stride, pointer);
}

static void d_enable_vertex_attrib_array_ARB(GLIContext ctx, GLuint index) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEnableVertexAttribArrayARB");
    if (found) ((void (*)(GLuint index))found)(index);
}

static void d_disable_vertex_attrib_array_ARB(GLIContext ctx, GLuint index) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDisableVertexAttribArrayARB");
    if (found) ((void (*)(GLuint index))found)(index);
}

static void d_get_vertex_attribdv_ARB(GLIContext ctx, GLuint index, GLenum pname, GLdouble *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetVertexAttribdvARB");
    if (found) ((void (*)(GLuint index, GLenum pname, GLdouble *params))found)(index, pname, params);
}

static void d_get_vertex_attribfv_ARB(GLIContext ctx, GLuint index, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetVertexAttribfvARB");
    if (found) ((void (*)(GLuint index, GLenum pname, GLfloat *params))found)(index, pname, params);
}

static void d_get_vertex_attribiv_ARB(GLIContext ctx, GLuint index, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetVertexAttribivARB");
    if (found) ((void (*)(GLuint index, GLenum pname, GLint *params))found)(index, pname, params);
}

static void d_get_vertex_attrib_pointerv_ARB(GLIContext ctx, GLuint index, GLenum pname, GLvoid **pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetVertexAttribPointervARB");
    if (found) ((void (*)(GLuint index, GLenum pname, GLvoid **pointer))found)(index, pname, pointer);
}

static void d_program_env_parameter4d_ARB(GLIContext ctx, GLenum target, GLuint index, GLdouble x, GLdouble y, GLdouble z, GLdouble w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramEnvParameter4dARB");
    if (found) ((void (*)(GLenum target, GLuint index, GLdouble x, GLdouble y, GLdouble z, GLdouble w))found)(target, index, x, y, z, w);
}

static void d_program_env_parameter4dv_ARB(GLIContext ctx, GLenum target, GLuint index, const GLdouble *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramEnvParameter4dvARB");
    if (found) ((void (*)(GLenum target, GLuint index, const GLdouble *params))found)(target, index, params);
}

static void d_program_env_parameter4f_ARB(GLIContext ctx, GLenum target, GLuint index, GLfloat x, GLfloat y, GLfloat z, GLfloat w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramEnvParameter4fARB");
    if (found) ((void (*)(GLenum target, GLuint index, GLfloat x, GLfloat y, GLfloat z, GLfloat w))found)(target, index, x, y, z, w);
}

static void d_program_env_parameter4fv_ARB(GLIContext ctx, GLenum target, GLuint index, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramEnvParameter4fvARB");
    if (found) ((void (*)(GLenum target, GLuint index, const GLfloat *params))found)(target, index, params);
}

static void d_program_local_parameter4d_ARB(GLIContext ctx, GLenum target, GLuint index, GLdouble x, GLdouble y, GLdouble z, GLdouble w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramLocalParameter4dARB");
    if (found) ((void (*)(GLenum target, GLuint index, GLdouble x, GLdouble y, GLdouble z, GLdouble w))found)(target, index, x, y, z, w);
}

static void d_program_local_parameter4dv_ARB(GLIContext ctx, GLenum target, GLuint index, const GLdouble *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramLocalParameter4dvARB");
    if (found) ((void (*)(GLenum target, GLuint index, const GLdouble *params))found)(target, index, params);
}

static void d_program_local_parameter4f_ARB(GLIContext ctx, GLenum target, GLuint index, GLfloat x, GLfloat y, GLfloat z, GLfloat w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramLocalParameter4fARB");
    if (found) ((void (*)(GLenum target, GLuint index, GLfloat x, GLfloat y, GLfloat z, GLfloat w))found)(target, index, x, y, z, w);
}

static void d_program_local_parameter4fv_ARB(GLIContext ctx, GLenum target, GLuint index, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramLocalParameter4fvARB");
    if (found) ((void (*)(GLenum target, GLuint index, const GLfloat *params))found)(target, index, params);
}

static void d_get_program_env_parameterdv_ARB(GLIContext ctx, GLenum target, GLuint index, GLdouble *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetProgramEnvParameterdvARB");
    if (found) ((void (*)(GLenum target, GLuint index, GLdouble *params))found)(target, index, params);
}

static void d_get_program_env_parameterfv_ARB(GLIContext ctx, GLenum target, GLuint index, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetProgramEnvParameterfvARB");
    if (found) ((void (*)(GLenum target, GLuint index, GLfloat *params))found)(target, index, params);
}

static void d_get_program_local_parameterdv_ARB(GLIContext ctx, GLenum target, GLuint index, GLdouble *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetProgramLocalParameterdvARB");
    if (found) ((void (*)(GLenum target, GLuint index, GLdouble *params))found)(target, index, params);
}

static void d_get_program_local_parameterfv_ARB(GLIContext ctx, GLenum target, GLuint index, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetProgramLocalParameterfvARB");
    if (found) ((void (*)(GLenum target, GLuint index, GLfloat *params))found)(target, index, params);
}

static void d_program_string_ARB(GLIContext ctx, GLenum target, GLenum format, GLsizei len, const GLvoid* string) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramStringARB");
    if (found) ((void (*)(GLenum target, GLenum format, GLsizei len, const GLvoid* string))found)(target, format, len, string);
}

static void d_get_program_string_ARB(GLIContext ctx, GLenum target, GLenum pname, GLvoid *string) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetProgramStringARB");
    if (found) ((void (*)(GLenum target, GLenum pname, GLvoid *string))found)(target, pname, string);
}

static void d_get_programiv_ARB(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetProgramivARB");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static void d_enable_vertex_attrib_ARB(GLIContext ctx, GLuint index, GLenum pname) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEnableVertexAttribARB");
    if (found) ((void (*)(GLuint index, GLenum pname))found)(index, pname);
}

static void d_disable_vertex_attrib_ARB(GLIContext ctx, GLuint index, GLenum pname) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDisableVertexAttribARB");
    if (found) ((void (*)(GLuint index, GLenum pname))found)(index, pname);
}

static GLboolean d_is_vertex_attrib_enabled_ARB(GLIContext ctx, GLuint index, GLenum pname) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsVertexAttribEnabledARB");
    return found ? ((GLboolean (*)(GLuint index, GLenum pname))found)(index, pname) : 0;
}

static void d_map_vertex_attrib1d_ARB(GLIContext ctx, GLuint index, GLuint size, GLdouble u1, GLdouble u2, GLint stride, GLint order, const GLdouble *points) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMapVertexAttrib1dARB");
    if (found) ((void (*)(GLuint index, GLuint size, GLdouble u1, GLdouble u2, GLint stride, GLint order, const GLdouble *points))found)(index, size, u1, u2, stride, order, points);
}

static void d_map_vertex_attrib1f_ARB(GLIContext ctx, GLuint index, GLuint size, GLfloat u1, GLfloat u2, GLint stride, GLint order, const GLfloat *points) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMapVertexAttrib1fARB");
    if (found) ((void (*)(GLuint index, GLuint size, GLfloat u1, GLfloat u2, GLint stride, GLint order, const GLfloat *points))found)(index, size, u1, u2, stride, order, points);
}

static void d_map_vertex_attrib2d_ARB(GLIContext ctx, GLuint index, GLuint size, GLdouble u1, GLdouble u2, GLint ustride, GLint uorder, GLdouble v1, GLdouble v2, GLint vstride, GLint vorder, const GLdouble *points) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMapVertexAttrib2dARB");
    if (found) ((void (*)(GLuint index, GLuint size, GLdouble u1, GLdouble u2, GLint ustride, GLint uorder, GLdouble v1, GLdouble v2, GLint vstride, GLint vorder, const GLdouble *points))found)(index, size, u1, u2, ustride, uorder, v1, v2, vstride, vorder, points);
}

static void d_map_vertex_attrib2f_ARB(GLIContext ctx, GLuint index, GLuint size, GLfloat u1, GLfloat u2, GLint ustride, GLint uorder, GLfloat v1, GLfloat v2, GLint vstride, GLint vorder, const GLfloat *points) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMapVertexAttrib2fARB");
    if (found) ((void (*)(GLuint index, GLuint size, GLfloat u1, GLfloat u2, GLint ustride, GLint uorder, GLfloat v1, GLfloat v2, GLint vstride, GLint vorder, const GLfloat *points))found)(index, size, u1, u2, ustride, uorder, v1, v2, vstride, vorder, points);
}

static void d_point_parameterf(GLIContext ctx, GLenum pname, GLfloat param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPointParameterf");
    if (found) ((void (*)(GLenum pname, GLfloat param))found)(pname, param);
}

static void d_point_parameterfv(GLIContext ctx, GLenum pname, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPointParameterfv");
    if (found) ((void (*)(GLenum pname, const GLfloat *params))found)(pname, params);
}

static void d_point_parameteri(GLIContext ctx, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPointParameteri");
    if (found) ((void (*)(GLenum pname, GLint param))found)(pname, param);
}

static void d_point_parameteriv(GLIContext ctx, GLenum pname, const GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPointParameteriv");
    if (found) ((void (*)(GLenum pname, const GLint *params))found)(pname, params);
}

static void d_fog_coordf(GLIContext ctx, GLfloat coord) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFogCoordf");
    if (found) ((void (*)(GLfloat coord))found)(coord);
}

static void d_fog_coordfv(GLIContext ctx, const GLfloat *coord) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFogCoordfv");
    if (found) ((void (*)(const GLfloat *coord))found)(coord);
}

static void d_fog_coordd(GLIContext ctx, GLdouble coord) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFogCoordd");
    if (found) ((void (*)(GLdouble coord))found)(coord);
}

static void d_fog_coorddv(GLIContext ctx, const GLdouble *coord) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFogCoorddv");
    if (found) ((void (*)(const GLdouble *coord))found)(coord);
}

static void d_fog_coord_pointer(GLIContext ctx, GLenum type, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFogCoordPointer");
    if (found) ((void (*)(GLenum type, GLsizei stride, const GLvoid *pointer))found)(type, stride, pointer);
}

static void d_vertex_array_parameteri_EXT(GLIContext ctx, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexArrayParameteriEXT");
    if (found) ((void (*)(GLenum pname, GLint param))found)(pname, param);
}

static void d_bind_vertex_array_EXT(GLIContext ctx, GLuint id) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBindVertexArrayEXT");
    if (found) ((void (*)(GLuint id))found)(id);
}

static void d_delete_vertex_arrays_EXT(GLIContext ctx, GLsizei n, const GLuint *ids) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDeleteVertexArraysEXT");
    if (found) ((void (*)(GLsizei n, const GLuint *ids))found)(n, ids);
}

static void d_gen_vertex_arrays_EXT(GLIContext ctx, GLsizei n, GLuint *ids) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGenVertexArraysEXT");
    if (found) ((void (*)(GLsizei n, GLuint *ids))found)(n, ids);
}

static GLboolean d_is_vertex_array_EXT(GLIContext ctx, GLuint id) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsVertexArrayEXT");
    return found ? ((GLboolean (*)(GLuint id))found)(id) : 0;
}

static void d_element_pointer_APPLE(GLIContext ctx, GLenum type, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glElementPointerAPPLE");
    if (found) ((void (*)(GLenum type, const GLvoid *pointer))found)(type, pointer);
}

static void d_draw_element_array_APPLE(GLIContext ctx, GLenum mode, GLint first, GLsizei count) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDrawElementArrayAPPLE");
    if (found) ((void (*)(GLenum mode, GLint first, GLsizei count))found)(mode, first, count);
}

static void d_draw_range_element_array_APPLE(GLIContext ctx, GLenum mode, GLuint start, GLuint end, GLint first, GLsizei count) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDrawRangeElementArrayAPPLE");
    if (found) ((void (*)(GLenum mode, GLuint start, GLuint end, GLint first, GLsizei count))found)(mode, start, end, first, count);
}

static void d_weightbv_ARB(GLIContext ctx, GLint size, const GLbyte *weights) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWeightbvARB");
    if (found) ((void (*)(GLint size, const GLbyte *weights))found)(size, weights);
}

static void d_weightsv_ARB(GLIContext ctx, GLint size, const GLshort *weights) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWeightsvARB");
    if (found) ((void (*)(GLint size, const GLshort *weights))found)(size, weights);
}

static void d_weightiv_ARB(GLIContext ctx, GLint size, const GLint *weights) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWeightivARB");
    if (found) ((void (*)(GLint size, const GLint *weights))found)(size, weights);
}

static void d_weightfv_ARB(GLIContext ctx, GLint size, const GLfloat *weights) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWeightfvARB");
    if (found) ((void (*)(GLint size, const GLfloat *weights))found)(size, weights);
}

static void d_weightdv_ARB(GLIContext ctx, GLint size, const GLdouble *weights) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWeightdvARB");
    if (found) ((void (*)(GLint size, const GLdouble *weights))found)(size, weights);
}

static void d_weightubv_ARB(GLIContext ctx, GLint size, const GLubyte *weights) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWeightubvARB");
    if (found) ((void (*)(GLint size, const GLubyte *weights))found)(size, weights);
}

static void d_weightusv_ARB(GLIContext ctx, GLint size, const GLushort *weights) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWeightusvARB");
    if (found) ((void (*)(GLint size, const GLushort *weights))found)(size, weights);
}

static void d_weightuiv_ARB(GLIContext ctx, GLint size, const GLuint *weights) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWeightuivARB");
    if (found) ((void (*)(GLint size, const GLuint *weights))found)(size, weights);
}

static void d_weight_pointer_ARB(GLIContext ctx, GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWeightPointerARB");
    if (found) ((void (*)(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer))found)(size, type, stride, pointer);
}

static void d_vertex_blend_ARB(GLIContext ctx, GLint count) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexBlendARB");
    if (found) ((void (*)(GLint count))found)(count);
}

static void d_multi_draw_arrays(GLIContext ctx, GLenum mode, const GLint *first, const GLsizei *count, GLsizei primcount) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiDrawArrays");
    if (found) ((void (*)(GLenum mode, const GLint *first, const GLsizei *count, GLsizei primcount))found)(mode, first, count, primcount);
}

static void d_multi_draw_elements(GLIContext ctx, GLenum mode, const GLsizei *count, GLenum type, const GLvoid **indices, GLsizei primcount) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiDrawElements");
    if (found) ((void (*)(GLenum mode, const GLsizei *count, GLenum type, const GLvoid **indices, GLsizei primcount))found)(mode, count, type, indices, primcount);
}

static void d_window_pos2d(GLIContext ctx, GLdouble x, GLdouble y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos2d");
    if (found) ((void (*)(GLdouble x, GLdouble y))found)(x, y);
}

static void d_window_pos2dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos2dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_window_pos2f(GLIContext ctx, GLfloat x, GLfloat y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos2f");
    if (found) ((void (*)(GLfloat x, GLfloat y))found)(x, y);
}

static void d_window_pos2fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos2fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_window_pos2i(GLIContext ctx, GLint x, GLint y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos2i");
    if (found) ((void (*)(GLint x, GLint y))found)(x, y);
}

static void d_window_pos2iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos2iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_window_pos2s(GLIContext ctx, GLshort x, GLshort y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos2s");
    if (found) ((void (*)(GLshort x, GLshort y))found)(x, y);
}

static void d_window_pos2sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos2sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_window_pos3d(GLIContext ctx, GLdouble x, GLdouble y, GLdouble z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos3d");
    if (found) ((void (*)(GLdouble x, GLdouble y, GLdouble z))found)(x, y, z);
}

static void d_window_pos3dv(GLIContext ctx, const GLdouble *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos3dv");
    if (found) ((void (*)(const GLdouble *v))found)(v);
}

static void d_window_pos3f(GLIContext ctx, GLfloat x, GLfloat y, GLfloat z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos3f");
    if (found) ((void (*)(GLfloat x, GLfloat y, GLfloat z))found)(x, y, z);
}

static void d_window_pos3fv(GLIContext ctx, const GLfloat *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos3fv");
    if (found) ((void (*)(const GLfloat *v))found)(v);
}

static void d_window_pos3i(GLIContext ctx, GLint x, GLint y, GLint z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos3i");
    if (found) ((void (*)(GLint x, GLint y, GLint z))found)(x, y, z);
}

static void d_window_pos3iv(GLIContext ctx, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos3iv");
    if (found) ((void (*)(const GLint *v))found)(v);
}

static void d_window_pos3s(GLIContext ctx, GLshort x, GLshort y, GLshort z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos3s");
    if (found) ((void (*)(GLshort x, GLshort y, GLshort z))found)(x, y, z);
}

static void d_window_pos3sv(GLIContext ctx, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glWindowPos3sv");
    if (found) ((void (*)(const GLshort *v))found)(v);
}

static void d_active_stencil_face_EXT(GLIContext ctx, GLenum face) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glActiveStencilFaceEXT");
    if (found) ((void (*)(GLenum face))found)(face);
}

static void d_stencil_op_separate_ATI(GLIContext ctx, GLenum face, GLenum sfail, GLenum dpfail, GLenum dppass) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glStencilOpSeparateATI");
    if (found) ((void (*)(GLenum face, GLenum sfail, GLenum dpfail, GLenum dppass))found)(face, sfail, dpfail, dppass);
}

static void d_stencil_func_separate_ATI(GLIContext ctx, GLenum frontfunc, GLenum backfunc, GLint ref, GLuint mask) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glStencilFuncSeparateATI");
    if (found) ((void (*)(GLenum frontfunc, GLenum backfunc, GLint ref, GLuint mask))found)(frontfunc, backfunc, ref, mask);
}

static void d_flush_render_APPLE(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFlushRenderAPPLE");
    if (found) ((void (*)(void))found)();
}

static void d_finish_render_APPLE(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFinishRenderAPPLE");
    if (found) ((void (*)(void))found)();
}

static void d_swap_APPLE(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glSwapAPPLE");
    if (found) ((void (*)(void))found)();
}

static void d_delete_object_ARB(GLIContext ctx, GLhandleARB obj) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDeleteObjectARB");
    if (found) ((void (*)(GLhandleARB obj))found)(obj);
}

static GLhandleARB d_get_handle_ARB(GLIContext ctx, GLenum pname) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetHandleARB");
    return found ? ((GLhandleARB (*)(GLenum pname))found)(pname) : 0;
}

static void d_detach_object_ARB(GLIContext ctx, GLhandleARB containerObj, GLhandleARB attachedObj) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDetachObjectARB");
    if (found) ((void (*)(GLhandleARB containerObj, GLhandleARB attachedObj))found)(containerObj, attachedObj);
}

static GLhandleARB d_create_shader_object_ARB(GLIContext ctx, GLenum shaderType) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCreateShaderObjectARB");
    return found ? ((GLhandleARB (*)(GLenum shaderType))found)(shaderType) : 0;
}

static void d_shader_source_ARB(GLIContext ctx, GLhandleARB shaderObj, GLsizei count, const GLcharARB **string, const GLint *length) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glShaderSourceARB");
    if (found) ((void (*)(GLhandleARB shaderObj, GLsizei count, const GLcharARB **string, const GLint *length))found)(shaderObj, count, string, length);
}

static void d_compile_shader_ARB(GLIContext ctx, GLhandleARB shaderObj) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCompileShaderARB");
    if (found) ((void (*)(GLhandleARB shaderObj))found)(shaderObj);
}

static GLhandleARB d_create_program_object_ARB(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCreateProgramObjectARB");
    return found ? ((GLhandleARB (*)(void))found)() : 0;
}

static void d_attach_object_ARB(GLIContext ctx, GLhandleARB containerObj, GLhandleARB obj) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glAttachObjectARB");
    if (found) ((void (*)(GLhandleARB containerObj, GLhandleARB obj))found)(containerObj, obj);
}

static void d_link_program_ARB(GLIContext ctx, GLhandleARB programObj) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glLinkProgramARB");
    if (found) ((void (*)(GLhandleARB programObj))found)(programObj);
}

static void d_use_program_object_ARB(GLIContext ctx, GLhandleARB programObj) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUseProgramObjectARB");
    if (found) ((void (*)(GLhandleARB programObj))found)(programObj);
}

static void d_validate_program_ARB(GLIContext ctx, GLhandleARB programObj) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glValidateProgramARB");
    if (found) ((void (*)(GLhandleARB programObj))found)(programObj);
}

static void d_uniform1f_ARB(GLIContext ctx, GLint location, GLfloat v0) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform1fARB");
    if (found) ((void (*)(GLint location, GLfloat v0))found)(location, v0);
}

static void d_uniform2f_ARB(GLIContext ctx, GLint location, GLfloat v0, GLfloat v1) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform2fARB");
    if (found) ((void (*)(GLint location, GLfloat v0, GLfloat v1))found)(location, v0, v1);
}

static void d_uniform3f_ARB(GLIContext ctx, GLint location, GLfloat v0, GLfloat v1, GLfloat v2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform3fARB");
    if (found) ((void (*)(GLint location, GLfloat v0, GLfloat v1, GLfloat v2))found)(location, v0, v1, v2);
}

static void d_uniform4f_ARB(GLIContext ctx, GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform4fARB");
    if (found) ((void (*)(GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3))found)(location, v0, v1, v2, v3);
}

static void d_uniform1i_ARB(GLIContext ctx, GLint location, GLint v0) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform1iARB");
    if (found) ((void (*)(GLint location, GLint v0))found)(location, v0);
}

static void d_uniform2i_ARB(GLIContext ctx, GLint location, GLint v0, GLint v1) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform2iARB");
    if (found) ((void (*)(GLint location, GLint v0, GLint v1))found)(location, v0, v1);
}

static void d_uniform3i_ARB(GLIContext ctx, GLint location, GLint v0, GLint v1, GLint v2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform3iARB");
    if (found) ((void (*)(GLint location, GLint v0, GLint v1, GLint v2))found)(location, v0, v1, v2);
}

static void d_uniform4i_ARB(GLIContext ctx, GLint location, GLint v0, GLint v1, GLint v2, GLint v3) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform4iARB");
    if (found) ((void (*)(GLint location, GLint v0, GLint v1, GLint v2, GLint v3))found)(location, v0, v1, v2, v3);
}

static void d_uniform1fv_ARB(GLIContext ctx, GLint location, GLsizei count, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform1fvARB");
    if (found) ((void (*)(GLint location, GLsizei count, const GLfloat *value))found)(location, count, value);
}

static void d_uniform2fv_ARB(GLIContext ctx, GLint location, GLsizei count, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform2fvARB");
    if (found) ((void (*)(GLint location, GLsizei count, const GLfloat *value))found)(location, count, value);
}

static void d_uniform3fv_ARB(GLIContext ctx, GLint location, GLsizei count, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform3fvARB");
    if (found) ((void (*)(GLint location, GLsizei count, const GLfloat *value))found)(location, count, value);
}

static void d_uniform4fv_ARB(GLIContext ctx, GLint location, GLsizei count, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform4fvARB");
    if (found) ((void (*)(GLint location, GLsizei count, const GLfloat *value))found)(location, count, value);
}

static void d_uniform1iv_ARB(GLIContext ctx, GLint location, GLsizei count, const GLint *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform1ivARB");
    if (found) ((void (*)(GLint location, GLsizei count, const GLint *value))found)(location, count, value);
}

static void d_uniform2iv_ARB(GLIContext ctx, GLint location, GLsizei count, const GLint *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform2ivARB");
    if (found) ((void (*)(GLint location, GLsizei count, const GLint *value))found)(location, count, value);
}

static void d_uniform3iv_ARB(GLIContext ctx, GLint location, GLsizei count, const GLint *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform3ivARB");
    if (found) ((void (*)(GLint location, GLsizei count, const GLint *value))found)(location, count, value);
}

static void d_uniform4iv_ARB(GLIContext ctx, GLint location, GLsizei count, const GLint *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform4ivARB");
    if (found) ((void (*)(GLint location, GLsizei count, const GLint *value))found)(location, count, value);
}

static void d_uniform_matrix2fv_ARB(GLIContext ctx, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniformMatrix2fvARB");
    if (found) ((void (*)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value))found)(location, count, transpose, value);
}

static void d_uniform_matrix3fv_ARB(GLIContext ctx, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniformMatrix3fvARB");
    if (found) ((void (*)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value))found)(location, count, transpose, value);
}

static void d_uniform_matrix4fv_ARB(GLIContext ctx, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniformMatrix4fvARB");
    if (found) ((void (*)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value))found)(location, count, transpose, value);
}

static void d_get_object_parameterfv_ARB(GLIContext ctx, GLhandleARB obj, GLenum pname, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetObjectParameterfvARB");
    if (found) ((void (*)(GLhandleARB obj, GLenum pname, GLfloat *params))found)(obj, pname, params);
}

static void d_get_object_parameteriv_ARB(GLIContext ctx, GLhandleARB obj, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetObjectParameterivARB");
    if (found) ((void (*)(GLhandleARB obj, GLenum pname, GLint *params))found)(obj, pname, params);
}

static void d_get_info_log_ARB(GLIContext ctx, GLhandleARB obj, GLsizei maxLength, GLsizei *length, GLcharARB *infoLog) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetInfoLogARB");
    if (found) ((void (*)(GLhandleARB obj, GLsizei maxLength, GLsizei *length, GLcharARB *infoLog))found)(obj, maxLength, length, infoLog);
}

static void d_get_attached_objects_ARB(GLIContext ctx, GLhandleARB containerObj, GLsizei maxCount, GLsizei *count, GLhandleARB *obj) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetAttachedObjectsARB");
    if (found) ((void (*)(GLhandleARB containerObj, GLsizei maxCount, GLsizei *count, GLhandleARB *obj))found)(containerObj, maxCount, count, obj);
}

static GLint d_get_uniform_location_ARB(GLIContext ctx, GLhandleARB programObj, const GLcharARB *name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetUniformLocationARB");
    return found ? ((GLint (*)(GLhandleARB programObj, const GLcharARB *name))found)(programObj, name) : 0;
}

static void d_get_active_uniform_ARB(GLIContext ctx, GLhandleARB programObj, GLuint index, GLsizei maxLength, GLsizei *length, GLint *size, GLenum *type, GLcharARB *name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetActiveUniformARB");
    if (found) ((void (*)(GLhandleARB programObj, GLuint index, GLsizei maxLength, GLsizei *length, GLint *size, GLenum *type, GLcharARB *name))found)(programObj, index, maxLength, length, size, type, name);
}

static void d_get_uniformfv_ARB(GLIContext ctx, GLhandleARB programObj, GLint location, GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetUniformfvARB");
    if (found) ((void (*)(GLhandleARB programObj, GLint location, GLfloat *params))found)(programObj, location, params);
}

static void d_get_uniformiv_ARB(GLIContext ctx, GLhandleARB programObj, GLint location, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetUniformivARB");
    if (found) ((void (*)(GLhandleARB programObj, GLint location, GLint *params))found)(programObj, location, params);
}

static void d_get_shader_source_ARB(GLIContext ctx, GLhandleARB obj, GLsizei maxLength, GLsizei *length, GLcharARB *source) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetShaderSourceARB");
    if (found) ((void (*)(GLhandleARB obj, GLsizei maxLength, GLsizei *length, GLcharARB *source))found)(obj, maxLength, length, source);
}

static void d_bind_attrib_location_ARB(GLIContext ctx, GLhandleARB programObj, GLuint index, const GLcharARB *name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBindAttribLocationARB");
    if (found) ((void (*)(GLhandleARB programObj, GLuint index, const GLcharARB *name))found)(programObj, index, name);
}

static void d_get_active_attrib_ARB(GLIContext ctx, GLhandleARB programObj, GLuint index, GLsizei maxLength, GLsizei *length, GLint *size, GLenum *type, GLcharARB *name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetActiveAttribARB");
    if (found) ((void (*)(GLhandleARB programObj, GLuint index, GLsizei maxLength, GLsizei *length, GLint *size, GLenum *type, GLcharARB *name))found)(programObj, index, maxLength, length, size, type, name);
}

static GLint d_get_attrib_location_ARB(GLIContext ctx, GLhandleARB programObj, const GLcharARB *name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetAttribLocationARB");
    return found ? ((GLint (*)(GLhandleARB programObj, const GLcharARB *name))found)(programObj, name) : 0;
}

static void d_pad(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glPad");
    if (found) ((void (*)(void))found)();
}

static void d_gen_queries(GLIContext ctx, GLsizei n, GLuint *ids) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGenQueries");
    if (found) ((void (*)(GLsizei n, GLuint *ids))found)(n, ids);
}

static void d_delete_queries(GLIContext ctx, GLsizei n, const GLuint *ids) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDeleteQueries");
    if (found) ((void (*)(GLsizei n, const GLuint *ids))found)(n, ids);
}

static GLboolean d_is_query(GLIContext ctx, GLuint id) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsQuery");
    return found ? ((GLboolean (*)(GLuint id))found)(id) : 0;
}

static void d_begin_query(GLIContext ctx, GLenum target, GLuint id) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBeginQuery");
    if (found) ((void (*)(GLenum target, GLuint id))found)(target, id);
}

static void d_end_query(GLIContext ctx, GLenum target) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEndQuery");
    if (found) ((void (*)(GLenum target))found)(target);
}

static void d_get_queryiv(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetQueryiv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static void d_get_query_objectiv(GLIContext ctx, GLuint id, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetQueryObjectiv");
    if (found) ((void (*)(GLuint id, GLenum pname, GLint *params))found)(id, pname, params);
}

static void d_get_query_objectuiv(GLIContext ctx, GLuint id, GLenum pname, GLuint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetQueryObjectuiv");
    if (found) ((void (*)(GLuint id, GLenum pname, GLuint *params))found)(id, pname, params);
}

static void d_bind_buffer(GLIContext ctx, GLenum target, GLuint buffer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBindBuffer");
    if (found) ((void (*)(GLenum target, GLuint buffer))found)(target, buffer);
}

static void d_delete_buffers(GLIContext ctx, GLsizei n, const GLuint *buffers) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDeleteBuffers");
    if (found) ((void (*)(GLsizei n, const GLuint *buffers))found)(n, buffers);
}

static void d_gen_buffers(GLIContext ctx, GLsizei n, GLuint *buffers) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGenBuffers");
    if (found) ((void (*)(GLsizei n, GLuint *buffers))found)(n, buffers);
}

static GLboolean d_is_buffer(GLIContext ctx, GLuint buffer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsBuffer");
    return found ? ((GLboolean (*)(GLuint buffer))found)(buffer) : 0;
}

static void d_buffer_data(GLIContext ctx, GLenum target, GLsizeiptrARB size, const GLvoid *data, GLenum usage) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBufferData");
    if (found) ((void (*)(GLenum target, GLsizeiptrARB size, const GLvoid *data, GLenum usage))found)(target, size, data, usage);
}

static void d_buffer_sub_data(GLIContext ctx, GLenum target, GLintptrARB offset, GLsizeiptrARB size, const GLvoid *data) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBufferSubData");
    if (found) ((void (*)(GLenum target, GLintptrARB offset, GLsizeiptrARB size, const GLvoid *data))found)(target, offset, size, data);
}

static void d_get_buffer_sub_data(GLIContext ctx, GLenum target, GLintptrARB offset, GLsizeiptrARB size, GLvoid *data) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetBufferSubData");
    if (found) ((void (*)(GLenum target, GLintptrARB offset, GLsizeiptrARB size, GLvoid *data))found)(target, offset, size, data);
}

static GLvoid * d_map_buffer(GLIContext ctx, GLenum target, GLenum access) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMapBuffer");
    return found ? ((GLvoid * (*)(GLenum target, GLenum access))found)(target, access) : 0;
}

static GLboolean d_unmap_buffer(GLIContext ctx, GLenum target) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUnmapBuffer");
    return found ? ((GLboolean (*)(GLenum target))found)(target) : 0;
}

static void d_get_buffer_parameteriv(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetBufferParameteriv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static void d_get_buffer_pointerv(GLIContext ctx, GLenum target, GLenum pname, GLvoid **params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetBufferPointerv");
    if (found) ((void (*)(GLenum target, GLenum pname, GLvoid **params))found)(target, pname, params);
}

static void d_depth_bounds_EXT(GLIContext ctx, GLclampd zmin, GLclampd zmax) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDepthBoundsEXT");
    if (found) ((void (*)(GLclampd zmin, GLclampd zmax))found)(zmin, zmax);
}

static void d_draw_buffers_ARB(GLIContext ctx, GLsizei n, const GLenum *bufs) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDrawBuffersARB");
    if (found) ((void (*)(GLsizei n, const GLenum *bufs))found)(n, bufs);
}

static GLboolean d_is_shader(GLIContext ctx, GLuint shader) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsShader");
    return found ? ((GLboolean (*)(GLuint shader))found)(shader) : 0;
}

static GLboolean d_is_program(GLIContext ctx, GLuint program) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsProgram");
    return found ? ((GLboolean (*)(GLuint program))found)(program) : 0;
}

static void d_get_shaderiv(GLIContext ctx, GLuint shader, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetShaderiv");
    if (found) ((void (*)(GLuint shader, GLenum pname, GLint *params))found)(shader, pname, params);
}

static void d_get_programiv(GLIContext ctx, GLuint program, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetProgramiv");
    if (found) ((void (*)(GLuint program, GLenum pname, GLint *params))found)(program, pname, params);
}

static void d_get_shader_info_log(GLIContext ctx, GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetShaderInfoLog");
    if (found) ((void (*)(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog))found)(shader, bufSize, length, infoLog);
}

static void d_get_program_info_log(GLIContext ctx, GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetProgramInfoLog");
    if (found) ((void (*)(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog))found)(program, bufSize, length, infoLog);
}

static void d_stencil_func_separate(GLIContext ctx, GLenum face, GLenum func, GLint ref, GLuint mask) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glStencilFuncSeparate");
    if (found) ((void (*)(GLenum face, GLenum func, GLint ref, GLuint mask))found)(face, func, ref, mask);
}

static void d_stencil_mask_separate(GLIContext ctx, GLenum face, GLuint mask) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glStencilMaskSeparate");
    if (found) ((void (*)(GLenum face, GLuint mask))found)(face, mask);
}

static void d_multi_draw_element_array_APPLE(GLIContext ctx, GLenum mode, const GLint *first, const GLsizei *count, GLsizei primcount) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiDrawElementArrayAPPLE");
    if (found) ((void (*)(GLenum mode, const GLint *first, const GLsizei *count, GLsizei primcount))found)(mode, first, count, primcount);
}

static void d_multi_draw_range_element_array_APPLE(GLIContext ctx, GLenum mode, GLuint start, GLuint end, const GLint *first, const GLsizei *count, GLsizei primcount) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glMultiDrawRangeElementArrayAPPLE");
    if (found) ((void (*)(GLenum mode, GLuint start, GLuint end, const GLint *first, const GLsizei *count, GLsizei primcount))found)(mode, start, end, first, count, primcount);
}

static GLboolean d_is_renderbuffer_EXT(GLIContext ctx, GLuint renderbuffer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsRenderbufferEXT");
    return found ? ((GLboolean (*)(GLuint renderbuffer))found)(renderbuffer) : 0;
}

static void d_bind_renderbuffer_EXT(GLIContext ctx, GLenum target, GLuint renderbuffer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBindRenderbufferEXT");
    if (found) ((void (*)(GLenum target, GLuint renderbuffer))found)(target, renderbuffer);
}

static void d_delete_renderbuffers_EXT(GLIContext ctx, GLsizei n, const GLuint *renderbuffers) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDeleteRenderbuffersEXT");
    if (found) ((void (*)(GLsizei n, const GLuint *renderbuffers))found)(n, renderbuffers);
}

static void d_gen_renderbuffers_EXT(GLIContext ctx, GLsizei n, GLuint *renderbuffers) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGenRenderbuffersEXT");
    if (found) ((void (*)(GLsizei n, GLuint *renderbuffers))found)(n, renderbuffers);
}

static void d_renderbuffer_storage_EXT(GLIContext ctx, GLenum target, GLenum internalformat, GLsizei width, GLsizei height) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRenderbufferStorageEXT");
    if (found) ((void (*)(GLenum target, GLenum internalformat, GLsizei width, GLsizei height))found)(target, internalformat, width, height);
}

static void d_get_renderbuffer_parameteriv_EXT(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetRenderbufferParameterivEXT");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static GLboolean d_is_framebuffer_EXT(GLIContext ctx, GLuint framebuffer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glIsFramebufferEXT");
    return found ? ((GLboolean (*)(GLuint framebuffer))found)(framebuffer) : 0;
}

static void d_bind_framebuffer_EXT(GLIContext ctx, GLenum target, GLuint framebuffer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBindFramebufferEXT");
    if (found) ((void (*)(GLenum target, GLuint framebuffer))found)(target, framebuffer);
}

static void d_delete_framebuffers_EXT(GLIContext ctx, GLsizei n, const GLuint *framebuffers) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDeleteFramebuffersEXT");
    if (found) ((void (*)(GLsizei n, const GLuint *framebuffers))found)(n, framebuffers);
}

static void d_gen_framebuffers_EXT(GLIContext ctx, GLsizei n, GLuint *framebuffers) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGenFramebuffersEXT");
    if (found) ((void (*)(GLsizei n, GLuint *framebuffers))found)(n, framebuffers);
}

static GLenum d_check_framebuffer_status_EXT(GLIContext ctx, GLenum target) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glCheckFramebufferStatusEXT");
    return found ? ((GLenum (*)(GLenum target))found)(target) : 0;
}

static void d_framebuffer_texture1D_EXT(GLIContext ctx, GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFramebufferTexture1DEXT");
    if (found) ((void (*)(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level))found)(target, attachment, textarget, texture, level);
}

static void d_framebuffer_texture2D_EXT(GLIContext ctx, GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFramebufferTexture2DEXT");
    if (found) ((void (*)(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level))found)(target, attachment, textarget, texture, level);
}

static void d_framebuffer_texture3D_EXT(GLIContext ctx, GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level, GLint zoffset) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFramebufferTexture3DEXT");
    if (found) ((void (*)(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level, GLint zoffset))found)(target, attachment, textarget, texture, level, zoffset);
}

static void d_framebuffer_renderbuffer_EXT(GLIContext ctx, GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFramebufferRenderbufferEXT");
    if (found) ((void (*)(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer))found)(target, attachment, renderbuffertarget, renderbuffer);
}

static void d_get_framebuffer_attachment_parameteriv_EXT(GLIContext ctx, GLenum target, GLenum attachment, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetFramebufferAttachmentParameterivEXT");
    if (found) ((void (*)(GLenum target, GLenum attachment, GLenum pname, GLint *params))found)(target, attachment, pname, params);
}

static void d_generate_mipmap_EXT(GLIContext ctx, GLenum target) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGenerateMipmapEXT");
    if (found) ((void (*)(GLenum target))found)(target);
}

static void d_buffer_parameteri_APPLE(GLIContext ctx, GLenum target, GLenum pname, GLint param) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBufferParameteriAPPLE");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint param))found)(target, pname, param);
}

static void d_flush_mapped_buffer_range_APPLE(GLIContext ctx, GLenum target, GLintptrARB offset, GLsizeiptrARB size) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFlushMappedBufferRangeAPPLE");
    if (found) ((void (*)(GLenum target, GLintptrARB offset, GLsizeiptrARB size))found)(target, offset, size);
}

static void d_program_env_parameters4fv_EXT(GLIContext ctx, GLenum target, GLuint index, GLsizei count, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramEnvParameters4fvEXT");
    if (found) ((void (*)(GLenum target, GLuint index, GLsizei count, const GLfloat *params))found)(target, index, count, params);
}

static void d_program_local_parameters4fv_EXT(GLIContext ctx, GLenum target, GLuint index, GLsizei count, const GLfloat *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramLocalParameters4fvEXT");
    if (found) ((void (*)(GLenum target, GLuint index, GLsizei count, const GLfloat *params))found)(target, index, count, params);
}

static GLenum d_object_purgeable_APPLE(GLIContext ctx, GLenum objectType, GLuint name, GLenum option) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glObjectPurgeableAPPLE");
    return found ? ((GLenum (*)(GLenum objectType, GLuint name, GLenum option))found)(objectType, name, option) : 0;
}

static GLenum d_object_unpurgeable_APPLE(GLIContext ctx, GLenum objectType, GLuint name, GLenum option) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glObjectUnpurgeableAPPLE");
    return found ? ((GLenum (*)(GLenum objectType, GLuint name, GLenum option))found)(objectType, name, option) : 0;
}

static void d_get_object_parameteriv_APPLE(GLIContext ctx, GLenum objectType, GLuint name, GLenum pname, GLint* params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetObjectParameterivAPPLE");
    if (found) ((void (*)(GLenum objectType, GLuint name, GLenum pname, GLint* params))found)(objectType, name, pname, params);
}

static void d_program_parameteri_EXT(GLIContext ctx, GLuint program_name, GLenum pname, GLint value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glProgramParameteriEXT");
    if (found) ((void (*)(GLuint program_name, GLenum pname, GLint value))found)(program_name, pname, value);
}

static void d_framebuffer_texture_EXT(GLIContext ctx, GLenum target, GLenum attachment, GLuint texture, GLint level) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFramebufferTextureEXT");
    if (found) ((void (*)(GLenum target, GLenum attachment, GLuint texture, GLint level))found)(target, attachment, texture, level);
}

static void d_framebuffer_texture_layer_EXT(GLIContext ctx, GLenum target, GLenum attachment, GLuint texture, GLint level, GLint layer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFramebufferTextureLayerEXT");
    if (found) ((void (*)(GLenum target, GLenum attachment, GLuint texture, GLint level, GLint layer))found)(target, attachment, texture, level, layer);
}

static void d_framebuffer_texture_face_EXT(GLIContext ctx, GLenum target, GLenum attachment, GLuint texture, GLint level, GLenum face) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glFramebufferTextureFaceEXT");
    if (found) ((void (*)(GLenum target, GLenum attachment, GLuint texture, GLint level, GLenum face))found)(target, attachment, texture, level, face);
}

static void d_bind_buffer_range_EXT(GLIContext ctx, GLenum target, GLuint index, GLuint buffer, GLintptr offset, GLsizeiptr size) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBindBufferRangeEXT");
    if (found) ((void (*)(GLenum target, GLuint index, GLuint buffer, GLintptr offset, GLsizeiptr size))found)(target, index, buffer, offset, size);
}

static void d_bind_buffer_offset_EXT(GLIContext ctx, GLenum target, GLuint index, GLuint buffer, GLintptr offset) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBindBufferOffsetEXT");
    if (found) ((void (*)(GLenum target, GLuint index, GLuint buffer, GLintptr offset))found)(target, index, buffer, offset);
}

static void d_bind_buffer_base_EXT(GLIContext ctx, GLenum target, GLuint index, GLuint buffer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBindBufferBaseEXT");
    if (found) ((void (*)(GLenum target, GLuint index, GLuint buffer))found)(target, index, buffer);
}

static void d_begin_transform_feedback_EXT(GLIContext ctx, GLenum primitiveMode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBeginTransformFeedbackEXT");
    if (found) ((void (*)(GLenum primitiveMode))found)(primitiveMode);
}

static void d_end_transform_feedback_EXT(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glEndTransformFeedbackEXT");
    if (found) ((void (*)(void))found)();
}

static void d_transform_feedback_varyings_EXT(GLIContext ctx, GLuint program, GLsizei count, const GLchar **varyings, GLenum bufferMode) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTransformFeedbackVaryingsEXT");
    if (found) ((void (*)(GLuint program, GLsizei count, const GLchar **varyings, GLenum bufferMode))found)(program, count, varyings, bufferMode);
}

static void d_get_transform_feedback_varying_EXT(GLIContext ctx, GLuint program, GLuint index, GLsizei bufSize, GLsizei *length, GLsizei *size, GLenum *type, GLchar *name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTransformFeedbackVaryingEXT");
    if (found) ((void (*)(GLuint program, GLuint index, GLsizei bufSize, GLsizei *length, GLsizei *size, GLenum *type, GLchar *name))found)(program, index, bufSize, length, size, type, name);
}

static void d_get_integer_indexedv_EXT(GLIContext ctx, GLenum param, GLuint index, GLint *values) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetIntegerIndexedvEXT");
    if (found) ((void (*)(GLenum param, GLuint index, GLint *values))found)(param, index, values);
}

static void d_get_boolean_indexedv_EXT(GLIContext ctx, GLenum param, GLuint index, GLboolean *values) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetBooleanIndexedvEXT");
    if (found) ((void (*)(GLenum param, GLuint index, GLboolean *values))found)(param, index, values);
}

static void d_uniform_buffer_EXT(GLIContext ctx, GLuint program, GLint location, GLuint buffer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniformBufferEXT");
    if (found) ((void (*)(GLuint program, GLint location, GLuint buffer))found)(program, location, buffer);
}

static GLint d_get_uniform_buffer_size_EXT(GLIContext ctx, GLuint program, GLint location) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetUniformBufferSizeEXT");
    return found ? ((GLint (*)(GLuint program, GLint location))found)(program, location) : 0;
}

static GLintptr d_get_uniform_buffer_offset_EXT(GLIContext ctx, GLuint program, GLint location) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetUniformBufferOffsetEXT");
    return found ? ((GLintptr (*)(GLuint program, GLint location))found)(program, location) : 0;
}

static void d_clear_colorIi_EXT(GLIContext ctx, GLint r, GLint g, GLint b, GLint a) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glClearColorIiEXT");
    if (found) ((void (*)(GLint r, GLint g, GLint b, GLint a))found)(r, g, b, a);
}

static void d_clear_colorIui_EXT(GLIContext ctx, GLuint r, GLuint g, GLuint b, GLuint a) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glClearColorIuiEXT");
    if (found) ((void (*)(GLuint r, GLuint g, GLuint b, GLuint a))found)(r, g, b, a);
}

static void d_tex_parameterIiv_EXT(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexParameterIivEXT");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static void d_tex_parameterIuiv_EXT(GLIContext ctx, GLenum target, GLenum pname, GLuint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glTexParameterIuivEXT");
    if (found) ((void (*)(GLenum target, GLenum pname, GLuint *params))found)(target, pname, params);
}

static void d_get_tex_parameterIiv_EXT(GLIContext ctx, GLenum target, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexParameterIivEXT");
    if (found) ((void (*)(GLenum target, GLenum pname, GLint *params))found)(target, pname, params);
}

static void d_get_tex_parameterIiuv_EXT(GLIContext ctx, GLenum target, GLenum pname, GLuint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetTexParameterIiuvEXT");
    if (found) ((void (*)(GLenum target, GLenum pname, GLuint *params))found)(target, pname, params);
}

static void d_vertex_attribI1i_EXT(GLIContext ctx, GLuint index, GLint x) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI1iEXT");
    if (found) ((void (*)(GLuint index, GLint x))found)(index, x);
}

static void d_vertex_attribI2i_EXT(GLIContext ctx, GLuint index, GLint x, GLint y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI2iEXT");
    if (found) ((void (*)(GLuint index, GLint x, GLint y))found)(index, x, y);
}

static void d_vertex_attribI3i_EXT(GLIContext ctx, GLuint index, GLint x, GLint y, GLint z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI3iEXT");
    if (found) ((void (*)(GLuint index, GLint x, GLint y, GLint z))found)(index, x, y, z);
}

static void d_vertex_attribI4i_EXT(GLIContext ctx, GLuint index, GLint x, GLint y, GLint z, GLint w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI4iEXT");
    if (found) ((void (*)(GLuint index, GLint x, GLint y, GLint z, GLint w))found)(index, x, y, z, w);
}

static void d_vertex_attribI1ui_EXT(GLIContext ctx, GLuint index, GLuint x) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI1uiEXT");
    if (found) ((void (*)(GLuint index, GLuint x))found)(index, x);
}

static void d_vertex_attribI2ui_EXT(GLIContext ctx, GLuint index, GLuint x, GLuint y) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI2uiEXT");
    if (found) ((void (*)(GLuint index, GLuint x, GLuint y))found)(index, x, y);
}

static void d_vertex_attribI3ui_EXT(GLIContext ctx, GLuint index, GLuint x, GLuint y, GLuint z) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI3uiEXT");
    if (found) ((void (*)(GLuint index, GLuint x, GLuint y, GLuint z))found)(index, x, y, z);
}

static void d_vertex_attribI4ui_EXT(GLIContext ctx, GLuint index, GLuint x, GLuint y, GLuint z, GLuint w) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI4uiEXT");
    if (found) ((void (*)(GLuint index, GLuint x, GLuint y, GLuint z, GLuint w))found)(index, x, y, z, w);
}

static void d_vertex_attribI1iv_EXT(GLIContext ctx, GLuint index, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI1ivEXT");
    if (found) ((void (*)(GLuint index, const GLint *v))found)(index, v);
}

static void d_vertex_attribI2iv_EXT(GLIContext ctx, GLuint index, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI2ivEXT");
    if (found) ((void (*)(GLuint index, const GLint *v))found)(index, v);
}

static void d_vertex_attribI3iv_EXT(GLIContext ctx, GLuint index, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI3ivEXT");
    if (found) ((void (*)(GLuint index, const GLint *v))found)(index, v);
}

static void d_vertex_attribI4iv_EXT(GLIContext ctx, GLuint index, const GLint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI4ivEXT");
    if (found) ((void (*)(GLuint index, const GLint *v))found)(index, v);
}

static void d_vertex_attribI1uiv_EXT(GLIContext ctx, GLuint index, const GLuint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI1uivEXT");
    if (found) ((void (*)(GLuint index, const GLuint *v))found)(index, v);
}

static void d_vertex_attribI2uiv_EXT(GLIContext ctx, GLuint index, const GLuint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI2uivEXT");
    if (found) ((void (*)(GLuint index, const GLuint *v))found)(index, v);
}

static void d_vertex_attribI3uiv_EXT(GLIContext ctx, GLuint index, const GLuint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI3uivEXT");
    if (found) ((void (*)(GLuint index, const GLuint *v))found)(index, v);
}

static void d_vertex_attribI4uiv_EXT(GLIContext ctx, GLuint index, const GLuint *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI4uivEXT");
    if (found) ((void (*)(GLuint index, const GLuint *v))found)(index, v);
}

static void d_vertex_attribI4bv_EXT(GLIContext ctx, GLuint index, const GLbyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI4bvEXT");
    if (found) ((void (*)(GLuint index, const GLbyte *v))found)(index, v);
}

static void d_vertex_attribI4sv_EXT(GLIContext ctx, GLuint index, const GLshort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI4svEXT");
    if (found) ((void (*)(GLuint index, const GLshort *v))found)(index, v);
}

static void d_vertex_attribI4ubv_EXT(GLIContext ctx, GLuint index, const GLubyte *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI4ubvEXT");
    if (found) ((void (*)(GLuint index, const GLubyte *v))found)(index, v);
}

static void d_vertex_attribI4usv_EXT(GLIContext ctx, GLuint index, const GLushort *v) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribI4usvEXT");
    if (found) ((void (*)(GLuint index, const GLushort *v))found)(index, v);
}

static void d_vertex_attribI_pointer_EXT(GLIContext ctx, GLuint index, GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glVertexAttribIPointerEXT");
    if (found) ((void (*)(GLuint index, GLint size, GLenum type, GLsizei stride, const GLvoid *pointer))found)(index, size, type, stride, pointer);
}

static void d_get_vertex_attribIiv_EXT(GLIContext ctx, GLuint index, GLenum pname, GLint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetVertexAttribIivEXT");
    if (found) ((void (*)(GLuint index, GLenum pname, GLint *params))found)(index, pname, params);
}

static void d_get_vertex_attribIuiv_EXT(GLIContext ctx, GLuint index, GLenum pname, GLuint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetVertexAttribIuivEXT");
    if (found) ((void (*)(GLuint index, GLenum pname, GLuint *params))found)(index, pname, params);
}

static void d_uniform1ui_EXT(GLIContext ctx, GLint location, GLuint v0) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform1uiEXT");
    if (found) ((void (*)(GLint location, GLuint v0))found)(location, v0);
}

static void d_uniform2ui_EXT(GLIContext ctx, GLint location, GLuint v0, GLuint v1) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform2uiEXT");
    if (found) ((void (*)(GLint location, GLuint v0, GLuint v1))found)(location, v0, v1);
}

static void d_uniform3ui_EXT(GLIContext ctx, GLint location, GLuint v0, GLuint v1, GLuint v2) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform3uiEXT");
    if (found) ((void (*)(GLint location, GLuint v0, GLuint v1, GLuint v2))found)(location, v0, v1, v2);
}

static void d_uniform4ui_EXT(GLIContext ctx, GLint location, GLuint v0, GLuint v1, GLuint v2, GLuint v3) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform4uiEXT");
    if (found) ((void (*)(GLint location, GLuint v0, GLuint v1, GLuint v2, GLuint v3))found)(location, v0, v1, v2, v3);
}

static void d_uniform1uiv_EXT(GLIContext ctx, GLint location, GLsizei count, const GLuint *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform1uivEXT");
    if (found) ((void (*)(GLint location, GLsizei count, const GLuint *value))found)(location, count, value);
}

static void d_uniform2uiv_EXT(GLIContext ctx, GLint location, GLsizei count, const GLuint *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform2uivEXT");
    if (found) ((void (*)(GLint location, GLsizei count, const GLuint *value))found)(location, count, value);
}

static void d_uniform3uiv_EXT(GLIContext ctx, GLint location, GLsizei count, const GLuint *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform3uivEXT");
    if (found) ((void (*)(GLint location, GLsizei count, const GLuint *value))found)(location, count, value);
}

static void d_uniform4uiv_EXT(GLIContext ctx, GLint location, GLsizei count, const GLuint *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniform4uivEXT");
    if (found) ((void (*)(GLint location, GLsizei count, const GLuint *value))found)(location, count, value);
}

static void d_get_uniformuiv_EXT(GLIContext ctx, GLuint program, GLint location, GLuint *params) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetUniformuivEXT");
    if (found) ((void (*)(GLuint program, GLint location, GLuint *params))found)(program, location, params);
}

static void d_bind_frag_data_location_EXT(GLIContext ctx, GLuint program, GLuint colorNumber, const GLchar *name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBindFragDataLocationEXT");
    if (found) ((void (*)(GLuint program, GLuint colorNumber, const GLchar *name))found)(program, colorNumber, name);
}

static GLint d_get_frag_data_location_EXT(GLIContext ctx, GLuint program, const GLchar *name) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetFragDataLocationEXT");
    return found ? ((GLint (*)(GLuint program, const GLchar *name))found)(program, name) : 0;
}

static void d_shader_binary_OES(GLIContext ctx, GLint n, GLuint *shaders, GLenum binaryformat, const GLvoid *binary, GLint length) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glShaderBinaryOES");
    if (found) ((void (*)(GLint n, GLuint *shaders, GLenum binaryformat, const GLvoid *binary, GLint length))found)(n, shaders, binaryformat, binary, length);
}

static void d_get_shader_precision_format_OES(GLIContext ctx, GLenum shadertype, GLenum precisiontype, GLint *range, GLint *precision) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetShaderPrecisionFormatOES");
    if (found) ((void (*)(GLenum shadertype, GLenum precisiontype, GLint *range, GLint *precision))found)(shadertype, precisiontype, range, precision);
}

static void d_release_shader_compiler_OES(GLIContext ctx) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glReleaseShaderCompilerOES");
    if (found) ((void (*)(void))found)();
}

static void d_get_renderbuffer_storage_formatsiv_OES(GLIContext ctx, GLenum target, GLint n, GLint *listofformats, GLint *numsupportedformats) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glGetRenderbufferStorageFormatsivOES");
    if (found) ((void (*)(GLenum target, GLint n, GLint *listofformats, GLint *numsupportedformats))found)(target, n, listofformats, numsupportedformats);
}

static void d_uniform_matrix2x3fv(GLIContext ctx, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniformMatrix2x3fv");
    if (found) ((void (*)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value))found)(location, count, transpose, value);
}

static void d_uniform_matrix3x2fv(GLIContext ctx, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniformMatrix3x2fv");
    if (found) ((void (*)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value))found)(location, count, transpose, value);
}

static void d_uniform_matrix2x4fv(GLIContext ctx, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniformMatrix2x4fv");
    if (found) ((void (*)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value))found)(location, count, transpose, value);
}

static void d_uniform_matrix4x2fv(GLIContext ctx, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniformMatrix4x2fv");
    if (found) ((void (*)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value))found)(location, count, transpose, value);
}

static void d_uniform_matrix3x4fv(GLIContext ctx, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniformMatrix3x4fv");
    if (found) ((void (*)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value))found)(location, count, transpose, value);
}

static void d_uniform_matrix4x3fv(GLIContext ctx, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glUniformMatrix4x3fv");
    if (found) ((void (*)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value))found)(location, count, transpose, value);
}

static void d_blit_framebuffer_EXT(GLIContext ctx, GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1, GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1, GLbitfield mask, GLenum filter) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glBlitFramebufferEXT");
    if (found) ((void (*)(GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1, GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1, GLbitfield mask, GLenum filter))found)(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter);
}

static void d_renderbuffer_storage_multisample_EXT(GLIContext ctx, GLenum target, GLsizei samples, GLenum internalformat, GLsizei width, GLsizei height) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glRenderbufferStorageMultisampleEXT");
    if (found) ((void (*)(GLenum target, GLsizei samples, GLenum internalformat, GLsizei width, GLsizei height))found)(target, samples, internalformat, width, height);
}

static void d_depth_rangef(GLIContext ctx, GLclampf zNear, GLclampf zFar) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glDepthRangef");
    if (found) ((void (*)(GLclampf zNear, GLclampf zFar))found)(zNear, zFar);
}

static void d_clear_depthf(GLIContext ctx, GLclampf depth) {
    static void *function;
    static int looked;
    (void)ctx;
    void *found = resolve(&function, &looked, "_glClearDepthf");
    if (found) ((void (*)(GLclampf depth))found)(depth);
}

/// The table, in gliDispatch.h's order: 759 entries.
const void *const perry_agl_dispatch[759] = {
    (const void *)d_accum,
    (const void *)d_alpha_func,
    (const void *)d_are_textures_resident,
    (const void *)d_array_element,
    (const void *)d_begin,
    (const void *)d_bind_texture,
    (const void *)d_bitmap,
    (const void *)d_blend_func,
    (const void *)d_call_list,
    (const void *)d_call_lists,
    (const void *)d_clear,
    (const void *)d_clear_accum,
    (const void *)d_clear_color,
    (const void *)d_clear_depth,
    (const void *)d_clear_index,
    (const void *)d_clear_stencil,
    (const void *)d_clip_plane,
    (const void *)d_color3b,
    (const void *)d_color3bv,
    (const void *)d_color3d,
    (const void *)d_color3dv,
    (const void *)d_color3f,
    (const void *)d_color3fv,
    (const void *)d_color3i,
    (const void *)d_color3iv,
    (const void *)d_color3s,
    (const void *)d_color3sv,
    (const void *)d_color3ub,
    (const void *)d_color3ubv,
    (const void *)d_color3ui,
    (const void *)d_color3uiv,
    (const void *)d_color3us,
    (const void *)d_color3usv,
    (const void *)d_color4b,
    (const void *)d_color4bv,
    (const void *)d_color4d,
    (const void *)d_color4dv,
    (const void *)d_color4f,
    (const void *)d_color4fv,
    (const void *)d_color4i,
    (const void *)d_color4iv,
    (const void *)d_color4s,
    (const void *)d_color4sv,
    (const void *)d_color4ub,
    (const void *)d_color4ubv,
    (const void *)d_color4ui,
    (const void *)d_color4uiv,
    (const void *)d_color4us,
    (const void *)d_color4usv,
    (const void *)d_color_mask,
    (const void *)d_color_material,
    (const void *)d_color_pointer,
    (const void *)d_copy_pixels,
    (const void *)d_copy_tex_image1D,
    (const void *)d_copy_tex_image2D,
    (const void *)d_copy_tex_sub_image1D,
    (const void *)d_copy_tex_sub_image2D,
    (const void *)d_cull_face,
    (const void *)d_delete_lists,
    (const void *)d_delete_textures,
    (const void *)d_depth_func,
    (const void *)d_depth_mask,
    (const void *)d_depth_range,
    (const void *)d_disable,
    (const void *)d_disable_client_state,
    (const void *)d_draw_arrays,
    (const void *)d_draw_buffer,
    (const void *)d_draw_elements,
    (const void *)d_draw_pixels,
    (const void *)d_edge_flag,
    (const void *)d_edge_flag_pointer,
    (const void *)d_edge_flagv,
    (const void *)d_enable,
    (const void *)d_enable_client_state,
    (const void *)d_end,
    (const void *)d_end_list,
    (const void *)d_eval_coord1d,
    (const void *)d_eval_coord1dv,
    (const void *)d_eval_coord1f,
    (const void *)d_eval_coord1fv,
    (const void *)d_eval_coord2d,
    (const void *)d_eval_coord2dv,
    (const void *)d_eval_coord2f,
    (const void *)d_eval_coord2fv,
    (const void *)d_eval_mesh1,
    (const void *)d_eval_mesh2,
    (const void *)d_eval_point1,
    (const void *)d_eval_point2,
    (const void *)d_feedback_buffer,
    (const void *)d_finish,
    (const void *)d_flush,
    (const void *)d_fogf,
    (const void *)d_fogfv,
    (const void *)d_fogi,
    (const void *)d_fogiv,
    (const void *)d_front_face,
    (const void *)d_frustum,
    (const void *)d_gen_lists,
    (const void *)d_gen_textures,
    (const void *)d_get_booleanv,
    (const void *)d_get_clip_plane,
    (const void *)d_get_doublev,
    (const void *)d_get_error,
    (const void *)d_get_floatv,
    (const void *)d_get_integerv,
    (const void *)d_get_lightfv,
    (const void *)d_get_lightiv,
    (const void *)d_get_mapdv,
    (const void *)d_get_mapfv,
    (const void *)d_get_mapiv,
    (const void *)d_get_materialfv,
    (const void *)d_get_materialiv,
    (const void *)d_get_pixel_mapfv,
    (const void *)d_get_pixel_mapuiv,
    (const void *)d_get_pixel_mapusv,
    (const void *)d_get_pointerv,
    (const void *)d_get_polygon_stipple,
    (const void *)d_get_string,
    (const void *)d_get_tex_envfv,
    (const void *)d_get_tex_enviv,
    (const void *)d_get_tex_gendv,
    (const void *)d_get_tex_genfv,
    (const void *)d_get_tex_geniv,
    (const void *)d_get_tex_image,
    (const void *)d_get_tex_level_parameterfv,
    (const void *)d_get_tex_level_parameteriv,
    (const void *)d_get_tex_parameterfv,
    (const void *)d_get_tex_parameteriv,
    (const void *)d_hint,
    (const void *)d_index_mask,
    (const void *)d_index_pointer,
    (const void *)d_indexd,
    (const void *)d_indexdv,
    (const void *)d_indexf,
    (const void *)d_indexfv,
    (const void *)d_indexi,
    (const void *)d_indexiv,
    (const void *)d_indexs,
    (const void *)d_indexsv,
    (const void *)d_indexub,
    (const void *)d_indexubv,
    (const void *)d_init_names,
    (const void *)d_interleaved_arrays,
    (const void *)d_is_enabled,
    (const void *)d_is_list,
    (const void *)d_is_texture,
    (const void *)d_light_modelf,
    (const void *)d_light_modelfv,
    (const void *)d_light_modeli,
    (const void *)d_light_modeliv,
    (const void *)d_lightf,
    (const void *)d_lightfv,
    (const void *)d_lighti,
    (const void *)d_lightiv,
    (const void *)d_line_stipple,
    (const void *)d_line_width,
    (const void *)d_list_base,
    (const void *)d_load_identity,
    (const void *)d_load_matrixd,
    (const void *)d_load_matrixf,
    (const void *)d_load_name,
    (const void *)d_logic_op,
    (const void *)d_map1d,
    (const void *)d_map1f,
    (const void *)d_map2d,
    (const void *)d_map2f,
    (const void *)d_map_grid1d,
    (const void *)d_map_grid1f,
    (const void *)d_map_grid2d,
    (const void *)d_map_grid2f,
    (const void *)d_materialf,
    (const void *)d_materialfv,
    (const void *)d_materiali,
    (const void *)d_materialiv,
    (const void *)d_matrix_mode,
    (const void *)d_mult_matrixd,
    (const void *)d_mult_matrixf,
    (const void *)d_new_list,
    (const void *)d_normal3b,
    (const void *)d_normal3bv,
    (const void *)d_normal3d,
    (const void *)d_normal3dv,
    (const void *)d_normal3f,
    (const void *)d_normal3fv,
    (const void *)d_normal3i,
    (const void *)d_normal3iv,
    (const void *)d_normal3s,
    (const void *)d_normal3sv,
    (const void *)d_normal_pointer,
    (const void *)d_ortho,
    (const void *)d_pass_through,
    (const void *)d_pixel_mapfv,
    (const void *)d_pixel_mapuiv,
    (const void *)d_pixel_mapusv,
    (const void *)d_pixel_storef,
    (const void *)d_pixel_storei,
    (const void *)d_pixel_transferf,
    (const void *)d_pixel_transferi,
    (const void *)d_pixel_zoom,
    (const void *)d_point_size,
    (const void *)d_polygon_mode,
    (const void *)d_polygon_offset,
    (const void *)d_polygon_stipple,
    (const void *)d_pop_attrib,
    (const void *)d_pop_client_attrib,
    (const void *)d_pop_matrix,
    (const void *)d_pop_name,
    (const void *)d_prioritize_textures,
    (const void *)d_push_attrib,
    (const void *)d_push_client_attrib,
    (const void *)d_push_matrix,
    (const void *)d_push_name,
    (const void *)d_raster_pos2d,
    (const void *)d_raster_pos2dv,
    (const void *)d_raster_pos2f,
    (const void *)d_raster_pos2fv,
    (const void *)d_raster_pos2i,
    (const void *)d_raster_pos2iv,
    (const void *)d_raster_pos2s,
    (const void *)d_raster_pos2sv,
    (const void *)d_raster_pos3d,
    (const void *)d_raster_pos3dv,
    (const void *)d_raster_pos3f,
    (const void *)d_raster_pos3fv,
    (const void *)d_raster_pos3i,
    (const void *)d_raster_pos3iv,
    (const void *)d_raster_pos3s,
    (const void *)d_raster_pos3sv,
    (const void *)d_raster_pos4d,
    (const void *)d_raster_pos4dv,
    (const void *)d_raster_pos4f,
    (const void *)d_raster_pos4fv,
    (const void *)d_raster_pos4i,
    (const void *)d_raster_pos4iv,
    (const void *)d_raster_pos4s,
    (const void *)d_raster_pos4sv,
    (const void *)d_read_buffer,
    (const void *)d_read_pixels,
    (const void *)d_rectd,
    (const void *)d_rectdv,
    (const void *)d_rectf,
    (const void *)d_rectfv,
    (const void *)d_recti,
    (const void *)d_rectiv,
    (const void *)d_rects,
    (const void *)d_rectsv,
    (const void *)d_render_mode,
    (const void *)d_rotated,
    (const void *)d_rotatef,
    (const void *)d_scaled,
    (const void *)d_scalef,
    (const void *)d_scissor,
    (const void *)d_select_buffer,
    (const void *)d_shade_model,
    (const void *)d_stencil_func,
    (const void *)d_stencil_mask,
    (const void *)d_stencil_op,
    (const void *)d_tex_coord1d,
    (const void *)d_tex_coord1dv,
    (const void *)d_tex_coord1f,
    (const void *)d_tex_coord1fv,
    (const void *)d_tex_coord1i,
    (const void *)d_tex_coord1iv,
    (const void *)d_tex_coord1s,
    (const void *)d_tex_coord1sv,
    (const void *)d_tex_coord2d,
    (const void *)d_tex_coord2dv,
    (const void *)d_tex_coord2f,
    (const void *)d_tex_coord2fv,
    (const void *)d_tex_coord2i,
    (const void *)d_tex_coord2iv,
    (const void *)d_tex_coord2s,
    (const void *)d_tex_coord2sv,
    (const void *)d_tex_coord3d,
    (const void *)d_tex_coord3dv,
    (const void *)d_tex_coord3f,
    (const void *)d_tex_coord3fv,
    (const void *)d_tex_coord3i,
    (const void *)d_tex_coord3iv,
    (const void *)d_tex_coord3s,
    (const void *)d_tex_coord3sv,
    (const void *)d_tex_coord4d,
    (const void *)d_tex_coord4dv,
    (const void *)d_tex_coord4f,
    (const void *)d_tex_coord4fv,
    (const void *)d_tex_coord4i,
    (const void *)d_tex_coord4iv,
    (const void *)d_tex_coord4s,
    (const void *)d_tex_coord4sv,
    (const void *)d_tex_coord_pointer,
    (const void *)d_tex_envf,
    (const void *)d_tex_envfv,
    (const void *)d_tex_envi,
    (const void *)d_tex_enviv,
    (const void *)d_tex_gend,
    (const void *)d_tex_gendv,
    (const void *)d_tex_genf,
    (const void *)d_tex_genfv,
    (const void *)d_tex_geni,
    (const void *)d_tex_geniv,
    (const void *)d_tex_image1D,
    (const void *)d_tex_image2D,
    (const void *)d_tex_parameterf,
    (const void *)d_tex_parameterfv,
    (const void *)d_tex_parameteri,
    (const void *)d_tex_parameteriv,
    (const void *)d_tex_sub_image1D,
    (const void *)d_tex_sub_image2D,
    (const void *)d_translated,
    (const void *)d_translatef,
    (const void *)d_vertex2d,
    (const void *)d_vertex2dv,
    (const void *)d_vertex2f,
    (const void *)d_vertex2fv,
    (const void *)d_vertex2i,
    (const void *)d_vertex2iv,
    (const void *)d_vertex2s,
    (const void *)d_vertex2sv,
    (const void *)d_vertex3d,
    (const void *)d_vertex3dv,
    (const void *)d_vertex3f,
    (const void *)d_vertex3fv,
    (const void *)d_vertex3i,
    (const void *)d_vertex3iv,
    (const void *)d_vertex3s,
    (const void *)d_vertex3sv,
    (const void *)d_vertex4d,
    (const void *)d_vertex4dv,
    (const void *)d_vertex4f,
    (const void *)d_vertex4fv,
    (const void *)d_vertex4i,
    (const void *)d_vertex4iv,
    (const void *)d_vertex4s,
    (const void *)d_vertex4sv,
    (const void *)d_vertex_pointer,
    (const void *)d_viewport,
    (const void *)d_blend_func_separate,
    (const void *)d_blend_color,
    (const void *)d_blend_equation,
    (const void *)d_lock_arrays_EXT,
    (const void *)d_unlock_arrays_EXT,
    (const void *)d_client_active_texture,
    (const void *)d_active_texture,
    (const void *)d_multi_tex_coord1d,
    (const void *)d_multi_tex_coord1dv,
    (const void *)d_multi_tex_coord1f,
    (const void *)d_multi_tex_coord1fv,
    (const void *)d_multi_tex_coord1i,
    (const void *)d_multi_tex_coord1iv,
    (const void *)d_multi_tex_coord1s,
    (const void *)d_multi_tex_coord1sv,
    (const void *)d_multi_tex_coord2d,
    (const void *)d_multi_tex_coord2dv,
    (const void *)d_multi_tex_coord2f,
    (const void *)d_multi_tex_coord2fv,
    (const void *)d_multi_tex_coord2i,
    (const void *)d_multi_tex_coord2iv,
    (const void *)d_multi_tex_coord2s,
    (const void *)d_multi_tex_coord2sv,
    (const void *)d_multi_tex_coord3d,
    (const void *)d_multi_tex_coord3dv,
    (const void *)d_multi_tex_coord3f,
    (const void *)d_multi_tex_coord3fv,
    (const void *)d_multi_tex_coord3i,
    (const void *)d_multi_tex_coord3iv,
    (const void *)d_multi_tex_coord3s,
    (const void *)d_multi_tex_coord3sv,
    (const void *)d_multi_tex_coord4d,
    (const void *)d_multi_tex_coord4dv,
    (const void *)d_multi_tex_coord4f,
    (const void *)d_multi_tex_coord4fv,
    (const void *)d_multi_tex_coord4i,
    (const void *)d_multi_tex_coord4iv,
    (const void *)d_multi_tex_coord4s,
    (const void *)d_multi_tex_coord4sv,
    (const void *)d_load_transpose_matrixd,
    (const void *)d_load_transpose_matrixf,
    (const void *)d_mult_transpose_matrixd,
    (const void *)d_mult_transpose_matrixf,
    (const void *)d_compressed_tex_image3D,
    (const void *)d_compressed_tex_image2D,
    (const void *)d_compressed_tex_image1D,
    (const void *)d_compressed_tex_sub_image3D,
    (const void *)d_compressed_tex_sub_image2D,
    (const void *)d_compressed_tex_sub_image1D,
    (const void *)d_get_compressed_tex_image,
    (const void *)d_secondary_color3b,
    (const void *)d_secondary_color3bv,
    (const void *)d_secondary_color3d,
    (const void *)d_secondary_color3dv,
    (const void *)d_secondary_color3f,
    (const void *)d_secondary_color3fv,
    (const void *)d_secondary_color3i,
    (const void *)d_secondary_color3iv,
    (const void *)d_secondary_color3s,
    (const void *)d_secondary_color3sv,
    (const void *)d_secondary_color3ub,
    (const void *)d_secondary_color3ubv,
    (const void *)d_secondary_color3ui,
    (const void *)d_secondary_color3uiv,
    (const void *)d_secondary_color3us,
    (const void *)d_secondary_color3usv,
    (const void *)d_secondary_color_pointer,
    (const void *)d_vertex_array_range_EXT,
    (const void *)d_flush_vertex_array_range_EXT,
    (const void *)d_draw_range_elements,
    (const void *)d_color_table,
    (const void *)d_color_table_parameterfv,
    (const void *)d_color_table_parameteriv,
    (const void *)d_copy_color_table,
    (const void *)d_get_color_table,
    (const void *)d_get_color_table_parameterfv,
    (const void *)d_get_color_table_parameteriv,
    (const void *)d_color_sub_table,
    (const void *)d_copy_color_sub_table,
    (const void *)d_convolution_filter1D,
    (const void *)d_convolution_filter2D,
    (const void *)d_convolution_parameterf,
    (const void *)d_convolution_parameterfv,
    (const void *)d_convolution_parameteri,
    (const void *)d_convolution_parameteriv,
    (const void *)d_copy_convolution_filter1D,
    (const void *)d_copy_convolution_filter2D,
    (const void *)d_get_convolution_filter,
    (const void *)d_get_convolution_parameterfv,
    (const void *)d_get_convolution_parameteriv,
    (const void *)d_get_separable_filter,
    (const void *)d_separable_filter2D,
    (const void *)d_get_histogram,
    (const void *)d_get_histogram_parameterfv,
    (const void *)d_get_histogram_parameteriv,
    (const void *)d_get_minmax,
    (const void *)d_get_minmax_parameterfv,
    (const void *)d_get_minmax_parameteriv,
    (const void *)d_histogram,
    (const void *)d_minmax,
    (const void *)d_reset_histogram,
    (const void *)d_reset_minmax,
    (const void *)d_tex_image3D,
    (const void *)d_tex_sub_image3D,
    (const void *)d_copy_tex_sub_image3D,
    (const void *)d_combiner_parameterfv_NV,
    (const void *)d_combiner_parameterf_NV,
    (const void *)d_combiner_parameteriv_NV,
    (const void *)d_combiner_parameteri_NV,
    (const void *)d_combiner_input_NV,
    (const void *)d_combiner_output_NV,
    (const void *)d_final_combiner_input_NV,
    (const void *)d_get_combiner_input_parameterfv_NV,
    (const void *)d_get_combiner_input_parameteriv_NV,
    (const void *)d_get_combiner_output_parameterfv_NV,
    (const void *)d_get_combiner_output_parameteriv_NV,
    (const void *)d_get_final_combiner_input_parameterfv_NV,
    (const void *)d_get_final_combiner_input_parameteriv_NV,
    (const void *)d_combiner_stage_parameterfv_NV,
    (const void *)d_get_combiner_stage_parameterfv_NV,
    (const void *)d_texture_range_APPLE,
    (const void *)d_get_tex_parameter_pointerv_APPLE,
    (const void *)d_blend_equation_separate_EXT,
    (const void *)d_sample_coverage,
    (const void *)d_sample_pass,
    (const void *)d_pn_trianglesi_ATI,
    (const void *)d_pn_trianglesf_ATI,
    (const void *)d_gen_fences_APPLE,
    (const void *)d_delete_fences_APPLE,
    (const void *)d_set_fence_APPLE,
    (const void *)d_is_fence_APPLE,
    (const void *)d_test_fence_APPLE,
    (const void *)d_finish_fence_APPLE,
    (const void *)d_test_object_APPLE,
    (const void *)d_finish_object_APPLE,
    (const void *)d_bind_program_ARB,
    (const void *)d_delete_programs_ARB,
    (const void *)d_gen_programs_ARB,
    (const void *)d_is_program_ARB,
    (const void *)d_vertex_attrib1s_ARB,
    (const void *)d_vertex_attrib1f_ARB,
    (const void *)d_vertex_attrib1d_ARB,
    (const void *)d_vertex_attrib2s_ARB,
    (const void *)d_vertex_attrib2f_ARB,
    (const void *)d_vertex_attrib2d_ARB,
    (const void *)d_vertex_attrib3s_ARB,
    (const void *)d_vertex_attrib3f_ARB,
    (const void *)d_vertex_attrib3d_ARB,
    (const void *)d_vertex_attrib4s_ARB,
    (const void *)d_vertex_attrib4f_ARB,
    (const void *)d_vertex_attrib4d_ARB,
    (const void *)d_vertex_attrib4Nub_ARB,
    (const void *)d_vertex_attrib1sv_ARB,
    (const void *)d_vertex_attrib1fv_ARB,
    (const void *)d_vertex_attrib1dv_ARB,
    (const void *)d_vertex_attrib2sv_ARB,
    (const void *)d_vertex_attrib2fv_ARB,
    (const void *)d_vertex_attrib2dv_ARB,
    (const void *)d_vertex_attrib3sv_ARB,
    (const void *)d_vertex_attrib3fv_ARB,
    (const void *)d_vertex_attrib3dv_ARB,
    (const void *)d_vertex_attrib4bv_ARB,
    (const void *)d_vertex_attrib4sv_ARB,
    (const void *)d_vertex_attrib4iv_ARB,
    (const void *)d_vertex_attrib4ubv_ARB,
    (const void *)d_vertex_attrib4usv_ARB,
    (const void *)d_vertex_attrib4uiv_ARB,
    (const void *)d_vertex_attrib4fv_ARB,
    (const void *)d_vertex_attrib4dv_ARB,
    (const void *)d_vertex_attrib4Nbv_ARB,
    (const void *)d_vertex_attrib4Nsv_ARB,
    (const void *)d_vertex_attrib4Niv_ARB,
    (const void *)d_vertex_attrib4Nubv_ARB,
    (const void *)d_vertex_attrib4Nusv_ARB,
    (const void *)d_vertex_attrib4Nuiv_ARB,
    (const void *)d_vertex_attrib_pointer_ARB,
    (const void *)d_enable_vertex_attrib_array_ARB,
    (const void *)d_disable_vertex_attrib_array_ARB,
    (const void *)d_get_vertex_attribdv_ARB,
    (const void *)d_get_vertex_attribfv_ARB,
    (const void *)d_get_vertex_attribiv_ARB,
    (const void *)d_get_vertex_attrib_pointerv_ARB,
    (const void *)d_program_env_parameter4d_ARB,
    (const void *)d_program_env_parameter4dv_ARB,
    (const void *)d_program_env_parameter4f_ARB,
    (const void *)d_program_env_parameter4fv_ARB,
    (const void *)d_program_local_parameter4d_ARB,
    (const void *)d_program_local_parameter4dv_ARB,
    (const void *)d_program_local_parameter4f_ARB,
    (const void *)d_program_local_parameter4fv_ARB,
    (const void *)d_get_program_env_parameterdv_ARB,
    (const void *)d_get_program_env_parameterfv_ARB,
    (const void *)d_get_program_local_parameterdv_ARB,
    (const void *)d_get_program_local_parameterfv_ARB,
    (const void *)d_program_string_ARB,
    (const void *)d_get_program_string_ARB,
    (const void *)d_get_programiv_ARB,
    (const void *)d_enable_vertex_attrib_ARB,
    (const void *)d_disable_vertex_attrib_ARB,
    (const void *)d_is_vertex_attrib_enabled_ARB,
    (const void *)d_map_vertex_attrib1d_ARB,
    (const void *)d_map_vertex_attrib1f_ARB,
    (const void *)d_map_vertex_attrib2d_ARB,
    (const void *)d_map_vertex_attrib2f_ARB,
    (const void *)d_point_parameterf,
    (const void *)d_point_parameterfv,
    (const void *)d_point_parameteri,
    (const void *)d_point_parameteriv,
    (const void *)d_fog_coordf,
    (const void *)d_fog_coordfv,
    (const void *)d_fog_coordd,
    (const void *)d_fog_coorddv,
    (const void *)d_fog_coord_pointer,
    (const void *)d_vertex_array_parameteri_EXT,
    (const void *)d_bind_vertex_array_EXT,
    (const void *)d_delete_vertex_arrays_EXT,
    (const void *)d_gen_vertex_arrays_EXT,
    (const void *)d_is_vertex_array_EXT,
    (const void *)d_element_pointer_APPLE,
    (const void *)d_draw_element_array_APPLE,
    (const void *)d_draw_range_element_array_APPLE,
    (const void *)d_weightbv_ARB,
    (const void *)d_weightsv_ARB,
    (const void *)d_weightiv_ARB,
    (const void *)d_weightfv_ARB,
    (const void *)d_weightdv_ARB,
    (const void *)d_weightubv_ARB,
    (const void *)d_weightusv_ARB,
    (const void *)d_weightuiv_ARB,
    (const void *)d_weight_pointer_ARB,
    (const void *)d_vertex_blend_ARB,
    (const void *)d_multi_draw_arrays,
    (const void *)d_multi_draw_elements,
    (const void *)d_window_pos2d,
    (const void *)d_window_pos2dv,
    (const void *)d_window_pos2f,
    (const void *)d_window_pos2fv,
    (const void *)d_window_pos2i,
    (const void *)d_window_pos2iv,
    (const void *)d_window_pos2s,
    (const void *)d_window_pos2sv,
    (const void *)d_window_pos3d,
    (const void *)d_window_pos3dv,
    (const void *)d_window_pos3f,
    (const void *)d_window_pos3fv,
    (const void *)d_window_pos3i,
    (const void *)d_window_pos3iv,
    (const void *)d_window_pos3s,
    (const void *)d_window_pos3sv,
    (const void *)d_active_stencil_face_EXT,
    (const void *)d_stencil_op_separate_ATI,
    (const void *)d_stencil_func_separate_ATI,
    (const void *)d_flush_render_APPLE,
    (const void *)d_finish_render_APPLE,
    (const void *)d_swap_APPLE,
    (const void *)d_delete_object_ARB,
    (const void *)d_get_handle_ARB,
    (const void *)d_detach_object_ARB,
    (const void *)d_create_shader_object_ARB,
    (const void *)d_shader_source_ARB,
    (const void *)d_compile_shader_ARB,
    (const void *)d_create_program_object_ARB,
    (const void *)d_attach_object_ARB,
    (const void *)d_link_program_ARB,
    (const void *)d_use_program_object_ARB,
    (const void *)d_validate_program_ARB,
    (const void *)d_uniform1f_ARB,
    (const void *)d_uniform2f_ARB,
    (const void *)d_uniform3f_ARB,
    (const void *)d_uniform4f_ARB,
    (const void *)d_uniform1i_ARB,
    (const void *)d_uniform2i_ARB,
    (const void *)d_uniform3i_ARB,
    (const void *)d_uniform4i_ARB,
    (const void *)d_uniform1fv_ARB,
    (const void *)d_uniform2fv_ARB,
    (const void *)d_uniform3fv_ARB,
    (const void *)d_uniform4fv_ARB,
    (const void *)d_uniform1iv_ARB,
    (const void *)d_uniform2iv_ARB,
    (const void *)d_uniform3iv_ARB,
    (const void *)d_uniform4iv_ARB,
    (const void *)d_uniform_matrix2fv_ARB,
    (const void *)d_uniform_matrix3fv_ARB,
    (const void *)d_uniform_matrix4fv_ARB,
    (const void *)d_get_object_parameterfv_ARB,
    (const void *)d_get_object_parameteriv_ARB,
    (const void *)d_get_info_log_ARB,
    (const void *)d_get_attached_objects_ARB,
    (const void *)d_get_uniform_location_ARB,
    (const void *)d_get_active_uniform_ARB,
    (const void *)d_get_uniformfv_ARB,
    (const void *)d_get_uniformiv_ARB,
    (const void *)d_get_shader_source_ARB,
    (const void *)d_bind_attrib_location_ARB,
    (const void *)d_get_active_attrib_ARB,
    (const void *)d_get_attrib_location_ARB,
    (const void *)d_pad,
    (const void *)d_gen_queries,
    (const void *)d_delete_queries,
    (const void *)d_is_query,
    (const void *)d_begin_query,
    (const void *)d_end_query,
    (const void *)d_get_queryiv,
    (const void *)d_get_query_objectiv,
    (const void *)d_get_query_objectuiv,
    (const void *)d_bind_buffer,
    (const void *)d_delete_buffers,
    (const void *)d_gen_buffers,
    (const void *)d_is_buffer,
    (const void *)d_buffer_data,
    (const void *)d_buffer_sub_data,
    (const void *)d_get_buffer_sub_data,
    (const void *)d_map_buffer,
    (const void *)d_unmap_buffer,
    (const void *)d_get_buffer_parameteriv,
    (const void *)d_get_buffer_pointerv,
    (const void *)d_depth_bounds_EXT,
    (const void *)d_draw_buffers_ARB,
    (const void *)d_is_shader,
    (const void *)d_is_program,
    (const void *)d_get_shaderiv,
    (const void *)d_get_programiv,
    (const void *)d_get_shader_info_log,
    (const void *)d_get_program_info_log,
    (const void *)d_stencil_func_separate,
    (const void *)d_stencil_mask_separate,
    (const void *)d_multi_draw_element_array_APPLE,
    (const void *)d_multi_draw_range_element_array_APPLE,
    (const void *)d_is_renderbuffer_EXT,
    (const void *)d_bind_renderbuffer_EXT,
    (const void *)d_delete_renderbuffers_EXT,
    (const void *)d_gen_renderbuffers_EXT,
    (const void *)d_renderbuffer_storage_EXT,
    (const void *)d_get_renderbuffer_parameteriv_EXT,
    (const void *)d_is_framebuffer_EXT,
    (const void *)d_bind_framebuffer_EXT,
    (const void *)d_delete_framebuffers_EXT,
    (const void *)d_gen_framebuffers_EXT,
    (const void *)d_check_framebuffer_status_EXT,
    (const void *)d_framebuffer_texture1D_EXT,
    (const void *)d_framebuffer_texture2D_EXT,
    (const void *)d_framebuffer_texture3D_EXT,
    (const void *)d_framebuffer_renderbuffer_EXT,
    (const void *)d_get_framebuffer_attachment_parameteriv_EXT,
    (const void *)d_generate_mipmap_EXT,
    (const void *)d_buffer_parameteri_APPLE,
    (const void *)d_flush_mapped_buffer_range_APPLE,
    (const void *)d_program_env_parameters4fv_EXT,
    (const void *)d_program_local_parameters4fv_EXT,
    (const void *)d_object_purgeable_APPLE,
    (const void *)d_object_unpurgeable_APPLE,
    (const void *)d_get_object_parameteriv_APPLE,
    (const void *)d_program_parameteri_EXT,
    (const void *)d_framebuffer_texture_EXT,
    (const void *)d_framebuffer_texture_layer_EXT,
    (const void *)d_framebuffer_texture_face_EXT,
    (const void *)d_bind_buffer_range_EXT,
    (const void *)d_bind_buffer_offset_EXT,
    (const void *)d_bind_buffer_base_EXT,
    (const void *)d_begin_transform_feedback_EXT,
    (const void *)d_end_transform_feedback_EXT,
    (const void *)d_transform_feedback_varyings_EXT,
    (const void *)d_get_transform_feedback_varying_EXT,
    (const void *)d_get_integer_indexedv_EXT,
    (const void *)d_get_boolean_indexedv_EXT,
    (const void *)d_uniform_buffer_EXT,
    (const void *)d_get_uniform_buffer_size_EXT,
    (const void *)d_get_uniform_buffer_offset_EXT,
    (const void *)d_clear_colorIi_EXT,
    (const void *)d_clear_colorIui_EXT,
    (const void *)d_tex_parameterIiv_EXT,
    (const void *)d_tex_parameterIuiv_EXT,
    (const void *)d_get_tex_parameterIiv_EXT,
    (const void *)d_get_tex_parameterIiuv_EXT,
    (const void *)d_vertex_attribI1i_EXT,
    (const void *)d_vertex_attribI2i_EXT,
    (const void *)d_vertex_attribI3i_EXT,
    (const void *)d_vertex_attribI4i_EXT,
    (const void *)d_vertex_attribI1ui_EXT,
    (const void *)d_vertex_attribI2ui_EXT,
    (const void *)d_vertex_attribI3ui_EXT,
    (const void *)d_vertex_attribI4ui_EXT,
    (const void *)d_vertex_attribI1iv_EXT,
    (const void *)d_vertex_attribI2iv_EXT,
    (const void *)d_vertex_attribI3iv_EXT,
    (const void *)d_vertex_attribI4iv_EXT,
    (const void *)d_vertex_attribI1uiv_EXT,
    (const void *)d_vertex_attribI2uiv_EXT,
    (const void *)d_vertex_attribI3uiv_EXT,
    (const void *)d_vertex_attribI4uiv_EXT,
    (const void *)d_vertex_attribI4bv_EXT,
    (const void *)d_vertex_attribI4sv_EXT,
    (const void *)d_vertex_attribI4ubv_EXT,
    (const void *)d_vertex_attribI4usv_EXT,
    (const void *)d_vertex_attribI_pointer_EXT,
    (const void *)d_get_vertex_attribIiv_EXT,
    (const void *)d_get_vertex_attribIuiv_EXT,
    (const void *)d_uniform1ui_EXT,
    (const void *)d_uniform2ui_EXT,
    (const void *)d_uniform3ui_EXT,
    (const void *)d_uniform4ui_EXT,
    (const void *)d_uniform1uiv_EXT,
    (const void *)d_uniform2uiv_EXT,
    (const void *)d_uniform3uiv_EXT,
    (const void *)d_uniform4uiv_EXT,
    (const void *)d_get_uniformuiv_EXT,
    (const void *)d_bind_frag_data_location_EXT,
    (const void *)d_get_frag_data_location_EXT,
    (const void *)d_shader_binary_OES,
    (const void *)d_get_shader_precision_format_OES,
    (const void *)d_release_shader_compiler_OES,
    (const void *)d_get_renderbuffer_storage_formatsiv_OES,
    (const void *)d_uniform_matrix2x3fv,
    (const void *)d_uniform_matrix3x2fv,
    (const void *)d_uniform_matrix2x4fv,
    (const void *)d_uniform_matrix4x2fv,
    (const void *)d_uniform_matrix3x4fv,
    (const void *)d_uniform_matrix4x3fv,
    (const void *)d_blit_framebuffer_EXT,
    (const void *)d_renderbuffer_storage_multisample_EXT,
    (const void *)d_depth_rangef,
    (const void *)d_clear_depthf,
};

const size_t perry_agl_dispatch_count = 759;
