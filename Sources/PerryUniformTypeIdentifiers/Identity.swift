import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// OSServices' identities: the local users and groups, from the password and
// group databases, which apps look themselves and others up in by name; and
// Backup Core's exclusions, which change nothing as there is no Time Machine.

final class IdentityState {
    let posixID: UInt32
    let posixName: NSObject
    let fullName: NSObject

    init(posixID: UInt32, posixName: String, fullName: String) {
        self.posixID = posixID
        self.posixName = NSObject.string(posixName)
        self.fullName = NSObject.string(fullName)
    }
}

/// A CSIdentityRef: a user or a group.
@ObjCClass("PerryCSIdentity")
public final class Identity: NSObject {
    static let states = StateTable<IdentityState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        Identity.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: Identity.objCClass.pointer)
    }

    /// A new identity (+1).
    static func make(_ state: IdentityState) -> UnsafeMutableRawPointer {
        let identity = objCClass.ownedInstance()
        states.set(identity, state)
        return identity
    }
}

final class IdentityQueryState {
    let name: String
    let beginsWith: Bool
    let groups: Bool
    var results: [IdentityState] = []

    init(name: String, beginsWith: Bool, groups: Bool) {
        self.name = name
        self.beginsWith = beginsWith
        self.groups = groups
    }

    /// The users or groups whose name (or a user's full name) matches.
    func run() {
        func matches(_ candidate: String) -> Bool { beginsWith ? candidate.hasPrefix(name) : candidate == name }
        results = []
        if groups {
            setgrent()
            defer { endgrent() }
            while let entry = getgrent() {
                let group = String(cString: entry.pointee.gr_name)
                if matches(group) { results.append(IdentityState(posixID: entry.pointee.gr_gid, posixName: group, fullName: group)) }
            }
        } else {
            setpwent()
            defer { endpwent() }
            while let entry = getpwent() {
                let user = String(cString: entry.pointee.pw_name)
                // GECOS: the full name, then the rest after a comma.
                let gecos = entry.pointee.pw_gecos.map { String(cString: $0) } ?? ""
                let full = gecos.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
                if matches(user) || (!full.isEmpty && matches(full)) {
                    results.append(IdentityState(posixID: entry.pointee.pw_uid, posixName: user, fullName: full.isEmpty ? user : full))
                }
            }
        }
    }
}

/// A CSIdentityQueryRef.
@ObjCClass("PerryCSIdentityQuery")
public final class IdentityQuery: NSObject {
    static let states = StateTable<IdentityQueryState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        IdentityQuery.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: IdentityQuery.objCClass.pointer)
    }
}

/// The local authority: an object apps only pass back.
nonisolated(unsafe) private var localAuthority: UnsafeMutableRawPointer?

@c(_CSGetLocalIdentityAuthority)
public func CSGetLocalIdentityAuthority() -> UnsafeMutableRawPointer? {
    if localAuthority == nil { localAuthority = NSObject.string("com.apple.identity.authority.local").objCOwnedReturnValue() }
    return localAuthority
}

@c(_CSGetDefaultIdentityAuthority)
public func CSGetDefaultIdentityAuthority() -> UnsafeMutableRawPointer? { CSGetLocalIdentityAuthority() }

/// CSIdentityQueryRef CSIdentityQueryCreateForName(CFAllocatorRef, CFStringRef,
/// CSIdentityQueryStringComparisonMethod (1 equal, 2 begins with),
/// CSIdentityClass (1 user, 2 group), CSIdentityAuthorityRef).
@c(_CSIdentityQueryCreateForName)
public func CSIdentityQueryCreateForName(_ allocator: UnsafeRawPointer?, _ name: UnsafeMutableRawPointer?, _ comparison: Int,
                                         _ identityClass: Int, _ authority: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let query = IdentityQuery.objCClass.ownedInstance()
    IdentityQuery.states.set(query, IdentityQueryState(name: String(objCArgument: name), beginsWith: comparison == 2, groups: identityClass == 2))
    return query
}

/// Boolean CSIdentityQueryExecute(CSIdentityQueryRef, CSIdentityQueryFlags, CFErrorRef *).
@c(_CSIdentityQueryExecute)
public func CSIdentityQueryExecute(_ query: UnsafeMutableRawPointer?, _ flags: UInt, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UInt8 {
    error?.pointee = nil
    guard let state = IdentityQuery.states[query] else { return 0 }
    state.run()
    return 1
}

/// CFArrayRef CSIdentityQueryCopyResults(CSIdentityQueryRef): new identities (+1 array).
@c(_CSIdentityQueryCopyResults)
public func CSIdentityQueryCopyResults(_ query: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = IdentityQuery.states[query] else { return nil }
    let array = NSMutableArray.empty()
    for result in state.results { array.add(NSObject(objCOwned: Identity.make(result))) }
    return ObjCRuntime.retain(array.objcObject)
}

@c(_CSIdentityGetFullName)
public func CSIdentityGetFullName(_ identity: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { Identity.states[identity]?.fullName.objcObject }

@c(_CSIdentityGetPosixName)
public func CSIdentityGetPosixName(_ identity: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { Identity.states[identity]?.posixName.objcObject }

@c(_CSIdentityGetPosixID)
public func CSIdentityGetPosixID(_ identity: UnsafeMutableRawPointer?) -> UInt32 { Identity.states[identity]?.posixID ?? UInt32.max }

/// OSStatus CSBackupSetItemExcluded(CFURLRef, Boolean exclude, Boolean byPath).
@c(_CSBackupSetItemExcluded)
public func CSBackupSetItemExcluded(_ item: UnsafeRawPointer?, _ exclude: UInt8, _ byPath: UInt8) -> Int32 { item == nil ? -50 : 0 }

@c(_CSBackupIsItemExcluded)
public func CSBackupIsItemExcluded(_ item: UnsafeRawPointer?, _ byPath: UnsafeMutablePointer<UInt8>?) -> UInt8 {
    byPath?.pointee = 0
    return 0
}
#endif
