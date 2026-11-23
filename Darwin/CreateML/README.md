# CreateML

Perry's CreateML for Mac apps, written for Perry from the API in the macOS
SDK's `CreateML.swiftinterface`: CreateML is a Swift-only framework, so this
is all of it, not an overlay on Objective-C. It replaces the Swift 5.0
`libswiftCreateML.dylib` Xcode ships as a file and provides what the SDK's
`CreateML.tbd` exports.

What works, in plain Swift:

- `MLDataValue` and its sequences, dictionaries and multi-arrays, the
  `MLDataValueConvertible` conversions of Swift's types, `MLIdentifier`;
- `MLUntypedColumn` and `MLDataColumn`: element-by-element arithmetic,
  comparisons and logic, masks, `map`, missing values, sorting, slices,
  conversions between types and statistics;
- `MLDataTable`: columns by name, rows, masks, `join`, `group` with every
  aggregator, `pack`/`unpack`, `expand`/`condense`, random, stratified and
  sequence splits, and reading and writing CSV (with all of
  `ParsingOptions`) and JSON;
- the metrics types, including evaluating predictions already in a table
  (`MLClassifierMetrics.__evaluation`, `MLRegressorMetrics.__evaluation`,
  and `MLObjectDetectorMetrics.__evaluation` with average precision at IoU
  0.5 and over 0.5 to 0.95);
- `MLProgress`, `MLCheckpoint`, `MLPhase`, `MLJob`, `MLTrainingSession`,
  `MLTrainingSessionParameters`, `MLModelMetadata`, `MLSplitStrategy`;
- every trainer's `ModelParameters`, options, algorithm and validation
  types, and their data sources' gathering of examples from labeled
  directories, labeled file names, annotation files and tables
  (`labeledImages()`, `labeledSounds()`, `labeledTexts()`, `labeledMedia()`,
  `gatherAnnotatedFileNames()`, `imagesWithObjectAnnotations()`,
  `labeledSensorData(…)`, their `stratifiedSplit`s…).

What throws: training, predicting with and exporting models, which Apple's
CreateML does in its private engine (`TuriCore` in the Swift 5.0 overlay).
Every trainer's initializers, `train`, `makeTrainingSession`,
`restoreTrainingSession` and `resume` throw `MLCreateError.generic` saying
training isn't available, and `MLClassifier` and `MLRegressor` too; so no
trainer instance can exist, and their instance members (which would
predict, evaluate or write) are never reached. Extracting features (body
and hand poses from videos and images, processing style-transfer images)
throws the same way. `MLGazetteer` and `MLWordEmbedding` compile their
dictionaries with Natural Language, but Core ML can't load the data Natural
Language writes as a model, where Apple's CreateML wraps it in one of its
own, so their initializers throw too (on a Mac as well); their prediction,
distance and writing code is Swift and would work given a model.

Build:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh CreateML <runtime directory>

There are no Objective-C headers to compile the module over, so
`include/module.modulemap` is an empty module of the name, and
`swiftc-flags` has the linker drop the SDK's `CreateML.framework`, which the
build script links but nothing uses. The library links Foundation, Combine,
CoreGraphics, CoreML, NaturalLanguage and TabularData; TabularData is a
Swift-only framework too, so Perry needs it for this to load.

The trainers' files in `Sources/Trainers` were generated from the
interface's declarations (signatures, cases, stored properties, defaults)
and then finished by hand; the rest is written by hand.

`Scripts/check-overlay.sh` against the Swift 5.0 overlay and the SDK's
`libswiftCreateML.tbd` reports 316 missing:

- 150 global strings of the Swift 5.0 overlay's bridge to its engine
  (`csvQuote`, `accuracyKey`, `tmpPath`…): their storage symbols (`…SSvp`).
  Today's compiler exports a library-evolution module's globals only
  through accessors, and `@_silgen_name` can't define a global, so their
  storage can't be exported; their addressors (`…SSvau`), which another
  module's code reaches a global through, are defined in
  `Sources/Core/Keys.swift`.
- the witness tables (`WP`) of `Array`'s and `Dictionary`'s conditional
  `MLDataValueConvertible` conformances: today's compiler emits a pattern
  (`Wp`) the runtime instantiates from the conformance descriptor, which is
  there.
- 164 symbols of Apple-private SPI with no public declaration:
  `MLFewShotSoundClassifier` (87), `DataSourceIssue` (74), and the
  `diagnose()` of three data sources, which returns `DataSourceIssue`s.

The rest of the Swift 5.0 overlay's internals that it exported (its
column, table, value and model classes, `_UntypedColumn`, `_Model`, the
helpers over its engine's error out-pointers, the default arguments of
`_Model`'s methods) are here: the column, table and value classes are
Perry's own storage, `_Model` and the engine's model calls throw like
training does, and the default arguments are `@_silgen_name` functions,
since today's compiler emits default arguments into callers.

Differences from Apple's:

- `MLDataTable.write(to:)` writes a directory with `table.json`, which
  `init(contentsOf:)` reads back; it doesn't read or write Apple's binary
  table directories;
- `stratifiedSplit` returns the table with a column `split` holding each
  row's part;
- `group`'s columns are named "Sum of x", "Count" and so on;
- `show()` and `show(_:)` give text, with no image;
- `MLSplitStrategy.automatic` trains on all examples below 50 and on 95%
  from 50 on.
