// NSKeyedUnarchiver's deprecated top-level unarchive, as Apple's Foundation
// overlay has it: a Swift method returning Any?, which swift-foundation
// hides, so only an unavailable declaration may name it by its Objective-C
// name (availability is the compiler's and binds nothing). It is reached
// through the Objective-C class's own decoding methods, not the identically
// named Objective-C class method, which would be this function again.
//
// An app that returns something from this (Microsoft Authenticator decoding
// a backup) must get a well-formed Any?, not the zero a missing function
// would leave in the registers, which ARC then releases as a garbage object.

@available(*, unavailable)
extension NSKeyedUnarchiver {
    /// The root object archived in `data`, without requiring secure coding;
    /// nil when there is none. Errors from reading the archive are thrown.
    public class func unarchiveTopLevelObjectWithData(_ data: Data) throws -> Any? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        // NSKeyedArchiveRootObjectKey, the key +archivedDataWithRootObject: uses.
        return unarchiver.decodeObject(forKey: "root")
    }
}
