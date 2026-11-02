import FoundationEssentials
import PerryObjCInterop
import PerryURLLoading

// Authentication: protection spaces, credentials, the credential storage
// and challenges, which reach a session's task delegate or a connection's
// delegate. A challenge's sender answers it for either. Default handling
// uses the credential storage's default credential for the space once.

/// The authentication methods and protection space protocols.
@ObjCConstants
enum AuthenticationConstants {
    static let NSURLAuthenticationMethodDefault = "NSURLAuthenticationMethodDefault"
    static let NSURLAuthenticationMethodHTTPBasic = "NSURLAuthenticationMethodHTTPBasic"
    static let NSURLAuthenticationMethodHTTPDigest = "NSURLAuthenticationMethodHTTPDigest"
    static let NSURLAuthenticationMethodHTMLForm = "NSURLAuthenticationMethodHTMLForm"
    static let NSURLAuthenticationMethodNTLM = "NSURLAuthenticationMethodNTLM"
    static let NSURLAuthenticationMethodNegotiate = "NSURLAuthenticationMethodNegotiate"
    static let NSURLAuthenticationMethodClientCertificate = "NSURLAuthenticationMethodClientCertificate"
    static let NSURLAuthenticationMethodServerTrust = "NSURLAuthenticationMethodServerTrust"
    static let NSURLProtectionSpaceHTTP = "http"
    static let NSURLProtectionSpaceHTTPS = "https"
    static let NSURLProtectionSpaceFTP = "ftp"
    static let NSURLProtectionSpaceHTTPProxy = "http"
    static let NSURLProtectionSpaceHTTPSProxy = "https"
    static let NSURLProtectionSpaceFTPProxy = "ftp"
    static let NSURLProtectionSpaceSOCKSProxy = "SOCKS"
    static let NSURLCredentialStorageChangedNotification = "NSURLCredentialStorageChangedNotification"
    static let NSURLCredentialStorageRemoveSynchronizableCredentials = "NSURLCredentialStorageRemoveSynchronizableCredentials"
}

// MARK: - Protection spaces

/// A protection space, as a state table holds it.
final class SpaceState: @unchecked Sendable {
    let space: ProtectionSpace

    init(_ space: ProtectionSpace) {
        self.space = space
    }
}

enum ProtectionSpaces {
    static let states = StateTable<SpaceState>()

    static func space(_ object: NSObject?) -> ProtectionSpace? { object.flatMap { states.get($0.objcObject)?.space } }

    static func object(_ space: ProtectionSpace) -> NSObject {
        let object = NSURLProtectionSpace.objCClass.autoreleasedInstance()
        states.set(object.objcObject, SpaceState(space))
        return object
    }
}

/// NSURLProtectionSpace.
@ObjCClass("NSURLProtectionSpace")
open class NSURLProtectionSpace: NSObject {
    var space: ProtectionSpace { ProtectionSpaces.states.get(objcObject)?.space ?? ProtectionSpace(host: "", port: 0, protocolName: nil, realm: nil, method: nil) }

    @ObjCMethod("dealloc")
    func dealloc() {
        ProtectionSpaces.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLProtectionSpace.objCClass.pointer)
    }

    @ObjCMethod("initWithHost:port:protocol:realm:authenticationMethod:")
    func initialize(host: String, port: Int, protocolName: String?, realm: String?, method: String?) -> Self {
        ProtectionSpaces.states.set(objcObject, SpaceState(ProtectionSpace(host: host, port: port, protocolName: protocolName,
                                                                           realm: realm, method: method)))
        return self
    }

    @ObjCMethod("initWithProxyHost:port:type:realm:authenticationMethod:")
    func initialize(proxyHost host: String, port: Int, type: String?, realm: String?, method: String?) -> Self {
        ProtectionSpaces.states.set(objcObject, SpaceState(ProtectionSpace(host: host, port: port, protocolName: nil, realm: realm,
                                                                           method: method, proxyType: type)))
        return self
    }

    @ObjCMethod("host") func host() -> String { space.host }
    @ObjCMethod("port") func port() -> Int { space.port }
    @ObjCMethod("protocol") func protocolName() -> String? { space.protocolName }
    @ObjCMethod("realm") func realm() -> String? { space.realm }
    @ObjCMethod("authenticationMethod") func authenticationMethod() -> String { space.method }
    @ObjCMethod("proxyType") func proxyType() -> String? { space.proxyType }
    @ObjCMethod("isProxy") func isProxy() -> Bool { space.proxyType != nil }
    @ObjCMethod("distinguishedNames") func distinguishedNames() -> NSObject? { nil }
    @ObjCMethod("serverTrust") func serverTrust() -> UnsafeMutableRawPointer? { nil }

    /// Over TLS, or by a method that never sends the password in the clear.
    @ObjCMethod("receivesCredentialSecurely")
    func receivesCredentialSecurely() -> Bool {
        let secure: Set<String> = ["NSURLAuthenticationMethodHTTPDigest", "NSURLAuthenticationMethodNTLM",
                                   "NSURLAuthenticationMethodNegotiate", "NSURLAuthenticationMethodClientCertificate",
                                   "NSURLAuthenticationMethodServerTrust"]
        let scheme = space.protocolName ?? space.proxyType
        return scheme == "https" || secure.contains(space.method)
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool { ProtectionSpaces.space(other) == space }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: space.hashValue) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("description")
    func description() -> String {
        "<NSURLProtectionSpace: \(objcObject)>: Host:\(space.host), Server:\(space.protocolName ?? "(null)"), "
            + "Auth-Scheme:\(space.method), Realm:\(space.realm ?? "(null)"), Port:\(space.port), "
            + "Proxy:\(space.proxyType != nil ? "YES" : "NO"), Proxy-Type:\(space.proxyType ?? "(null)")"
    }
}

// MARK: - Credentials

final class CredentialState: @unchecked Sendable {
    let credential: Credential
    /// A server trust or identity, and certificates, retained.
    let trust: UnsafeMutableRawPointer?
    let identity: UnsafeMutableRawPointer?
    let certificates: NSObject?

    init(_ credential: Credential, trust: UnsafeMutableRawPointer? = nil, identity: UnsafeMutableRawPointer? = nil,
         certificates: NSObject? = nil) {
        self.credential = credential
        self.trust = trust.flatMap { ObjCRuntime.retain($0) }
        self.identity = identity.flatMap { ObjCRuntime.retain($0) }
        self.certificates = certificates
    }

    deinit {
        ObjCRuntime.release(trust)
        ObjCRuntime.release(identity)
    }
}

enum Credentials {
    static let states = StateTable<CredentialState>()

    static func credential(_ object: UnsafeMutableRawPointer?) -> Credential? { object.flatMap { states.get($0)?.credential } }

    static func object(_ credential: Credential) -> NSObject {
        let object = NSURLCredential.objCClass.autoreleasedInstance()
        states.set(object.objcObject, CredentialState(credential))
        return object
    }
}

/// NSURLCredential.
@ObjCClass("NSURLCredential")
open class NSURLCredential: NSObject {
    var state: CredentialState? { Credentials.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Credentials.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLCredential.objCClass.pointer)
    }

    @ObjCClassMethod("credentialWithUser:password:persistence:")
    static func make(_ cls: ObjCClass, user: String?, password: String?, persistence: UInt) -> NSObject {
        let object = cls.autoreleasedInstance()
        Credentials.states.set(object.objcObject, CredentialState(Credential(user: user, password: password, persistence: Int(persistence))))
        return object
    }

    @ObjCMethod("initWithUser:password:persistence:")
    func initialize(user: String?, password: String?, persistence: UInt) -> Self {
        Credentials.states.set(objcObject, CredentialState(Credential(user: user, password: password, persistence: Int(persistence))))
        return self
    }

    @ObjCClassMethod("credentialForTrust:")
    static func make(_ cls: ObjCClass, trust: UnsafeMutableRawPointer?) -> NSObject {
        let object = cls.autoreleasedInstance()
        Credentials.states.set(object.objcObject, CredentialState(Credential(user: nil, password: nil, persistence: 1), trust: trust))
        return object
    }

    @ObjCMethod("initWithTrust:")
    func initialize(trust: UnsafeMutableRawPointer?) -> Self {
        Credentials.states.set(objcObject, CredentialState(Credential(user: nil, password: nil, persistence: 1), trust: trust))
        return self
    }

    @ObjCClassMethod("credentialWithIdentity:certificates:persistence:")
    static func make(_ cls: ObjCClass, identity: UnsafeMutableRawPointer?, certificates: NSObject?, persistence: UInt) -> NSObject {
        let object = cls.autoreleasedInstance()
        Credentials.states.set(object.objcObject, CredentialState(Credential(user: nil, password: nil, persistence: Int(persistence)),
                                                                  identity: identity, certificates: certificates))
        return object
    }

    @ObjCMethod("initWithIdentity:certificates:persistence:")
    func initialize(identity: UnsafeMutableRawPointer?, certificates: NSObject?, persistence: UInt) -> Self {
        Credentials.states.set(objcObject, CredentialState(Credential(user: nil, password: nil, persistence: Int(persistence)),
                                                           identity: identity, certificates: certificates))
        return self
    }

    @ObjCMethod("user") func user() -> String? { state?.credential.user }
    @ObjCMethod("password") func password() -> String? { state?.credential.password }
    @ObjCMethod("hasPassword") func hasPassword() -> Bool { state?.credential.password != nil }
    @ObjCMethod("persistence") func persistence() -> UInt { UInt(state?.credential.persistence ?? 0) }
    @ObjCMethod("identity") func identity() -> UnsafeMutableRawPointer? { state?.identity }
    @ObjCMethod("certificates") func certificates() -> NSObject? { state?.certificates ?? NSMutableArray.of([]) }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let mine = state?.credential, let theirs = Credentials.credential(other?.objcObject) else { return false }
        return mine.user == theirs.user && mine.password == theirs.password && mine.persistence == theirs.persistence
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: (state?.credential.user ?? "").hashValue) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("description")
    func description() -> String { "<NSURLCredential: \(objcObject)>: \(state?.credential.user ?? "(null)")" }
}

// MARK: - The credential storage

/// Credentials by protection space, in the order they were set; each
/// space's first is its default until another is made the default.
final class CredentialStore: @unchecked Sendable {
    let lock = Lock()
    var credentials: [ProtectionSpace: [(user: String, object: NSObject)]] = [:]
    var defaults: [ProtectionSpace: NSObject] = [:]
    var order: [ProtectionSpace] = []

    func set(_ credential: NSObject, for space: ProtectionSpace, default isDefault: Bool) {
        let user = Credentials.credential(credential.objcObject)?.user ?? ""
        lock.withLock {
            if credentials[space] == nil { order.append(space) }
            var list = credentials[space, default: []].filter { $0.user != user }
            list.append((user, credential))
            credentials[space] = list
            if isDefault || defaults[space] == nil { defaults[space] = credential }
        }
    }

    func remove(_ credential: NSObject, for space: ProtectionSpace) {
        let user = Credentials.credential(credential.objcObject)?.user ?? ""
        lock.withLock {
            credentials[space]?.removeAll { $0.user == user }
            if let current = defaults[space], Credentials.credential(current.objcObject)?.user == user { defaults[space] = nil }
            if credentials[space]?.isEmpty ?? false {
                credentials[space] = nil
                order.removeAll { $0 == space }
            }
        }
    }

    func list(_ space: ProtectionSpace) -> [(user: String, object: NSObject)] { lock.withLock { credentials[space] ?? [] } }
    func defaultCredential(_ space: ProtectionSpace) -> NSObject? { lock.withLock { defaults[space] } }
}

enum CredentialStorage {
    static let store = CredentialStore()
    nonisolated(unsafe) static var shared: NSObject?

    /// What default handling answers: the space's default credential the
    /// first time, else the server's answer as it is.
    static func defaultAnswer(_ challenge: Challenge) -> (Int, Credential?) {
        if challenge.previousFailureCount == 0, let stored = store.defaultCredential(challenge.space),
           let credential = Credentials.credential(stored.objcObject) {
            return (0, credential)
        }
        return (1, nil)
    }
}

/// NSURLCredentialStorage.
@ObjCClass("NSURLCredentialStorage")
open class NSURLCredentialStorage: NSObject {
    @ObjCClassMethod("sharedCredentialStorage")
    static func sharedCredentialStorage() -> NSObject {
        if let shared = CredentialStorage.shared { return shared }
        let object = objCClass.object.newInstance()
        CredentialStorage.shared = object
        return object
    }

    private func dictionary(_ space: ProtectionSpace) -> NSMutableDictionary {
        NSMutableDictionary.of(CredentialStorage.store.list(space).map { ($0.user, $0.object) })
    }

    @ObjCMethod("credentialsForProtectionSpace:")
    func credentials(for space: NSObject?) -> NSObject? {
        guard let space = ProtectionSpaces.space(space), !CredentialStorage.store.list(space).isEmpty else { return nil }
        return dictionary(space)
    }

    @ObjCMethod("allCredentials")
    func allCredentials() -> NSObject {
        let store = CredentialStorage.store
        let result = NSMutableDictionary.empty()
        for space in store.lock.withLock({ store.order }) { result.set(dictionary(space), forKey: ProtectionSpaces.object(space)) }
        return result
    }

    @ObjCMethod("setCredential:forProtectionSpace:")
    func setCredential(_ credential: NSObject, for space: NSObject) {
        guard let space = ProtectionSpaces.space(space) else { return }
        CredentialStorage.store.set(credential, for: space, default: false)
    }

    @ObjCMethod("setDefaultCredential:forProtectionSpace:")
    func setDefaultCredential(_ credential: NSObject, for space: NSObject) {
        guard let space = ProtectionSpaces.space(space) else { return }
        CredentialStorage.store.set(credential, for: space, default: true)
    }

    @ObjCMethod("removeCredential:forProtectionSpace:")
    func removeCredential(_ credential: NSObject, for space: NSObject) {
        guard let space = ProtectionSpaces.space(space) else { return }
        CredentialStorage.store.remove(credential, for: space)
    }

    @ObjCMethod("removeCredential:forProtectionSpace:options:")
    func removeCredential(_ credential: NSObject, for space: NSObject, options: NSObject?) { removeCredential(credential, for: space) }

    @ObjCMethod("defaultCredentialForProtectionSpace:")
    func defaultCredential(for space: NSObject?) -> NSObject? {
        ProtectionSpaces.space(space).flatMap { CredentialStorage.store.defaultCredential($0) }
    }
}

// MARK: - Challenges

final class ChallengeState: @unchecked Sendable {
    let space: NSObject
    let proposed: NSObject?
    let previousFailureCount: Int
    let failureResponse: NSObject?
    let error: NSObject?
    let sender: NSObject?

    init(space: NSObject, proposed: NSObject?, previousFailureCount: Int, failureResponse: NSObject?, error: NSObject?,
         sender: NSObject?) {
        self.space = space
        self.proposed = proposed
        self.previousFailureCount = previousFailureCount
        self.failureResponse = failureResponse
        self.error = error
        self.sender = sender
    }
}

enum Challenges {
    static let states = StateTable<ChallengeState>()

    /// The challenge object, with a sender giving `answer` its answer.
    static func object(_ challenge: Challenge, answer: SenderState) -> NSObject {
        let object = NSURLAuthenticationChallenge.objCClass.autoreleasedInstance()
        states.set(object.objcObject, ChallengeState(
            space: ProtectionSpaces.object(challenge.space), proposed: challenge.proposed.map(Credentials.object),
            previousFailureCount: challenge.previousFailureCount, failureResponse: challenge.failureResponse.map(Responses.object),
            error: Errors.object(challenge.error), sender: ChallengeSenders.object(answer)))
        return object
    }
}

/// NSURLAuthenticationChallenge.
@ObjCClass("NSURLAuthenticationChallenge")
open class NSURLAuthenticationChallenge: NSObject {
    var state: ChallengeState? { Challenges.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Challenges.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLAuthenticationChallenge.objCClass.pointer)
    }

    @ObjCMethod("initWithProtectionSpace:proposedCredential:previousFailureCount:failureResponse:error:sender:")
    func initialize(space: NSObject, proposed: NSObject?, previousFailureCount: Int, failureResponse: NSObject?, error: NSObject?,
                    sender: NSObject?) -> Self {
        Challenges.states.set(objcObject, ChallengeState(space: space, proposed: proposed, previousFailureCount: previousFailureCount,
                                                         failureResponse: failureResponse, error: error, sender: sender))
        return self
    }

    @ObjCMethod("initWithAuthenticationChallenge:sender:")
    func initialize(challenge: NSObject, sender: NSObject?) -> Self {
        guard let other = Challenges.states.get(challenge.objcObject) else { return self }
        Challenges.states.set(objcObject, ChallengeState(space: other.space, proposed: other.proposed,
                                                         previousFailureCount: other.previousFailureCount,
                                                         failureResponse: other.failureResponse, error: other.error, sender: sender))
        return self
    }

    @ObjCMethod("protectionSpace") func protectionSpace() -> NSObject? { state?.space }
    @ObjCMethod("proposedCredential") func proposedCredential() -> NSObject? { state?.proposed }
    @ObjCMethod("previousFailureCount") func previousFailureCount() -> Int { state?.previousFailureCount ?? 0 }
    @ObjCMethod("failureResponse") func failureResponse() -> NSObject? { state?.failureResponse }
    @ObjCMethod("error") func error() -> NSObject? { state?.error }
    @ObjCMethod("sender") func sender() -> NSObject? { state?.sender }
}

/// A challenge's answer, given once: by the sender, or by a session's
/// completion handler.
final class SenderState: @unchecked Sendable {
    let lock = Lock()
    var answer: (@Sendable (Int, Credential?) -> Void)?
    let challenge: Challenge

    init(_ answer: @escaping @Sendable (Int, Credential?) -> Void, challenge: Challenge) {
        self.answer = answer
        self.challenge = challenge
    }

    func give(_ disposition: Int, _ credential: Credential?) {
        let answer = lock.withLock { () -> (@Sendable (Int, Credential?) -> Void)? in
            defer { self.answer = nil }
            return self.answer
        }
        answer?(disposition, credential)
    }
}

enum ChallengeSenders {
    static let states = StateTable<SenderState>()

    static func object(_ answer: SenderState) -> NSObject {
        let object = NSURLAuthenticationChallengeSender.objCClass.autoreleasedInstance()
        states.set(object.objcObject, answer)
        return object
    }
}

/// The sender of the challenges CFNetwork makes (NSURLAuthenticationChallengeSender).
@ObjCClass("NSURLSessionAuthenticationChallengeSender")
open class NSURLAuthenticationChallengeSender: NSObject {
    var state: SenderState? { ChallengeSenders.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        // Unanswered: as default handling.
        if let state {
            let (disposition, credential) = CredentialStorage.defaultAnswer(state.challenge)
            state.give(disposition, credential)
        }
        ChallengeSenders.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLAuthenticationChallengeSender.objCClass.pointer)
    }

    @ObjCMethod("useCredential:forAuthenticationChallenge:")
    func use(_ credential: NSObject?, for challenge: NSObject?) {
        state?.give(0, Credentials.credential(credential?.objcObject))
    }

    @ObjCMethod("continueWithoutCredentialForAuthenticationChallenge:")
    func continueWithoutCredential(for challenge: NSObject?) { state?.give(0, nil) }

    @ObjCMethod("cancelAuthenticationChallenge:")
    func cancel(_ challenge: NSObject?) { state?.give(2, nil) }

    @ObjCMethod("performDefaultHandlingForAuthenticationChallenge:")
    func performDefaultHandling(for challenge: NSObject?) {
        guard let state else { return }
        let (disposition, credential) = CredentialStorage.defaultAnswer(state.challenge)
        state.give(disposition, credential)
    }

    @ObjCMethod("rejectProtectionSpaceAndContinueWithChallenge:")
    func rejectProtectionSpace(_ challenge: NSObject?) { state?.give(3, nil) }
}
