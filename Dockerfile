# arm64 Linux environment for building and testing Perry.
# Debian's LLVM supplies clang and ld64.lld for the Mach-O test fixtures;
# the lld bundled with Swift's toolchain cannot link Mach-O. The C libraries
# are the ones Perry's providers bind Darwin's imports to, or build on.
FROM swift:6.4-trixie

RUN apt-get update \
 && apt-get install -y --no-install-recommends clang-19 lld-19 \
        libxml2-dev zlib1g-dev libbz2-dev libexpat1-dev \
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
 && clang-19 -O2 -fPIC -shared -o /usr/lib/aarch64-linux-gnu/libperry-sqlite3.so -Wl,-soname,libperry-sqlite3.so \
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
 && ar rcs /usr/lib/aarch64-linux-gnu/liblzfse.a *.o && cp lzfse.h /usr/include/ \
 && cd / && rm -rf /tmp/lzfse /tmp/lzfse.tar.gz \
 && ldconfig

# OpenAL Soft, for OpenAL.framework's API, which its provider opens at run
# time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libopenal1 \
 && rm -rf /var/lib/apt/lists/*

# LLVM's libc++ and libc++abi as Apple builds them for arm64, which C++ in
# iOS apps and Swift's runtime were built against: std::string in the
# alternate layout (its data pointer first), and type_info compared as
# Apple's arm64 compares it, by name for types marked not unique. Named
# libperry-c++ so they never stand in for the system's; the CXX provider
# opens them at run time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends cmake ninja-build python3 xz-utils \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSLo /tmp/llvm.tar.xz https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.7/llvm-project-19.1.7.src.tar.xz \
 && echo "82401fea7b79d0078043f7598b835284d6650a75b93e64b6f761ea7b63097501  /tmp/llvm.tar.xz" | sha256sum -c - \
 && mkdir /tmp/llvm && tar -xJf /tmp/llvm.tar.xz -C /tmp/llvm --strip-components=1 \
        llvm-project-19.1.7.src/runtimes llvm-project-19.1.7.src/libcxx llvm-project-19.1.7.src/libcxxabi \
        llvm-project-19.1.7.src/libunwind llvm-project-19.1.7.src/cmake llvm-project-19.1.7.src/llvm/cmake \
        llvm-project-19.1.7.src/llvm/utils \
 && cmake -G Ninja -S /tmp/llvm/runtimes -B /tmp/llvm-build -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang-19 -DCMAKE_CXX_COMPILER=clang++-19 \
        -DCMAKE_CXX_FLAGS=-D_LIBCPP_TYPEINFO_COMPARISON_IMPLEMENTATION=2 \
        -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
        -DLIBCXX_ABI_DEFINES=_LIBCPP_ABI_ALTERNATE_STRING_LAYOUT \
        -DLIBCXX_SHARED_OUTPUT_NAME=perry-c++ -DLIBCXXABI_SHARED_OUTPUT_NAME=perry-c++abi \
        -DLIBCXX_ENABLE_STATIC=OFF -DLIBCXXABI_ENABLE_STATIC=OFF -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
        -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF \
 && ninja -C /tmp/llvm-build cxx cxxabi \
 && cp -P /tmp/llvm-build/lib/libperry-c++*.so.1* /usr/lib/aarch64-linux-gnu/ \
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

WORKDIR /perry
