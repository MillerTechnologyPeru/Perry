# CoreTransferable

Perry's initial CoreTransferable ABI surface for SwiftUI loading: the
`Transferable` and `TransferRepresentation` protocols, a single-expression
representation builder, `Never` conformances, and a URL data representation.
URL data uses the absolute URL's UTF-8 bytes and rejects invalid UTF-8 on import.

This is a subset, not a complete sharing or drag-and-drop implementation.
Tuple, proxy, file and Codable representations, visibility, NSItemProvider
transport, and the newer import/export convenience APIs are not implemented.
Primitive representations store conversion closures; their `Never` body must
not be evaluated by a transport.

Build the ARM64 Darwin framework on macOS:

```sh
Scripts/build-framework.sh CoreTransferable
```

Run the native macOS representation tests:

```sh
swift test --package-path Darwin/CoreTransferable --scratch-path .build/coretransferable-tests
```

The protocol requirements follow Xcode's CoreTransferable Swift interface.
The exported protocol descriptor, Never witness table and URL conformance
match the symbols imported by Perry's SwiftUI overlay.
