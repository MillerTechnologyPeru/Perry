// CoreImage's Swift overlay adds no API of its own any more: the module
// re-exports the framework's Objective-C API, and the library exists for
// the symbol programs linked against it force-load.
@_exported import CoreImage
