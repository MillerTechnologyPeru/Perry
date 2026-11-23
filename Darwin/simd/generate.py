#!/usr/bin/env python3
"""Writes Darwin/simd/Sources/*.generated.swift: every declaration of the SDK's
simd.swiftinterface (vector functions, the matrix types' initializers,
subscripts and operators, the element-wise math functions, quaternions),
with Perry's own bodies over simd's C header functions, so that the overlay
exports the symbols the SDK's does.

Usage: Darwin/simd/generate.py [path to simd's x86_64-apple-macos.swiftinterface]
"""
import re, sys, json
def strip_q(s):
    return re.sub(r'\b(Swift|simd|CoreFoundation|Darwin|_Concurrency)::', '', s)
def parse(text):
    """Split into a tree: list of nodes {head, body(None|str), children(None|list)}.
    Top-level items: attributes lines + decl. extension blocks have children."""
    lines = text.split('\n')
    i = 0
    out = []
    def read_block(i, depth_end):
        items = []
        attrs = []
        while i < len(lines):
            line = lines[i]
            s = line.strip()
            if s == '}' :
                return items, i + 1
            if s.startswith('//') or s.startswith('import ') or s.startswith('@_exported') or s == '':
                i += 1; continue
            if s.startswith('@') and not re.search(r'\b(public|internal|prefix|extension)\b', s):
                attrs.append(s); i += 1; continue
            # declaration
            if re.match(r'^(@.* )?(extension|public struct|public enum)\b', s) or s.startswith('extension '):
                head = s[:-1].strip() if s.endswith('{') else s
                if s.endswith('{'):
                    if s.endswith('{\n}'): pass
                    children, i = read_block(i + 1, None)
                else:
                    children = []; i += 1
                items.append({'attrs': attrs, 'head': head, 'children': children})
                attrs = []
                continue
            # member/func: find body
            if '{' in s:
                head = s[:s.index('{')].rstrip()
                # brace matching
                depth = 0; body = []
                j = i
                text_from = line[line.index('{'):]
                buf = text_from
                depth = buf.count('{') - buf.count('}')
                body.append(buf)
                j = i + 1
                while depth > 0:
                    l = lines[j]; body.append(l)
                    depth += l.count('{') - l.count('}')
                    j += 1
                items.append({'attrs': attrs, 'head': head, 'body': '\n'.join(body)})
                attrs = []
                i = j
            else:
                # bodyless decl, possibly var with { get } on following lines? handled above since '{' present
                items.append({'attrs': attrs, 'head': s, 'body': None})
                attrs = []
                i += 1
        return items, i
    items, _ = read_block(0, None)
    return items

import re, sys

# Types ----------------------------------------------------------------
def vec(t):
    """(scalar, n) for a vector type name, else None."""
    t = t.strip()
    m = re.fullmatch(r'SIMD(\d+)<(\w+)>', t)
    if m: return (m.group(2), int(m.group(1)))
    m = re.fullmatch(r'simd_(float|double|int|uint|long|ulong|short|ushort|char|uchar)(\d+)', t)
    if m:
        s = {'float':'Float','double':'Double','int':'Int32','uint':'UInt32','long':'Int','ulong':'UInt','short':'Int16','ushort':'UInt16','char':'Int8','uchar':'UInt8'}[m.group(1)]
        return (s, int(m.group(2)))
    return None

def mat(t):
    """(scalar word, columns, rows) for a matrix type name."""
    m = re.fullmatch(r'(?:simd_)?(float|double)(\d)x(\d)', t.strip())
    if m: return (m.group(1), int(m.group(2)), int(m.group(3)))
    return None

def matname(s, c, r): return 'simd_%s%dx%d' % (s, c, r)

def split_params(s):
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch in '(<[': depth += 1
        if ch in ')>]': depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur); cur = ''
        else: cur += ch
    if cur.strip(): out.append(cur)
    params = []
    for p in out:
        names, typ = p.split(':', 1)
        names = names.split()
        typ = typ.strip()
        if typ.startswith('inout '): typ = typ[6:]
        params.append((names[0], names[-1], typ))
    return params

def signature(head):
    """name, params, return type of a func/init/subscript/var head."""
    m = re.search(r'\b(func\s+(\S+)\s*|init|subscript)\s*(<[^(]*>)?\(', head)
    if m:
        name = m.group(2) if m.group(2) else m.group(1)
        start = m.end()
        depth = 1; i = start
        while depth:
            if head[i] == '(': depth += 1
            if head[i] == ')': depth -= 1
            i += 1
        params = split_params(head[start:i-1])
        rest = head[i:]
        rm = re.search(r'->\s*(.*)$', rest)
        return name, params, (rm.group(1).strip() if rm else None)
    m = re.search(r'\bvar\s+(\w+)\s*:\s*(.*)$', head)
    return m.group(1), [], m.group(2).strip()

def names(params): return [p[1] for p in params]

# Bodies ---------------------------------------------------------------
UNARY_TG = set('''ceil floor trunc round cos cosh cospi acos acosh sin sinh sinpi asin asinh tan tanh tanpi atan atanh
 exp exp2 exp10 expm1 log log2 log10 log1p lgamma tgamma erf erfc cbrt isfinite isinf isnan isnormal'''.split())
BINARY_TG = set('atan2 pow hypot fmod remainder nextafter fmin fmax'.split())
SIMD_UNARY = {'abs':'simd_abs','sign':'simd_sign','recip':'simd_recip','rsqrt':'simd_rsqrt','fract':'simd_fract',
  'reduce_add':'simd_reduce_add','reduce_min':'simd_reduce_min','reduce_max':'simd_reduce_max',
  'length':'simd_length','length_squared':'simd_length_squared','norm_one':'simd_norm_one','norm_inf':'simd_norm_inf',
  'normalize':'simd_normalize'}
SIMD_BINARY = {'dot':'simd_dot','project':'simd_project','distance':'simd_distance','distance_squared':'simd_distance_squared',
  'cross':'simd_cross'}

def splat(t, v):
    return '%s(repeating: %s)' % (t, v)

def global_body(name, params, ret):
    a = names(params)
    t0 = params[0][2] if params else None
    if name == 'sincos' or name == 'sincospi':
        return ['var s = %s()' % t0, 'var c = %s()' % t0, '__tg_%s(%s, &s, &c)' % (name, a[0]), 'return (s, c)']
    if name in ('min', 'max'):
        if params[1][2] != t0:
            return ['return simd_%s(%s, %s)' % (name, a[0], splat(t0, a[1]))]
        return ['return simd_%s(%s, %s)' % (name, a[0], a[1])]
    if name == 'clamp':
        if params[1][2] != t0:
            return ['return simd_clamp(%s, %s, %s)' % (a[0], splat(t0, a[1]), splat(t0, a[2]))]
        return ['return simd_clamp(%s, %s, %s)' % tuple(a)]
    if name == 'mix':
        t = a[2] if params[2][2] == t0 else splat(t0, a[2])
        return ['return simd_mix(%s, %s, %s)' % (a[0], a[1], t)]
    if name == 'step':
        return ['return simd_step(%s, %s)' % (a[1], a[0])]
    if name == 'smoothstep':
        return ['return simd_smoothstep(%s, %s, %s)' % (a[1], a[2], a[0])]
    if name == 'reflect':
        return ['return simd_reflect(%s, %s)' % (a[0], a[1])]
    if name == 'refract':
        return ['return simd_refract(%s, %s, %s)' % (a[0], a[1], a[2])]
    if name == 'fma':
        return ['return __tg_fma(%s, %s, %s)' % tuple(a)]
    if name == 'log' and t0.startswith('simd_quat'):
        return None  # written by hand
    if name == 'exp' and t0.startswith('simd_quat'):
        return ['return __tg_exp(%s)' % a[0]]
    if name == 'dot' and t0.startswith('simd_quat'):
        return ['return simd_dot(%s, %s)' % (a[0], a[1])]
    if name in SIMD_UNARY and len(a) == 1:
        return ['return %s(%s)' % (SIMD_UNARY[name], a[0])]
    if name in SIMD_BINARY:
        return ['return %s(%s, %s)' % (SIMD_BINARY[name], a[0], a[1])]
    if name in UNARY_TG and len(a) == 1:
        return ['return __tg_%s(%s)' % (name, a[0])]
    if name in BINARY_TG:
        return ['return __tg_%s(%s, %s)' % (name, a[0], a[1])]
    # deprecated matrix_ functions
    if name.startswith('matrix_'):
        if name == 'matrix_from_diagonal': return ['return %s(diagonal: %s)' % (ret, a[0])]
        if name == 'matrix_invert': return ['return simd_inverse(%s)' % a[0]]
        if name == 'matrix_determinant': return ['return simd_determinant(%s)' % a[0]]
        if name == 'matrix_transpose': return ['return simd_transpose(%s)' % a[0]]
        if name == 'matrix_equal': return ['return simd_equal(%s, %s)' % (a[0], a[1])]
        if name == 'matrix_from_columns': return ['return %s(%s)' % (ret, ', '.join(a))]
        if name == 'matrix_from_rows':
            s, c, r = mat(ret)
            return ['return simd_transpose(%s(%s))' % (matname(s, r, c), ', '.join(a))]
    raise Exception('no global body for %s %s' % (name, params))

def matrix_body(T, name, params, ret, head, accessor=None):
    s, C, R = mat(T)
    a = names(params)
    V = 'SIMD%d<%s>' % (R, 'Float' if s == 'float' else 'Double')
    if name == 'init':
        if len(params) == 1 and params[0][0] == '_' and params[0][2] in ('Float', 'Double'):
            D = 'SIMD%d<%s>' % (min(C, R), 'Float' if s == 'float' else 'Double')
            return ['self.init(diagonal: %s)' % splat(D, a[0])]
        if params[0][0] == 'diagonal':
            return ['self.init()'] + ['self.columns.%d[%d] = diagonal[%d]' % (i, i, i) for i in range(min(C, R))]
        if params[0][0] == '_' and params[0][2].startswith('['):
            return ['precondition(%s.count == %d, "a %s needs %d columns")' % (a[0], C, T, C),
                    'self.init(columns: (%s))' % ', '.join('%s[%d]' % (a[0], i) for i in range(C))]
        if params[0][0] == 'rows':
            return ['precondition(rows.count == %d, "a %s needs %d rows")' % (R, T, R),
                    'self = simd_transpose(%s(rows))' % matname(s, R, C)]
        if len(params) == C and all(p[0] == '_' for p in params):
            return ['self.init(columns: (%s))' % ', '.join(a)]
        if len(params) == 1 and mat(params[0][2]):
            return ['self = %s' % a[0]]
        if params[0][2].startswith('simd_quat'):
            return ['self = simd_matrix%dx%d(%s)' % (C, R, a[0])]
    if name == 'cmatrix': return ['return self']
    if name == 'transpose': return ['return simd_transpose(self)']
    if name == 'inverse': return ['return simd_inverse(self)']
    if name == 'determinant': return ['return simd_determinant(self)']
    if name == 'debugDescription':
        cols = ', '.join('\\(columns.%d._descriptionAsArray)' % i for i in range(C))
        return ['return "%s([%s])"' % (T, cols)]
    if name == '==': return ['return simd_equal(lhs, rhs)']
    if name == '+': return ['return simd_add(lhs, rhs)']
    if name == '-':
        if len(params) == 1: return ['return simd_sub(%s(), rhs)' % T]
        return ['return simd_sub(lhs, rhs)']
    if name in ('+=', '-=', '*='):
        return ['lhs = lhs %s rhs' % name[0]]
    if name == '*':
        if params[1][2] in ('Float', 'Double'):
            return ['return simd_mul(rhs, lhs)']
        return ['return simd_mul(lhs, rhs)']
    raise Exception('no matrix body for %s %s %s' % (T, name, params))

def quat_body(T, name, params, ret, head):
    a = names(params)
    sc = 'Float' if T == 'simd_quatf' else 'Double'
    if name == 'init':
        if params[0][0] == 'ix': return ['self.init(vector: SIMD4<%s>(ix, iy, iz, r))' % sc]
        if params[0][0] == 'real': return ['self.init(vector: SIMD4<%s>(imag.x, imag.y, imag.z, real))' % sc]
        if params[0][0] == 'angle': return ['self = simd_quaternion(angle, axis)']
        if params[0][0] == 'from': return ['self = simd_quaternion(from, to)']
        if mat(params[0][2]): return ['self = simd_quaternion(%s)' % a[0]]
    simple = {'angle':'simd_angle(self)','axis':'simd_axis(self)','conjugate':'simd_conjugate(self)',
              'inverse':'simd_inverse(self)','normalized':'simd_normalize(self)','length':'simd_length(self)'}
    if name in simple: return ['return ' + simple[name]]
    if name == 'act': return ['return simd_act(self, %s)' % a[0]]
    if name == '==': return ['return lhs.vector == rhs.vector']
    if name == '+': return ['return simd_add(lhs, rhs)']
    if name == '-':
        if len(params) == 1: return ['return simd_sub(%s(), rhs)' % T]
        return ['return simd_sub(lhs, rhs)']
    if name == '*': return ['return simd_mul(lhs, rhs)']
    if name == '/':
        if params[1][2] == sc: return ['return %s(vector: lhs.vector / rhs)' % T]
        return ['return simd_mul(lhs, rhs.inverse)']
    if name in ('+=', '-=', '*=', '/='): return ['lhs = lhs %s rhs' % name[0]]
    if name == 'hash': return ['hasher.combine(vector)']
    if name == 'hashValue': return ['var hasher = Hasher()', 'hash(into: &hasher)', 'return hasher.finalize()']
    if name == 'debugDescription': return ['return "%s(real: \\(real), imag: \\(imag))"' % T]
    raise Exception('no quaternion body for %s %s' % (name, params))

HAND = {}  # (ctx, name) -> lines written by hand

def member_body(ctx, it, head):
    name, params, ret = signature(head)
    T = ctx.split()[1] if ctx else None
    if T and T.startswith('simd_quat'):
        return name, quat_body(T, name, params, ret, head)
    if T and mat(T):
        return name, matrix_body(T, name, params, ret, head)
    return name, None

def emit_accessor_member(ctx, it, head, out, ind):
    """A subscript or a var with get/set accessors in the interface's body."""
    name, params, ret = signature(head)
    T = ctx.split()[1]
    body = it['body']
    if name not in ('subscript', 'real', 'imag'):
        return False
    out.append(ind + head + ' {')
    if name == 'subscript' and len(params) == 1:
        s, C, R = mat(T)
        out.append(ind + '  get {')
        out.append(ind + '    switch column {')
        for i in range(C): out.append(ind + '    case %d: return columns.%d' % (i, i))
        out.append(ind + '    default: preconditionFailure("column index out of range")')
        out.append(ind + '    }')
        out.append(ind + '  }')
        out.append(ind + '  set {')
        out.append(ind + '    switch column {')
        for i in range(C): out.append(ind + '    case %d: columns.%d = newValue' % (i, i))
        out.append(ind + '    default: preconditionFailure("column index out of range")')
        out.append(ind + '    }')
        out.append(ind + '  }')
    elif name == 'subscript':
        out.append(ind + '  get { return self[column][row] }')
        out.append(ind + '  set { self[column][row] = newValue }')
    elif name == 'real':
        out.append(ind + '  get { return vector.w }')
        out.append(ind + '  set { vector.w = newValue }')
    elif name == 'imag':
        out.append(ind + '  get { return %s(vector.x, vector.y, vector.z) }' % ret)
        out.append(ind + '  set { vector = SIMD4(newValue.x, newValue.y, newValue.z, vector.w) }')
    else:
        return False
    out.append(ind + '}')
    return True

def clean_head(h):
    return strip_q(h)

def generate(items):
    files = {'Vector': [], 'Math': [], 'Matrix': [], 'Quaternion': [], 'SIMD': []}
    cur = 'Vector'
    def put(f, lines): files[f].extend(lines)
    for it in items:
        if 'children' in it:
            ctx = clean_head(it['head'])
            T = ctx.split()[1]
            f = 'Quaternion' if T.startswith('simd_quat') else 'Matrix' if mat(T) else 'SIMD'
            out = [a for a in it['attrs']]
            out.append(ctx + ' {')
            for m in it['children']:
                head = clean_head(m['head'])
                for a in m['attrs']: out.append('  ' + a)
                if head.startswith('@inlinable internal var _descriptionAsArray'):
                    n = int(T[4])
                    comps = ', '.join('\\(%s)' % c for c in 'xyzw'[:n])
                    out.append('  ' + head + ' {')
                    out.append('    return "[%s]"' % comps)
                    out.append('  }')
                    continue
                if 'init(_ scalar: Self.Scalar)' in head:
                    out += ['  ' + head + ' {', '    self.init(repeating: scalar)', '  }']; continue
                if 'prefix public static func - (rhs: Self)' in head:
                    out += ['  ' + head + ' {', '    return 0 &- rhs', '  }']; continue
                if m.get('body') is not None and re.search(r'\b(get|set)\b', m['body']) and ('subscript' in head or ' var ' in head):
                    if emit_accessor_member(ctx, m, head, out, '  '):
                        continue
                name, body = member_body(ctx, m, head)
                if body is None:
                    raise Exception('no body: %s %s' % (ctx, head))
                if ' var ' in head:
                    out.append('  ' + head + ' {')
                else:
                    out.append('  ' + head + ' {')
                out += ['    ' + l for l in body]
                out.append('  }')
            out.append('}')
            put(f, out)
            continue
        head = clean_head(it['head'])
        if head.startswith('public typealias') or 'typealias' in head:
            put('Matrix' if re.search(r'x\d =', head) else 'Vector', it['attrs'] + [head]); continue
        name, params, ret = signature(head)
        t0 = params[0][2] if params else ''
        if t0.startswith('simd_quat'): f = 'Quaternion'
        elif name.startswith('matrix_'): f = 'Matrix'
        elif t0.startswith('simd_'): f = 'Math'
        else: f = 'Vector'
        body = global_body(name, params, ret)
        if body is None:
            continue
        put(f, it['attrs'] + [head + ' {'] + ['  ' + l for l in body] + ['}'])
    return files


HEADER = """// Generated by Darwin/simd/generate.py from the declarations in the macOS
// SDK's simd.swiftinterface; the bodies are the generator's, over simd's C
// functions. Edit the generator, not this file.
"""

if __name__ == '__main__':
    import os, subprocess
    here = os.path.dirname(os.path.abspath(__file__))
    if len(sys.argv) > 1:
        interface = sys.argv[1]
    else:
        sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
        interface = os.path.join(sdk, 'usr/lib/swift/simd.swiftmodule/x86_64-apple-macos.swiftinterface')
    files = generate(parse(open(interface).read()))
    for k, v in files.items():
        with open(os.path.join(here, 'Sources', k + '.generated.swift'), 'w') as f:
            f.write(HEADER + 'import Darwin\n\n' + '\n'.join(v) + '\n')
