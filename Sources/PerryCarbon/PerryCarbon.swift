// libPerryCarbon: the provider for Carbon.framework, for Mac programs built
// before Cocoa took over. Its exports move here from CPerryCarbon's C, a
// part at a time, as Swift over Graphite, the Mac Toolbox in Swift
// (Documentation/Plans/graphite.md): this target converts Carbon's C types,
// Pascal strings, handles and result codes to Graphite's and back. Until a
// part moves, CPerryCarbon's C exports it.

@_exported import CPerryCarbon
