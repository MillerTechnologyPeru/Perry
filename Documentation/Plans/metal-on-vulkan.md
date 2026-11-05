# Plan: Metal on Vulkan

## Goal

Run prebuilt arm64 iOS apps that use Metal under Perry on arm64 Linux, with no CPU emulation, through a Metal provider (`libPerryMetal.so`, for `Metal.framework`) on Vulkan. The first targets are the Snapdragon handhelds running ROCKNIX (Retroid Pocket Flip 2, Retroid Pocket 5).

Not yet: 32-bit iOS apps (they predate Metal), MetalKit beyond a minimal `MTKView`, Metal Performance Shaders, ray tracing.

## Phase 0: what the spike found

### Licenses (read from the LICENSE files)

| Component | License | For Perry (MIT) |
|---|---|---|
| darlinghq/indium (commit 68c2c18) | 0BSD | Permissive. |
| steelbrain/metal2vulkan (commit 219f013) | `GPL-2.0-or-later OR LGPL-3.0-or-later` | Take the LGPL-3.0-or-later option. Keep it a separate shared library that Perry opens at run time, with its notices shipped and the library replaceable. Never link it statically into Perry or copy its sources in. |

Metal is Apple's trademark. The provider is `libPerryMetal.so` only because the loader maps `Metal.framework` to `libPerry<Name>.so`.

### Vulkan on the devices

| Device | Driver | Vulkan | Timeline semaphores |
|---|---|---|---|
| Retroid Pocket Flip 2 (SM8250) | Turnip, Mesa 26.2.4, Adreno 650 | 1.3 | yes (core in 1.2) |
| Retroid Pocket 5 (SM8250) | Turnip, Mesa 26.2.4, Adreno 650 | 1.3 | yes |
| Lenovo Duet 3 (Snapdragon 7c Gen 2), Debian sid, Cadmium kernel | Turnip, Mesa 26.2.6, Adreno 618 | 1.3 | yes |
| Docker (`perry-dev`) | lavapipe (llvmpipe), Mesa 25.0.7 | 1.4 | yes |

Both devices meet Indium's Vulkan 1.3 and metal2vulkan's 1.2.

### Indium

- Builds on arm64 Linux with clang 19 once `<cstdint>`, `<stdexcept>` and `<string>` are force-included (newer libstdc++ no longer pulls them in).
- Indium includes its own AIR-to-SPIR-V translator, Iridium. Iridium was written for LLVM's typed pointers. It reads `LLVMGetElementType` of a function's pointer type, which is null under the opaque pointers every LLVM from 17 on uses, so its basic compute test crashes in `Iridium::AIR::Function::analyze`. Debian trixie ships LLVM 17, 18, 19 and 22. Using it would need either a typed-pointer LLVM (15 with opaque pointers turned off, built in the image) or a port of Iridium to opaque pointers, which means inferring every pointee type from AIR metadata and uses.
- Swapping Iridium for metal2vulkan's translator would mean rewriting Indium's library and pipeline code around metal2vulkan's binding plans: the binding-map mismatch the plan warned about.

### metal2vulkan-runtime

- Builds with Rust 1.98.1 (pinned by its `rust-toolchain.toml`) in about 2 minutes, and its `compute_dispatch` example runs correctly on lavapipe: a translated kernel on a Vulkan device, the Phase 0 exit test.
- It is one stack, so its runtime and translator agree on bindings. It needs only Vulkan 1.2 and opens the Vulkan loader at run time.
- It has no C API. Perry reaches it through a small Rust `cdylib` that exports C functions over the runtime. That library links the runtime in, so it is LGPL too and lives outside Perry's MIT sources: the `capi/` crate on the `perry-capi` branch of MillerTechnologyPeru/metal2vulkan, built as `libmetal2vulkan.so` (its own Cargo workspace, so upstream's manifest is unchanged). `libPerryMetal.so` opens it with `dlopen`: from `PERRY_METAL2VULKAN`, else beside itself, else from the library path. Perry declares the ABI itself (`Sources/CPerryMetal`), and checks its version, `m2v_abi_version`.

### Decision

By the plan's rule (switch to metal2vulkan-runtime when integrating Indium with a translator is harder than adopting one beta crate), use **metal2vulkan-runtime** for the whole stack, pinned to a git revision. Indium stays a reference.

## Phase 1: the provider (done)

- `PerryMetal` defines `_MTLDevice` (Metal's own base class for devices), adopting the `MTLDevice` protocol, one per metal2vulkan device for the life of the process; and exports `MTLCreateSystemDefaultDevice` and `MTLCopyAllDevices`. Selectors it lacks end the app with the runtime's unrecognized-selector error, naming the selector.
- `supportsFamily:` is metal2vulkan's answer, which is true only where every row of Apple's table for a family is exact (none, on Adreno), and Apple1 and Common1 always, which every iOS device has.
- Fixture: `Tests/Fixtures/Darwin/Foundry`, which prints only what every GPU answers the same way, so the macOS reference matches.

## Phase 2: compute (done)

- Classes, each a peer holding metal2vulkan's handle: `_MTLBuffer`, `_MTLLibrary`, `_MTLFunction`, `_MTLComputePipelineState`, `_MTLCommandQueue`, `_MTLCommandBuffer`, `_MTLComputeCommandEncoder`, with the Metal protocols they adopt.
- Libraries from `newDefaultLibrary` (the bundle's `default.metallib`), `newDefaultLibraryWithBundle:error:`, `newLibraryWithData:error:` (dispatch data), `newLibraryWithFile:error:` and `newLibraryWithURL:error:`; failures fill `NSError`s in `MTLLibraryErrorDomain`.
- A command buffer keeps the pipelines and buffers its encoders bind until it completes. Scheduled and completed handlers run on metal2vulkan's thread inside an autorelease pool.
- Fixture: `Tests/Fixtures/Darwin/Forge`, with kernels in `Shaders.metal` that `Scripts/build-darwin-fixtures.sh` builds into `default.metallib`: vector add, a `constant` scalar from `setBytes`, a threadgroup-memory reduction, both dispatch forms, a completed handler.
- Both fixtures print exactly what they print on macOS, on the Flip 2, the Pocket 5 and the Duet 3.

## Phases 3 to 5

As in the original plan: offscreen rendering (render pipelines, passes, textures, samplers, depth), then presentation through `CAMetalLayer` on the compositor's surface, then compatibility work. The shim grows a function per Metal call Perry needs, behind a new ABI version when one changes.

Still to do for Phase 2's tests: build `libmetal2vulkan.so` in the Docker image from a pinned commit of the fork, so the Linux test suite runs Forge on lavapipe too.
