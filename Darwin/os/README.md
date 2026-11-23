# os

Perry's Swift overlay of the `os` module: `os_log` and `os_signpost` with
printf formats, `OSLog`'s handles and categories, `OSLogMessage` and its
interpolations (privacy, number, string, pointer and extended formats),
`Logger`, `OSSignposter` with its interval state, signpost IDs and
animation intervals, workgroups, and `OSAllocatedUnfairLock`; written for
Perry from the API in the macOS SDK's `os.swiftinterface`. It replaces the
Swift 5.0 overlay Xcode ships as a file (which has `os_log` and
`os_signpost` only) and the additions that were needed beside it
(`Darwin/osAdditions`, folded in here).

It is compiled as the module `os` over the SDK's headers:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh os <runtime directory>

How it works:

- Programs compile most of `OSLogMessage` into themselves. The members
  here are what they call when it isn't inlined, and they lay out the
  argument buffer as the compiled code does (a summary byte, the argument
  count, then each argument's descriptor, size and bytes), so the two can
  be mixed. `Logger`'s methods, `os_log(_:log:_:)` with a message and
  `OSSignposter`'s methods, which the compiler normally folds into the
  caller, write the buffer at run time and call `_os_log_impl` and
  `_os_signpost_emit_with_name_impl`.
- `os_log` and `os_signpost` with a printf format read the format for each
  argument's kind, size and `{public}`/`{private}`/`{sensitive}` privacy
  and write the C variadic arguments into the same buffer, as the C
  macros do.
- An animation format string is copied once, kept for good, as the
  caller may hold its address.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftos.tbd`. What it still lacks:

- the initializing entry points (`fc`) of the convenience initializers on
  `OSLog` (`init(subsystem:category:)`, both), `WorkGroup`
  (`init(port:name:)`) and `WorkGroupParallel` (`init(name:)`), which
  only a subclass's initializer calls (these classes can't be subclassed
  in Swift); the allocating ones programs call are there;
- the metrics API the library exports without a public declaration
  (`OSMetricBridge`, `OSMetricCounter`, `OSMetricGauge`,
  `OSMetricHistogram`, `OSMetricGroup`, `OSMetricDimensions`,
  `OSMetricType`, `OSMetricUnit`, `OSMetricScale`, `OSMetricFlags`,
  `OSMetricBinType`, `OSMetricStatisticalLevel`); `OSMetricOperation`,
  which public inlined code names, is here.

The workgroup methods call the `os_workgroup_*` functions, which Perry's
runtime doesn't have: there they land in the loader's unresolved stubs.
