#!/bin/sh
# Checks a built libPerryCarbon.so against Sources/PerryCarbon/exports.txt:
# every name listed is exported and nothing else of Carbon's is, so moving
# Carbon from C to Swift (Documentation/Plans/graphite.md) can neither drop
# an export nor add one by mistake. On ppc a function whose arguments go past
# the registers is exported as perry_ppc_moved_<name> (DarwinCMacro), which
# counts as <name>.
#
# Libraries after the first are other providers: a listed name one of them
# also exports fails the check too, since which of the two a program gets
# would depend on the loader's re-export order.
#
# NM names the nm to read the libraries with (default nm); for ppc, the
# cross toolchain's, such as powerpc-linux-gnu-nm.
# Usage: Scripts/check-carbon-exports.sh libPerryCarbon.so [libPerryOther.so...]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
nm=${NM:-nm}
library=${1:?usage: check-carbon-exports.sh libPerryCarbon.so [other providers...]}
shift
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Darwin's names (one leading underscore) and perry_ entry points, with a
# moved function under its own name, less the linker's own symbols.
exported() {
    "$nm" -D --defined-only "$1" | awk 'NF >= 3 { print $3 }' |
        sed -n -e 's/^perry_ppc_moved_/_/p' -e '/^_[A-Za-z]/p' -e '/^perry_provider_startup$/p' |
        grep -vx -e _edata -e _end -e _etext | sort -u
}

sed -e '/^#/d' -e '/^$/d' "$root/Sources/PerryCarbon/exports.txt" | sort -u > "$work/listed"
exported "$library" > "$work/built"
comm -23 "$work/listed" "$work/built" > "$work/missing"
comm -13 "$work/listed" "$work/built" > "$work/unlisted"
status=0
if [ -s "$work/missing" ]; then
    echo "$library is missing $(wc -l < "$work/missing") listed exports:" >&2
    sed 's/^/  /' "$work/missing" >&2
    status=1
fi
if [ -s "$work/unlisted" ]; then
    echo "$library exports $(wc -l < "$work/unlisted") names exports.txt doesn't list:" >&2
    sed 's/^/  /' "$work/unlisted" >&2
    status=1
fi
# Every provider has an entry point of its own.
for other; do
    exported "$other" | grep -vx perry_provider_startup | comm -12 "$work/listed" - > "$work/both"
    if [ -s "$work/both" ]; then
        echo "$other also exports $(wc -l < "$work/both") of Carbon's names:" >&2
        sed 's/^/  /' "$work/both" >&2
        status=1
    fi
done
[ "$status" -ne 0 ] || echo "$library: $(wc -l < "$work/listed") exports, as listed"
exit "$status"
