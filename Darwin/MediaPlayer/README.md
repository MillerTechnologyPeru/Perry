# MediaPlayer

Perry's Swift overlay of MediaPlayer: what the library itself holds,
`MPMusicPlayerPlayParameters`' conformance to `Codable`, from the API in the
iOS SDK's `MediaPlayer.swiftinterface`. The rest of MediaPlayer's Swift API
is in the framework. It replaces the iOS Simulator's
`libswiftMediaPlayer.dylib`.

    Scripts/build-overlay.sh MediaPlayer <runtime directory>

Play parameters are coded as their dictionary: each key with its string,
Boolean or number value (a number as an integer, or as a double when it is
one). Decoding makes the parameters from the same dictionary, and stops
the program when the framework refuses it (the initializer can't fail).
`Scripts/check-overlay.sh` finds nothing missing against the simulator's
library.
