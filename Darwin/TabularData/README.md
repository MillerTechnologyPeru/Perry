# TabularData

Perry's TabularData.framework, written for Perry from the API in the macOS
SDK's `TabularData.swiftinterface`: `DataFrame` and its `Slice`, `Rows` and
`Row`; `Column`, `ColumnSlice`, `DiscontiguousColumnSlice`, `FilledColumn`,
`AnyColumn`, `AnyColumnSlice` and `ColumnID`; reading and writing CSV and
JSON; filtering, sorting, joins, grouping with its aggregations, summaries
and splits; column arithmetic and statistics; encoding and decoding
columns; and the tables descriptions draw. TabularData is a Swift-only
framework, so this is all of it; Perry's CreateML imports it.

It is built as a framework with Swift code, which the loader finds in the
Swift runtime directory (`PERRY_SWIFT_RUNTIME`):

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-framework.sh TabularData <runtime directory>

(without the variables, for iOS arm64). Its interfaces go to
`.build/perry-frameworks` for Perry's other frameworks to build against.

## Matching Apple's ABI

No type in the interface is `@frozen`, so layouts are Perry's own, except
what the interface exposes to inlinable code: `Column`'s storage is
`PackedOptionalsStorage` holding a `PackedOptionalsBuffer` laid out as the
interface's inlinable code expects (a header of capacity, count and nil
count, then a bitmap of present elements, then the elements, each part
rounded to `Alignment.bufferAlignment`), `ColumnSlice` stores `slice` and
`FilledColumn` stores `base` and `defaultValue`. Every `@usableFromInline`
declaration exists; the `@inlinable` ones have Perry's own bodies. Enum
cases are in the interface's order.

What the library prints follows Apple's: the box-drawn tables (column
types, row indices, `N more` columns past the line width, `...` past the
row count), number and date formatting, error messages (with Apple's
spelling), summary column names, join column names (`left.`/`right.`),
aggregation names (`sum(x)`, `mean(x)`…) and arithmetic result names
(`a+b`, `a*2`).

`Scripts/check-overlay.sh` against the SDK's `TabularData.tbd` (for x86_64
macOS and arm64 iOS alike) reports 8 missing: the witness tables (`WP`) of
the generic column types' conformances to TabularData's own protocols
(`Column`, `ColumnSlice` and `DiscontiguousColumnSlice` to `ColumnProtocol`
and `OptionalColumnProtocol`, `FilledColumn` to `ColumnProtocol`,
`RowGrouping` to `RowGroupingProtocol`). Today's compiler emits these as
patterns (`Wp`) instantiated at run time, because the protocols inherit
from the standard library's; programs never reference them, they ask for
the witness table through the conformance descriptor, which is there. (The
system's CreateML imports 129 TabularData symbols; all are exported.)

## Behavior

Compared with Apple's TabularData on a Mac (one x86_64 program run against
each): CSV reading and type inference (integers, then booleans, then
floating point, then ISO 8601 dates, else strings; every reading option),
CSV writing, JSON reading (columns sorted by name, booleans read as
integers unless booleans are asked for, arrays and objects kept as
`JSONSerialization` makes them) and writing, filtering, sorting (stable,
missing values last), grouping and its aggregations, summaries, joins,
slices, rows, type-erased columns and the descriptions print the same.

Where it differs:

- `init(contentsOfSFrameDirectory:)` reads the archive's metadata
  (`dir_archive.ini`, the frame index and its column names) and throws the
  same errors for a missing or bad archive or column, but doesn't decode
  the column segments (Turi's block-compressed encodings): for a valid
  archive it throws `SFrameReadingError.unsupportedLayout`.
- Seeded random and stratified splits are reproducible but use Perry's own
  generator (SplitMix64), so they pick different rows than Apple's.
- JSON writing writes `Data` values as base64 strings (Apple's raises an
  Objective-C exception).
- `Column.withContiguousStorageIfAvailable` of optional elements returns
  nil (elements are packed, not stored as optionals); the non-optional
  variant gives the elements when none is missing.
- `JSONReadingError.wrongType` names the type asked for; Apple's names
  `boolean` when an integer was asked for.
- Some misuse Apple's traps on is accepted: appending a frame with other
  columns (matched by name, missing ones nil) and a range of a slice whose
  bounds aren't rows of it (intersected).
