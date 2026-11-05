// swift-cmark, built into the Docker image as static archives: the parser,
// its node tree, and GitHub's extensions (tables, strikethrough, autolinks).
// Nodes and extensions are complete types, as swift-cmark's own module
// has them.
#define CMARK_GFM_STATIC_DEFINE 1
#include <perry-cmark-gfm/cmark-gfm.h>
#include <perry-cmark-gfm/cmark-gfm-extension_api.h>
#include <perry-cmark-gfm/cmark-gfm-core-extensions.h>
#include <perry-cmark-gfm/node.h>
#include <perry-cmark-gfm/syntax_extension.h>
