# XPC

Perry's Swift overlay of XPC: the object constants (`XPC_TYPE_*`, the
booleans, the connection errors and keys), `XPCDictionary` and `XPCArray`
with their typed subscripts, `XPCLiteralValue`, `XPCEndpoint`,
`XPCSession`, `XPCListener` with its incoming session requests,
`XPCPeerRequirement`, `XPCReceivedMessage`, `XPCRichError`, and the Swift
forms of the session and listener C functions; written for Perry from the
API in the macOS SDK's `XPC.swiftinterface`. It replaces the Swift 5.0
overlay Xcode ships as a file, which a runtime directory made for an
x86_64 Mac app used to take.

It is compiled as the module `XPC` over the SDK's headers, with the
`Lifetimes` feature (`swiftc-flags`) for the `RawSpan` subscripts:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh XPC <runtime directory>

How it works:

- Dictionaries, arrays and the values in them are the C library's
  objects, read and made with its functions (Perry's `xpc.c` has them).
- A Codable message is a dictionary holding the value's encoding under
  the key `contents`: keyed containers encode as dictionaries, unkeyed
  ones as arrays, single values as XPC's scalars, and `XPCDictionary`,
  `XPCArray` and `XPCEndpoint` as their own objects. Sending and receiving
  sides here agree; Apple's own encoding of such messages is private.
- The session, listener, peer requirement and reply functions are looked
  up when first used. Where the runtime lacks them, as Perry's does (it has
  no connections), making a session or listener throws an `XPCRichError`
  and the rest does nothing; an anonymous listener is one no peer reaches.
- `XPCSession(endpoint:)`, the anonymous `XPCListener` and its `endpoint`
  call `xpc_session_create_xpc_endpoint`, `xpc_listener_create_anonymous`
  and `xpc_listener_create_endpoint`, which the library exports without
  headers; their arguments are taken to follow their public siblings'.
- `XPCReceivedMessage.isSync` is false: the C library tells only its own
  callers whether a sender waits.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftXPC.tbd`. What it still lacks:

- the initializing entry points (`fc`) of `XPCSession`'s and
  `XPCListener`'s convenience initializers, which only a subclass's
  initializer calls; Swift doesn't make them, and the classes can't be
  subclassed outside the module. The allocating ones programs call are
  there;
- what the library exports without a public declaration: the Codable
  machinery behind its messages (`XPCCodableObject`,
  `XPCCodableObjectRepresentable`, `XPCEncodedContents`,
  `TopLevelGraphEncodingNode`, `encodeToEncodingContainer`,
  `decodeFromEncodingContainer`, `encodeAsXPCObject`,
  `OS_xpc_object.decode(as:withUserInfo:)`, `CodingUserInfoKey.xpcCodable`,
  the `testEncodeDecodePipeline` functions, `Array.byteDescription`),
  `XPCSession`'s connection and audit-token members (`init(fromConnection:…)`,
  `extractConnection()`, `auditToken`, `rejectPeer(reason:)`,
  `setTargetUserSession(userIdentifier:)`, `send(_:userInfo:replyHandler:)`),
  `XPCListener`'s `setIncomingSessionHandler(_:)` and its requests'
  `_accept(_:)`, `withUnsafeAuditToken(_:)` and `satisfies(requirement:)`,
  `XPCReceivedMessage`'s `init(dictionary:)`, `detachHandoff()`,
  `reply(_:userInfo:)` and `decode(as:userInfo:)`,
  `XPCPeerRequirement.fromLWCRData(_:)` and `audit_token_t.satisfies(requirement:)`.

Other members exported without a declaration whose types say what they do
are here: the `[UInt8]` subscripts, `xpc_uuid_get_uuid` and
`xpc_uuid_create_with_uuid`, `XPCDictionary`'s `contains(key:)`,
`createReply()`, `sendReply()`, `encode(_:forKey:)`, `decode(as:forKey:)`
and `auditToken`, the less-used `XPC_TYPE_*` constants, `XPCListener`'s
`targetQueue` and `setPeerRequirement(_:)`, and `audit_token_t`'s fields.
