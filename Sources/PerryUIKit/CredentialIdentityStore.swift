import PerryObjCInterop

// AuthenticationServices' credential identity store: the identities an app
// that provides passwords to AutoFill lists for the system's suggestions.
// There is no AutoFill here, so the app's provider is never enabled: the
// store's state says so, and saving or removing identities does nothing and
// reports that it failed.

/// The store's state: AutoFill is not enabled for the app.
@ObjCClass("ASCredentialIdentityStoreState")
open class ASCredentialIdentityStoreState: NSObject {
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { false }
    @ObjCMethod("supportsIncrementalUpdates") func supportsIncrementalUpdates() -> Bool { false }
}

@ObjCClass("ASCredentialIdentityStore")
open class ASCredentialIdentityStore: NSObject {
    nonisolated(unsafe) static var shared: NSObject?

    @ObjCClassMethod("sharedStore")
    static func sharedStore() -> NSObject {
        if let shared { return shared }
        let store = objCClass.object.newInstance()
        shared = store
        return store
    }

    /// Calls the block with the store's state.
    @ObjCMethod("getCredentialIdentityStoreStateWithCompletion:")
    func getState(completion: ObjCBlock?) {
        guard let completion else { return }
        let state = ASCredentialIdentityStoreState.objCClass.object.newInstance()
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
        Updates.afterPass {
            withExtendedLifetime(state) { completion.function(as: Invoke.self)(completion.object, state.objcObject) }
        }
    }

    /// Calls a (success, error) block with failure, as the provider is not enabled.
    private func fail(_ completion: ObjCBlock?) {
        guard let completion else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Bool, UnsafeMutableRawPointer?) -> Void
        Updates.afterPass { completion.function(as: Invoke.self)(completion.object, false, nil) }
    }

    @ObjCMethod("saveCredentialIdentities:completion:")
    func save(_ identities: NSObject?, completion: ObjCBlock?) { fail(completion) }
    @ObjCMethod("removeCredentialIdentities:completion:")
    func remove(_ identities: NSObject?, completion: ObjCBlock?) { fail(completion) }
    @ObjCMethod("removeAllCredentialIdentitiesWithCompletion:")
    func removeAll(completion: ObjCBlock?) { fail(completion) }
    @ObjCMethod("replaceCredentialIdentitiesWithIdentities:completion:")
    func replace(_ identities: NSObject?, completion: ObjCBlock?) { fail(completion) }
    @ObjCMethod("saveCredentialIdentityEntries:completion:")
    func saveEntries(_ entries: NSObject?, completion: ObjCBlock?) { fail(completion) }
    @ObjCMethod("removeCredentialIdentityEntries:completion:")
    func removeEntries(_ entries: NSObject?, completion: ObjCBlock?) { fail(completion) }
    @ObjCMethod("replaceCredentialIdentityEntries:completion:")
    func replaceEntries(_ entries: NSObject?, completion: ObjCBlock?) { fail(completion) }
}

final class ServiceIdentifierState: ObjectState {
    var identifier = ""
    /// ASCredentialServiceIdentifierType: domain 0, URL 1, app 2.
    var type = 0
}

/// A website or app a credential is for.
@ObjCClass("ASCredentialServiceIdentifier")
open class ASCredentialServiceIdentifier: NSObject {
    static let states = StateTable<ServiceIdentifierState>()
    var service: ServiceIdentifierState { ASCredentialServiceIdentifier.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        ASCredentialServiceIdentifier.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: ASCredentialServiceIdentifier.objCClass.pointer)
    }

    @ObjCMethod("initWithIdentifier:type:")
    func initialize(identifier: String?, type: Int) -> UnsafeMutableRawPointer? {
        (service.identifier, service.type) = (identifier ?? "", type)
        return ObjCRuntime.retain(objcObject)
    }

    @ObjCMethod("identifier") func identifier() -> String { service.identifier }
    @ObjCMethod("type") func type() -> Int { service.type }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

final class PasswordIdentityState: ObjectState {
    var service: NSObject?
    var user = ""
    var recordIdentifier: String?
    var rank = 0
}

/// A user name and the service it signs in to, as AutoFill would list it.
@ObjCClass("ASPasswordCredentialIdentity")
open class ASPasswordCredentialIdentity: NSObject {
    static let states = StateTable<PasswordIdentityState>()
    var identity: PasswordIdentityState { ASPasswordCredentialIdentity.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        ASPasswordCredentialIdentity.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: ASPasswordCredentialIdentity.objCClass.pointer)
    }

    @ObjCMethod("initWithServiceIdentifier:user:recordIdentifier:")
    func initialize(service: NSObject?, user: String?, recordIdentifier: String?) -> UnsafeMutableRawPointer? {
        (identity.service, identity.user, identity.recordIdentifier) = (service, user ?? "", recordIdentifier)
        return ObjCRuntime.retain(objcObject)
    }

    @ObjCClassMethod("identityWithServiceIdentifier:user:recordIdentifier:")
    static func make(service: NSObject?, user: String?, recordIdentifier: String?) -> NSObject {
        let made = objCClass.object.allocated().unsafeCast(to: ASPasswordCredentialIdentity.self)
        _ = made.initialize(service: service, user: user, recordIdentifier: recordIdentifier)
        return made
    }

    @ObjCMethod("serviceIdentifier") func serviceIdentifier() -> NSObject? { identity.service }
    @ObjCMethod("user") func user() -> String { identity.user }
    @ObjCMethod("recordIdentifier") func recordIdentifier() -> String? { identity.recordIdentifier }
    @ObjCMethod("rank") func rank() -> Int { identity.rank }
    @ObjCMethod("setRank:") func setRank(_ rank: Int) { identity.rank = rank }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}
