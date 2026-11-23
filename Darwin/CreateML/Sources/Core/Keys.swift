import Foundation

// The names of the parameters, results and files the Swift 5.0 overlay passed
// its C engine, which it exported as global strings. Perry's engine has no
// use for them; they are kept, with values of the same kind, for programs
// built against that overlay, which reach a global of another module through
// its addressor. Swift exports a library-evolution module's globals through
// accessors instead, so each addressor here is a function of that name
// (the globals' storage symbols can't be: see README.md).

/// The storage of the keys, by name.
private var keyStorage: [String: UnsafeMutablePointer<String>] = [:]
private let keyLock = NSLock()

/// The address of a key's storage, made the first time it's asked for.
private func keyAddress(_ name: String, _ value: @autoclosure () -> String) -> UnsafeMutableRawPointer {
    keyLock.lock()
    defer { keyLock.unlock() }
    if let pointer = keyStorage[name] { return UnsafeMutableRawPointer(pointer) }
    let pointer = UnsafeMutablePointer<String>.allocate(capacity: 1)
    pointer.initialize(to: value())
    keyStorage[name] = pointer
    return UnsafeMutableRawPointer(pointer)
}

@_spi(Swift50) @_silgen_name("$s8CreateML11accuracyKeySSvau")
public func _accuracyKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("accuracyKey", "accuracy") }

@_spi(Swift50) @_silgen_name("$s8CreateML21addMetaDataMethodNameSSvau")
public func _addMetaDataMethodNameAddressor() -> UnsafeMutableRawPointer { keyAddress("addMetaDataMethodName", "addMetaData") }

@_spi(Swift50) @_silgen_name("$s8CreateML35augmentationOptionsApplePipelineKeySSvau")
public func _augmentationOptionsApplePipelineKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsApplePipelineKey", "augmentationOptionsApplePipeline") }

@_spi(Swift50) @_silgen_name("$s8CreateML26augmentationOptionsBlurKeySSvau")
public func _augmentationOptionsBlurKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsBlurKey", "augmentationOptionsBlur") }

@_spi(Swift50) @_silgen_name("$s8CreateML26augmentationOptionsCropKeySSvau")
public func _augmentationOptionsCropKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsCropKey", "augmentationOptionsCrop") }

@_spi(Swift50) @_silgen_name("$s8CreateML30augmentationOptionsExposureKeySSvau")
public func _augmentationOptionsExposureKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsExposureKey", "augmentationOptionsExposure") }

@_spi(Swift50) @_silgen_name("$s8CreateML26augmentationOptionsFlipKeySSvau")
public func _augmentationOptionsFlipKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsFlipKey", "augmentationOptionsFlip") }

@_spi(Swift50) @_silgen_name("$s8CreateML22augmentationOptionsKeySSvau")
public func _augmentationOptionsKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsKey", "augmentationOptions") }

@_spi(Swift50) @_silgen_name("$s8CreateML27augmentationOptionsNoiseKeySSvau")
public func _augmentationOptionsNoiseKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsNoiseKey", "augmentationOptionsNoise") }

@_spi(Swift50) @_silgen_name("$s8CreateML39augmentationOptionsParameterMaxRangeKeySSvau")
public func _augmentationOptionsParameterMaxRangeKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsParameterMaxRangeKey", "augmentationOptionsParameterMaxRange") }

@_spi(Swift50) @_silgen_name("$s8CreateML39augmentationOptionsParameterMinRangeKeySSvau")
public func _augmentationOptionsParameterMinRangeKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsParameterMinRangeKey", "augmentationOptionsParameterMinRange") }

@_spi(Swift50) @_silgen_name("$s8CreateML46augmentationOptionsParameterNumberOfBuffersKeySSvau")
public func _augmentationOptionsParameterNumberOfBuffersKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsParameterNumberOfBuffersKey", "augmentationOptionsParameterNumberOfBuffers") }

@_spi(Swift50) @_silgen_name("$s8CreateML41augmentationOptionsParameterRandomSeedKeySSvau")
public func _augmentationOptionsParameterRandomSeedKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsParameterRandomSeedKey", "augmentationOptionsParameterRandomSeed") }

@_spi(Swift50) @_silgen_name("$s8CreateML30augmentationOptionsRotationKeySSvau")
public func _augmentationOptionsRotationKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("augmentationOptionsRotationKey", "augmentationOptionsRotation") }

@_spi(Swift50) @_silgen_name("$s8CreateML7autoKeySSvau")
public func _autoKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("autoKey", "auto") }

@_spi(Swift50) @_silgen_name("$s8CreateML22automaticClassifierKeySSvau")
public func _automaticClassifierKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("automaticClassifierKey", "automaticClassifier") }

@_spi(Swift50) @_silgen_name("$s8CreateML21automaticRegressorKeySSvau")
public func _automaticRegressorKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("automaticRegressorKey", "automaticRegressor") }

@_spi(Swift50) @_silgen_name("$s8CreateML6btcKeySSvau")
public func _btcKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("btcKey", "btc") }

@_spi(Swift50) @_silgen_name("$s8CreateML6btrKeySSvau")
public func _btrKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("btrKey", "btr") }

@_spi(Swift50) @_silgen_name("$s8CreateML16cmCountColumnKeySSvau")
public func _cmCountColumnKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("cmCountColumnKey", "cmCountColumn") }

@_spi(Swift50) @_silgen_name("$s8CreateML20cmPredictedColumnKeySSvau")
public func _cmPredictedColumnKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("cmPredictedColumnKey", "cmPredictedColumn") }

@_spi(Swift50) @_silgen_name("$s8CreateML23cmPrintFirstCellNameKeySSvau")
public func _cmPrintFirstCellNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("cmPrintFirstCellNameKey", "cmPrintFirstCell") }

@_spi(Swift50) @_silgen_name("$s8CreateML16cmTruthColumnKeySSvau")
public func _cmTruthColumnKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("cmTruthColumnKey", "cmTruthColumn") }

@_spi(Swift50) @_silgen_name("$s8CreateML18columnSubsampleKeySSvau")
public func _columnSubsampleKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("columnSubsampleKey", "columnSubsample") }

@_spi(Swift50) @_silgen_name("$s8CreateML12confusionKeySSvau")
public func _confusionKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("confusionKey", "confusion") }

@_spi(Swift50) @_silgen_name("$s8CreateML23convergenceThresholdKeySSvau")
public func _convergenceThresholdKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("convergenceThresholdKey", "convergenceThreshold") }

@_spi(Swift50) @_silgen_name("$s8CreateML10csvCommentSSvau")
public func _csvCommentAddressor() -> UnsafeMutableRawPointer { keyAddress("csvComment", "comment") }

@_spi(Swift50) @_silgen_name("$s8CreateML12csvDelimiterSSvau")
public func _csvDelimiterAddressor() -> UnsafeMutableRawPointer { keyAddress("csvDelimiter", "delimiter") }

@_spi(Swift50) @_silgen_name("$s8CreateML14csvDoubleQuoteSSvau")
public func _csvDoubleQuoteAddressor() -> UnsafeMutableRawPointer { keyAddress("csvDoubleQuote", "doubleQuote") }

@_spi(Swift50) @_silgen_name("$s8CreateML9csvEscapeSSvau")
public func _csvEscapeAddressor() -> UnsafeMutableRawPointer { keyAddress("csvEscape", "escape") }

@_spi(Swift50) @_silgen_name("$s8CreateML9csvHeaderSSvau")
public func _csvHeaderAddressor() -> UnsafeMutableRawPointer { keyAddress("csvHeader", "header") }

@_spi(Swift50) @_silgen_name("$s8CreateML17csvLineTerminatorSSvau")
public func _csvLineTerminatorAddressor() -> UnsafeMutableRawPointer { keyAddress("csvLineTerminator", "lineTerminator") }

@_spi(Swift50) @_silgen_name("$s8CreateML10csvMaxRowsSSvau")
public func _csvMaxRowsAddressor() -> UnsafeMutableRawPointer { keyAddress("csvMaxRows", "maxRows") }

@_spi(Swift50) @_silgen_name("$s8CreateML16csvMissingValuesSSvau")
public func _csvMissingValuesAddressor() -> UnsafeMutableRawPointer { keyAddress("csvMissingValues", "missingValues") }

@_spi(Swift50) @_silgen_name("$s8CreateML8csvQuoteSSvau")
public func _csvQuoteAddressor() -> UnsafeMutableRawPointer { keyAddress("csvQuote", "quote") }

@_spi(Swift50) @_silgen_name("$s8CreateML16csvSelectColumnsSSvau")
public func _csvSelectColumnsAddressor() -> UnsafeMutableRawPointer { keyAddress("csvSelectColumns", "selectColumns") }

@_spi(Swift50) @_silgen_name("$s8CreateML20csvSkipInitialSpacesSSvau")
public func _csvSkipInitialSpacesAddressor() -> UnsafeMutableRawPointer { keyAddress("csvSkipInitialSpaces", "skipInitialSpaces") }

@_spi(Swift50) @_silgen_name("$s8CreateML11csvSkipRowsSSvau")
public func _csvSkipRowsAddressor() -> UnsafeMutableRawPointer { keyAddress("csvSkipRows", "skipRows") }

@_spi(Swift50) @_silgen_name("$s8CreateML22defaultImageColumnNameSSvau")
public func _defaultImageColumnNameAddressor() -> UnsafeMutableRawPointer { keyAddress("defaultImageColumnName", "defaultImage") }

@_spi(Swift50) @_silgen_name("$s8CreateML22defaultLabelColumnNameSSvau")
public func _defaultLabelColumnNameAddressor() -> UnsafeMutableRawPointer { keyAddress("defaultLabelColumnName", "defaultLabel") }

@_spi(Swift50) @_silgen_name("$s8CreateML15downloadPathKeySSvau")
public func _downloadPathKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("downloadPathKey", "downloadPath") }

@_spi(Swift50) @_silgen_name("$s8CreateML6dtcKeySSvau")
public func _dtcKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("dtcKey", "dtc") }

@_spi(Swift50) @_silgen_name("$s8CreateML6dtrKeySSvau")
public func _dtrKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("dtrKey", "dtr") }

@_spi(Swift50) @_silgen_name("$s8CreateML22earlyStoppingRoundsKeySSvau")
public func _earlyStoppingRoundsKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("earlyStoppingRoundsKey", "earlyStoppingRounds") }

@_spi(Swift50) @_silgen_name("$s8CreateML15errorOnBadLinesSSvau")
public func _errorOnBadLinesAddressor() -> UnsafeMutableRawPointer { keyAddress("errorOnBadLines", "errorOnBadLines") }

@_spi(Swift50) @_silgen_name("$s8CreateML18evaluateMethodNameSSvau")
public func _evaluateMethodNameAddressor() -> UnsafeMutableRawPointer { keyAddress("evaluateMethodName", "evaluate") }

@_spi(Swift50) @_silgen_name("$s8CreateML16exportMethodNameSSvau")
public func _exportMethodNameAddressor() -> UnsafeMutableRawPointer { keyAddress("exportMethodName", "export") }

@_spi(Swift50) @_silgen_name("$s8CreateML17featureColumnsKeySSvau")
public func _featureColumnsKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("featureColumnsKey", "featureColumns") }

@_spi(Swift50) @_silgen_name("$s8CreateML19featureRescalingKeySSvau")
public func _featureRescalingKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("featureRescalingKey", "featureRescaling") }

@_spi(Swift50) @_silgen_name("$s8CreateML18getValueMethodNameSSvau")
public func _getValueMethodNameAddressor() -> UnsafeMutableRawPointer { keyAddress("getValueMethodName", "getValue") }

@_spi(Swift50) @_silgen_name("$s8CreateML5icKeySSvau")
public func _icKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("icKey", "ic") }

@_spi(Swift50) @_silgen_name("$s8CreateML27initializeOptionsMethodNameSSvau")
public func _initializeOptionsMethodNameAddressor() -> UnsafeMutableRawPointer { keyAddress("initializeOptionsMethodName", "initializeOptions") }

@_spi(Swift50) @_silgen_name("$s8CreateML12l1PenaltyKeySSvau")
public func _l1PenaltyKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("l1PenaltyKey", "l1Penalty") }

@_spi(Swift50) @_silgen_name("$s8CreateML12l2PenaltyKeySSvau")
public func _l2PenaltyKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("l2PenaltyKey", "l2Penalty") }

@_spi(Swift50) @_silgen_name("$s8CreateML20listFieldsMethodNameSSvau")
public func _listFieldsMethodNameAddressor() -> UnsafeMutableRawPointer { keyAddress("listFieldsMethodName", "listFields") }

@_spi(Swift50) @_silgen_name("$s8CreateML25loadImagesArrayMethodNameSSvau")
public func _loadImagesArrayMethodNameAddressor() -> UnsafeMutableRawPointer { keyAddress("loadImagesArrayMethodName", "loadImagesArray") }

@_spi(Swift50) @_silgen_name("$s8CreateML20loadImagesMethodNameSSvau")
public func _loadImagesMethodNameAddressor() -> UnsafeMutableRawPointer { keyAddress("loadImagesMethodName", "loadImages") }

@_spi(Swift50) @_silgen_name("$s8CreateML6lrcKeySSvau")
public func _lrcKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("lrcKey", "lrc") }

@_spi(Swift50) @_silgen_name("$s8CreateML5lrKeySSvau")
public func _lrKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("lrKey", "lr") }

@_spi(Swift50) @_silgen_name("$s8CreateML11maxDepthKeySSvau")
public func _maxDepthKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("maxDepthKey", "maxDepth") }

@_spi(Swift50) @_silgen_name("$s8CreateML11maxErrorKeySSvau")
public func _maxErrorKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("maxErrorKey", "maxError") }

@_spi(Swift50) @_silgen_name("$s8CreateML16maxIterationsKeySSvau")
public func _maxIterationsKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("maxIterationsKey", "maxIterations") }

@_spi(Swift50) @_silgen_name("$s8CreateML17metaDataAuthorKeySSvau")
public func _metaDataAuthorKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("metaDataAuthorKey", "author") }

@_spi(Swift50) @_silgen_name("$s8CreateML18metaDataLicenseKeySSvau")
public func _metaDataLicenseKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("metaDataLicenseKey", "license") }

@_spi(Swift50) @_silgen_name("$s8CreateML27metaDataShortDescriptionKeySSvau")
public func _metaDataShortDescriptionKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("metaDataShortDescriptionKey", "shortDescription") }

@_spi(Swift50) @_silgen_name("$s8CreateML22metaDataUserDefinedKeySSvau")
public func _metaDataUserDefinedKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("metaDataUserDefinedKey", "userDefined") }

@_spi(Swift50) @_silgen_name("$s8CreateML18metaDataVersionKeySSvau")
public func _metaDataVersionKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("metaDataVersionKey", "version") }

@_spi(Swift50) @_silgen_name("$s8CreateML9metricKeySSvau")
public func _metricKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("metricKey", "metric") }

@_spi(Swift50) @_silgen_name("$s8CreateML17minChildWeightKeySSvau")
public func _minChildWeightKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("minChildWeightKey", "minChildWeight") }

@_spi(Swift50) @_silgen_name("$s8CreateML19minLossReductionKeySSvau")
public func _minLossReductionKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("minLossReductionKey", "minLossReduction") }

@_spi(Swift50) @_silgen_name("$s8CreateML14modelExtensionSSvau")
public func _modelExtensionAddressor() -> UnsafeMutableRawPointer { keyAddress("modelExtension", "mlmodel") }

@_spi(Swift50) @_silgen_name("$s8CreateML19numberOfExamplesKeySSvau")
public func _numberOfExamplesKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("numberOfExamplesKey", "numberOfExamples") }

@_spi(Swift50) @_silgen_name("$s8CreateML24parameterAlgorithmCRFKeySSvau")
public func _parameterAlgorithmCRFKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterAlgorithmCRFKey", "algorithmCRF") }

@_spi(Swift50) @_silgen_name("$s8CreateML21parameterAlgorithmKeySSvau")
public func _parameterAlgorithmKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterAlgorithmKey", "algorithm") }

@_spi(Swift50) @_silgen_name("$s8CreateML27parameterAlgorithmMaxEntKeySSvau")
public func _parameterAlgorithmMaxEntKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterAlgorithmMaxEntKey", "algorithmMaxEnt") }

@_spi(Swift50) @_silgen_name("$s8CreateML29parameterAlgorithmRevisionKeySSvau")
public func _parameterAlgorithmRevisionKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterAlgorithmRevisionKey", "algorithmRevision") }

@_spi(Swift50) @_silgen_name("$s8CreateML24parameterAlgorithmRNNKeySSvau")
public func _parameterAlgorithmRNNKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterAlgorithmRNNKey", "algorithmRNN") }

@_spi(Swift50) @_silgen_name("$s8CreateML20parameterFeaturesKeySSvau")
public func _parameterFeaturesKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterFeaturesKey", "features") }

@_spi(Swift50) @_silgen_name("$s8CreateML21parameterFieldNameKeySSvau")
public func _parameterFieldNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterFieldNameKey", "field") }

@_spi(Swift50) @_silgen_name("$s8CreateML20parameterFilenameKeySSvau")
public func _parameterFilenameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterFilenameKey", "filename") }

@_spi(Swift50) @_silgen_name("$s8CreateML22parameterHeightNameKeySSvau")
public func _parameterHeightNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterHeightNameKey", "height") }

@_spi(Swift50) @_silgen_name("$s8CreateML27parameterImageColumnNameKeySSvau")
public func _parameterImageColumnNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterImageColumnNameKey", "image") }

@_spi(Swift50) @_silgen_name("$s8CreateML32parameterImageInputColumnNameKeySSvau")
public func _parameterImageInputColumnNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterImageInputColumnNameKey", "imageInput") }

@_spi(Swift50) @_silgen_name("$s8CreateML27parameterLabelColumnNameKeySSvau")
public func _parameterLabelColumnNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterLabelColumnNameKey", "label") }

@_spi(Swift50) @_silgen_name("$s8CreateML32parameterLabelInputColumnNameKeySSvau")
public func _parameterLabelInputColumnNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterLabelInputColumnNameKey", "labelInput") }

@_spi(Swift50) @_silgen_name("$s8CreateML20parameterLanguageKeySSvau")
public func _parameterLanguageKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterLanguageKey", "language") }

@_spi(Swift50) @_silgen_name("$s8CreateML28parameterLengthColumnNameKeySSvau")
public func _parameterLengthColumnNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterLengthColumnNameKey", "length") }

@_spi(Swift50) @_silgen_name("$s8CreateML30parameterLocationColumnNameKeySSvau")
public func _parameterLocationColumnNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterLocationColumnNameKey", "location") }

@_spi(Swift50) @_silgen_name("$s8CreateML24parameterMetaDataNameKeySSvau")
public func _parameterMetaDataNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterMetaDataNameKey", "metaData") }

@_spi(Swift50) @_silgen_name("$s8CreateML21parameterModelNameKeySSvau")
public func _parameterModelNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterModelNameKey", "model") }

@_spi(Swift50) @_silgen_name("$s8CreateML30parameterOptionalArguments0KeySSvau")
public func _parameterOptionalArguments0KeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterOptionalArguments0Key", "optionalArguments0") }

@_spi(Swift50) @_silgen_name("$s8CreateML30parameterOptionalArguments1KeySSvau")
public func _parameterOptionalArguments1KeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterOptionalArguments1Key", "optionalArguments1") }

@_spi(Swift50) @_silgen_name("$s8CreateML30parameterOptionalArguments2KeySSvau")
public func _parameterOptionalArguments2KeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterOptionalArguments2Key", "optionalArguments2") }

@_spi(Swift50) @_silgen_name("$s8CreateML29parameterOutputTypeClassValueSSvau")
public func _parameterOutputTypeClassValueAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterOutputTypeClassValue", "outputTypeClassValue") }

@_spi(Swift50) @_silgen_name("$s8CreateML22parameterOutputTypeKeySSvau")
public func _parameterOutputTypeKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterOutputTypeKey", "outputType") }

@_spi(Swift50) @_silgen_name("$s8CreateML18parameterResultKeySSvau")
public func _parameterResultKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterResultKey", "result") }

@_spi(Swift50) @_silgen_name("$s8CreateML24parameterSavePathNameKeySSvau")
public func _parameterSavePathNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterSavePathNameKey", "savePath") }

@_spi(Swift50) @_silgen_name("$s8CreateML17parameterTableKeySSvau")
public func _parameterTableKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterTableKey", "table") }

@_spi(Swift50) @_silgen_name("$s8CreateML18parameterTargetKeySSvau")
public func _parameterTargetKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterTargetKey", "target") }

@_spi(Swift50) @_silgen_name("$s8CreateML26parameterTextColumnNameKeySSvau")
public func _parameterTextColumnNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterTextColumnNameKey", "text") }

@_spi(Swift50) @_silgen_name("$s8CreateML16parameterTextKeySSvau")
public func _parameterTextKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterTextKey", "text") }

@_spi(Swift50) @_silgen_name("$s8CreateML27parameterTokenColumnNameKeySSvau")
public func _parameterTokenColumnNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterTokenColumnNameKey", "token") }

@_spi(Swift50) @_silgen_name("$s8CreateML19parameterURLNameKeySSvau")
public func _parameterURLNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterURLNameKey", "uRL") }

@_spi(Swift50) @_silgen_name("$s8CreateML20parameterURLsNameKeySSvau")
public func _parameterURLsNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterURLsNameKey", "uRLs") }

@_spi(Swift50) @_silgen_name("$s8CreateML21parameterWidthNameKeySSvau")
public func _parameterWidthNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("parameterWidthNameKey", "width") }

@_spi(Swift50) @_silgen_name("$s8CreateML10penaltyKeySSvau")
public func _penaltyKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("penaltyKey", "penalty") }

@_spi(Swift50) @_silgen_name("$s8CreateML10prCountKeySSvau")
public func _prCountKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("prCountKey", "prCount") }

@_spi(Swift50) @_silgen_name("$s8CreateML22predictLabelsForStringSSvau")
public func _predictLabelsForStringAddressor() -> UnsafeMutableRawPointer { keyAddress("predictLabelsForString", "predictLabelsForString") }

@_spi(Swift50) @_silgen_name("$s8CreateML17predictMethodNameSSvau")
public func _predictMethodNameAddressor() -> UnsafeMutableRawPointer { keyAddress("predictMethodName", "predict") }

@_spi(Swift50) @_silgen_name("$s8CreateML15predictWithTextSSvau")
public func _predictWithTextAddressor() -> UnsafeMutableRawPointer { keyAddress("predictWithText", "predictWithText") }

@_spi(Swift50) @_silgen_name("$s8CreateML14prLabelNameKeySSvau")
public func _prLabelNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("prLabelNameKey", "prLabel") }

@_spi(Swift50) @_silgen_name("$s8CreateML20prPrecisionColumnKeySSvau")
public func _prPrecisionColumnKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("prPrecisionColumnKey", "prPrecisionColumn") }

@_spi(Swift50) @_silgen_name("$s8CreateML14prPredictedKeySSvau")
public func _prPredictedKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("prPredictedKey", "prPredicted") }

@_spi(Swift50) @_silgen_name("$s8CreateML23prPrintFirstCellNameKeySSvau")
public func _prPrintFirstCellNameKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("prPrintFirstCellNameKey", "prPrintFirstCell") }

@_spi(Swift50) @_silgen_name("$s8CreateML25prPrintPrecisionColumnKeySSvau")
public func _prPrintPrecisionColumnKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("prPrintPrecisionColumnKey", "prPrintPrecisionColumn") }

@_spi(Swift50) @_silgen_name("$s8CreateML22prPrintRecallColumnKeySSvau")
public func _prPrintRecallColumnKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("prPrintRecallColumnKey", "prPrintRecallColumn") }

@_spi(Swift50) @_silgen_name("$s8CreateML17prRecallColumnKeySSvau")
public func _prRecallColumnKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("prRecallColumnKey", "prRecallColumn") }

@_spi(Swift50) @_silgen_name("$s8CreateML16prTruthColumnKeySSvau")
public func _prTruthColumnKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("prTruthColumnKey", "prTruthColumn") }

@_spi(Swift50) @_silgen_name("$s8CreateML13randomSeedKeySSvau")
public func _randomSeedKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("randomSeedKey", "randomSeed") }

@_spi(Swift50) @_silgen_name("$s8CreateML16reportByClassKeySSvau")
public func _reportByClassKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("reportByClassKey", "reportByClass") }

@_spi(Swift50) @_silgen_name("$s8CreateML9reportKeySSvau")
public func _reportKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("reportKey", "report") }

@_spi(Swift50) @_silgen_name("$s8CreateML15resNetModelNameSSvau")
public func _resNetModelNameAddressor() -> UnsafeMutableRawPointer { keyAddress("resNetModelName", "resNet") }

@_spi(Swift50) @_silgen_name("$s8CreateML6rfcKeySSvau")
public func _rfcKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("rfcKey", "rfc") }

@_spi(Swift50) @_silgen_name("$s8CreateML6rfrKeySSvau")
public func _rfrKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("rfrKey", "rfr") }

@_spi(Swift50) @_silgen_name("$s8CreateML7rmseKeySSvau")
public func _rmseKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("rmseKey", "rmse") }

@_spi(Swift50) @_silgen_name("$s8CreateML15rowSubsampleKeySSvau")
public func _rowSubsampleKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("rowSubsampleKey", "rowSubsample") }

@_spi(Swift50) @_silgen_name("$s8CreateML14saveMethodNameSSvau")
public func _saveMethodNameAddressor() -> UnsafeMutableRawPointer { keyAddress("saveMethodName", "save") }

@_spi(Swift50) @_silgen_name("$s8CreateML19scenePrintModelNameSSvau")
public func _scenePrintModelNameAddressor() -> UnsafeMutableRawPointer { keyAddress("scenePrintModelName", "scenePrint") }

@_spi(Swift50) @_silgen_name("$s8CreateML19squeezeNetModelNameSSvau")
public func _squeezeNetModelNameAddressor() -> UnsafeMutableRawPointer { keyAddress("squeezeNetModelName", "squeezeNet") }

@_spi(Swift50) @_silgen_name("$s8CreateML11stepSizeKeySSvau")
public func _stepSizeKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("stepSizeKey", "stepSize") }

@_spi(Swift50) @_silgen_name("$s8CreateML6svcKeySSvau")
public func _svcKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("svcKey", "svc") }

@_spi(Swift50) @_silgen_name("$s8CreateML5tcKeySSvau")
public func _tcKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("tcKey", "tc") }

@_spi(Swift50) @_silgen_name("$s8CreateML7tmpPathSSvau")
public func _tmpPathAddressor() -> UnsafeMutableRawPointer { keyAddress("tmpPath", NSTemporaryDirectory()) }

@_spi(Swift50) @_silgen_name("$s8CreateML19trainingAccuracyKeySSvau")
public func _trainingAccuracyKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("trainingAccuracyKey", "trainingAccuracy") }

@_spi(Swift50) @_silgen_name("$s8CreateML20trainingConfusionKeySSvau")
public func _trainingConfusionKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("trainingConfusionKey", "trainingConfusion") }

@_spi(Swift50) @_silgen_name("$s8CreateML19trainingMaxErrorKeySSvau")
public func _trainingMaxErrorKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("trainingMaxErrorKey", "trainingMaxError") }

@_spi(Swift50) @_silgen_name("$s8CreateML27trainingNumberOfExamplesKeySSvau")
public func _trainingNumberOfExamplesKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("trainingNumberOfExamplesKey", "trainingNumberOfExamples") }

@_spi(Swift50) @_silgen_name("$s8CreateML22trainingReportClassKeySSvau")
public func _trainingReportClassKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("trainingReportClassKey", "trainingReportClass") }

@_spi(Swift50) @_silgen_name("$s8CreateML15trainingRMSEKeySSvau")
public func _trainingRMSEKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("trainingRMSEKey", "trainingRMSE") }

@_spi(Swift50) @_silgen_name("$s8CreateML15trainMethodNameSSvau")
public func _trainMethodNameAddressor() -> UnsafeMutableRawPointer { keyAddress("trainMethodName", "train") }

@_spi(Swift50) @_silgen_name("$s8CreateML21validationAccuracyKeySSvau")
public func _validationAccuracyKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("validationAccuracyKey", "validationAccuracy") }

@_spi(Swift50) @_silgen_name("$s8CreateML22validationConfusionKeySSvau")
public func _validationConfusionKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("validationConfusionKey", "validationConfusion") }

@_spi(Swift50) @_silgen_name("$s8CreateML17validationDataKeySSvau")
public func _validationDataKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("validationDataKey", "validationData") }

@_spi(Swift50) @_silgen_name("$s8CreateML21validationMaxErrorKeySSvau")
public func _validationMaxErrorKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("validationMaxErrorKey", "validationMaxError") }

@_spi(Swift50) @_silgen_name("$s8CreateML29validationNumberOfExamplesKeySSvau")
public func _validationNumberOfExamplesKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("validationNumberOfExamplesKey", "validationNumberOfExamples") }

@_spi(Swift50) @_silgen_name("$s8CreateML24validationReportClassKeySSvau")
public func _validationReportClassKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("validationReportClassKey", "validationReportClass") }

@_spi(Swift50) @_silgen_name("$s8CreateML17validationRMSEKeySSvau")
public func _validationRMSEKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("validationRMSEKey", "validationRMSE") }

@_spi(Swift50) @_silgen_name("$s8CreateML5wtKeySSvau")
public func _wtKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("wtKey", "wt") }

@_spi(Swift50) @_silgen_name("$s8CreateML16wtLabelHeaderKeySSvau")
public func _wtLabelHeaderKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("wtLabelHeaderKey", "wtLabelHeader") }

@_spi(Swift50) @_silgen_name("$s8CreateML16wtTokenHeaderKeySSvau")
public func _wtTokenHeaderKeyAddressor() -> UnsafeMutableRawPointer { keyAddress("wtTokenHeaderKey", "wtTokenHeader") }
