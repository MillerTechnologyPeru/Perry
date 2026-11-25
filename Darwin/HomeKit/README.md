# HomeKit

Perry's Swift overlay of HomeKit: the one symbol the library itself holds,
the Swift 4 global `HMCharacteristicPropertySupportsEventNotification`, a
string. The rest of HomeKit's Swift API is in the framework, where the iOS
SDK's `HomeKit.swiftinterface` declares it. It replaces the iOS
Simulator's `libswiftHomeKit.dylib`.

    Scripts/build-overlay.sh HomeKit <runtime directory>

The Swift global hides the framework's constant of the same name, so it
reads the constant by its symbol (with `dlsym`), and answers the
constant's name where the process has none. `Scripts/check-overlay.sh`
finds nothing missing against the simulator's library.
