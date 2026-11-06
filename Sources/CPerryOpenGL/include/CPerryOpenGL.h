#ifndef CPERRY_OPENGL_H
#define CPERRY_OPENGL_H

// Entry points for a program's OpenGL ES calls.
//
// An EAGLContext can be current on several threads at once; an EGL context
// is current on one. UIKit gives the EGL context to the thread that draws,
// when it draws: each gl function a program imports is entered through a
// few instructions made here, which go straight on to the host's function
// unless some thread's current context is not its own in EGL, and then
// call UIKit first.

/// Tells the entry points whether some thread's current EAGLContext is not
/// current to it in EGL (not zero), in which case they call UIKit first.
void perry_gl_set_contended(int contended);

/// What the entry points call first while contended: UIKit's, which gives
/// the calling thread its context.
void perry_gl_set_before_call(void (*before)(void));

/// An entry point for `function`, or `function` itself when none can be
/// made.
void *perry_gl_entry(void *function);

#endif
