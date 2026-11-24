#!/bin/sh
# Runs the Stopwatch fixture (Tests/Fixtures/Darwin/Stopwatch) and writes
# each case's median nanoseconds per operation as JSON, with "startup",
# the median nanoseconds a run that returns from main at once takes.
#
# Usage: Scripts/perry-bench.sh [-n runs] [-c baseline.json] [command...]
#
# The command runs the fixture, `perry .build/perry-fixtures/darwin/Stopwatch.app`
# unless given (a Mac build runs as itself). With -c, a Markdown table
# comparing the results with the baseline goes to stderr. Timings on shared
# machines are noisy, so nothing here fails on them; refresh
# Tests/Benchmarks/baseline.json by hand when a change is meant to move one.
set -eu
runs=5
baseline=""
while getopts n:c: option; do
    case $option in
        n) runs=$OPTARG ;;
        c) baseline=$OPTARG ;;
        *) echo "usage: $0 [-n runs] [-c baseline.json] [command...]" >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
cd "$(dirname "$0")/.."
if [ $# -eq 0 ]; then
    perry=$(ls .build/linux/debug/perry .build/debug/perry 2>/dev/null | head -1)
    [ -n "$perry" ] || { echo "no perry in .build: build it, or give the command" >&2; exit 1; }
    set -- "$perry" .build/perry-fixtures/darwin/Stopwatch.app
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
i=0
while [ "$i" -lt "$runs" ]; do
    "$@" > "$scratch/run-$i.txt"
    "$@" startup > /dev/null
    perl -MTime::HiRes=time -e '$s = time; system(@ARGV) == 0 or exit 1; printf "startup %.0f\n", (time - $s) * 1e9' \
        "$@" startup >> "$scratch/run-$i.txt"
    i=$((i + 1))
done

python3 - "$scratch" "$runs" "$baseline" <<'PYTHON'
import json, statistics, sys
scratch, runs, baseline = sys.argv[1], int(sys.argv[2]), sys.argv[3]
samples = {}
for run in range(runs):
    for line in open(f"{scratch}/run-{run}.txt"):
        name, value = line.split()
        samples.setdefault(name, []).append(float(value))
results = {name: round(statistics.median(values), 1) for name, values in samples.items()}
json.dump(results, sys.stdout, indent=2)
print()
if baseline:
    try:
        old = json.load(open(baseline))
    except OSError:
        print(f"no baseline at {baseline}", file=sys.stderr)
        sys.exit(0)
    print("| Case | Baseline ns | Now ns | Change |", file=sys.stderr)
    print("| --- | ---: | ---: | ---: |", file=sys.stderr)
    for name, value in results.items():
        before = old.get(name)
        change = f"{(value - before) / before * 100:+.0f}%" if before else ""
        print(f"| {name} | {before if before is not None else ''} | {value} | {change} |", file=sys.stderr)
PYTHON
