import FoundationEssentials
import PerryObjCInterop

// Merge policies: how a context resolves conflicts between its changes and
// the store's. A context here saves to a store no other context writes
// behind its back, so there are no conflicts to resolve; the policy is kept
// for the apps that set and read it. The five standard policies are the
// constants Core Data exports, and the class properties naming them.

final class MergePolicyState: ObjectState {
    /// NSMergePolicyType: error 0, property store trump 1, property object
    /// trump 2, overwrite 3, rollback 4.
    var mergeType: UInt = 0
}

@ObjCClass("NSMergePolicy")
open class NSMergePolicy: NSObject {
    static let states = StateTable<MergePolicyState>()
    var state: MergePolicyState { NSMergePolicy.states[objcObject] }

    /// A policy of `type`, kept for good: the constants and the class
    /// properties give the same ones.
    static func standard(_ type: UInt) -> UnsafeMutableRawPointer? {
        let policy = NSMergePolicy.objCClass.object.newInstance().unsafeCast(to: NSMergePolicy.self)
        policy.state.mergeType = type
        return ObjCRuntime.retain(policy.objcObject)
    }

    @ObjCMethod("initWithMergeType:")
    func initialize(mergeType: UInt) -> Self {
        state.mergeType = mergeType
        return self
    }

    @ObjCMethod("mergeType") func mergeType() -> UInt { state.mergeType }

    /// No conflicts arise here; resolving them succeeds.
    @ObjCMethod("resolveConflicts:error:")
    func resolveConflicts(_ conflicts: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool { true }
    @ObjCMethod("resolveOptimisticLockingVersionConflicts:error:")
    func resolveOptimisticLockingVersionConflicts(_ conflicts: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool { true }
    @ObjCMethod("resolveConstraintConflicts:error:")
    func resolveConstraintConflicts(_ conflicts: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool { true }

    @ObjCClassMethod("errorMergePolicy") static func errorMergePolicy() -> UnsafeMutableRawPointer { MergePolicies.NSErrorMergePolicyObject }
    @ObjCClassMethod("rollbackMergePolicy") static func rollbackMergePolicy() -> UnsafeMutableRawPointer { MergePolicies.NSRollbackMergePolicyObject }
    @ObjCClassMethod("overwriteMergePolicy") static func overwriteMergePolicy() -> UnsafeMutableRawPointer { MergePolicies.NSOverwriteMergePolicyObject }
    @ObjCClassMethod("mergeByPropertyObjectTrumpMergePolicy") static func mergeByPropertyObjectTrumpMergePolicy() -> UnsafeMutableRawPointer {
        MergePolicies.NSMergeByPropertyObjectTrumpMergePolicyObject
    }
    @ObjCClassMethod("mergeByPropertyStoreTrumpMergePolicy") static func mergeByPropertyStoreTrumpMergePolicy() -> UnsafeMutableRawPointer {
        MergePolicies.NSMergeByPropertyStoreTrumpMergePolicyObject
    }
}

/// The standard policies, which Core Data exports as `id` constants.
@ObjCConstants
enum MergePolicies {
    nonisolated(unsafe) static let NSErrorMergePolicy = NSMergePolicy.standard(0)
    nonisolated(unsafe) static let NSMergeByPropertyStoreTrumpMergePolicy = NSMergePolicy.standard(1)
    nonisolated(unsafe) static let NSMergeByPropertyObjectTrumpMergePolicy = NSMergePolicy.standard(2)
    nonisolated(unsafe) static let NSOverwriteMergePolicy = NSMergePolicy.standard(3)
    nonisolated(unsafe) static let NSRollbackMergePolicy = NSMergePolicy.standard(4)
}
