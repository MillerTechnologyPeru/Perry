# Network

Perry's Swift overlay of Network: `NWConnection`, `NWListener`,
`NWBrowser`, `NWConnectionGroup`, `NWPathMonitor` (also an
`AsyncSequence`), `NWEthernetChannel`, `NWParameters` with its protocol
stack, privacy contexts and proxy configurations, the protocol options
and metadata (IP, TCP, UDP, TLS, QUIC, WebSocket, framers), endpoints,
addresses, interfaces, paths, TXT records and `TXTRecordDecoder`, and
macOS and iOS 26's protocol-stack API (`NetworkConnection`,
`NetworkChannel`, `NetworkListener`, `NetworkBrowser`, QUIC streams and
datagrams, `TLS { TCP { IP() } }` and the other protocol values,
`NWParametersBuilder`, `withNetworkConnection`), written for Perry from the
API in the macOS SDK's `Network.swiftinterface`. It replaces the Swift 5.0
overlay Xcode ships as a file, which a runtime directory made for an
x86_64 Mac app used to take, and the additions that were needed beside it
(Darwin/NetworkAdditions, folded in here).

It is compiled as the module `Network` over the SDK's C headers, and works
over the Network C API (`nw_*`), as Apple builds it:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh Network <runtime directory>

`Scripts/check-overlay.sh` against the Swift 5.0 overlay reports nothing
missing. Every declaration of the public interface is here (a symbol graph
of the SDK's interface against this module's differs only in the members
Swift synthesizes, which are in the binary). Against the SDK's
`libswiftNetwork.tbd`, the framework's own Swift symbols, it reports about
10,000, none of them of a public declaration: the framework's Swift
internals and Apple-private SPI, among them the Swift protocol
implementations (`QUICConnectionProtocol`, `TCPProtocol`, `IPProtocol`,
`SwiftTLSProtocol`, the harnesses and protocol handlers), HTTP types
(`HTTPField`, `HTTPRequest`, `HTTPResponse`), the distributed actor system
(`NetworkActorSystem`, `NWActorSystem`), `NWActivity`, Oblivious HTTP and
QUIC-stream parameters, pairing and invitations of listener services,
browse descriptor options, application service endpoints, the SPI
initializers from C API objects (`NWConnection(_: nw_connection_t)` and
the like), Codable conformances of the value types, and the initializing
entry points (`fc`) of convenience initializers (`NWConnection(host:port:using:)`,
`NWParameters(tls:tcp:)`, …), which only a subclass's initializer calls.

A Mac with Network.framework can run it: a program linked with
`-flat_namespace` and run with `DYLD_INSERT_LIBRARIES` set to this dylib
connects, listens, monitors paths and runs `NetworkListener` with
`NetworkConnection` over the system's C API.

How things are done here, where the C API leaves a gap:

- Most options have setters in the C API and no getters, so an options
  object keeps the values it set; one the C API made (from a parameters'
  protocol stack) answers the defaults until set. The C API can't replace
  a stack's IP options, so setting `ProtocolStack.internetProtocol` does
  nothing (change the options it answers instead).
- `NWParameters(tls:tcp:)`, `(dtls:udp:)` and `(quic:)` are made with
  `nw_parameters_create` and the options given put on the stack.
- An `NWInterface` named in an address (`fe80::1%en0`) has no C API
  object: it can't be required or prohibited on parameters, and an
  Ethernet channel on it fails with `ENXIO`.
- `NWError.wifiAware` is not marked macOS 26: a case with a payload can't
  be at this deployment target. Its layout is the same.
- In the protocol-stack API, TLV and Coder are framed in Swift above the
  protocol below them: a TLV is its type and length, big-endian, of the
  sizes given (4 bytes each by default), then its value; a coded value on a
  stream has a 4-byte length before it, on a datagram or message protocol
  it is a message of its own. This is Perry's wire format, not
  necessarily Apple's. A QUIC stream opened with protocols prepended takes
  the Swift framing; WebSocket or framer options can't be added to a
  stream taken from a group and are left out. A connection starts at its
  first use. `NetworkConnection<QUIC>.securityProtocolMetadata` can only
  answer once the connection is established. TLS early data is asked for
  with session tickets (there is no switch for it), and on macOS optional
  peer authentication is "not required".

Runtime: the overlay calls about 400 functions and data symbols of the
Network C API. Perry's runtime (Sources/PerrySystemConfiguration) has 35
of them (the path monitor, the browser, a few endpoint functions); the
connections, listeners, groups, parameters, protocol options, framers,
content contexts and reports need the rest.
