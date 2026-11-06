// OpenGL ES functions with floating-point parameters, for 32-bit Darwin
// code, which passes them in core registers where the host's armhf library
// takes them in VFP registers. Each thunk takes its floats Darwin's way
// (the base AAPCS) and calls the host's function; the rest of OpenGL ES
// takes integers and pointers, and binds to the host's directly.

#include "CPerryGeometry.h"

#if defined(__arm__)

#include <string.h>

typedef unsigned int GLenum, GLuint;
typedef int GLint;
typedef unsigned char GLboolean;
typedef float GLfloat;

#define THUNK(name, parameters, arguments) \
    static void (*host_##name) parameters; \
    __attribute__((pcs("aapcs"))) static void thunk_##name parameters { host_##name arguments; }

THUNK(glAlphaFunc, (GLenum function, GLfloat reference), (function, reference))
THUNK(glBlendColor, (GLfloat r, GLfloat g, GLfloat b, GLfloat a), (r, g, b, a))
THUNK(glClearColor, (GLfloat r, GLfloat g, GLfloat b, GLfloat a), (r, g, b, a))
THUNK(glClearDepthf, (GLfloat depth), (depth))
THUNK(glClearDepthfOES, (GLfloat depth), (depth))
THUNK(glColor4f, (GLfloat r, GLfloat g, GLfloat b, GLfloat a), (r, g, b, a))
THUNK(glDepthRangef, (GLfloat near, GLfloat far), (near, far))
THUNK(glDepthRangefOES, (GLfloat near, GLfloat far), (near, far))
THUNK(glDrawTexfOES, (GLfloat x, GLfloat y, GLfloat z, GLfloat width, GLfloat height), (x, y, z, width, height))
THUNK(glFogf, (GLenum name, GLfloat value), (name, value))
THUNK(glFrustumf, (GLfloat l, GLfloat r, GLfloat b, GLfloat t, GLfloat n, GLfloat f), (l, r, b, t, n, f))
THUNK(glFrustumfOES, (GLfloat l, GLfloat r, GLfloat b, GLfloat t, GLfloat n, GLfloat f), (l, r, b, t, n, f))
THUNK(glLightModelf, (GLenum name, GLfloat value), (name, value))
THUNK(glLightf, (GLenum light, GLenum name, GLfloat value), (light, name, value))
THUNK(glLineWidth, (GLfloat width), (width))
THUNK(glMaterialf, (GLenum face, GLenum name, GLfloat value), (face, name, value))
THUNK(glMinSampleShading, (GLfloat value), (value))
THUNK(glMultiTexCoord4f, (GLenum target, GLfloat s, GLfloat t, GLfloat r, GLfloat q), (target, s, t, r, q))
THUNK(glNormal3f, (GLfloat x, GLfloat y, GLfloat z), (x, y, z))
THUNK(glOrthof, (GLfloat l, GLfloat r, GLfloat b, GLfloat t, GLfloat n, GLfloat f), (l, r, b, t, n, f))
THUNK(glOrthofOES, (GLfloat l, GLfloat r, GLfloat b, GLfloat t, GLfloat n, GLfloat f), (l, r, b, t, n, f))
THUNK(glPointParameterf, (GLenum name, GLfloat value), (name, value))
THUNK(glPointSize, (GLfloat size), (size))
THUNK(glPolygonOffset, (GLfloat factor, GLfloat units), (factor, units))
THUNK(glRotatef, (GLfloat angle, GLfloat x, GLfloat y, GLfloat z), (angle, x, y, z))
THUNK(glSampleCoverage, (GLfloat value, GLboolean invert), (value, invert))
THUNK(glSamplerParameterf, (GLuint sampler, GLenum name, GLfloat value), (sampler, name, value))
THUNK(glScalef, (GLfloat x, GLfloat y, GLfloat z), (x, y, z))
THUNK(glTexEnvf, (GLenum target, GLenum name, GLfloat value), (target, name, value))
THUNK(glTexGenfOES, (GLenum coordinate, GLenum name, GLfloat value), (coordinate, name, value))
THUNK(glTexParameterf, (GLenum target, GLenum name, GLfloat value), (target, name, value))
THUNK(glTranslatef, (GLfloat x, GLfloat y, GLfloat z), (x, y, z))
THUNK(glUniform1f, (GLint location, GLfloat x), (location, x))
THUNK(glUniform2f, (GLint location, GLfloat x, GLfloat y), (location, x, y))
THUNK(glUniform3f, (GLint location, GLfloat x, GLfloat y, GLfloat z), (location, x, y, z))
THUNK(glUniform4f, (GLint location, GLfloat x, GLfloat y, GLfloat z, GLfloat w), (location, x, y, z, w))
THUNK(glVertexAttrib1f, (GLuint index, GLfloat x), (index, x))
THUNK(glVertexAttrib2f, (GLuint index, GLfloat x, GLfloat y), (index, x, y))
THUNK(glVertexAttrib3f, (GLuint index, GLfloat x, GLfloat y, GLfloat z), (index, x, y, z))
THUNK(glVertexAttrib4f, (GLuint index, GLfloat x, GLfloat y, GLfloat z, GLfloat w), (index, x, y, z, w))
THUNK(glClearBufferfi, (GLenum buffer, GLint drawbuffer, GLfloat depth, GLint stencil), (buffer, drawbuffer, depth, stencil))

#define ENTRY(name) { #name, (void **)&host_##name, (void *)thunk_##name }
static const struct { const char *name; void **host; void *thunk; } thunks[] = {
    ENTRY(glAlphaFunc), ENTRY(glBlendColor), ENTRY(glClearColor), ENTRY(glClearDepthf), ENTRY(glClearDepthfOES),
    ENTRY(glColor4f), ENTRY(glDepthRangef), ENTRY(glDepthRangefOES), ENTRY(glDrawTexfOES), ENTRY(glFogf),
    ENTRY(glFrustumf), ENTRY(glFrustumfOES), ENTRY(glLightModelf), ENTRY(glLightf), ENTRY(glLineWidth),
    ENTRY(glMaterialf), ENTRY(glMinSampleShading), ENTRY(glMultiTexCoord4f), ENTRY(glNormal3f), ENTRY(glOrthof),
    ENTRY(glOrthofOES), ENTRY(glPointParameterf), ENTRY(glPointSize), ENTRY(glPolygonOffset), ENTRY(glRotatef),
    ENTRY(glSampleCoverage), ENTRY(glSamplerParameterf), ENTRY(glScalef), ENTRY(glTexEnvf), ENTRY(glTexGenfOES),
    ENTRY(glTexParameterf), ENTRY(glTranslatef), ENTRY(glUniform1f), ENTRY(glUniform2f), ENTRY(glUniform3f),
    ENTRY(glUniform4f), ENTRY(glVertexAttrib1f), ENTRY(glVertexAttrib2f), ENTRY(glVertexAttrib3f),
    ENTRY(glVertexAttrib4f), ENTRY(glClearBufferfi),
};

void *perry_gles_darwin_function(const char *name, void *host) {
    for (unsigned i = 0; i < sizeof(thunks) / sizeof(thunks[0]); i++) {
        if (strcmp(thunks[i].name, name) == 0) {
            *thunks[i].host = host;
            return thunks[i].thunk;
        }
    }
    return host;
}

#else

void *perry_gles_darwin_function(const char *name, void *host) {
    (void)name;
    return host;
}

#endif
