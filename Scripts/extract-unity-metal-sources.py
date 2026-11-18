#!/usr/bin/env python3
"""Writes every Metal Shading Language source a Unity game carries to a
directory, named as Perry's source cache names them (<key>.metal), so
Scripts/compile-metal-sources.sh can compile them all before the game is
first run, instead of in rounds as the game asks for them.

A Unity player keeps its shaders in its asset files and asset bundles: each
Shader object ends in a blob of LZ4 blocks, which hold one program for every
variant of every pass, and a Metal program is its source text behind a small
header. Nothing is run: the files are read, the bundles unpacked, and the
blobs found by their layout. Sources kept as plain strings, as a plugin's are
in its binary, are taken too.

Usage: Scripts/extract-unity-metal-sources.py <App.app or its Data directory> <directory>
"""

import ctypes
import ctypes.util
import lzma
import os
import struct
import sys

# The start of a Metal program in a shader blob.
METAL_MAGIC = b"\xfe\xca\x0d\xf0"
# What every source Unity writes for Metal has, to find the blobs by.
ANCHOR = b"metal_stdlib"


def fnv1a(data):
    value = 0xCBF29CE484222325
    for byte in data:
        value = ((value ^ byte) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return value


def cache_key(source):
    """The name Perry's Metal source cache gives a source: FNV-1a of its bytes, and their count."""
    return "%016x-%d" % (fnv1a(source), len(source))


# MARK: LZ4

_compression = None
if sys.platform == "darwin":
    try:
        _compression = ctypes.CDLL(ctypes.util.find_library("compression") or "libcompression.dylib")
        _compression.compression_decode_buffer.restype = ctypes.c_size_t
        _compression.compression_decode_buffer.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t,
                                                           ctypes.c_void_p, ctypes.c_int]
    except OSError:
        _compression = None


def lz4_block_python(data, size):
    out = bytearray()
    i, n = 0, len(data)
    while i < n:
        token = data[i]
        i += 1
        literals = token >> 4
        if literals == 15:
            while True:
                more = data[i]
                i += 1
                literals += more
                if more != 255:
                    break
        out += data[i:i + literals]
        i += literals
        if i >= n:
            break
        offset = data[i] | data[i + 1] << 8
        i += 2
        if offset == 0 or offset > len(out):
            raise ValueError("bad LZ4 offset")
        length = token & 15
        if length == 15:
            while True:
                more = data[i]
                i += 1
                length += more
                if more != 255:
                    break
        length += 4
        start = len(out) - offset
        if offset >= length:
            out += out[start:start + length]
        else:
            for k in range(length):
                out.append(out[start + k])
    if len(out) != size:
        raise ValueError("LZ4 block of %d bytes, not %d" % (len(out), size))
    return bytes(out)


def lz4_block(data, size):
    """A raw LZ4 block's bytes, which must be `size` long."""
    if size == 0:
        return b""
    if _compression is not None:
        buffer = ctypes.create_string_buffer(size)
        written = _compression.compression_decode_buffer(buffer, size, bytes(data), len(data), None, 0x100)
        if written == size:
            return buffer.raw
    return lz4_block_python(data, size)


def lzma_block(data, size):
    """A block as Unity writes LZMA: five bytes of properties, then the stream with no size."""
    properties = data[0]
    lc, remainder = properties % 9, properties // 9
    lp, pb = remainder % 5, remainder // 5
    dictionary = struct.unpack_from("<I", data, 1)[0]
    decoder = lzma.LZMADecompressor(format=lzma.FORMAT_RAW,
                                    filters=[{"id": lzma.FILTER_LZMA1, "dict_size": dictionary, "lc": lc, "lp": lp, "pb": pb}])
    return decoder.decompress(data[5:], max_length=size)


def decompress(data, size, method):
    if method == 0:
        return bytes(data)
    if method == 1:
        return lzma_block(data, size)
    if method in (2, 3):
        return lz4_block(data, size)
    raise ValueError("unknown compression %d" % method)


# MARK: Bundles

def cstring(data, at):
    end = data.index(b"\0", at)
    return data[at:end], end + 1


def bundle_files(data):
    """The files inside a UnityFS bundle, as (name, bytes)."""
    at = 8
    version = struct.unpack_from(">I", data, at)[0]
    at += 4
    _, at = cstring(data, at)
    _, at = cstring(data, at)
    _, compressed_size, uncompressed_size, flags = struct.unpack_from(">qIII", data, at)
    at += 20
    if version >= 7:
        at = (at + 15) & ~15
    if flags & 0x80:
        info = data[len(data) - compressed_size:]
    else:
        info = data[at:at + compressed_size]
        at += compressed_size
    info = decompress(info, uncompressed_size, flags & 0x3F)
    position = 16
    count = struct.unpack_from(">i", info, position)[0]
    position += 4
    blocks = []
    for _ in range(count):
        blocks.append(struct.unpack_from(">IIH", info, position))
        position += 10
    count = struct.unpack_from(">i", info, position)[0]
    position += 4
    nodes = []
    for _ in range(count):
        offset, size, _ = struct.unpack_from(">qqI", info, position)
        position += 20
        name, position = cstring(info, position)
        nodes.append((name.decode("utf-8", "replace"), offset, size))
    if flags & 0x200:
        at = (at + 15) & ~15
    parts = []
    for uncompressed, compressed, block_flags in blocks:
        parts.append(decompress(data[at:at + compressed], uncompressed, block_flags & 0x3F))
        at += compressed
    whole = b"".join(parts)
    return [(name, whole[offset:offset + size]) for name, offset, size in nodes]


# MARK: Shader blobs

def read_lists(data, at, count, nested):
    """`count` lists of numbers (or one flat list of `count` numbers' worth), as Unity serializes vectors."""
    if not nested:
        if at + 4 > len(data):
            return None
        length = struct.unpack_from("<I", data, at)[0]
        if length != count or at + 4 + 4 * length > len(data):
            return None
        return [[value] for value in struct.unpack_from("<%dI" % length, data, at + 4)], at + 4 + 4 * length
    if at + 4 > len(data) or struct.unpack_from("<I", data, at)[0] != count:
        return None
    at += 4
    lists = []
    for _ in range(count):
        if at + 4 > len(data):
            return None
        length = struct.unpack_from("<I", data, at)[0]
        if not 1 <= length <= 65536 or at + 4 + 4 * length > len(data):
            return None
        lists.append(list(struct.unpack_from("<%dI" % length, data, at + 4)))
        at += 4 + 4 * length
    return lists, at


def blob_header(data, at):
    """A shader's compressed blob, if its description starts at `at`: the platforms it was compiled for, then
    for each the offsets, compressed lengths and decompressed lengths of its blocks, then the blocks."""
    if at + 8 > len(data):
        return None
    platforms = struct.unpack_from("<I", data, at)[0]
    if not 1 <= platforms <= 8 or at + 4 + 4 * platforms > len(data):
        return None
    if any(value > 64 for value in struct.unpack_from("<%dI" % platforms, data, at + 4)):
        return None
    start = at + 4 + 4 * platforms
    for nested in (True, False):
        position = start
        tables = []
        for _ in range(3):
            read = read_lists(data, position, platforms, nested)
            if read is None:
                break
            tables.append(read[0])
            position = read[1]
        if len(tables) != 3 or position + 4 > len(data):
            continue
        offsets, compressed, decompressed = tables
        if [len(row) for row in offsets] != [len(row) for row in compressed] or [len(row) for row in offsets] != [len(row) for row in decompressed]:
            continue
        length = struct.unpack_from("<I", data, position)[0]
        blob = position + 4
        if length == 0 or blob + length > len(data):
            continue
        end = max(o + c for row_o, row_c in zip(offsets, compressed) for o, c in zip(row_o, row_c))
        if end != length:
            continue
        blocks = [(blob + o, c, d) for row_o, row_c, row_d in zip(offsets, compressed, decompressed) for o, c, d in zip(row_o, row_c, row_d)]
        if any(c == 0 or d < c // 2 for _, c, d in blocks):
            continue
        return blob, length, blocks
    return None


def shader_blocks(data):
    """The decompressed blocks of every shader blob in a file's bytes."""
    found = []
    covered_to = 0
    at = data.find(ANCHOR)
    while at >= 0:
        if at >= covered_to:
            # The blob's description is a little before the first source's text, on a 4-byte boundary.
            position = at & ~3
            limit = max(covered_to, position - (8 << 20))
            header = None
            while position >= limit:
                header = blob_header(data, position)
                if header is not None and header[0] <= at < header[0] + header[1]:
                    break
                header = None
                position -= 4
            if header is not None:
                blob, length, blocks = header
                for start, compressed, decompressed in blocks:
                    try:
                        found.append(lz4_block(data[start:start + compressed], decompressed))
                    except ValueError:
                        pass
                covered_to = blob + length
            else:
                # Text that is not in a blob (or in a layout not known): passed over.
                covered_to = at + 1
        at = data.find(ANCHOR, max(at + 1, covered_to))
    return found


def metal_sources(block):
    """The Metal sources in a decompressed block. A program is its length, then a header that gives where its
    entry point's name is (the first number after the magic, or in older players the second), the name, and
    the source to the program's end."""
    sources = []
    at = block.find(METAL_MAGIC)
    while at >= 0:
        if at >= 4 and at + 16 <= len(block):
            length = struct.unpack_from("<I", block, at - 4)[0]
            if 16 < length and at + length <= len(block):
                for candidate in struct.unpack_from("<II", block, at + 4):
                    if not 12 <= candidate < min(length, 4096):
                        continue
                    first = block[at + candidate]
                    if not (first == 0x5F or 0x41 <= first <= 0x5A or 0x61 <= first <= 0x7A):
                        continue
                    name_end = block.find(b"\0", at + candidate, at + length)
                    if name_end < 0:
                        continue
                    source = block[name_end + 1:at + length].rstrip(b"\0")
                    if source:
                        sources.append(source)
                    break
        at = block.find(METAL_MAGIC, at + 4)
    return sources


def embedded_sources(data):
    """Metal sources kept as plain text, as a plugin's own shaders are in its binary: each string that has the
    anchor in it, from the zero byte before to the one after."""
    sources = []
    at = data.find(ANCHOR)
    while at >= 0:
        start = data.rfind(b"\0", max(0, at - (1 << 20)), at) + 1
        end = data.find(b"\0", at, at + (1 << 20))
        if end < 0:
            end = min(len(data), at + (1 << 20))
        text = data[start:end]
        if all(byte in (9, 10, 13) or 32 <= byte <= 126 for byte in text):
            sources.append(text)
        at = data.find(ANCHOR, end)
    return sources


# MARK: Files

def files_to_read(root):
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            if name.endswith((".mp4", ".bank", ".png", ".jpg", ".resS", ".resource", ".dll", ".json", ".plist")):
                continue
            yield os.path.join(directory, name)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[-1])
    root, output = sys.argv[1], sys.argv[2]
    os.makedirs(output, exist_ok=True)
    sources = {}
    blobs = 0
    for path in files_to_read(root):
        try:
            with open(path, "rb") as file:
                data = file.read()
        except OSError:
            continue
        parts = [(path, data)]
        if data.startswith(b"UnityFS\0"):
            try:
                parts = [("%s/%s" % (path, name), part) for name, part in bundle_files(data)]
            except (ValueError, struct.error, lzma.LZMAError) as error:
                print("%s: not unpacked: %s" % (path, error), file=sys.stderr)
                continue
        for _, part in parts:
            if ANCHOR not in part:
                continue
            for block in shader_blocks(part):
                blobs += 1
                for source in metal_sources(block):
                    sources.setdefault(cache_key(source), source)
            for source in embedded_sources(part):
                sources.setdefault(cache_key(source), source)
    written = 0
    for key, source in sources.items():
        target = os.path.join(output, key + ".metal")
        if not os.path.exists(target):
            with open(target, "wb") as file:
                file.write(source)
            written += 1
    print("%d sources in %d blocks, %d new in %s" % (len(sources), blobs, written, output))


if __name__ == "__main__":
    main()
