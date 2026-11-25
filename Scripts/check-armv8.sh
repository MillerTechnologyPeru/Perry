#!/bin/sh
# Lists the arm64 libraries in a directory that use instructions newer than
# Armv8.0, and how many of each: the extensions a CPU Perry runs on may not
# have. The OnePlus 6T's (Snapdragon 845) has no dot product, for one, and
# traps on the udot in the iOS Simulator's libswiftCore. Perry's arm64
# libraries are built for apple-a7 (Scripts/darwin-toolchain.sh), which has
# none of them.
#
# It looks for the instructions of LSE atomics, CRC32, RDM, FP16 arithmetic,
# dot product, SHA-3 and SM3/SM4, pointer authentication, complex numbers,
# FJCVTZS, RCpc loads and stores, flag manipulation, FRINT32/64, BFloat16,
# Int8 matrix multiplication and memory tagging, in each Mach-O's arm64
# slice, as llvm-objdump (Xcode's on a Mac) disassembles it. A library built
# for the iOS Simulator is left out, with a note: it is not built here
# (Scripts/check-runtime-provenance.sh lists it), and goes from a runtime
# directory built from source.
#
# Usage: Scripts/check-armv8.sh <directory>...
# Exits 1 when it lists any.
set -eu
[ $# -ge 1 ] || { echo "usage: $0 <directory>..." >&2; exit 2; }
if command -v xcrun >/dev/null 2>&1; then
    objdump=$(xcrun --find llvm-objdump)
else
    objdump=$(command -v llvm-objdump)
fi
exec python3 -I - "$objdump" "$@" <<'EOF'
import os, re, struct, subprocess, sys

objdump = sys.argv[1]
ARM64 = 0x0100000C

# Mnemonics of the extensions after Armv8.0.
NEWER = re.compile(r"""^(
    cas[abl]*|casp[al]*|ld(add|clr|eor|set|smax|smin|umax|umin)[abhl]*|
    st(add|clr|eor|set|smax|smin|umax|umin)[bhl]*|swp[abhl]*|
    crc32c?[bhwx]|sqrdml[as]h|
    [su]dot|usdot|sudot|[su]mmla|usmmla|
    eor3|bcax|rax1|xar|sha512[a-z0-9]*|sm3[a-z0-9]*|sm4[a-z0-9]*|
    pac[a-z0-9]*|aut[a-z0-9]*|xpac[di]|xpaclri|reta[ab]|bra[ab]z?|blra[ab]z?|ereta[ab]|ldra[ab]|
    fcmla|fcadd|fjcvtzs|
    ldapr[bh]?|ldapur[a-z]*|stlur[bh]?|
    cfinv|rmif|setf8|setf16|axflag|xaflag|
    frint(32|64)[xz]|
    bfdot|bfmmla|bfmlal[bt]|bfcvtn?2?|
    irg|gmi|subps?|addg|subg|st2?z?g|stzgm|stgm|ldgm?|stgp
)$""", re.X)
# FP16 arithmetic: a floating-point instruction on half-precision registers
# or lanes, other than the conversions Armv8.0 has. In Apple's syntax a
# vector's arrangement follows the mnemonic (udot.4s, fadd.8h).
FLOAT = re.compile(r"^f[a-z0-9]+$")
HALF = re.compile(r"(^|[\s,{])(h\d+|v\d+\.(4h|8h))\b")
CONVERSIONS = {"fcvt", "fcvtl", "fcvtl2", "fcvtn", "fcvtn2"}

SIMULATORS = {7, 8, 9, 12}  # LC_BUILD_VERSION platforms

def arm64_platform(path):
    """The build platform of a Mach-O's arm64 slice (0 when it has no build
    version), or None without an arm64 slice."""
    with open(path, "rb") as f:
        data = f.read(1 << 20)
    if len(data) < 32:
        return None
    magic = struct.unpack_from(">I", data)[0]
    offset = None
    if magic == 0xCFFAEDFE and struct.unpack_from("<i", data, 4)[0] == ARM64:
        offset = 0
    elif magic in (0xCAFEBABE, 0xCAFEBABF):
        count = struct.unpack_from(">I", data, 4)[0]
        for i in range(min(count, 100)):
            if magic == 0xCAFEBABF:
                cpu, _, start = struct.unpack_from(">iiQ", data, 8 + i * 32)
            else:
                cpu, _, start = struct.unpack_from(">iiI", data, 8 + i * 20)
            if cpu == ARM64:
                offset = start
    if offset is None:
        return None
    with open(path, "rb") as f:
        f.seek(offset)
        header = f.read(32)
        ncmds, sizeofcmds = struct.unpack_from("<II", header, 16)
        commands = f.read(sizeofcmds)
    position = 0
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", commands, position)
        if cmd == 0x32:
            return struct.unpack_from("<I", commands, position + 8)[0]
        position += size
    return 0

failed = 0
checked = 0
for directory in sys.argv[2:]:
    for root, _, names in os.walk(directory):
        for name in sorted(names):
            path = os.path.join(root, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            platform = arm64_platform(path)
            if platform is None:
                continue
            if platform in SIMULATORS:
                print("%s: left out, built for a simulator" % os.path.relpath(path, directory), file=sys.stderr)
                continue
            checked += 1
            output = subprocess.run([objdump, "-d", "--arch-name=arm64", "--no-show-raw-insn", "--no-leading-addr", path],
                                    capture_output=True, text=True, check=True).stdout
            found = {}
            for line in output.splitlines():
                if not line.startswith(("\t", " ")):
                    continue
                parts = line.split(None, 1)
                if not parts:
                    continue
                mnemonic, _, arrangement = parts[0].partition(".")
                operands = parts[1] if len(parts) > 1 else ""
                half = arrangement in ("4h", "8h", "h") or HALF.search(operands)
                if NEWER.match(mnemonic) or (FLOAT.match(mnemonic) and mnemonic not in CONVERSIONS and half):
                    found[mnemonic] = found.get(mnemonic, 0) + 1
            if found:
                failed += 1
                listed = ", ".join("%s %d" % item for item in sorted(found.items(), key=lambda item: -item[1]))
                print("%s: %s" % (os.path.relpath(path, directory), listed))
print("%d of %d arm64 libraries use instructions newer than Armv8.0" % (failed, checked), file=sys.stderr)
sys.exit(1 if failed else 0)
EOF
