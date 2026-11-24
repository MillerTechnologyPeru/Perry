#ifndef PERRY_OPENGL_H
#define PERRY_OPENGL_H

void *perry_provider_symbol(const char *name);

/// Whether the current NSOpenGLContext was made with a core profile pixel
/// format (cgl.c).
int perry_cgl_current_is_core(void);

/// libGL's function of a Mac's name ("_glClear"), for the provider's own
/// drawing (provider.c).
void *perry_opengl_function(const char *name);

/// Auxiliary color buffers (auxiliary.c): the functions that replace libGL's,
/// what glGetIntegerv answers, and the copy to the window around a swap.
void *perry_aux_symbol(const char *name);
void perry_aux_integer(unsigned int name, int *values);
void perry_aux_before_swap(void);
void perry_aux_after_swap(void);

#endif
