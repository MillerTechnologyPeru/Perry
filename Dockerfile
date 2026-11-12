# Linux environment for building and testing Perry, on arm64 or x86_64.
# Debian's LLVM supplies clang and ld64.lld for the Mach-O test fixtures;
# the lld bundled with Swift's toolchain cannot link Mach-O. The C libraries
# are the ones Perry's providers bind Darwin's imports to, or build on.
FROM swift:6.4-trixie

RUN apt-get update \
 && apt-get install -y --no-install-recommends clang-19 lld-19 \
        libxml2-dev zlib1g-dev libbz2-dev libexpat1-dev libxar1 \
        libssl-dev openssl-provider-legacy liblzma-dev liblz4-dev libbrotli-dev curl ca-certificates \
        libpng-dev libjpeg62-turbo-dev libgif-dev libwebp-dev libheif-dev \
        libcairo2-dev libfreetype-dev libfontconfig-dev pkgconf fonts-dejavu-core libopenblas-dev \
        libjavascriptcoregtk-4.1-dev \
 && rm -rf /var/lib/apt/lists/*

ENV PERRY_LLVM_BIN=/usr/lib/llvm-19/bin

# SQLite as the iOS SDK has it (3.54.0, newer than Debian's), with Apple's
# compile options where they change behaviour. Not SQLLOG, a debugging hook
# whose callback the host program must supply, nor DEFAULT_AUTOVACUUM and
# DEFAULT_RECURSIVE_TRIGGERS, which Apple defines with their default values
# (compile_options lists them all the same). Named libperry-sqlite3 so it
# never stands in for the system's libsqlite3. The linker searches the
# system library directory, not /usr/local.
RUN curl -fsSLo /tmp/sqlite.tar.gz https://www.sqlite.org/2026/sqlite-autoconf-3540000.tar.gz \
 && echo "134ec0802dda5795816e25d25872d20b312cb3973438c49b30bc40b7705ea9ed  /tmp/sqlite.tar.gz" | sha256sum -c - \
 && mkdir /tmp/sqlite && tar -xzf /tmp/sqlite.tar.gz -C /tmp/sqlite --strip-components=1 \
 && clang-19 -O2 -fPIC -shared -o /usr/lib/$(uname -m)-linux-gnu/libperry-sqlite3.so -Wl,-soname,libperry-sqlite3.so \
        -DSQLITE_THREADSAFE=2 -DSQLITE_USE_URI=1 -DSQLITE_DQS=3 -DSQLITE_TEMP_STORE=1 \
        -DSQLITE_DEFAULT_CACHE_SIZE=2000 -DSQLITE_DEFAULT_FILE_FORMAT=4 \
        -DSQLITE_DEFAULT_JOURNAL_SIZE_LIMIT=32768 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DEFAULT_PAGE_SIZE=4096 \
        -DSQLITE_DEFAULT_SYNCHRONOUS=2 -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 \
        -DSQLITE_MAX_ATTACHED=10 -DSQLITE_MAX_COLUMN=2000 -DSQLITE_MAX_COMPOUND_SELECT=500 \
        -DSQLITE_MAX_EXPR_DEPTH=1000 -DSQLITE_MAX_FUNCTION_ARG=127 -DSQLITE_MAX_LIKE_PATTERN_LENGTH=50000 \
        -DSQLITE_MAX_MMAP_SIZE=1073741824 -DSQLITE_MAX_VARIABLE_NUMBER=500000 -DSQLITE_MAX_TRIGGER_DEPTH=1000 \
        -DSQLITE_OMIT_AUTORESET -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_BUG_COMPATIBLE_20160819 \
        -DSQLITE_ENABLE_API_ARMOR -DSQLITE_ENABLE_BYTECODE_VTAB -DSQLITE_ENABLE_CARRAY \
        -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_DBPAGE_VTAB -DSQLITE_ENABLE_DBSTAT_VTAB \
        -DSQLITE_ENABLE_EXPLAIN_COMMENTS -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS \
        -DSQLITE_ENABLE_FTS3_TOKENIZER -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_MATH_FUNCTIONS \
        -DSQLITE_ENABLE_NORMALIZE -DSQLITE_ENABLE_PERCENTILE -DSQLITE_ENABLE_PREUPDATE_HOOK -DSQLITE_ENABLE_RTREE \
        -DSQLITE_ENABLE_SESSION -DSQLITE_ENABLE_SETLK_TIMEOUT -DSQLITE_ENABLE_SNAPSHOT \
        -DSQLITE_ENABLE_STMT_SCANSTATUS -DSQLITE_ENABLE_UNKNOWN_SQL_FUNCTION -DSQLITE_ENABLE_UPDATE_DELETE_LIMIT \
        /tmp/sqlite/sqlite3.c -lm \
 && rm -rf /tmp/sqlite /tmp/sqlite.tar.gz

# LZFSE, Apple's open-source compressor, which Debian does not package.
RUN curl -fsSLo /tmp/lzfse.tar.gz https://github.com/lzfse/lzfse/archive/refs/tags/lzfse-1.0.tar.gz \
 && echo "cf85f373f09e9177c0b21dbfbb427efaedc02d035d2aade65eb58a3cbf9ad267  /tmp/lzfse.tar.gz" | sha256sum -c - \
 && mkdir /tmp/lzfse && tar -xzf /tmp/lzfse.tar.gz -C /tmp/lzfse --strip-components=1 \
 && cd /tmp/lzfse/src \
 && for f in lzfse_decode.c lzfse_decode_base.c lzfse_encode.c lzfse_encode_base.c lzfse_fse.c lzvn_decode_base.c lzvn_encode_base.c; do \
        clang-19 -O2 -fPIC -c "$f" || exit 1; done \
 && ar rcs /usr/lib/$(uname -m)-linux-gnu/liblzfse.a *.o && cp lzfse.h /usr/include/ \
 && cd / && rm -rf /tmp/lzfse /tmp/lzfse.tar.gz \
 && ldconfig

# OpenAL Soft, for OpenAL.framework's API, which its provider opens at run
# time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libopenal1 \
 && rm -rf /var/lib/apt/lists/*

# GStreamer, for AVPlayer's video and audio, which AVFoundation's provider
# opens at run time: playbin and its decoders (libav's for H.264 and AAC).
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
        gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav \
 && rm -rf /var/lib/apt/lists/*

# LLVM's libc++ and libc++abi as Apple builds them, which C++ in apps and
# Swift's runtime were built against. For arm64: std::string in the
# alternate layout (its data pointer first), type_info compared as Apple's
# arm64 compares it, by name for types marked not unique, and the ARM C++
# ABI's constructors and destructors that return this, which apps' inlined
# code uses (and its two-word new[] cookies, as Apple's arm64 has). x86_64
# has the defaults, as Apple's does. Both
# are built with Darwin's mbstate_t, 128 bytes in place of glibc's 8:
# std::fpos, which holds one, is returned as Darwin code expects, and
# stream buffers are laid out as it lays them out; glibc reads and writes
# only its own fields, at the start. Named libperry-c++ so they never stand
# in for the system's; the CXX provider opens them at run time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends cmake ninja-build python3 xz-utils \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSLo /tmp/llvm.tar.xz https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.7/llvm-project-19.1.7.src.tar.xz \
 && echo "82401fea7b79d0078043f7598b835284d6650a75b93e64b6f761ea7b63097501  /tmp/llvm.tar.xz" | sha256sum -c - \
 && mkdir /tmp/llvm && tar -xJf /tmp/llvm.tar.xz -C /tmp/llvm --strip-components=1 \
        llvm-project-19.1.7.src/runtimes llvm-project-19.1.7.src/libcxx llvm-project-19.1.7.src/libcxxabi \
        llvm-project-19.1.7.src/libunwind llvm-project-19.1.7.src/cmake llvm-project-19.1.7.src/llvm/cmake \
        llvm-project-19.1.7.src/llvm/utils \
 && printf '%s\n' \
        '#ifndef ____mbstate_t_defined' \
        '#define ____mbstate_t_defined 1' \
        'typedef union {' \
        '    struct { int __count; union { unsigned int __wch; char __wchb[4]; } __value; };' \
        '    char __darwin[128];' \
        '    long long __align;' \
        '} __mbstate_t;' \
        '#endif' > /tmp/llvm/darwin-mbstate.h \
 && if [ "$(uname -m)" = aarch64 ]; then \
        cxx_abi="-D_LIBCPP_TYPEINFO_COMPARISON_IMPLEMENTATION=2 -fc++-abi=arm"; \
        abi_defines=_LIBCPP_ABI_ALTERNATE_STRING_LAYOUT; \
    fi \
 && cmake -G Ninja -S /tmp/llvm/runtimes -B /tmp/llvm-build -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang-19 -DCMAKE_CXX_COMPILER=clang++-19 \
        "-DCMAKE_C_FLAGS=-include /tmp/llvm/darwin-mbstate.h" \
        "-DCMAKE_CXX_FLAGS=$cxx_abi -include /tmp/llvm/darwin-mbstate.h" \
        -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
        -DLIBCXX_ABI_DEFINES=$abi_defines \
        -DLIBCXX_SHARED_OUTPUT_NAME=perry-c++ -DLIBCXXABI_SHARED_OUTPUT_NAME=perry-c++abi \
        -DLIBCXX_ENABLE_STATIC=OFF -DLIBCXXABI_ENABLE_STATIC=OFF -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
        -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF \
 && ninja -C /tmp/llvm-build cxx cxxabi \
 && cp -P /tmp/llvm-build/lib/libperry-c++*.so.1* /usr/lib/$(uname -m)-linux-gnu/ \
 && rm -rf /tmp/llvm /tmp/llvm-build /tmp/llvm.tar.xz \
 && ldconfig

# SDL3 and Mesa's drivers, for UIKit's live view: windows, input, and
# compositing layers on the GPU (through /dev/dri when a container has it);
# and Mesa's EGL and OpenGL ES, which EAGLContext and apps' gl* calls use,
# on the GPU or in software. UIKit loads them at run time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libsdl3-0 libgl1-mesa-dri libegl1 libgles2 libgles1 libgl1 libglx-mesa0 libegl-mesa0 libgbm1 \
 && rm -rf /var/lib/apt/lists/*

# D-Bus and Python's bindings for it, for CoreBluetooth's tests, which run a
# fake BlueZ (Tests/Fixtures/bluez) on a bus of their own.
RUN apt-get update \
 && apt-get install -y --no-install-recommends dbus-daemon python3-dbus python3-gi \
 && rm -rf /var/lib/apt/lists/*

# Avahi and its Bonjour compatibility library (libdns_sd), which
# NSNetService and NSNetServiceBrowser run over; the tests that need the
# daemon start it on a bus of their own.
RUN apt-get update \
 && apt-get install -y --no-install-recommends avahi-daemon libavahi-compat-libdnssd1 \
 && rm -rf /var/lib/apt/lists/*

# DejaVu's oblique faces, for italic text in the system font.
RUN apt-get update \
 && apt-get install -y --no-install-recommends fonts-dejavu-extra \
 && rm -rf /var/lib/apt/lists/*

# swift-cmark, Swift's fork of cmark-gfm, which Foundation parses Markdown
# with: GitHub's tables, strikethrough and autolinks, the ^[text](attributes)
# syntax, and the inline-only and whitespace-preserving modes Foundation's
# options choose. Static archives, built position-independent for
# PerryFoundation and named libperry-cmark-gfm so they never stand in for a
# system cmark; their functions stay hidden in the provider.
RUN curl -fsSLo /tmp/cmark.tar.gz https://github.com/swiftlang/swift-cmark/archive/437611671145d47e6d9679761b8a5987766f4ae5.tar.gz \
 && echo "bcc825cecd1710cdca28f7cc0a74423a691966be2f3a4c6fa8739a2009ed5bf2  /tmp/cmark.tar.gz" | sha256sum -c - \
 && mkdir /tmp/cmark && tar -xzf /tmp/cmark.tar.gz -C /tmp/cmark --strip-components=1 \
 && cmake -G Ninja -S /tmp/cmark -B /tmp/cmark-build -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang-19 \
        -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF \
 && ninja -C /tmp/cmark-build libcmark-gfm libcmark-gfm-extensions \
 && cp /tmp/cmark-build/src/libcmark-gfm.a /usr/lib/$(uname -m)-linux-gnu/libperry-cmark-gfm.a \
 && cp /tmp/cmark-build/extensions/libcmark-gfm-extensions.a /usr/lib/$(uname -m)-linux-gnu/libperry-cmark-gfm-extensions.a \
 && mkdir -p /usr/include/perry-cmark-gfm \
 && cp /tmp/cmark/src/include/*.h /tmp/cmark/extensions/include/*.h /usr/include/perry-cmark-gfm/ \
 && rm -rf /tmp/cmark /tmp/cmark-build /tmp/cmark.tar.gz

# WPE WebKit, WebKit's port for embedding, which WKWebView and UIWebView
# load at run time: its web and network processes, and WPEBackend-fdo,
# which hands each frame the web process draws to the view in shared
# memory.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libwpewebkit-2.0-1 libwpebackend-fdo-1.0-1 libwayland-server0 \
 && rm -rf /var/lib/apt/lists/*

# Vulkan's loader and Mesa's Vulkan drivers (lavapipe on the CPU when a
# container has no GPU), which metal2vulkan opens at run time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libvulkan1 mesa-vulkan-drivers \
 && rm -rf /var/lib/apt/lists/*

# metal2vulkan (GPL-2.0-or-later OR LGPL-3.0-or-later, taken as LGPL), the
# Metal API on Vulkan, through the C ABI crate on MillerTechnologyPeru's
# fork: libmetal2vulkan.so, a separate library Metal's provider opens at run
# time. Built with the Rust its toolchain file pins, which is removed after.
RUN curl -fsSLo /tmp/m2v.tar.gz https://github.com/MillerTechnologyPeru/metal2vulkan/archive/01bd4c610748a2a9bcf2b1db3a059da41f086fa5.tar.gz \
 && echo "f16fa652633b2e990509b071ee1d5a4d018d73b6affaf58dad2bd27776d700d1  /tmp/m2v.tar.gz" | sha256sum -c - \
 && mkdir /tmp/m2v && tar -xzf /tmp/m2v.tar.gz -C /tmp/m2v --strip-components=1 \
        --wildcards '*/capi' '*/crates/metal2vulkan' '*/crates/metal2vulkan-air' '*/crates/metal2vulkan-runtime' \
        '*/Cargo.toml' '*/rust-toolchain.toml' '*/LICENSE*' \
 && curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.98.1 \
 && cd /tmp/m2v/capi && /root/.cargo/bin/cargo build --release \
 && strip -o /usr/lib/$(uname -m)-linux-gnu/libmetal2vulkan.so target/release/libmetal2vulkan_capi.so \
 && mkdir -p /usr/share/doc/metal2vulkan && cp /tmp/m2v/LICENSE* /usr/share/doc/metal2vulkan/ \
 && cd / && rm -rf /tmp/m2v /tmp/m2v.tar.gz /root/.cargo /root/.rustup

WORKDIR /perry
