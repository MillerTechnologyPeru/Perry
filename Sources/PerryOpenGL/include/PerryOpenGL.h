#ifndef PERRY_OPENGL_H
#define PERRY_OPENGL_H

void *perry_provider_symbol(const char *name);

/// Whether the current NSOpenGLContext was made with a core profile pixel
/// format (cgl.c).
int perry_cgl_current_is_core(void);

#endif
