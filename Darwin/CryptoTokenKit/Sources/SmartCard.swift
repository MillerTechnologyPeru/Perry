// CryptoTokenKit's Swift API: TKSmartCard's APDU transmission and sessions
// with Swift types, over the Objective-C methods the header refines for
// Swift (sendIns:p1:p2:data:le:reply:, sendIns:p1:p2:data:le:sw:error:,
// inSessionWithError:executeBlock:).

import Foundation

@available(macOS 10.10, iOS 9.0, tvOS 11.0, watchOS 4.0, visionOS 1.0, *)
extension TKSmartCard {
    /// Sends an APDU to the card; the reply gets the response data without
    /// its status bytes, the status word (SW1SW2), and the error if one.
    public func send(ins: UInt8, p1: UInt8, p2: UInt8, data: Data? = nil, le: Int? = nil,
                     reply: @escaping (Data?, UInt16, (any Error)?) -> Void) {
        __sendIns(ins, p1: p1, p2: p2, data: data, le: le.map { NSNumber(value: $0) }) { response, sw, error in
            reply(response, sw, error)
        }
    }

    /// Sends an APDU to the card in its session and waits for the
    /// response: its status word and data without the status bytes.
    @available(macOS 10.12, iOS 10.0, tvOS 11.0, watchOS 4.0, visionOS 1.0, *)
    public func send(ins: UInt8, p1: UInt8, p2: UInt8, data: Data? = nil, le: Int? = nil) throws -> (sw: UInt16, response: Data) {
        var sw: UInt16 = 0
        let response = try __sendIns(ins, p1: p1, p2: p2, data: data, le: le.map { NSNumber(value: $0) }, sw: &sw)
        return (sw: sw, response: response)
    }

    /// Begins a session with the card, runs the body in it, ends the
    /// session and answers the body's result. An error the body throws is
    /// thrown as it is.
    @available(macOS 10.12, iOS 10.0, tvOS 11.0, watchOS 4.0, visionOS 1.0, *)
    public func withSession<T>(_ body: @escaping () throws -> T) throws -> T {
        var result: T?
        var bodyError: (any Error)?
        do {
            try __inSession { errorPointer in
                do {
                    result = try body()
                    return true
                } catch {
                    bodyError = error
                    errorPointer?.pointee = error as NSError
                    return false
                }
            }
        } catch {
            throw bodyError ?? error
        }
        if let bodyError {
            throw bodyError
        }
        guard let result else {
            throw NSError(domain: TKErrorDomain, code: TKError.Code.communicationError.rawValue)
        }
        return result
    }

    /// Sends an APDU to the card and waits for its reply without blocking.
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)
    final public func send(ins: UInt8, p1: UInt8, p2: UInt8, data: Data? = nil, le: Int? = nil) async throws -> (sw: UInt16, response: Data) {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(sw: UInt16, response: Data), any Error>) in
            send(ins: ins, p1: p1, p2: p2, data: data, le: le) { response, sw, error in
                continuation.resume(with: error.map { .failure($0) } ?? .success((sw: sw, response: response ?? Data())))
            }
        }
    }
}
