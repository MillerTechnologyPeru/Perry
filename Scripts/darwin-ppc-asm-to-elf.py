# Turns Darwin ppc assembly (Apple GCC's cc1) into GNU as ELF syntax, so code
# Apple's compiler made can be linked into a Linux test: ha16/lo16 become
# @ha/@l, Mach-O sections ELF ones, non-lazy pointers plain words, and
# .comm alignments bytes.
#
# usage: darwin-ppc-asm-to-elf.py in.s out.s
import re, sys
out = []
lines = open(sys.argv[1]).read().split('\n')
i = 0
while i < len(lines):
    l = lines[i]
    l = re.sub(r'ha16\(([^)]*)\)', r'\1@ha', l)
    l = re.sub(r'hi16\(([^)]*)\)', r'\1@h', l)
    l = re.sub(r'lo16\(([^)]*)\)', r'\1@l', l)
    l = l.replace('$non_lazy_ptr', '_nlp')
    s = l.strip()
    if s.startswith('.subsections_via_symbols') or s.startswith('.machine'):
        i += 1; continue
    if s.startswith('.section __TEXT,__text') or s.startswith('.section __TEXT,__symbol_stub'):
        out.append('\t.text'); i += 1; continue
    if s in ('.const', '.cstring', '.literal4', '.literal8', '.literal16') or s.startswith('.section __TEXT,__const'):
        out.append('\t.section .rodata'); i += 1; continue
    if s == '.non_lazy_symbol_pointer':
        out.append('\t.data'); i += 1; continue
    if s == '.data':
        out.append('\t.data'); i += 1; continue
    m = re.match(r'\.indirect_symbol\s+(\S+)', s)
    if m:
        # the following ".long 0" becomes the symbol's address
        sym = m.group(1)
        i += 1
        if i < len(lines) and lines[i].strip().replace('\t', ' ') == '.long 0':
            out.append('\t.long ' + sym); i += 1
        continue
    m = re.match(r'\.comm\s+(\S+),(\d+),(\d+)', s)
    if m:
        out.append('\t.comm %s,%s,%d' % (m.group(1), m.group(2), 1 << int(m.group(3)))); i += 1; continue
    out.append(l)
    i += 1
out.append('\t.section .note.GNU-stack,"",@progbits')
open(sys.argv[2], 'w').write('\n'.join(out) + '\n')
