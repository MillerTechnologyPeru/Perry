# box86

i386 Perry runs on ARM Linux under [box86](https://github.com/ptitSeb/box86),
which runs the i386 code and hands calls into libraries it knows (libc, GL,
X11, SDL…) to the machine's own armhf ones. It runs on 64-bit ARM too, as a
32-bit armhf process.

## The runtime folder

`install-runtime.sh <ssh destination> <folder>` copies, from a checkout with
i386 Perry built:

| Path | What |
| --- | --- |
| `bin/` | `perry32` and its providers, from `.build/i386/bin`, without `libPerryCFNetwork.so` |
| `sysroot/usr/lib/swift/linux`, `sysroot/usr/lib/i386-linux-gnu` | the i386 Debian and Swift libraries Perry is built against, from `.toolchains/i386-sdk/sysroot` |
| `gst-plugins/` | links to the seven GStreamer plugins Perry's audio uses |
| `libc23box.so` | built here from `libc23box.c` |
| `libperrybox.so` | only if `PERRY_BOX_SHIM` names one; see below |

Launchers take this folder as `PERRY_ROOT`. The armhf libraries box86 hands
calls to (GL, X11, SDL2, PulseAudio, libstdc++…) come from the machine: a
Debian with the `armhf` architecture added, or ROCKNIX's `/usr/lib32`.

`libPerryCFNetwork.so` is left out because its i386 libcurl needs Kerberos
and libunistring functions box86 doesn't have; apps that need the network
don't work this way yet.

## box86 itself

Tested with box86 built from commit `bb716a2` (0.3.9 plus fixes), built on
the Duet 3 as its README says for an armhf build on 64-bit ARM:

```sh
cmake .. -DSD865=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER=arm-linux-gnueabihf-gcc -DCMAKE_ASM_COMPILER=arm-linux-gnueabihf-gcc
make -j6
```

`box86-mmap-base.patch` is applied first (`git apply`). It adds a setting,
`BOX86_MMAP_BASE=0x…`: the address box86 places mappings from when none is
asked for, its own bridges into wrapped libraries among them, in place of
0x40000000. A Mac program may map a block at a fixed address, where on the
Mac nothing is, and that maps over whatever box86 put there: Halo keeps its
game state at 0x40000000, and its launcher sets `BOX86_MMAP_BASE=0x48000000`.

ROCKNIX's own box86 (0.3.9, built on 1 November 2026) crashes in libc as
Perry starts, so on ROCKNIX launchers run a copy of that build from the
runtime folder (`$PERRY_ROOT/box86`) rather than `/usr/bin/box86`.

## Shims

Perry's i386 build is linked against glibc 2.41, and box86's libc bridge
lacks some of its functions; a library that asks for one doesn't load. Two
libraries preloaded with `BOX86_LD_PRELOAD` give them.

### libc23box

`libc23box.c`, built by `install-runtime.sh`:

- glibc 2.38's `__isoc23_strtoul`, `__isoc23_vfscanf`, `__isoc23_vscanf`,
  `__isoc23_vsscanf` and `__isoc23_vswscanf`, as the C99 functions box86
  wraps.
- `capget` and `capset`, as system calls, for machines with no armhf libcap
  (ROCKNIX), where box86 loads the i386 one.
- `tsearch`, `tfind`, `tdelete` and `twalk`, and `openpty`, which glibc 2.34
  moved into libc.
- `xcb_poll_for_reply` and `_XReadEvents`, doing nothing, for the i386 cairo
  where a launcher has box86 run it (`BOX86_EMULATED_LIBS`): they belong to
  its Xlib and XCB surfaces, which Perry doesn't make.

`libc23box.map` gives each the glibc version libraries ask for it with;
unversioned, box86 doesn't match them.

### libperrybox

A larger shim, whose source isn't in the repository yet: it was generated
from box86's list of wrapped functions and the imports of Perry's i386
libraries, and has to be made again that way. It defines, by version:

- **GLIBC_2.0–2.1:** long double math (`sinl`, `cosl`, `expl`, `sqrtl`,
  `fmal`, `nanl`…) computed as double, as box86's x87 does; `fdim`, `nan`,
  `ecvt`, `gcvt`, `llabs`, `vdprintf`, `vscanf`, `gethostid`, `personality`.
- **GLIBC_2.3–2.33:** `strncasecmp_l`, `signalfd`, `register_printf_specifier`,
  `scandirat64`, `fts64_*`, `strfromf128`, `strtof128`, `thrd_current`,
  `posix_spawn_file_actions_addchdir_np`, `gettid`, `mallinfo2`.
- **GLIBC_2.34–2.36:** C11 threads (`cnd_*`, `mtx_*`, `tss_*`); the 64-bit
  time functions (`__gmtime64_r`, `__localtime64_r`, `__nanosleep64`,
  `__pthread_cond_timedwait64`, `__sem_timedwait64`, `__sigtimedwait64`,
  `__utimensat64`); `res_query`, `res_search`, `res_nquery`; `epoll_pwait2`;
  and the mount and pidfd calls (`fsopen`, `fsmount`, `pidfd_open`…), which
  fail with `ENOSYS`.
- **GLIBC_2.38:** `strlcpy`, `strlcat`, `wcslcpy`, `wcslcat`,
  `__isoc23_wcstol` and the `__isoc23` scanf functions above.
- **Other libraries' functions** missing from box86's wrappers: cairo's PNG
  and SVG surfaces, libcap's `cap_get_proc`, `cap_get_flag` and `cap_free`,
  fontconfig's `FcConfigCreate`, `FcNameParse` and `FcPatternRemove`,
  `XRRGetCrtcTransform`, `png_image_write_to_memory`, ALSA's channel maps
  and `snd_pcm_sw_params_set_period_event`, and PulseAudio's
  `pa_operation_set_state_callback` and `pa_threaded_mainloop_set_name`.

It is built with `-nostdlib`, against nothing:

```sh
clang -target i686-unknown-linux-gnu -shared -fPIC -O2 -fno-builtin -w -nostdlib \
    -Wl,-soname,libperrybox.so -Wl,--version-script,shim.map -o libperrybox.so shim.c
```

## Sound

Perry's audio plays through GStreamer. Under box86 the i386 GStreamer and
GLib are used, not the machine's: launchers list them in
`BOX86_EMULATED_LIBS`, as box86's wrapper for a native GLib lacks
`g_weak_ref_clear`, and point `GST_PLUGIN_SYSTEM_PATH` at `gst-plugins/`.
