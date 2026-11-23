# simd

Perry's Swift overlay of simd: the vector functions (`abs`, `min`, `clamp`,
`mix`, `dot`, `length`, `normalize`, `reflect`, `cross`...), the element-wise
math functions of simd's vector types (`sin`, `exp`, `pow`, `fma`,
`isnan`...), the matrix types' initializers, subscripts, operators,
`inverse`, `determinant` and `transpose`, the deprecated `matrix_*`
functions, and quaternions, written for Perry from the API in the macOS
SDK's `simd.swiftinterface`. It replaces the Swift 5.0 overlay Xcode ships
as a file, which a runtime directory made for an x86_64 Mac app used to
take.

It is compiled as the module `simd` over the SDK's C headers, as Apple
builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh simd <runtime directory>

Most of the overlay is one declaration per vector or matrix type, so
`Sources/*.generated.swift` are written by `generate.py`: it takes every
declaration of the SDK's interface (signature and attributes) and gives it
Perry's own body over simd's C functions (`simd_mul`, `simd_inverse`,
`simd_quaternion`, `__tg_cos`...), which the headers define inline or
libSystem exports (`_simd_cos_f4`, `__invert_f4` and the like, which Perry's
libSystem must provide anyway, as programs inline the same calls). Rerun it
after an SDK update:

    Darwin/simd/generate.py

`QuaternionLog.swift` is the quaternion logarithm, which the C headers
leave out, and `Float16.swift` the Float16 vector functions.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftsimd.tbd`. What it still lacks, for x86_64:

- the 60 functions of Float16 vectors (`abs`, `min`, `max`, `ceil`,
  `floor`, `trunc`, `rint`, `sqrt` of `SIMD2...SIMD32<Float16>`), which the
  SDK exports only for arm64 (Swift has no Float16 on x86_64 macOS). They
  are built for arm64, where nothing is missing.
