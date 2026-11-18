import PerryObjCInterop

// Foundation's string constants that name things other parts of Perry
// post, read or ignore: notifications, key-value operators and
// exceptions. Programs pass them as they are, so a missing one would bind
// to something that isn't a string.

@ObjCConstants
enum FoundationNames {
    // Notifications.
    static let NSBundleDidLoadNotification = "NSBundleDidLoadNotification"
    static let NSConnectionDidDieNotification = "NSConnectionDidDieNotification"
    static let NSPortDidBecomeInvalidNotification = "NSPortDidBecomeInvalidNotification"
    static let NSFileHandleReadCompletionNotification = "NSFileHandleReadCompletionNotification"
    static let NSFileHandleDataAvailableNotification = "NSFileHandleDataAvailableNotification"
    static let NSFileHandleConnectionAcceptedNotification = "NSFileHandleConnectionAcceptedNotification"
    static let NSTaskDidTerminateNotification = "NSTaskDidTerminateNotification"
    static let NSMetadataQueryDidStartGatheringNotification = "NSMetadataQueryDidStartGatheringNotification"
    static let NSMetadataQueryGatheringProgressNotification = "NSMetadataQueryGatheringProgressNotification"
    static let NSMetadataQueryDidFinishGatheringNotification = "NSMetadataQueryDidFinishGatheringNotification"
    static let NSMetadataQueryDidUpdateNotification = "NSMetadataQueryDidUpdateNotification"
    static let NSUndoManagerCheckpointNotification = "NSUndoManagerCheckpointNotification"
    static let NSUndoManagerWillUndoChangeNotification = "NSUndoManagerWillUndoChangeNotification"
    static let NSUndoManagerWillRedoChangeNotification = "NSUndoManagerWillRedoChangeNotification"
    static let NSUndoManagerDidUndoChangeNotification = "NSUndoManagerDidUndoChangeNotification"
    static let NSUndoManagerDidRedoChangeNotification = "NSUndoManagerDidRedoChangeNotification"
    static let NSUndoManagerDidOpenUndoGroupNotification = "NSUndoManagerDidOpenUndoGroupNotification"
    static let NSUndoManagerWillCloseUndoGroupNotification = "NSUndoManagerWillCloseUndoGroupNotification"
    static let NSUndoManagerDidCloseUndoGroupNotification = "NSUndoManagerDidCloseUndoGroupNotification"

    // Key-value coding's collection operators.
    static let NSAverageKeyValueOperator = "avg"
    static let NSCountKeyValueOperator = "count"
    static let NSDistinctUnionOfArraysKeyValueOperator = "distinctUnionOfArrays"
    static let NSDistinctUnionOfObjectsKeyValueOperator = "distinctUnionOfObjects"
    static let NSDistinctUnionOfSetsKeyValueOperator = "distinctUnionOfSets"
    static let NSMaximumKeyValueOperator = "max"
    static let NSMinimumKeyValueOperator = "min"
    static let NSSumKeyValueOperator = "sum"
    static let NSUnionOfArraysKeyValueOperator = "unionOfArrays"
    static let NSUnionOfObjectsKeyValueOperator = "unionOfObjects"
    static let NSUnionOfSetsKeyValueOperator = "unionOfSets"

    // Exceptions.
    static let NSParseErrorException = "NSParseErrorException"
}
