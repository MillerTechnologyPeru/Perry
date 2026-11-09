#!/usr/bin/env python3
"""Reports a PERRY_PROFILE run: the functions the main thread spent its time
in (self: the frame that was running) and under (inclusive: anywhere on the
stack), as shares of the samples.

    perry-profile.py <samples> [--images <samples>.images] [--files DIR ...]
                     [--top N] [--callers NAME] [--since SECONDS]

Each address is put in the Mach-O image or Linux mapping it falls in, then
named from a copy of that file found by its name in a --files directory:
Mach-O images with atos, ELF libraries with llvm-nm (xcrun's on a Mac). An
address with no copy to name it from shows as file+offset. --callers lists
who called the functions whose names contain NAME, and what they called.
"""

import argparse
import bisect
import collections
import os
import re
import subprocess
import sys


def read_images(path):
    """[(start, end, path, offset base, kind)]: Mach-O images and executable mappings."""
    images = []
    for line in open(path, errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("macho "):
            _, base, size, file = line.split(" ", 3)
            base, size = int(base, 16), int(size, 16)
            images.append((base, base + size, file, base, "macho"))
            continue
        fields = line.split(None, 5)
        if len(fields) < 6 or "x" not in fields[1] or not fields[5].startswith("/"):
            continue
        start, end = (int(x, 16) for x in fields[0].split("-"))
        offset = int(fields[2], 16)
        # The file offset of the mapping: an address's place in the file.
        images.append((start, end, fields[5], start - offset, "elf"))
    images.sort()
    return images


def locate(images, starts, address):
    index = bisect.bisect_right(starts, address) - 1
    if index >= 0:
        start, end, path, base, kind = images[index]
        if start <= address < end:
            return path, address - base, kind
    return None, address, None


def find_file(name, directories):
    for directory in directories:
        for root, _, files in os.walk(directory):
            if name in files:
                return os.path.join(root, name)
    return None


def tool(name):
    for candidate in (name, f"xcrun {name}"):
        try:
            subprocess.run(candidate.split() + ["--version"], capture_output=True, check=True)
            return candidate.split()
        except (OSError, subprocess.CalledProcessError):
            continue
    return None


class Namer:
    def __init__(self, directories):
        self.directories = directories
        self.files = {}
        self.elf_symbols = {}
        self.names = {}

    def file(self, path):
        name = os.path.basename(path)
        if name not in self.files:
            self.files[name] = find_file(name, self.directories)
        return self.files[name]

    def resolve(self, wanted):
        """Names every (path, offset, kind) in `wanted`."""
        by_file = collections.defaultdict(set)
        for path, offset, kind in wanted:
            by_file[(path, kind)].add(offset)
        for (path, kind), offsets in by_file.items():
            local = self.file(path)
            short = os.path.basename(path)
            if not local:
                for offset in offsets:
                    self.names[(path, offset)] = f"{short}+0x{offset:x}"
                continue
            if kind == "macho":
                self.name_macho(path, local, sorted(offsets), short)
            else:
                self.name_elf(path, local, sorted(offsets), short)

    def name_macho(self, path, local, offsets, short):
        for chunk in range(0, len(offsets), 500):
            part = offsets[chunk:chunk + 500]
            # A return address points after the call: name the call.
            result = subprocess.run(["atos", "-o", local, "-l", "0"] + [hex(max(o - 1, 0)) for o in part],
                                    capture_output=True, text=True)
            lines = result.stdout.splitlines()
            for offset, line in zip(part, lines):
                name = re.sub(r" \(in [^)]*\)( \(.*\))?$", "", line.strip())
                self.names[(path, offset)] = f"{name} [{short}]" if not name.startswith("0x") else f"{short}+0x{offset:x}"

    def name_elf(self, path, local, offsets, short):
        if local not in self.elf_symbols:
            nm = tool("llvm-nm")
            symbols = []
            # The symbol table, and the dynamic one, which is all a
            # stripped library keeps.
            for extra in ([], ["-D"]) if nm else ():
                result = subprocess.run(nm + ["--defined-only", "-n", "-C"] + extra + [local], capture_output=True, text=True)
                for line in result.stdout.splitlines():
                    parts = line.split(" ", 2)
                    if len(parts) == 3 and parts[1].lower() in ("t", "w"):
                        try:
                            symbols.append((int(parts[0], 16), parts[2]))
                        except ValueError:
                            pass
            symbols.sort()
            self.elf_symbols[local] = symbols
        symbols = self.elf_symbols[local]
        addresses = [s[0] for s in symbols]
        for offset in offsets:
            index = bisect.bisect_right(addresses, max(offset - 1, 0)) - 1
            self.names[(path, offset)] = f"{symbols[index][1]} [{short}]" if index >= 0 else f"{short}+0x{offset:x}"

    def name(self, path, offset):
        return self.names.get((path, offset), f"{os.path.basename(path or '?')}+0x{offset:x}")


def short(name, width=150):
    name = re.sub(r"<[^<>]*>", "", name)
    name = re.sub(r"<[^<>]*>", "", name)
    return name if len(name) <= width else name[:width - 1] + "…"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("samples")
    parser.add_argument("--images")
    parser.add_argument("--files", action="append", default=[])
    parser.add_argument("--top", type=int, default=30)
    parser.add_argument("--callers")
    parser.add_argument("--skip", type=int, default=0, help="samples to skip from the start (start-up)")
    parser.add_argument("--thread", help="with PERRY_PROFILE_ALL, only this thread's samples (its hex id)")
    parser.add_argument("--within", help="only samples with a function whose name contains this on the stack")
    args = parser.parse_args()

    images = read_images(args.images or args.samples + ".images")
    starts = [image[0] for image in images]
    stacks, threads = [], []
    for line in open(args.samples):
        fields = line.split()
        thread = fields.pop(0)[1:] if fields and fields[0].startswith("t") else None
        try:
            stacks.append([int(x, 16) for x in fields])
            threads.append(thread)
        except ValueError:
            continue
    stacks, threads = stacks[args.skip:], threads[args.skip:]
    if any(threads):
        counts = collections.Counter(threads)
        print("threads: " + ", ".join(f"{t} {100 * n / len(threads):.1f}%" for t, n in counts.most_common(12)))
        if args.thread:
            stacks = [stack for stack, thread in zip(stacks, threads) if thread == args.thread]
    if not stacks:
        sys.exit("no samples")

    located = [[locate(images, starts, address) for address in stack] for stack in stacks]
    namer = Namer(args.files)
    namer.resolve({frame for stack in located for frame in stack if frame[0]})
    named = [[namer.name(path, offset) if path else f"0x{offset:x}" for path, offset, _ in stack] for stack in located]

    if args.within:
        named = [stack for stack in named if any(args.within in name for name in stack)]
        if not named:
            sys.exit(f"no samples within {args.within}")
    total = len(named)
    leaf = collections.Counter(stack[0] for stack in named if stack)
    inclusive = collections.Counter()
    for stack in named:
        for name in set(stack):
            inclusive[name] += 1

    print(f"{total} samples")
    print(f"\nself (top {args.top}):")
    for name, count in leaf.most_common(args.top):
        print(f"  {100 * count / total:5.1f}%  {short(name)}")
    print(f"\ninclusive (top {args.top}):")
    for name, count in inclusive.most_common(args.top):
        print(f"  {100 * count / total:5.1f}%  {short(name)}")

    if args.callers:
        callers, callees = collections.Counter(), collections.Counter()
        hits = 0
        for stack in named:
            seen = False
            for index, name in enumerate(stack):
                if args.callers in name and not seen:
                    seen = True
                    hits += 1
                    if index + 1 < len(stack):
                        callers[stack[index + 1]] += 1
                    if index > 0:
                        callees[stack[index - 1]] += 1
        print(f"\n{args.callers}: {100 * hits / total:.1f}% of samples")
        print("  called from:")
        for name, count in callers.most_common(15):
            print(f"    {100 * count / total:5.1f}%  {short(name)}")
        print("  calling:")
        for name, count in callees.most_common(15):
            print(f"    {100 * count / total:5.1f}%  {short(name)}")


if __name__ == "__main__":
    main()
