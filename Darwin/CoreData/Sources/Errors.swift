import Foundation

// Core Data's error codes as CocoaError.Code values, under their current
// names, the deprecated ones ending in Error and (on CocoaError) the
// capitalized Swift 3 ones, and the userInfo of Core Data's errors as
// properties, as the Swift 5.0 overlay had them.

/// A Core Data error code of CoreDataErrors.h.
private func coreDataCode(_ value: Int) -> CocoaError.Code {
    CocoaError.Code(rawValue: value)
}

extension CocoaError.Code {
    public static var coreData: CocoaError.Code { coreDataCode(NSCoreDataError) }

    @available(*, deprecated, renamed: "coreData")
    public static var coreDataError: CocoaError.Code { coreDataCode(NSCoreDataError) }

    public static var entityMigrationPolicy: CocoaError.Code { coreDataCode(NSEntityMigrationPolicyError) }

    @available(*, deprecated, renamed: "entityMigrationPolicy")
    public static var entityMigrationPolicyError: CocoaError.Code { coreDataCode(NSEntityMigrationPolicyError) }

    public static var externalRecordImport: CocoaError.Code { coreDataCode(NSExternalRecordImportError) }

    @available(*, deprecated, renamed: "externalRecordImport")
    public static var externalRecordImportError: CocoaError.Code { coreDataCode(NSExternalRecordImportError) }

    public static var inferredMappingModel: CocoaError.Code { coreDataCode(NSInferredMappingModelError) }

    @available(*, deprecated, renamed: "inferredMappingModel")
    public static var inferredMappingModelError: CocoaError.Code { coreDataCode(NSInferredMappingModelError) }

    public static var managedObjectConstraintMerge: CocoaError.Code { coreDataCode(NSManagedObjectConstraintMergeError) }

    @available(*, deprecated, renamed: "managedObjectConstraintMerge")
    public static var managedObjectConstraintMergeError: CocoaError.Code { coreDataCode(NSManagedObjectConstraintMergeError) }

    public static var managedObjectContextLocking: CocoaError.Code { coreDataCode(NSManagedObjectContextLockingError) }

    @available(*, deprecated, renamed: "managedObjectContextLocking")
    public static var managedObjectContextLockingError: CocoaError.Code { coreDataCode(NSManagedObjectContextLockingError) }

    public static var managedObjectExternalRelationship: CocoaError.Code { coreDataCode(NSManagedObjectExternalRelationshipError) }

    @available(*, deprecated, renamed: "managedObjectExternalRelationship")
    public static var managedObjectExternalRelationshipError: CocoaError.Code { coreDataCode(NSManagedObjectExternalRelationshipError) }

    public static var managedObjectMerge: CocoaError.Code { coreDataCode(NSManagedObjectMergeError) }

    @available(*, deprecated, renamed: "managedObjectMerge")
    public static var managedObjectMergeError: CocoaError.Code { coreDataCode(NSManagedObjectMergeError) }

    public static var managedObjectReferentialIntegrity: CocoaError.Code { coreDataCode(NSManagedObjectReferentialIntegrityError) }

    @available(*, deprecated, renamed: "managedObjectReferentialIntegrity")
    public static var managedObjectReferentialIntegrityError: CocoaError.Code { coreDataCode(NSManagedObjectReferentialIntegrityError) }

    public static var managedObjectValidation: CocoaError.Code { coreDataCode(NSManagedObjectValidationError) }

    @available(*, deprecated, renamed: "managedObjectValidation")
    public static var managedObjectValidationError: CocoaError.Code { coreDataCode(NSManagedObjectValidationError) }

    public static var migration: CocoaError.Code { coreDataCode(NSMigrationError) }

    public static var migrationCancelled: CocoaError.Code { coreDataCode(NSMigrationCancelledError) }

    @available(*, deprecated, renamed: "migrationCancelled")
    public static var migrationCancelledError: CocoaError.Code { coreDataCode(NSMigrationCancelledError) }

    @available(*, deprecated, renamed: "migration")
    public static var migrationError: CocoaError.Code { coreDataCode(NSMigrationError) }

    public static var migrationManagerDestinationStore: CocoaError.Code { coreDataCode(NSMigrationManagerDestinationStoreError) }

    @available(*, deprecated, renamed: "migrationManagerDestinationStore")
    public static var migrationManagerDestinationStoreError: CocoaError.Code { coreDataCode(NSMigrationManagerDestinationStoreError) }

    public static var migrationManagerSourceStore: CocoaError.Code { coreDataCode(NSMigrationManagerSourceStoreError) }

    @available(*, deprecated, renamed: "migrationManagerSourceStore")
    public static var migrationManagerSourceStoreError: CocoaError.Code { coreDataCode(NSMigrationManagerSourceStoreError) }

    public static var migrationMissingMappingModel: CocoaError.Code { coreDataCode(NSMigrationMissingMappingModelError) }

    @available(*, deprecated, renamed: "migrationMissingMappingModel")
    public static var migrationMissingMappingModelError: CocoaError.Code { coreDataCode(NSMigrationMissingMappingModelError) }

    public static var migrationMissingSourceModel: CocoaError.Code { coreDataCode(NSMigrationMissingSourceModelError) }

    @available(*, deprecated, renamed: "migrationMissingSourceModel")
    public static var migrationMissingSourceModelError: CocoaError.Code { coreDataCode(NSMigrationMissingSourceModelError) }

    public static var persistentStoreCoordinatorLocking: CocoaError.Code { coreDataCode(NSPersistentStoreCoordinatorLockingError) }

    @available(*, deprecated, renamed: "persistentStoreCoordinatorLocking")
    public static var persistentStoreCoordinatorLockingError: CocoaError.Code { coreDataCode(NSPersistentStoreCoordinatorLockingError) }

    public static var persistentStoreIncompatibleSchema: CocoaError.Code { coreDataCode(NSPersistentStoreIncompatibleSchemaError) }

    @available(*, deprecated, renamed: "persistentStoreIncompatibleSchema")
    public static var persistentStoreIncompatibleSchemaError: CocoaError.Code { coreDataCode(NSPersistentStoreIncompatibleSchemaError) }

    public static var persistentStoreIncompatibleVersionHash: CocoaError.Code { coreDataCode(NSPersistentStoreIncompatibleVersionHashError) }

    @available(*, deprecated, renamed: "persistentStoreIncompatibleVersionHash")
    public static var persistentStoreIncompatibleVersionHashError: CocoaError.Code { coreDataCode(NSPersistentStoreIncompatibleVersionHashError) }

    public static var persistentStoreIncompleteSave: CocoaError.Code { coreDataCode(NSPersistentStoreIncompleteSaveError) }

    @available(*, deprecated, renamed: "persistentStoreIncompleteSave")
    public static var persistentStoreIncompleteSaveError: CocoaError.Code { coreDataCode(NSPersistentStoreIncompleteSaveError) }

    public static var persistentStoreInvalidType: CocoaError.Code { coreDataCode(NSPersistentStoreInvalidTypeError) }

    @available(*, deprecated, renamed: "persistentStoreInvalidType")
    public static var persistentStoreInvalidTypeError: CocoaError.Code { coreDataCode(NSPersistentStoreInvalidTypeError) }

    public static var persistentStoreOpen: CocoaError.Code { coreDataCode(NSPersistentStoreOpenError) }

    @available(*, deprecated, renamed: "persistentStoreOpen")
    public static var persistentStoreOpenError: CocoaError.Code { coreDataCode(NSPersistentStoreOpenError) }

    public static var persistentStoreOperation: CocoaError.Code { coreDataCode(NSPersistentStoreOperationError) }

    @available(*, deprecated, renamed: "persistentStoreOperation")
    public static var persistentStoreOperationError: CocoaError.Code { coreDataCode(NSPersistentStoreOperationError) }

    public static var persistentStoreSave: CocoaError.Code { coreDataCode(NSPersistentStoreSaveError) }

    public static var persistentStoreSaveConflicts: CocoaError.Code { coreDataCode(NSPersistentStoreSaveConflictsError) }

    @available(*, deprecated, renamed: "persistentStoreSaveConflicts")
    public static var persistentStoreSaveConflictsError: CocoaError.Code { coreDataCode(NSPersistentStoreSaveConflictsError) }

    @available(*, deprecated, renamed: "persistentStoreSave")
    public static var persistentStoreSaveError: CocoaError.Code { coreDataCode(NSPersistentStoreSaveError) }

    public static var persistentStoreTimeout: CocoaError.Code { coreDataCode(NSPersistentStoreTimeoutError) }

    @available(*, deprecated, renamed: "persistentStoreTimeout")
    public static var persistentStoreTimeoutError: CocoaError.Code { coreDataCode(NSPersistentStoreTimeoutError) }

    public static var persistentStoreTypeMismatch: CocoaError.Code { coreDataCode(NSPersistentStoreTypeMismatchError) }

    @available(*, deprecated, renamed: "persistentStoreTypeMismatch")
    public static var persistentStoreTypeMismatchError: CocoaError.Code { coreDataCode(NSPersistentStoreTypeMismatchError) }

    public static var persistentStoreUnsupportedRequestType: CocoaError.Code { coreDataCode(NSPersistentStoreUnsupportedRequestTypeError) }

    @available(*, deprecated, renamed: "persistentStoreUnsupportedRequestType")
    public static var persistentStoreUnsupportedRequestTypeError: CocoaError.Code { coreDataCode(NSPersistentStoreUnsupportedRequestTypeError) }

    public static var sqlite: CocoaError.Code { coreDataCode(NSSQLiteError) }

    @available(*, deprecated, renamed: "sqlite")
    public static var sqliteError: CocoaError.Code { coreDataCode(NSSQLiteError) }

    public static var validationDateTooLate: CocoaError.Code { coreDataCode(NSValidationDateTooLateError) }

    @available(*, deprecated, renamed: "validationDateTooLate")
    public static var validationDateTooLateError: CocoaError.Code { coreDataCode(NSValidationDateTooLateError) }

    public static var validationDateTooSoon: CocoaError.Code { coreDataCode(NSValidationDateTooSoonError) }

    @available(*, deprecated, renamed: "validationDateTooSoon")
    public static var validationDateTooSoonError: CocoaError.Code { coreDataCode(NSValidationDateTooSoonError) }

    public static var validationInvalidDate: CocoaError.Code { coreDataCode(NSValidationInvalidDateError) }

    @available(*, deprecated, renamed: "validationInvalidDate")
    public static var validationInvalidDateError: CocoaError.Code { coreDataCode(NSValidationInvalidDateError) }

    public static var validationMissingMandatoryProperty: CocoaError.Code { coreDataCode(NSValidationMissingMandatoryPropertyError) }

    @available(*, deprecated, renamed: "validationMissingMandatoryProperty")
    public static var validationMissingMandatoryPropertyError: CocoaError.Code { coreDataCode(NSValidationMissingMandatoryPropertyError) }

    public static var validationMultipleErrors: CocoaError.Code { coreDataCode(NSValidationMultipleErrorsError) }

    @available(*, deprecated, renamed: "validationMultipleErrors")
    public static var validationMultipleErrorsError: CocoaError.Code { coreDataCode(NSValidationMultipleErrorsError) }

    public static var validationNumberTooLarge: CocoaError.Code { coreDataCode(NSValidationNumberTooLargeError) }

    @available(*, deprecated, renamed: "validationNumberTooLarge")
    public static var validationNumberTooLargeError: CocoaError.Code { coreDataCode(NSValidationNumberTooLargeError) }

    public static var validationNumberTooSmall: CocoaError.Code { coreDataCode(NSValidationNumberTooSmallError) }

    @available(*, deprecated, renamed: "validationNumberTooSmall")
    public static var validationNumberTooSmallError: CocoaError.Code { coreDataCode(NSValidationNumberTooSmallError) }

    public static var validationRelationshipDeniedDelete: CocoaError.Code { coreDataCode(NSValidationRelationshipDeniedDeleteError) }

    @available(*, deprecated, renamed: "validationRelationshipDeniedDelete")
    public static var validationRelationshipDeniedDeleteError: CocoaError.Code { coreDataCode(NSValidationRelationshipDeniedDeleteError) }

    public static var validationRelationshipExceedsMaximumCount: CocoaError.Code { coreDataCode(NSValidationRelationshipExceedsMaximumCountError) }

    @available(*, deprecated, renamed: "validationRelationshipExceedsMaximumCount")
    public static var validationRelationshipExceedsMaximumCountError: CocoaError.Code { coreDataCode(NSValidationRelationshipExceedsMaximumCountError) }

    public static var validationRelationshipLacksMinimumCount: CocoaError.Code { coreDataCode(NSValidationRelationshipLacksMinimumCountError) }

    @available(*, deprecated, renamed: "validationRelationshipLacksMinimumCount")
    public static var validationRelationshipLacksMinimumCountError: CocoaError.Code { coreDataCode(NSValidationRelationshipLacksMinimumCountError) }

    public static var validationStringPatternMatching: CocoaError.Code { coreDataCode(NSValidationStringPatternMatchingError) }

    @available(*, deprecated, renamed: "validationStringPatternMatching")
    public static var validationStringPatternMatchingError: CocoaError.Code { coreDataCode(NSValidationStringPatternMatchingError) }

    public static var validationStringTooLong: CocoaError.Code { coreDataCode(NSValidationStringTooLongError) }

    @available(*, deprecated, renamed: "validationStringTooLong")
    public static var validationStringTooLongError: CocoaError.Code { coreDataCode(NSValidationStringTooLongError) }

    public static var validationStringTooShort: CocoaError.Code { coreDataCode(NSValidationStringTooShortError) }

    @available(*, deprecated, renamed: "validationStringTooShort")
    public static var validationStringTooShortError: CocoaError.Code { coreDataCode(NSValidationStringTooShortError) }
}

extension CocoaError {
    @available(*, unavailable, renamed: "entityMigrationPolicy")
    public static var EntityMigrationPolicyError: CocoaError.Code { coreDataCode(NSEntityMigrationPolicyError) }

    @available(*, unavailable, renamed: "externalRecordImport")
    public static var ExternalRecordImportError: CocoaError.Code { coreDataCode(NSExternalRecordImportError) }

    @available(*, unavailable, renamed: "inferredMappingModel")
    public static var InferredMappingModelError: CocoaError.Code { coreDataCode(NSInferredMappingModelError) }

    @available(*, unavailable, renamed: "managedObjectConstraintMerge")
    public static var ManagedObjectConstraintMergeError: CocoaError.Code { coreDataCode(NSManagedObjectConstraintMergeError) }

    @available(*, unavailable, renamed: "managedObjectContextLocking")
    public static var ManagedObjectContextLockingError: CocoaError.Code { coreDataCode(NSManagedObjectContextLockingError) }

    @available(*, unavailable, renamed: "managedObjectExternalRelationship")
    public static var ManagedObjectExternalRelationshipError: CocoaError.Code { coreDataCode(NSManagedObjectExternalRelationshipError) }

    @available(*, unavailable, renamed: "managedObjectMerge")
    public static var ManagedObjectMergeError: CocoaError.Code { coreDataCode(NSManagedObjectMergeError) }

    @available(*, unavailable, renamed: "managedObjectReferentialIntegrity")
    public static var ManagedObjectReferentialIntegrityError: CocoaError.Code { coreDataCode(NSManagedObjectReferentialIntegrityError) }

    @available(*, unavailable, renamed: "managedObjectValidation")
    public static var ManagedObjectValidationError: CocoaError.Code { coreDataCode(NSManagedObjectValidationError) }

    @available(*, unavailable, renamed: "migrationCancelled")
    public static var MigrationCancelledError: CocoaError.Code { coreDataCode(NSMigrationCancelledError) }

    @available(*, unavailable, renamed: "migration")
    public static var MigrationError: CocoaError.Code { coreDataCode(NSMigrationError) }

    @available(*, unavailable, renamed: "migrationManagerDestinationStore")
    public static var MigrationManagerDestinationStoreError: CocoaError.Code { coreDataCode(NSMigrationManagerDestinationStoreError) }

    @available(*, unavailable, renamed: "migrationManagerSourceStore")
    public static var MigrationManagerSourceStoreError: CocoaError.Code { coreDataCode(NSMigrationManagerSourceStoreError) }

    @available(*, unavailable, renamed: "migrationMissingMappingModel")
    public static var MigrationMissingMappingModelError: CocoaError.Code { coreDataCode(NSMigrationMissingMappingModelError) }

    @available(*, unavailable, renamed: "migrationMissingSourceModel")
    public static var MigrationMissingSourceModelError: CocoaError.Code { coreDataCode(NSMigrationMissingSourceModelError) }

    @available(*, unavailable, renamed: "persistentStoreCoordinatorLocking")
    public static var PersistentStoreCoordinatorLockingError: CocoaError.Code { coreDataCode(NSPersistentStoreCoordinatorLockingError) }

    @available(*, unavailable, renamed: "persistentStoreIncompatibleSchema")
    public static var PersistentStoreIncompatibleSchemaError: CocoaError.Code { coreDataCode(NSPersistentStoreIncompatibleSchemaError) }

    @available(*, unavailable, renamed: "persistentStoreIncompatibleVersionHash")
    public static var PersistentStoreIncompatibleVersionHashError: CocoaError.Code { coreDataCode(NSPersistentStoreIncompatibleVersionHashError) }

    @available(*, unavailable, renamed: "persistentStoreIncompleteSave")
    public static var PersistentStoreIncompleteSaveError: CocoaError.Code { coreDataCode(NSPersistentStoreIncompleteSaveError) }

    @available(*, unavailable, renamed: "persistentStoreInvalidType")
    public static var PersistentStoreInvalidTypeError: CocoaError.Code { coreDataCode(NSPersistentStoreInvalidTypeError) }

    @available(*, unavailable, renamed: "persistentStoreOpen")
    public static var PersistentStoreOpenError: CocoaError.Code { coreDataCode(NSPersistentStoreOpenError) }

    @available(*, unavailable, renamed: "persistentStoreOperation")
    public static var PersistentStoreOperationError: CocoaError.Code { coreDataCode(NSPersistentStoreOperationError) }

    @available(*, unavailable, renamed: "persistentStoreSaveConflicts")
    public static var PersistentStoreSaveConflictsError: CocoaError.Code { coreDataCode(NSPersistentStoreSaveConflictsError) }

    @available(*, unavailable, renamed: "persistentStoreSave")
    public static var PersistentStoreSaveError: CocoaError.Code { coreDataCode(NSPersistentStoreSaveError) }

    @available(*, unavailable, renamed: "persistentStoreTimeout")
    public static var PersistentStoreTimeoutError: CocoaError.Code { coreDataCode(NSPersistentStoreTimeoutError) }

    @available(*, unavailable, renamed: "persistentStoreTypeMismatch")
    public static var PersistentStoreTypeMismatchError: CocoaError.Code { coreDataCode(NSPersistentStoreTypeMismatchError) }

    @available(*, unavailable, renamed: "persistentStoreUnsupportedRequestType")
    public static var PersistentStoreUnsupportedRequestTypeError: CocoaError.Code { coreDataCode(NSPersistentStoreUnsupportedRequestTypeError) }

    @available(*, unavailable, renamed: "sqlite")
    public static var SQLiteError: CocoaError.Code { coreDataCode(NSSQLiteError) }

    @available(*, unavailable, renamed: "validationDateTooLate")
    public static var ValidationDateTooLateError: CocoaError.Code { coreDataCode(NSValidationDateTooLateError) }

    @available(*, unavailable, renamed: "validationDateTooSoon")
    public static var ValidationDateTooSoonError: CocoaError.Code { coreDataCode(NSValidationDateTooSoonError) }

    @available(*, unavailable, renamed: "validationInvalidDate")
    public static var ValidationInvalidDateError: CocoaError.Code { coreDataCode(NSValidationInvalidDateError) }

    @available(*, unavailable, renamed: "validationMissingMandatoryProperty")
    public static var ValidationMissingMandatoryPropertyError: CocoaError.Code { coreDataCode(NSValidationMissingMandatoryPropertyError) }

    @available(*, unavailable, renamed: "validationMultipleErrors")
    public static var ValidationMultipleErrorsError: CocoaError.Code { coreDataCode(NSValidationMultipleErrorsError) }

    @available(*, unavailable, renamed: "validationNumberTooLarge")
    public static var ValidationNumberTooLargeError: CocoaError.Code { coreDataCode(NSValidationNumberTooLargeError) }

    @available(*, unavailable, renamed: "validationNumberTooSmall")
    public static var ValidationNumberTooSmallError: CocoaError.Code { coreDataCode(NSValidationNumberTooSmallError) }

    @available(*, unavailable, renamed: "validationRelationshipDeniedDelete")
    public static var ValidationRelationshipDeniedDeleteError: CocoaError.Code { coreDataCode(NSValidationRelationshipDeniedDeleteError) }

    @available(*, unavailable, renamed: "validationRelationshipExceedsMaximumCount")
    public static var ValidationRelationshipExceedsMaximumCountError: CocoaError.Code { coreDataCode(NSValidationRelationshipExceedsMaximumCountError) }

    @available(*, unavailable, renamed: "validationRelationshipLacksMinimumCount")
    public static var ValidationRelationshipLacksMinimumCountError: CocoaError.Code { coreDataCode(NSValidationRelationshipLacksMinimumCountError) }

    @available(*, unavailable, renamed: "validationStringPatternMatching")
    public static var ValidationStringPatternMatchingError: CocoaError.Code { coreDataCode(NSValidationStringPatternMatchingError) }

    @available(*, unavailable, renamed: "validationStringTooLong")
    public static var ValidationStringTooLongError: CocoaError.Code { coreDataCode(NSValidationStringTooLongError) }

    @available(*, unavailable, renamed: "validationStringTooShort")
    public static var ValidationStringTooShortError: CocoaError.Code { coreDataCode(NSValidationStringTooShortError) }

    public static var coreData: CocoaError.Code { coreDataCode(NSCoreDataError) }

    @available(*, deprecated, renamed: "coreData")
    public static var coreDataError: CocoaError.Code { coreDataCode(NSCoreDataError) }

    public static var entityMigrationPolicy: CocoaError.Code { coreDataCode(NSEntityMigrationPolicyError) }

    @available(*, deprecated, renamed: "entityMigrationPolicy")
    public static var entityMigrationPolicyError: CocoaError.Code { coreDataCode(NSEntityMigrationPolicyError) }

    public static var externalRecordImport: CocoaError.Code { coreDataCode(NSExternalRecordImportError) }

    @available(*, deprecated, renamed: "externalRecordImport")
    public static var externalRecordImportError: CocoaError.Code { coreDataCode(NSExternalRecordImportError) }

    public static var inferredMappingModel: CocoaError.Code { coreDataCode(NSInferredMappingModelError) }

    @available(*, deprecated, renamed: "inferredMappingModel")
    public static var inferredMappingModelError: CocoaError.Code { coreDataCode(NSInferredMappingModelError) }

    public static var managedObjectConstraintMerge: CocoaError.Code { coreDataCode(NSManagedObjectConstraintMergeError) }

    @available(*, deprecated, renamed: "managedObjectConstraintMerge")
    public static var managedObjectConstraintMergeError: CocoaError.Code { coreDataCode(NSManagedObjectConstraintMergeError) }

    public static var managedObjectContextLocking: CocoaError.Code { coreDataCode(NSManagedObjectContextLockingError) }

    @available(*, deprecated, renamed: "managedObjectContextLocking")
    public static var managedObjectContextLockingError: CocoaError.Code { coreDataCode(NSManagedObjectContextLockingError) }

    public static var managedObjectExternalRelationship: CocoaError.Code { coreDataCode(NSManagedObjectExternalRelationshipError) }

    @available(*, deprecated, renamed: "managedObjectExternalRelationship")
    public static var managedObjectExternalRelationshipError: CocoaError.Code { coreDataCode(NSManagedObjectExternalRelationshipError) }

    public static var managedObjectMerge: CocoaError.Code { coreDataCode(NSManagedObjectMergeError) }

    @available(*, deprecated, renamed: "managedObjectMerge")
    public static var managedObjectMergeError: CocoaError.Code { coreDataCode(NSManagedObjectMergeError) }

    public static var managedObjectReferentialIntegrity: CocoaError.Code { coreDataCode(NSManagedObjectReferentialIntegrityError) }

    @available(*, deprecated, renamed: "managedObjectReferentialIntegrity")
    public static var managedObjectReferentialIntegrityError: CocoaError.Code { coreDataCode(NSManagedObjectReferentialIntegrityError) }

    public static var managedObjectValidation: CocoaError.Code { coreDataCode(NSManagedObjectValidationError) }

    @available(*, deprecated, renamed: "managedObjectValidation")
    public static var managedObjectValidationError: CocoaError.Code { coreDataCode(NSManagedObjectValidationError) }

    public static var migration: CocoaError.Code { coreDataCode(NSMigrationError) }

    public static var migrationCancelled: CocoaError.Code { coreDataCode(NSMigrationCancelledError) }

    @available(*, deprecated, renamed: "migrationCancelled")
    public static var migrationCancelledError: CocoaError.Code { coreDataCode(NSMigrationCancelledError) }

    @available(*, deprecated, renamed: "migration")
    public static var migrationError: CocoaError.Code { coreDataCode(NSMigrationError) }

    public static var migrationManagerDestinationStore: CocoaError.Code { coreDataCode(NSMigrationManagerDestinationStoreError) }

    @available(*, deprecated, renamed: "migrationManagerDestinationStore")
    public static var migrationManagerDestinationStoreError: CocoaError.Code { coreDataCode(NSMigrationManagerDestinationStoreError) }

    public static var migrationManagerSourceStore: CocoaError.Code { coreDataCode(NSMigrationManagerSourceStoreError) }

    @available(*, deprecated, renamed: "migrationManagerSourceStore")
    public static var migrationManagerSourceStoreError: CocoaError.Code { coreDataCode(NSMigrationManagerSourceStoreError) }

    public static var migrationMissingMappingModel: CocoaError.Code { coreDataCode(NSMigrationMissingMappingModelError) }

    @available(*, deprecated, renamed: "migrationMissingMappingModel")
    public static var migrationMissingMappingModelError: CocoaError.Code { coreDataCode(NSMigrationMissingMappingModelError) }

    public static var migrationMissingSourceModel: CocoaError.Code { coreDataCode(NSMigrationMissingSourceModelError) }

    @available(*, deprecated, renamed: "migrationMissingSourceModel")
    public static var migrationMissingSourceModelError: CocoaError.Code { coreDataCode(NSMigrationMissingSourceModelError) }

    public static var persistentStoreCoordinatorLocking: CocoaError.Code { coreDataCode(NSPersistentStoreCoordinatorLockingError) }

    @available(*, deprecated, renamed: "persistentStoreCoordinatorLocking")
    public static var persistentStoreCoordinatorLockingError: CocoaError.Code { coreDataCode(NSPersistentStoreCoordinatorLockingError) }

    public static var persistentStoreIncompatibleSchema: CocoaError.Code { coreDataCode(NSPersistentStoreIncompatibleSchemaError) }

    @available(*, deprecated, renamed: "persistentStoreIncompatibleSchema")
    public static var persistentStoreIncompatibleSchemaError: CocoaError.Code { coreDataCode(NSPersistentStoreIncompatibleSchemaError) }

    public static var persistentStoreIncompatibleVersionHash: CocoaError.Code { coreDataCode(NSPersistentStoreIncompatibleVersionHashError) }

    @available(*, deprecated, renamed: "persistentStoreIncompatibleVersionHash")
    public static var persistentStoreIncompatibleVersionHashError: CocoaError.Code { coreDataCode(NSPersistentStoreIncompatibleVersionHashError) }

    public static var persistentStoreIncompleteSave: CocoaError.Code { coreDataCode(NSPersistentStoreIncompleteSaveError) }

    @available(*, deprecated, renamed: "persistentStoreIncompleteSave")
    public static var persistentStoreIncompleteSaveError: CocoaError.Code { coreDataCode(NSPersistentStoreIncompleteSaveError) }

    public static var persistentStoreInvalidType: CocoaError.Code { coreDataCode(NSPersistentStoreInvalidTypeError) }

    @available(*, deprecated, renamed: "persistentStoreInvalidType")
    public static var persistentStoreInvalidTypeError: CocoaError.Code { coreDataCode(NSPersistentStoreInvalidTypeError) }

    public static var persistentStoreOpen: CocoaError.Code { coreDataCode(NSPersistentStoreOpenError) }

    @available(*, deprecated, renamed: "persistentStoreOpen")
    public static var persistentStoreOpenError: CocoaError.Code { coreDataCode(NSPersistentStoreOpenError) }

    public static var persistentStoreOperation: CocoaError.Code { coreDataCode(NSPersistentStoreOperationError) }

    @available(*, deprecated, renamed: "persistentStoreOperation")
    public static var persistentStoreOperationError: CocoaError.Code { coreDataCode(NSPersistentStoreOperationError) }

    public static var persistentStoreSave: CocoaError.Code { coreDataCode(NSPersistentStoreSaveError) }

    public static var persistentStoreSaveConflicts: CocoaError.Code { coreDataCode(NSPersistentStoreSaveConflictsError) }

    @available(*, deprecated, renamed: "persistentStoreSaveConflicts")
    public static var persistentStoreSaveConflictsError: CocoaError.Code { coreDataCode(NSPersistentStoreSaveConflictsError) }

    @available(*, deprecated, renamed: "persistentStoreSave")
    public static var persistentStoreSaveError: CocoaError.Code { coreDataCode(NSPersistentStoreSaveError) }

    public static var persistentStoreTimeout: CocoaError.Code { coreDataCode(NSPersistentStoreTimeoutError) }

    @available(*, deprecated, renamed: "persistentStoreTimeout")
    public static var persistentStoreTimeoutError: CocoaError.Code { coreDataCode(NSPersistentStoreTimeoutError) }

    public static var persistentStoreTypeMismatch: CocoaError.Code { coreDataCode(NSPersistentStoreTypeMismatchError) }

    @available(*, deprecated, renamed: "persistentStoreTypeMismatch")
    public static var persistentStoreTypeMismatchError: CocoaError.Code { coreDataCode(NSPersistentStoreTypeMismatchError) }

    public static var persistentStoreUnsupportedRequestType: CocoaError.Code { coreDataCode(NSPersistentStoreUnsupportedRequestTypeError) }

    @available(*, deprecated, renamed: "persistentStoreUnsupportedRequestType")
    public static var persistentStoreUnsupportedRequestTypeError: CocoaError.Code { coreDataCode(NSPersistentStoreUnsupportedRequestTypeError) }

    public static var sqlite: CocoaError.Code { coreDataCode(NSSQLiteError) }

    @available(*, deprecated, renamed: "sqlite")
    public static var sqliteError: CocoaError.Code { coreDataCode(NSSQLiteError) }

    public static var validationDateTooLate: CocoaError.Code { coreDataCode(NSValidationDateTooLateError) }

    @available(*, deprecated, renamed: "validationDateTooLate")
    public static var validationDateTooLateError: CocoaError.Code { coreDataCode(NSValidationDateTooLateError) }

    public static var validationDateTooSoon: CocoaError.Code { coreDataCode(NSValidationDateTooSoonError) }

    @available(*, deprecated, renamed: "validationDateTooSoon")
    public static var validationDateTooSoonError: CocoaError.Code { coreDataCode(NSValidationDateTooSoonError) }

    public static var validationInvalidDate: CocoaError.Code { coreDataCode(NSValidationInvalidDateError) }

    @available(*, deprecated, renamed: "validationInvalidDate")
    public static var validationInvalidDateError: CocoaError.Code { coreDataCode(NSValidationInvalidDateError) }

    public static var validationMissingMandatoryProperty: CocoaError.Code { coreDataCode(NSValidationMissingMandatoryPropertyError) }

    @available(*, deprecated, renamed: "validationMissingMandatoryProperty")
    public static var validationMissingMandatoryPropertyError: CocoaError.Code { coreDataCode(NSValidationMissingMandatoryPropertyError) }

    public static var validationMultipleErrors: CocoaError.Code { coreDataCode(NSValidationMultipleErrorsError) }

    @available(*, deprecated, renamed: "validationMultipleErrors")
    public static var validationMultipleErrorsError: CocoaError.Code { coreDataCode(NSValidationMultipleErrorsError) }

    public static var validationNumberTooLarge: CocoaError.Code { coreDataCode(NSValidationNumberTooLargeError) }

    @available(*, deprecated, renamed: "validationNumberTooLarge")
    public static var validationNumberTooLargeError: CocoaError.Code { coreDataCode(NSValidationNumberTooLargeError) }

    public static var validationNumberTooSmall: CocoaError.Code { coreDataCode(NSValidationNumberTooSmallError) }

    @available(*, deprecated, renamed: "validationNumberTooSmall")
    public static var validationNumberTooSmallError: CocoaError.Code { coreDataCode(NSValidationNumberTooSmallError) }

    public static var validationRelationshipDeniedDelete: CocoaError.Code { coreDataCode(NSValidationRelationshipDeniedDeleteError) }

    @available(*, deprecated, renamed: "validationRelationshipDeniedDelete")
    public static var validationRelationshipDeniedDeleteError: CocoaError.Code { coreDataCode(NSValidationRelationshipDeniedDeleteError) }

    public static var validationRelationshipExceedsMaximumCount: CocoaError.Code { coreDataCode(NSValidationRelationshipExceedsMaximumCountError) }

    @available(*, deprecated, renamed: "validationRelationshipExceedsMaximumCount")
    public static var validationRelationshipExceedsMaximumCountError: CocoaError.Code { coreDataCode(NSValidationRelationshipExceedsMaximumCountError) }

    public static var validationRelationshipLacksMinimumCount: CocoaError.Code { coreDataCode(NSValidationRelationshipLacksMinimumCountError) }

    @available(*, deprecated, renamed: "validationRelationshipLacksMinimumCount")
    public static var validationRelationshipLacksMinimumCountError: CocoaError.Code { coreDataCode(NSValidationRelationshipLacksMinimumCountError) }

    public static var validationStringPatternMatching: CocoaError.Code { coreDataCode(NSValidationStringPatternMatchingError) }

    @available(*, deprecated, renamed: "validationStringPatternMatching")
    public static var validationStringPatternMatchingError: CocoaError.Code { coreDataCode(NSValidationStringPatternMatchingError) }

    public static var validationStringTooLong: CocoaError.Code { coreDataCode(NSValidationStringTooLongError) }

    @available(*, deprecated, renamed: "validationStringTooLong")
    public static var validationStringTooLongError: CocoaError.Code { coreDataCode(NSValidationStringTooLongError) }

    public static var validationStringTooShort: CocoaError.Code { coreDataCode(NSValidationStringTooShortError) }

    @available(*, deprecated, renamed: "validationStringTooShort")
    public static var validationStringTooShortError: CocoaError.Code { coreDataCode(NSValidationStringTooShortError) }

    @available(*, unavailable, renamed: "coreData")
    public static var CoreDataError: CocoaError.Code { coreDataCode(NSCoreDataError) }
}

extension CocoaError {
    public var validationObject: Any? {
        userInfo[NSValidationObjectErrorKey]
    }

    public var validationKey: String? {
        userInfo[NSValidationKeyErrorKey] as? String
    }

    public var validationPredicate: NSPredicate? {
        userInfo[NSValidationPredicateErrorKey] as? NSPredicate
    }

    public var validationValue: Any? {
        userInfo[NSValidationValueErrorKey]
    }

    public var affectedStores: [AnyObject]? {
        userInfo[NSAffectedStoresErrorKey] as? [AnyObject]
    }

    public var affectedObjects: [AnyObject]? {
        userInfo[NSAffectedObjectsErrorKey] as? [AnyObject]
    }

    public var persistentStoreSaveConflicts: [NSMergeConflict]? {
        userInfo[NSPersistentStoreSaveConflictsErrorKey] as? [NSMergeConflict]
    }
}
