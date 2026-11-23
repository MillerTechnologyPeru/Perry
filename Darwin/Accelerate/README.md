# Accelerate

Perry's Swift overlay of Accelerate: vDSP (arithmetic, conversions,
convolution, DFT/FFT/DCT, biquads, windows, integration...), vForce,
`Quadrature`, `BLAS`, vImage (`vImage.PixelBuffer` and its operations,
pixel formats, converters, Core Video formats, `vImage_Buffer` and
`vImage_CGImageFormat` additions), BNNS (layers, optimizers, the direct
functions, `BNNSNDArrayDescriptor` and `BNNSTensor` helpers, the 5.0
overlay's constants and initializers) and BNNSGraph (contexts, compile
options and the graph builder), with the buffer protocols they take
(`AccelerateBuffer`, `AccelerateMatrixBuffer`...), written for Perry from
the API in the macOS SDK's `Accelerate.swiftinterface`. It replaces the
Swift 5.0 overlay Xcode ships as a file, which a runtime directory made for
an x86_64 Mac app used to take.

It is compiled as the module `Accelerate` over the SDK's C headers, as
Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh Accelerate <runtime directory>

`Sources/Core.swift` holds the namespaces and buffer protocols; `vDSP/`,
`vImage/` and `BNNS/` the rest, over the C functions of vecLib, vImage
and BNNS. Declarations keep the interface's signatures, `@_silgen_name`s,
`@frozen` layouts and case orders; most `@inlinable` attributes are dropped
(the bodies are Perry's own and use internal helpers; the symbols are the
same), so a few always-emit-into-client members are exported as extras.

Where Perry's behaviour is its own choice or differs from Apple's:

- vDSP: the allocating `convolve`/`correlate` return
  `vector.count - kernel.count` elements; inout forms take `result.count`
  as the length and need inputs at least that long. `twoPoleTwoZeroFilter`
  is `vDSP_deq22`, its first two outputs the initial ones. A multichannel
  `Biquad` takes its channels one after another, `count / channelCount`
  each, and copies of a `Biquad` share their state. `FFT2D` is set up for
  the larger of its two sides. `gather` indices are 1-based, as
  `vDSP_vgathr` takes them. `vDSP.SortOrder` is 1 and -1. Error
  descriptions are Perry's wording.
- vImage: `vImage.Error` raw values are the C `kvImage...` codes;
  `BufferType` raw values are case ordinals. `colorThreshold`,
  `linearInterpolate` and interleaving are Swift loops. A nil background
  color in rotations, shears and warps means edge extension; `scale` is
  high-quality resampling; float histograms, equalization and contrast
  stretching work over 0...1; a nil convolution divisor is the kernel's
  sum; the gaussian kernels are binomials. `multiply(by: simd_float4x4)`,
  the luma/chroma initializers (4:2:0 bi-planar, ARGB, alpha 255) and
  `makePixelBufferAndCGImageFormat`'s format choice are Perry's reading of
  the documentation. Non-throwing operations ignore vImage's error code;
  buffers with padded rows go through a packed copy in
  `withUnsafeBufferPointer`. The color spaces of `vImage_CGImageFormat`s
  made by the overlay are retained and never released (the C struct has no
  deinit).
- BNNS: the layers own their `BNNSFilter`. `BNNS.Shape(_:)` picks
  vector, row-major matrix, CHW image, then first-major tensor layouts by
  rank. Optimizer accumulator counts follow `bnns.h`. Fused layers'
  intermediate descriptors are the output's.
- BNNSGraph: compiled graphs (`BNNSGraph.Context` from a file) run on
  libBNNS. `BNNSGraph.Builder`, whose C side is private to Apple (121
  undeclared `_bnns_graph_builder_*` functions), is Perry's own
  interpreter: nodes are evaluated once on zeros when added, for their
  shapes, and contexts made from a builder run the graph in Swift with
  Double math; shapes are static (`setDynamicShapes` only takes the
  builder's own, `setBatchSize` does nothing) and the one function is
  `main`, arguments outputs first. The semantics of a few operations are
  Perry's reading (floored `%`, the axes of `channelNorm`/`instanceNorm`/
  `l2Norm`/`rmsNorm`, RNN gate orders i-f-o-g and z-r-n).
  `CompileOptions.predefinedOptimizations`, exported by the OS but not in
  the interface, is there too.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftAccelerate.tbd`. What it still lacks, for x86_64
(none of these but the first group is exported by the OS's own overlay
either, as `dyld_info -exports /usr/lib/swift/libswiftAccelerate.dylib`
shows; the tbd lists more than the library has):

- 13 Float16 symbols (`vDSP.float16ToFloat`, `floatToFloat16` and their
  `convertElements`, `withUnsafePixelBuffer` of Planar16F, `Float16`'s
  `BNNSScalar` and graph-builder conformances, `Builder.constant(values:
  [[Float16]])`), which the SDK exports only for arm64 (Swift has no
  Float16 on x86_64 macOS); they are built for arm64, where nothing the OS
  overlay exports is missing;
- the initializing entry points (`fc`) of the 23 BNNS layers' convenience
  initializers, which Swift doesn't emit for convenience initializers (the
  allocating ones are there);
- the requirements base descriptors of the protocols without requirements
  (`FusableLayerParameters`, `vDSP_IntegerConvertable`,
  `vDSP_FloatingPointConvertable`, `BNNSGraph.Builder.SliceIndex`), which
  Swift emits only for protocols that have some;
- 22 static witness tables (`WP`) of the generic types' conformances
  (`Array`, `ContiguousArray`, `ArraySlice`, the buffer pointers and
  `Slice` to the buffer protocols and `OperationParameter`,
  `vImage.PixelBuffer` to the buffer and matrix buffer protocols,
  `BNNSGraph.Builder.Tensor` to `OperationParameter`): Swift instantiates
  those at run time from their conformance descriptors, which are there;
- the property descriptors of `vImage_ARGBToYpCbCrMatrix.itu_R_601_4` and
  `itu_R_709_2`, static properties of an imported C type, for which Swift
  emits none (the getters are there).
