# arm64 Linux environment for building and testing Perry.
# Ubuntu's LLVM supplies clang and ld64.lld for the Mach-O test fixtures;
# the lld bundled with Swift's toolchain cannot link Mach-O. libxml2 is the
# library libPerryxml2 binds Darwin's libxml2 imports to.
FROM swift:6.4-noble

RUN apt-get update \
 && apt-get install -y --no-install-recommends clang-18 lld-18 libxml2-dev \
 && rm -rf /var/lib/apt/lists/*

ENV PERRY_LLVM_BIN=/usr/lib/llvm-18/bin
WORKDIR /perry
