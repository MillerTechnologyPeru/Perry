import PerryObjCInterop

// Foundation's string constants that programs pass to Foundation, read
// out of its dictionaries or name its events by, with Darwin's values. Most
// key services Perry does not have (Spotlight, iCloud, extensions); they are
// here so a program that names them links and compares equal strings.

/// The user defaults keys of NeXT's and Mac OS X 10.0's date and number
/// formats, which Darwin still exports; nothing reads them.
@ObjCConstants
enum LegacyUserDefaultsKeys {
    static let NSAMPMDesignation = "NSAMPMDesignation"
    static let NSCurrencySymbol = "NSCurrencySymbol"
    static let NSDateFormatString = "NSDateFormatString"
    static let NSDateTimeOrdering = "NSDateTimeOrdering"
    static let NSDecimalDigits = "NSDecimalDigits"
    static let NSDecimalSeparator = "NSDecimalSeparator"
    static let NSEarlierTimeDesignations = "NSEarlierTimeDesignations"
    static let NSHourNameDesignations = "NSHourNameDesignations"
    static let NSInternationalCurrencyString = "NSInternationalCurrencyString"
    static let NSLaterTimeDesignations = "NSLaterTimeDesignations"
    static let NSMonthNameArray = "NSMonthNameArray"
    static let NSNegativeCurrencyFormatString = "NSNegativeCurrencyFormatString"
    static let NSNextDayDesignations = "NSNextDayDesignations"
    static let NSNextNextDayDesignations = "NSNextNextDayDesignations"
    static let NSPositiveCurrencyFormatString = "NSPositiveCurrencyFormatString"
    static let NSPriorDayDesignations = "NSPriorDayDesignations"
    static let NSShortDateFormatString = "NSShortDateFormatString"
    static let NSShortMonthNameArray = "NSShortMonthNameArray"
    static let NSShortTimeDateFormatString = "NSShortTimeDateFormatString"
    static let NSShortWeekDayNameArray = "NSShortWeekDayNameArray"
    static let NSThisDayDesignations = "NSThisDayDesignations"
    static let NSThousandsSeparator = "NSThousandsSeparator"
    static let NSTimeDateFormatString = "NSTimeDateFormatString"
    static let NSTimeFormatString = "NSTimeFormatString"
    static let NSWeekDayNameArray = "NSWeekDayNameArray"
    static let NSYearMonthWeekDesignations = "NSYearMonthWeekDesignations"
}

/// Calendar identifiers, the same strings as kCFCalendarIdentifier….
@ObjCConstants
enum CalendarIdentifiersMore {
    static let NSCalendarIdentifierBangla = "bangla"
    static let NSCalendarIdentifierDangi = "dangi"
    static let NSCalendarIdentifierGujarati = "gujarati"
    static let NSCalendarIdentifierKannada = "kannada"
    static let NSCalendarIdentifierMalayalam = "malayalam"
    static let NSCalendarIdentifierMarathi = "marathi"
    static let NSCalendarIdentifierOdia = "odia"
    static let NSCalendarIdentifierTamil = "tamil"
    static let NSCalendarIdentifierTelugu = "telugu"
    static let NSCalendarIdentifierVietnamese = "vietnamese"
    static let NSCalendarIdentifierVikram = "vikram"
}

/// Exception names: archiving's, NSInvocationOperation's, and the old
/// style's.
@ObjCConstants
enum FoundationExceptionsMore {
    static let NSInconsistentArchiveException = "NSArchiverArchiveInconsistency"
    static let NSInvalidUnarchiveOperationException = "NSInvalidUnarchiveOperationException"
    static let NSInvocationOperationCancelledException = "NSInvocationOperationCancelledException"
    static let NSInvocationOperationVoidResultException = "NSInvocationOperationVoidResultException"
    static let NSOldStyleException = "NSOldStyleException"
}

/// Notification names. Perry posts NSThreadWillExitNotification and the
/// threading ones only where NSThread does; the others' events (low disk
/// space for on-demand resources, extension hosts, iCloud defaults) never
/// happen here.
@ObjCConstants
enum FoundationNotificationsMore {
    static let NSBundleResourceRequestLowDiskSpaceNotification = "NSBundleResourceRequestLowDiskSpaceNotification"
    static let NSDidBecomeSingleThreadedNotification = "NSDidBecomeSingleThreadedNotification"
    static let NSExtensionHostDidBecomeActiveNotification = "NSExtensionHostDidBecomeActiveNotification"
    static let NSExtensionHostDidEnterBackgroundNotification = "NSExtensionHostDidEnterBackgroundNotification"
    static let NSExtensionHostWillEnterForegroundNotification = "NSExtensionHostWillEnterForegroundNotification"
    static let NSExtensionHostWillResignActiveNotification = "NSExtensionHostWillResignActiveNotification"
    static let NSSystemClockDidChangeNotification = "NSSystemClockDidChangeNotification"
    static let NSThreadWillExitNotification = "NSThreadWillExitNotification"
    static let NSUbiquitousUserDefaultsCompletedInitialSyncNotification = "NSUbiquitousUserDefaultsCompletedInitialSyncNotification"
    static let NSUbiquitousUserDefaultsDidChangeAccountsNotification = "NSUbiquitousUserDefaultsDidChangeAccountsNotification"
    static let NSUbiquitousUserDefaultsNoCloudAccountNotification = "NSUbiquitousUserDefaultsNoCloudAccountNotification"
    static let NSUserDefaultsSizeLimitExceededNotification = "com.apple.CFPreferences.byteCountLimitReached"
    static let NSWillBecomeMultiThreadedNotification = "NSWillBecomeMultiThreadedNotification"
}

/// NSLinguisticTagger's schemes and tags.
@ObjCConstants
enum LinguisticTagsMore {
    static let NSLinguisticTagAdjective = "Adjective"
    static let NSLinguisticTagAdverb = "Adverb"
    static let NSLinguisticTagClassifier = "Classifier"
    static let NSLinguisticTagCloseParenthesis = "CloseParenthesis"
    static let NSLinguisticTagCloseQuote = "CloseQuote"
    static let NSLinguisticTagConjunction = "Conjunction"
    static let NSLinguisticTagDash = "Dash"
    static let NSLinguisticTagDeterminer = "Determiner"
    static let NSLinguisticTagIdiom = "Idiom"
    static let NSLinguisticTagInterjection = "Interjection"
    static let NSLinguisticTagNoun = "Noun"
    static let NSLinguisticTagNumber = "Number"
    static let NSLinguisticTagOpenParenthesis = "OpenParenthesis"
    static let NSLinguisticTagOpenQuote = "OpenQuote"
    static let NSLinguisticTagOrganizationName = "OrganizationName"
    static let NSLinguisticTagOther = "Other"
    static let NSLinguisticTagOtherPunctuation = "Punctuation"
    static let NSLinguisticTagOtherWhitespace = "Whitespace"
    static let NSLinguisticTagOtherWord = "OtherWord"
    static let NSLinguisticTagParagraphBreak = "ParagraphBreak"
    static let NSLinguisticTagParticle = "Particle"
    static let NSLinguisticTagPersonalName = "PersonalName"
    static let NSLinguisticTagPlaceName = "PlaceName"
    static let NSLinguisticTagPreposition = "Preposition"
    static let NSLinguisticTagPronoun = "Pronoun"
    static let NSLinguisticTagPunctuation = "Punctuation"
    static let NSLinguisticTagSchemeLanguage = "Language"
    static let NSLinguisticTagSchemeLemma = "Lemma"
    static let NSLinguisticTagSchemeLexicalClass = "LexicalClass"
    static let NSLinguisticTagSchemeNameType = "NameType"
    static let NSLinguisticTagSchemeNameTypeOrLexicalClass = "NameTypeOrLexicalClass"
    static let NSLinguisticTagSchemeScript = "Script"
    static let NSLinguisticTagSchemeTokenType = "TokenType"
    static let NSLinguisticTagSentenceTerminator = "SentenceTerminator"
    static let NSLinguisticTagVerb = "Verb"
    static let NSLinguisticTagWhitespace = "Whitespace"
    static let NSLinguisticTagWord = "Word"
    static let NSLinguisticTagWordJoiner = "WordJoiner"
}

/// NSMetadataItem's attributes (Spotlight's kMDItem… names), its query's
/// scopes and update keys, and iCloud items' attributes and values.
@ObjCConstants
enum MetadataKeys {
    static let NSMetadataItemContentTypeKey = "kMDItemContentType"
    static let NSMetadataItemContentTypeTreeKey = "kMDItemContentTypeTree"
    static let NSMetadataItemDisplayNameKey = "kMDItemDisplayName"
    static let NSMetadataItemFSContentChangeDateKey = "kMDItemFSContentChangeDate"
    static let NSMetadataItemFSCreationDateKey = "kMDItemFSCreationDate"
    static let NSMetadataItemFSNameKey = "kMDItemFSName"
    static let NSMetadataItemFSSizeKey = "kMDItemFSSize"
    static let NSMetadataItemIsUbiquitousKey = "NSMetadataItemIsUbiquitousKey"
    static let NSMetadataItemPathKey = "kMDItemPath"
    static let NSMetadataItemURLKey = "kMDItemURL"
    static let NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope = "NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope"
    static let NSMetadataQueryResultContentRelevanceAttribute = "NSMetadataQueryResultContentRelevanceAttribute"
    static let NSMetadataQueryUbiquitousDataScope = "NSMetadataQueryUbiquitousDataScope"
    static let NSMetadataQueryUbiquitousDocumentsScope = "NSMetadataQueryUbiquitousDocumentsScope"
    static let NSMetadataQueryUpdateAddedItemsKey = "kMDQueryUpdateAddedItems"
    static let NSMetadataQueryUpdateChangedItemsKey = "kMDQueryUpdateChangedItems"
    static let NSMetadataQueryUpdateRemovedItemsKey = "kMDQueryUpdateRemovedItems"
    static let NSMetadataUbiquitousItemContainerDisplayNameKey = "NSMetadataUbiquitousItemContainerDisplayNameKey"
    static let NSMetadataUbiquitousItemDownloadRequestedKey = "NSMetadataUbiquitousItemDownloadRequestedKey"
    static let NSMetadataUbiquitousItemDownloadingErrorKey = "NSMetadataUbiquitousItemDownloadingErrorKey"
    static let NSMetadataUbiquitousItemDownloadingStatusCurrent = "NSMetadataUbiquitousItemDownloadingStatusCurrent"
    static let NSMetadataUbiquitousItemDownloadingStatusDownloaded = "NSMetadataUbiquitousItemDownloadingStatusDownloaded"
    static let NSMetadataUbiquitousItemDownloadingStatusKey = "NSMetadataUbiquitousItemDownloadingStatusKey"
    static let NSMetadataUbiquitousItemDownloadingStatusNotDownloaded = "NSMetadataUbiquitousItemDownloadingStatusNotDownloaded"
    static let NSMetadataUbiquitousItemHasUnresolvedConflictsKey = "NSMetadataUbiquitousItemHasUnresolvedConflictsKey"
    static let NSMetadataUbiquitousItemIsDownloadedKey = "NSMetadataUbiquitousItemIsDownloadedKey"
    static let NSMetadataUbiquitousItemIsDownloadingKey = "NSMetadataUbiquitousItemIsDownloadingKey"
    static let NSMetadataUbiquitousItemIsExternalDocumentKey = "NSMetadataUbiquitousItemIsExternalDocumentKey"
    static let NSMetadataUbiquitousItemIsSharedKey = "NSMetadataUbiquitousItemIsSharedKey"
    static let NSMetadataUbiquitousItemIsUploadedKey = "NSMetadataUbiquitousItemIsUploadedKey"
    static let NSMetadataUbiquitousItemIsUploadingKey = "NSMetadataUbiquitousItemIsUploadingKey"
    static let NSMetadataUbiquitousItemPercentDownloadedKey = "NSMetadataUbiquitousItemPercentDownloadedKey"
    static let NSMetadataUbiquitousItemPercentUploadedKey = "NSMetadataUbiquitousItemPercentUploadedKey"
    static let NSMetadataUbiquitousItemURLInLocalContainerKey = "NSMetadataUbiquitousItemURLInLocalContainerKey"
    static let NSMetadataUbiquitousItemUploadingErrorKey = "NSMetadataUbiquitousItemUploadingErrorKey"
    static let NSMetadataUbiquitousSharedItemCurrentUserPermissionsKey = "NSMetadataUbiquitousSharedItemCurrentUserPermissionsKey"
    static let NSMetadataUbiquitousSharedItemCurrentUserRoleKey = "NSMetadataUbiquitousSharedItemCurrentUserRoleKey"
    static let NSMetadataUbiquitousSharedItemMostRecentEditorNameComponentsKey = "NSMetadataUbiquitousSharedItemMostRecentEditorNameComponentsKey"
    static let NSMetadataUbiquitousSharedItemOwnerNameComponentsKey = "NSMetadataUbiquitousSharedItemOwnerNameComponentsKey"
    static let NSMetadataUbiquitousSharedItemPermissionsReadOnly = "NSMetadataUbiquitousSharedItemPermissionsReadOnly"
    static let NSMetadataUbiquitousSharedItemPermissionsReadWrite = "NSMetadataUbiquitousSharedItemPermissionsReadWrite"
    static let NSMetadataUbiquitousSharedItemRoleOwner = "NSMetadataUbiquitousSharedItemRoleOwner"
    static let NSMetadataUbiquitousSharedItemRoleParticipant = "NSMetadataUbiquitousSharedItemRoleParticipant"
}

/// NSProgress's user info keys and kinds.
@ObjCConstants
enum ProgressKeysMore {
    static let NSProgressEstimatedTimeRemainingKey = "NSProgressEstimatedTimeRemainingKey"
    static let NSProgressFileAnimationImageKey = "NSProgressFlyToImageKey"
    static let NSProgressFileAnimationImageOriginalRectKey = "NSProgressFileAnimationImageOriginalRectKey"
    static let NSProgressFileCompletedCountKey = "NSProgressFileCompletedCountKey"
    static let NSProgressFileIconKey = "NSProgressFileIconKey"
    static let NSProgressFileOperationKindCopying = "NSProgressFileOperationKindCopying"
    static let NSProgressFileOperationKindDecompressingAfterDownloading = "NSProgressFileOperationKindDecompressingAfterDownloading"
    static let NSProgressFileOperationKindDownloading = "NSProgressFileOperationKindDownloading"
    static let NSProgressFileOperationKindDuplicating = "NSProgressFileOperationKindDuplicating"
    static let NSProgressFileOperationKindKey = "NSProgressFileOperationKindKey"
    static let NSProgressFileOperationKindReceiving = "NSProgressFileOperationKindReceiving"
    static let NSProgressFileOperationKindUploading = "NSProgressFileOperationKindUploading"
    static let NSProgressFileTotalCountKey = "NSProgressFileTotalCountKey"
    static let NSProgressFileURLKey = "NSProgressFileURLKey"
    static let NSProgressKindFile = "NSProgressKindFile"
    static let NSProgressThroughputKey = "NSProgressThroughputKey"
}

/// NSStream's properties and values: the same strings as CFStream's
/// kCFStreamProperty… constants.
@ObjCConstants
enum StreamKeysMore {
    static let NSStreamFileCurrentOffsetKey = "kCFStreamPropertyFileCurrentOffset"
    static let NSStreamNetworkServiceTypeCallSignaling = "kCFStreamNetworkServiceTypeCallSignaling"
    static let NSStreamSOCKSErrorDomain = "NSStreamSOCKSErrorDomain"
    static let NSStreamSOCKSProxyConfigurationKey = "kCFStreamPropertySOCKSProxy"
    static let NSStreamSOCKSProxyHostKey = "SOCKSProxy"
    static let NSStreamSOCKSProxyPasswordKey = "kCFStreamPropertySOCKSPassword"
    static let NSStreamSOCKSProxyPortKey = "SOCKSPort"
    static let NSStreamSOCKSProxyUserKey = "kCFStreamPropertySOCKSUser"
    static let NSStreamSOCKSProxyVersion4 = "kCFStreamSocketSOCKSVersion4"
    static let NSStreamSOCKSProxyVersion5 = "kCFStreamSocketSOCKSVersion5"
    static let NSStreamSOCKSProxyVersionKey = "kCFStreamPropertySOCKSVersion"
    static let NSStreamSocketSSLErrorDomain = "NSStreamSocketSSLErrorDomain"
    static let NSStreamSocketSecurityLevelKey = "kCFStreamPropertySocketSecurityLevel"
    static let NSStreamSocketSecurityLevelNegotiatedSSL = "kCFStreamSocketSecurityLevelNegotiatedSSL"
    static let NSStreamSocketSecurityLevelNone = "kCFStreamSocketSecurityLevelNone"
    static let NSStreamSocketSecurityLevelSSLv2 = "kCFStreamSocketSecurityLevelSSLv2"
    static let NSStreamSocketSecurityLevelSSLv3 = "kCFStreamSocketSecurityLevelSSLv3"
    static let NSStreamSocketSecurityLevelTLSv1 = "kCFStreamSocketSecurityLevelTLSv1"
}

/// +stringEncodingForData:encodingOptions:…'s option keys.
@ObjCConstants
enum StringEncodingDetectionKeys {
    static let NSStringEncodingDetectionAllowLossyKey = "NSStringEncodingDetectionAllowLossyKey"
    static let NSStringEncodingDetectionDisallowedEncodingsKey = "NSStringEncodingDetectionDisallowedEncodingsKey"
    static let NSStringEncodingDetectionFromWindowsKey = "NSStringEncodingDetectionFromWindowsKey"
    static let NSStringEncodingDetectionLikelyLanguageKey = "NSStringEncodingDetectionLikelyLanguageKey"
    static let NSStringEncodingDetectionLossySubstitutionKey = "NSStringEncodingDetectionLossySubstitutionKey"
    static let NSStringEncodingDetectionSuggestedEncodingsKey = "NSStringEncodingDetectionSuggestedEncodingsKey"
    static let NSStringEncodingDetectionUseOnlySuggestedEncodingsKey = "NSStringEncodingDetectionUseOnlySuggestedEncodingsKey"
}

/// NSString's -stringByApplyingTransform:reverse: transforms. On Darwin
/// each is the CFString kCFStringTransform… constant itself, a private
/// token; here they are the ICU transform IDs Perry's kCFStringTransform…
/// constants are, which the transforms take.
@ObjCConstants
enum StringTransformNames {
    static let NSStringTransformFullwidthToHalfwidth = "Fullwidth-Halfwidth"
    static let NSStringTransformHiraganaToKatakana = "Hiragana-Katakana"
    static let NSStringTransformLatinToArabic = "Latin-Arabic"
    static let NSStringTransformLatinToCyrillic = "Latin-Cyrillic"
    static let NSStringTransformLatinToGreek = "Latin-Greek"
    static let NSStringTransformLatinToHangul = "Latin-Hangul"
    static let NSStringTransformLatinToHebrew = "Latin-Hebrew"
    static let NSStringTransformLatinToHiragana = "Latin-Hiragana"
    static let NSStringTransformLatinToKatakana = "Latin-Katakana"
    static let NSStringTransformLatinToThai = "Latin-Thai"
    static let NSStringTransformMandarinToLatin = "Han-Latin"
    static let NSStringTransformStripCombiningMarks = "NFD; [:Mn:] Remove; NFC"
    static let NSStringTransformStripDiacritics = "NFD; [:Nonspacing Mark:] Remove; NFC"
    static let NSStringTransformToLatin = "Any-Latin"
    static let NSStringTransformToUnicodeName = "Any-Name"
    static let NSStringTransformToXMLHex = "Any-Hex/XML"
}

/// NSTextCheckingResult's address, transit and contact component keys.
@ObjCConstants
enum TextCheckingKeysMore {
    static let NSTextCheckingAirlineKey = "Airline"
    static let NSTextCheckingCityKey = "City"
    static let NSTextCheckingCountryKey = "Country"
    static let NSTextCheckingFlightKey = "Flight"
    static let NSTextCheckingJobTitleKey = "JobTitle"
    static let NSTextCheckingNameKey = "Name"
    static let NSTextCheckingOrganizationKey = "Organization"
    static let NSTextCheckingPhoneKey = "Phone"
    static let NSTextCheckingStateKey = "State"
    static let NSTextCheckingStreetKey = "Street"
    static let NSTextCheckingZIPKey = "ZIP"
}

/// NSURL's resource keys and values, the same strings as CFURL's
/// kCFURL… keys, and the file scheme.
@ObjCConstants
enum URLResourceKeysMore {
    static let NSURLCustomIconKey = "NSURLCustomIconKey"
    static let NSURLDirectoryEntryCountKey = "NSURLDirectoryEntryCountKey"
    static let NSURLEffectiveIconKey = "NSURLEffectiveIconKey"
    static let NSURLFileContentIdentifierKey = "NSURLFileContentIdentifierKey"
    static let NSURLFileIdentifierKey = "NSURLFileIdentifierKey"
    static let NSURLFileProtectionComplete = "NSURLFileProtectionComplete"
    static let NSURLFileProtectionCompleteUnlessOpen = "NSURLFileProtectionCompleteUnlessOpen"
    static let NSURLFileProtectionCompleteUntilFirstUserAuthentication = "NSURLFileProtectionCompleteUntilFirstUserAuthentication"
    static let NSURLFileProtectionCompleteWhenUserInactive = "NSURLFileProtectionCompleteWhenUserInactive"
    static let NSURLFileProtectionNone = "NSURLFileProtectionNone"
    static let NSURLFileResourceTypeBlockSpecial = "NSURLFileResourceTypeBlockSpecial"
    static let NSURLFileResourceTypeCharacterSpecial = "NSURLFileResourceTypeCharacterSpecial"
    static let NSURLFileResourceTypeDirectory = "NSURLFileResourceTypeDirectory"
    static let NSURLFileResourceTypeNamedPipe = "NSURLFileResourceTypeNamedPipe"
    static let NSURLFileResourceTypeRegular = "NSURLFileResourceTypeRegular"
    static let NSURLFileResourceTypeSocket = "NSURLFileResourceTypeSocket"
    static let NSURLFileResourceTypeSymbolicLink = "NSURLFileResourceTypeSymbolicLink"
    static let NSURLFileResourceTypeUnknown = "NSURLFileResourceTypeUnknown"
    static let NSURLFileScheme = "file"
    static let NSURLIsPurgeableKey = "NSURLIsPurgeableKey"
    static let NSURLIsSparseKey = "NSURLIsSparseKey"
    static let NSURLKeysOfUnsetValuesKey = "NSURLKeysOfUnsetValuesKey"
    static let NSURLLabelColorKey = "NSURLLabelColorKey"
    static let NSURLMayHaveExtendedAttributesKey = "NSURLMayHaveExtendedAttributesKey"
    static let NSURLMayShareFileContentKey = "NSURLMayShareFileContentKey"
    static let NSURLThumbnailKey = "NSURLThumbnailKey"
    static let NSURLUbiquitousItemDownloadingStatusCurrent = "NSURLUbiquitousItemDownloadingStatusCurrent"
    static let NSURLUbiquitousItemDownloadingStatusDownloaded = "NSURLUbiquitousItemDownloadingStatusDownloaded"
    static let NSURLUbiquitousItemDownloadingStatusNotDownloaded = "NSURLUbiquitousItemDownloadingStatusNotDownloaded"
    static let NSURLUbiquitousItemIsDownloadedKey = "NSURLUbiquitousItemIsDownloadedKey"
    static let NSURLUbiquitousItemIsExcludedFromSyncKey = "NSURLUbiquitousItemIsExcludedFromSyncKey"
    static let NSURLUbiquitousItemIsSyncPausedKey = "NSURLUbiquitousItemIsSyncPausedKey"
    static let NSURLUbiquitousItemPercentDownloadedKey = "NSURLUbiquitousItemPercentDownloadedKey"
    static let NSURLUbiquitousItemPercentUploadedKey = "NSURLUbiquitousItemPercentUploadedKey"
    static let NSURLUbiquitousItemSupportedSyncControlsKey = "NSURLUbiquitousItemSupportedSyncControlsKey"
    static let NSURLUbiquitousSharedItemPermissionsReadOnly = "NSURLUbiquitousSharedItemPermissionsReadOnly"
    static let NSURLUbiquitousSharedItemPermissionsReadWrite = "NSURLUbiquitousSharedItemPermissionsReadWrite"
    static let NSURLUbiquitousSharedItemRoleOwner = "NSURLUbiquitousSharedItemRoleOwner"
    static let NSURLUbiquitousSharedItemRoleParticipant = "NSURLUbiquitousSharedItemRoleParticipant"
    static let NSURLVolumeMountFromLocationKey = "NSURLVolumeMountFromLocationKey"
    static let NSURLVolumeSubtypeKey = "NSURLVolumeSubtypeKey"
    static let NSURLVolumeSupportsAccessPermissionsKey = "NSURLVolumeSupportsAccessPermissionsKey"
    static let NSURLVolumeSupportsExclusiveRenamingKey = "NSURLVolumeSupportsExclusiveRenamingKey"
    static let NSURLVolumeSupportsFileCloningKey = "NSURLVolumeSupportsFileCloningKey"
    static let NSURLVolumeSupportsFileProtectionKey = "NSURLVolumeSupportsFileProtectionKey"
    static let NSURLVolumeSupportsImmutableFilesKey = "NSURLVolumeSupportsImmutableFilesKey"
    static let NSURLVolumeSupportsSwapRenamingKey = "NSURLVolumeSupportsSwapRenamingKey"
    static let NSURLVolumeTypeNameKey = "NSURLVolumeTypeNameKey"
}

/// NSExtensionItem's user info keys and the JavaScript preprocessing keys.
@ObjCConstants
enum ExtensionItemKeys {
    static let NSExtensionItemAttachmentsKey = "NSExtensionItemAttachmentsKey"
    static let NSExtensionItemAttributedContentTextKey = "NSExtensionItemAttributedContentTextKey"
    static let NSExtensionItemAttributedTitleKey = "NSExtensionItemAttributedTitleKey"
    static let NSExtensionItemsAndErrorsKey = "NSExtensionItemsAndErrorsKey"
    static let NSExtensionJavaScriptFinalizeArgumentKey = "NSExtensionJavaScriptFinalizeArgumentKey"
    static let NSExtensionJavaScriptPreprocessingResultsKey = "NSExtensionJavaScriptPreprocessingResultsKey"
}

/// Other user info, error and dictionary keys and domains.
@ObjCConstants
enum FoundationKeysMore {
    static let NSAssertionHandlerKey = "NSAssertionHandler"
    static let NSFileHandleNotificationFileHandleItem = "NSFileHandleNotificationFileHandleItem"
    static let NSFileHandleNotificationMonitorModes = "NSFileHandleNotificationMonitorModes"
    static let NSFileProtectionCompleteWhenUserInactive = "NSFileProtectionCompleteWhenUserInactive"
    static let NSHTTPCookieSetByJavaScript = "SetInJavaScript"
    static let NSInflectionConceptsKey = "NSContextInflectionConcepts"
    static let NSItemProviderErrorDomain = "NSItemProviderErrorDomain"
    static let NSItemProviderPreferredImageSizeKey = "NSItemProviderPreferredImageSize"
    static let NSLoadedClasses = "NSLoadedClasses"
    static let NSLocalizedFailureErrorKey = "NSLocalizedFailure"
    static let NSMultipleUnderlyingErrorsKey = "NSMultipleUnderlyingErrorsKey"
    static let NSStringEncodingErrorKey = "NSStringEncoding"
    static let NSThumbnail1024x1024SizeKey = "NSThumbnail1024x1024SizeKey"
    static let NSURLSessionUploadTaskResumeData = "NSURLSessionUploadTaskResumeData"
    static let NSUndoManagerGroupIsDiscardableKey = "NSUndoManagerGroupIsDiscardableKey"
    static let NSUserActivityTypeBrowsingWeb = "NSUserActivityTypeBrowsingWeb"
}

/// NSBundleResourceRequest's highest loading priority, DBL_MAX.
@ObjCConstants
enum BundleResourceRequestPriorities {
    static let NSBundleResourceRequestLoadingPriorityUrgent: Double = 1.7976931348623157e308
}

/// NSConnection's run loop mode for replies, and NSDebugEnabled, the BOOL
/// Foundation's debugging checks read, off.
@ObjCConstants
enum DistributedObjectsConstants {
    static let NSConnectionReplyMode = "NSConnectionReplyMode"
    static let NSDebugEnabled: Int64 = 0
}
