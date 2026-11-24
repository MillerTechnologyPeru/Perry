# Debian packages for Perry

What a Debian system needs to build Perry with every provider and run apps on it. Names are Debian 13 (trixie), the release the Dockerfile builds on; forky/sid uses the same names. The Swift toolchain (6.4.2 for Debian, from swift.org) is separate.

## Building

Tools:

```sh
sudo apt-get install --no-install-recommends \
    clang-19 lld-19 pkgconf cmake ninja-build python3 xz-utils curl ca-certificates
```

`clang-19` and `lld-19` link the Mach-O test fixtures (Swift's own lld cannot), and build the libraries below that Debian doesn't package. `cmake`, `ninja-build` and `python3` build libc++ and cmark.

Libraries that providers link against, with their headers:

| Package | Used by |
| --- | --- |
| `libxml2-dev` | Foundation (XML), PerryXML2 |
| `zlib1g-dev` | PerryZ, Bom, compression, ImageIO |
| `libbz2-dev` | PerryBZ2 |
| `libexpat1-dev` | PerryExpat |
| `liblzma-dev`, `liblz4-dev`, `libbrotli-dev` | Compression |
| `libssl-dev` | Security |
| `libpng-dev`, `libjpeg62-turbo-dev`, `libgif-dev`, `libwebp-dev`, `libheif-dev` | ImageIO codecs |
| `libcairo2-dev`, `libfreetype-dev`, `libfontconfig-dev` | Core Graphics and Core Text (Silica, Cairo, FontConfig packages) |
| `libopenblas-dev` | Accelerate (BLAS and LAPACK) |
| `libjavascriptcoregtk-4.1-dev` | JavaScriptCore |
| `libsdl3-dev` | UIKit and AppKit windows and input (SDL package) |

The same in one line:

```sh
sudo apt-get install --no-install-recommends \
    libxml2-dev zlib1g-dev libbz2-dev libexpat1-dev liblzma-dev liblz4-dev libbrotli-dev libssl-dev \
    libpng-dev libjpeg62-turbo-dev libgif-dev libwebp-dev libheif-dev \
    libcairo2-dev libfreetype-dev libfontconfig-dev libopenblas-dev \
    libjavascriptcoregtk-4.1-dev libsdl3-dev
```

`libm`, `libdl`, `libresolv` and `libgcc_s` come with libc and gcc; `libdispatch` comes with the Swift toolchain.

### Not packaged by Debian

The Dockerfile builds these from pinned, checksummed sources:

| Library | Source | Used by |
| --- | --- | --- |
| `libperry-sqlite3.so` | SQLite 3.54.0, with Apple's compile options | PerrySQLite3 |
| `liblzfse.a` and `lzfse.h` | lzfse 1.0 | Compression |
| `libperry-cmark-gfm.a`, `libperry-cmark-gfm-extensions.a` | swift-cmark | Foundation's Markdown |
| `libperry-c++.so.1`, `libperry-c++abi.so.1` | LLVM 19.1.7 libc++, built with Apple's ABI | CXX provider, at run time |
| `libmetal2vulkan.so` | metal2vulkan (Rust) | Metal provider, at run time |

## Running apps

Providers open these with `dlopen` when an app first uses them. A missing one only affects the frameworks that need it.

| Packages | For |
| --- | --- |
| `libsdl3-0`, `libegl1`, `libgles1`, `libgles2`, `libgl1`, `libglx-mesa0`, `libegl-mesa0`, `libgl1-mesa-dri`, `libgbm1` | UIKit's live view, EAGLContext and OpenGL ES |
| `libvulkan1`, `mesa-vulkan-drivers` | Metal, through metal2vulkan |
| `libwpewebkit-2.0-1`, `libwpebackend-fdo-1.0-1`, `libwayland-server0` (they bring `libwpe-1.0-1`) | WKWebView and UIWebView |
| `libgstreamer1.0-0`, `libgstreamer-plugins-base1.0-0`, `gstreamer1.0-plugins-base`, `gstreamer1.0-plugins-good`, `gstreamer1.0-libav` | AVPlayer video and audio |
| `libopenal1` | OpenAL |
| `libssl3t64`, `openssl-provider-legacy` | Security, CommonCrypto's older ciphers |
| `libcurl4t64` | PerryCurl |
| `libxar1` | Xar archives |
| `avahi-daemon`, `libavahi-compat-libdnssd1` | NSNetService and Bonjour |
| `libtiff6` | ImageIO TIFF |
| `libpoppler-glib8t64` | ImageIO and Core Graphics PDF |
| `libx11-6` | X11 display and keyboard queries (AppKit, IOKit, UIKit) |
| `fonts-dejavu-core`, `fonts-dejavu-extra` | The system font, with italics |

```sh
sudo apt-get install --no-install-recommends \
    libsdl3-0 libegl1 libgles1 libgles2 libgl1 libglx-mesa0 libegl-mesa0 libgl1-mesa-dri libgbm1 \
    libvulkan1 mesa-vulkan-drivers \
    libwpewebkit-2.0-1 libwpebackend-fdo-1.0-1 libwayland-server0 \
    libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav \
    libopenal1 libssl3t64 openssl-provider-legacy libcurl4t64 libxar1 \
    avahi-daemon libavahi-compat-libdnssd1 libtiff6 libpoppler-glib8t64 libx11-6 \
    fonts-dejavu-core fonts-dejavu-extra
```

`libtiff6`, `libpoppler-glib8t64` and `libx11-6` are not in the Dockerfile, so a container built from it may lack them.

## Tests only

`dbus-daemon`, `python3-dbus` and `python3-gi` run the fake BlueZ for CoreBluetooth's tests.
