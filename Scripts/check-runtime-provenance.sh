#!/bin/sh
# Lists the libraries in a Swift runtime directory (PERRY_SWIFT_RUNTIME) that
# Perry's scripts did not build from source: each Mach-O whose slices were
# built for a simulator, or for a deployment target other than the ones the
# builds ask for. The iOS Simulator's libraries say iossimulator, and
# Xcode's Swift 5.0 overlays iOS 7.0 or macOS 10.9; a source build's say
# iOS 18.0, macOS 15.0 or Mac Catalyst 18.0. A link (one of Darwin's split
# names) must lead to a library in the directory.
#
# It reads the load commands itself, so it runs on a Mac or in Linux.
#
# Usage: Scripts/check-runtime-provenance.sh [--report] <runtime directory> [platform:version...]
#   default targets: ios:18.0 macos:15.0 maccatalyst:18.0
#   --report: list them and exit 0 (CI, until none is left)
# Exits 1 when it lists any.
set -eu
report=0
if [ "${1:-}" = --report ]; then
    report=1
    shift
fi
[ $# -ge 1 ] || { echo "usage: $0 [--report] <runtime directory> [platform:version...]" >&2; exit 2; }
exec python3 -I - "$report" "$@" <<'EOF'
import os, struct, sys

report = sys.argv[1] == "1"
directory = sys.argv[2]
targets = sys.argv[3:] or ["ios:18.0", "macos:15.0", "maccatalyst:18.0"]
wanted = {}
for target in targets:
    platform, _, version = target.partition(":")
    wanted.setdefault(platform, set()).add(version)

PLATFORMS = {1: "macos", 2: "ios", 3: "tvos", 4: "watchos", 5: "bridgeos", 6: "maccatalyst",
             7: "iossimulator", 8: "tvossimulator", 9: "watchossimulator", 10: "driverkit",
             11: "visionos", 12: "visionossimulator"}
# LC_VERSION_MIN_* commands, from before LC_BUILD_VERSION.
VERSION_MIN = {0x24: "macos", 0x25: "ios", 0x2F: "tvos", 0x30: "watchos"}
CPUS = {7: "i386", 0x01000007: "x86_64", 12: "arm", 0x0100000C: "arm64", 0x0200000C: "arm64_32"}

def version(packed):
    text = "%d.%d" % (packed >> 16, (packed >> 8) & 0xFF)
    return text + (".%d" % (packed & 0xFF) if packed & 0xFF else "")

def slices(data):
    """(cpu, offset) for each slice of a thin or universal Mach-O."""
    magic = struct.unpack_from(">I", data)[0]
    if magic in (0xCAFEBABE, 0xCAFEBABF):
        count = struct.unpack_from(">I", data, 4)[0]
        wide = magic == 0xCAFEBABF
        for i in range(count):
            if wide:
                cpu, _, offset = struct.unpack_from(">iiQ", data, 8 + i * 32)
            else:
                cpu, _, offset = struct.unpack_from(">iiI", data, 8 + i * 20)
            yield cpu, offset
    elif magic in (0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE):
        endian = "<" if magic in (0xCEFAEDFE, 0xCFFAEDFE) else ">"
        yield struct.unpack_from(endian + "i", data, 4)[0], 0

def builds(data, offset):
    """(platform, minimum version) for each build version command of a slice."""
    magic = struct.unpack_from("<I", data, offset)[0]
    endian = "<" if magic in (0xFEEDFACE, 0xFEEDFACF) else ">"
    header = 32 if magic in (0xFEEDFACF, 0xCFFAEDFE) else 28
    ncmds = struct.unpack_from(endian + "I", data, offset + 16)[0]
    position = offset + header
    for _ in range(ncmds):
        cmd, size = struct.unpack_from(endian + "II", data, position)
        if cmd == 0x32:
            platform, minos = struct.unpack_from(endian + "II", data, position + 8)
            yield PLATFORMS.get(platform, "platform %d" % platform), version(minos)
        elif cmd in VERSION_MIN:
            minos = struct.unpack_from(endian + "I", data, position + 8)[0]
            yield VERSION_MIN[cmd], version(minos)
        position += size

problems = []
checked = 0
for name in sorted(os.listdir(directory)):
    path = os.path.join(directory, name)
    if os.path.islink(path):
        target = os.path.realpath(path)
        if os.path.dirname(target) != os.path.realpath(directory) or not os.path.isfile(target):
            problems.append((name, "a link to %s, outside the directory" % os.readlink(path)))
        continue
    if not os.path.isfile(path):
        continue
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 8 or not list(slices(data)):
        continue
    checked += 1
    reasons = []
    for cpu, offset in slices(data):
        arch = CPUS.get(cpu, "cpu %d" % cpu)
        found = list(builds(data, offset))
        if not found:
            reasons.append("%s: no build version" % arch)
        for platform, minos in found:
            if platform.endswith("simulator"):
                reasons.append("%s: built for %s %s" % (arch, platform, minos))
            elif minos not in wanted.get(platform, ()):
                reasons.append("%s: %s %s" % (arch, platform, minos))
    if reasons:
        problems.append((name, ", ".join(reasons)))

for name, reason in problems:
    print("%s: %s" % (name, reason))
summary = "%d of %d libraries in %s not built from source here" % (len(problems), checked, directory)
print(summary, file=sys.stderr)
step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
if step_summary:
    with open(step_summary, "a") as f:
        f.write("### Runtime provenance\n\n%s\n\n" % summary)
        for name, reason in problems:
            f.write("- `%s`: %s\n" % (name, reason))
sys.exit(0 if report or not problems else 1)
EOF
