# DataDetection

Perry's Swift overlay of DataDetection, which has no API of its own: the
SDK's `DataDetection.swiftinterface` declares nothing, and programs built
against it link the library for its `_swift_FORCE_LOAD_$_swiftDataDetection`
symbol (`swiftc-flags`), finding their Swift API in the framework. It
replaces the iOS Simulator's `libswiftDataDetection.dylib`, so that the
library programs link is there.

    Scripts/build-overlay.sh DataDetection <runtime directory>
