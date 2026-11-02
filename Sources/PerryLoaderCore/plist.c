#define _GNU_SOURCE
#include "plist.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static perry_plist *new_node(perry_plist_type type) {
    perry_plist *node = calloc(1, sizeof(*node));
    node->type = type;
    return node;
}

static void container_append(perry_plist *container, char *key, perry_plist *value) {
    size_t n = container->container.count;
    container->container.values = realloc(container->container.values, sizeof(perry_plist *) * (n + 1));
    container->container.values[n] = value;
    if (container->type == PERRY_PLIST_DICT) {
        container->container.keys = realloc(container->container.keys, sizeof(char *) * (n + 1));
        container->container.keys[n] = key;
    }
    container->container.count = n + 1;
}

void perry_plist_free(perry_plist *plist) {
    if (!plist)
        return;
    switch (plist->type) {
    case PERRY_PLIST_STRING:
        free(plist->string);
        break;
    case PERRY_PLIST_DATA:
        free(plist->data.bytes);
        break;
    case PERRY_PLIST_ARRAY:
    case PERRY_PLIST_DICT:
        for (size_t i = 0; i < plist->container.count; i++) {
            perry_plist_free(plist->container.values[i]);
            if (plist->container.keys)
                free(plist->container.keys[i]);
        }
        free(plist->container.values);
        free(plist->container.keys);
        break;
    default:
        break;
    }
    free(plist);
}

const perry_plist *perry_plist_get(const perry_plist *dict, const char *key) {
    if (!dict || dict->type != PERRY_PLIST_DICT)
        return NULL;
    for (size_t i = 0; i < dict->container.count; i++)
        if (strcmp(dict->container.keys[i], key) == 0)
            return dict->container.values[i];
    return NULL;
}

const char *perry_plist_get_string(const perry_plist *dict, const char *key) {
    const perry_plist *value = perry_plist_get(dict, key);
    return value && value->type == PERRY_PLIST_STRING ? value->string : NULL;
}

// MARK: - UTF-8 helpers

static void append_utf8(char **buf, size_t *len, size_t *cap, uint32_t cp) {
    if (*len + 5 > *cap) {
        *cap = (*cap + 5) * 2;
        *buf = realloc(*buf, *cap);
    }
    char *p = *buf + *len;
    if (cp < 0x80) {
        p[0] = (char)cp;
        *len += 1;
    } else if (cp < 0x800) {
        p[0] = (char)(0xc0 | (cp >> 6));
        p[1] = (char)(0x80 | (cp & 0x3f));
        *len += 2;
    } else if (cp < 0x10000) {
        p[0] = (char)(0xe0 | (cp >> 12));
        p[1] = (char)(0x80 | ((cp >> 6) & 0x3f));
        p[2] = (char)(0x80 | (cp & 0x3f));
        *len += 3;
    } else {
        p[0] = (char)(0xf0 | (cp >> 18));
        p[1] = (char)(0x80 | ((cp >> 12) & 0x3f));
        p[2] = (char)(0x80 | ((cp >> 6) & 0x3f));
        p[3] = (char)(0x80 | (cp & 0x3f));
        *len += 4;
    }
    (*buf)[*len] = 0;
}

static void append_byte(char **buf, size_t *len, size_t *cap, char c) {
    if (*len + 2 > *cap) {
        *cap = (*cap + 2) * 2;
        *buf = realloc(*buf, *cap);
    }
    (*buf)[(*len)++] = c;
    (*buf)[*len] = 0;
}

// MARK: - Binary plist

typedef struct bplist {
    const uint8_t *bytes;
    size_t length;
    const uint8_t *offsets;
    uint8_t offset_size;
    uint8_t ref_size;
    uint64_t object_count;
    const char *error;
} bplist;

static uint64_t read_be(const uint8_t *p, unsigned size) {
    uint64_t v = 0;
    for (unsigned i = 0; i < size; i++)
        v = (v << 8) | p[i];
    return v;
}

static perry_plist *bplist_object(bplist *bp, uint64_t index, int depth);

static bool bplist_count(bplist *bp, const uint8_t **p, uint8_t low, uint64_t *count) {
    if (low != 0xf) {
        *count = low;
        return true;
    }
    const uint8_t *q = *p;
    if (q >= bp->bytes + bp->length || (*q & 0xf0) != 0x10)
        return false;
    unsigned size = 1u << (*q & 0x0f);
    if (size > 8 || q + 1 + size > bp->bytes + bp->length)
        return false;
    *count = read_be(q + 1, size);
    *p = q + 1 + size;
    return true;
}

static perry_plist *bplist_object(bplist *bp, uint64_t index, int depth) {
    if (index >= bp->object_count || depth > 64) {
        bp->error = "invalid object reference";
        return NULL;
    }
    uint64_t offset = read_be(bp->offsets + index * bp->offset_size, bp->offset_size);
    if (offset >= bp->length) {
        bp->error = "object offset out of range";
        return NULL;
    }
    const uint8_t *end = bp->bytes + bp->length;
    const uint8_t *p = bp->bytes + offset;
    uint8_t marker = *p++;
    uint8_t high = marker >> 4, low = marker & 0x0f;
    uint64_t count;
    perry_plist *node;

    switch (high) {
    case 0x0:
        if (marker == 0x08 || marker == 0x09) {
            node = new_node(PERRY_PLIST_BOOL);
            node->boolean = marker == 0x09;
            return node;
        }
        break;
    case 0x1: {
        unsigned size = 1u << low;
        if (size > 16 || p + size > end)
            break;
        node = new_node(PERRY_PLIST_INTEGER);
        // 16-byte integers hold the value in the low 8 bytes.
        node->integer = (int64_t)read_be(p + (size > 8 ? size - 8 : 0), size > 8 ? 8 : size);
        return node;
    }
    case 0x2:
    case 0x3: {
        unsigned size = 1u << low;
        if ((size != 4 && size != 8) || p + size > end)
            break;
        node = new_node(high == 0x2 ? PERRY_PLIST_REAL : PERRY_PLIST_DATE);
        uint64_t bits = read_be(p, size);
        if (size == 4) {
            float f;
            uint32_t b32 = (uint32_t)bits;
            memcpy(&f, &b32, 4);
            node->real = f;
        } else {
            memcpy(&node->real, &bits, 8);
        }
        return node;
    }
    case 0x4:
        if (!bplist_count(bp, &p, low, &count) || p + count > end)
            break;
        node = new_node(PERRY_PLIST_DATA);
        node->data.bytes = malloc(count ? count : 1);
        memcpy(node->data.bytes, p, count);
        node->data.length = count;
        return node;
    case 0x5:
        if (!bplist_count(bp, &p, low, &count) || p + count > end)
            break;
        node = new_node(PERRY_PLIST_STRING);
        node->string = strndup((const char *)p, count);
        return node;
    case 0x6: {
        if (!bplist_count(bp, &p, low, &count) || p + count * 2 > end)
            break;
        char *buf = NULL;
        size_t len = 0, cap = 0;
        append_utf8(&buf, &len, &cap, 0);
        len = 0;
        for (uint64_t i = 0; i < count; i++) {
            uint32_t cp = (uint32_t)read_be(p + i * 2, 2);
            if (cp >= 0xd800 && cp < 0xdc00 && i + 1 < count) {
                uint32_t lo = (uint32_t)read_be(p + (i + 1) * 2, 2);
                if (lo >= 0xdc00 && lo < 0xe000) {
                    cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
                    i++;
                }
            }
            append_utf8(&buf, &len, &cap, cp);
        }
        node = new_node(PERRY_PLIST_STRING);
        node->string = buf;
        return node;
    }
    case 0x8: {
        unsigned size = low + 1u;
        if (size > 8 || p + size > end)
            break;
        node = new_node(PERRY_PLIST_UID);
        node->integer = (int64_t)read_be(p, size);
        return node;
    }
    case 0xa:
    case 0xd: {
        bool dict = high == 0xd;
        if (!bplist_count(bp, &p, low, &count) || p + count * bp->ref_size * (dict ? 2 : 1) > end)
            break;
        node = new_node(dict ? PERRY_PLIST_DICT : PERRY_PLIST_ARRAY);
        for (uint64_t i = 0; i < count; i++) {
            char *key = NULL;
            if (dict) {
                perry_plist *k = bplist_object(bp, read_be(p + i * bp->ref_size, bp->ref_size), depth + 1);
                if (!k || k->type != PERRY_PLIST_STRING) {
                    perry_plist_free(k);
                    perry_plist_free(node);
                    bp->error = bp->error ? bp->error : "dictionary key is not a string";
                    return NULL;
                }
                key = k->string;
                k->string = NULL;
                perry_plist_free(k);
            }
            const uint8_t *ref = p + (dict ? count + i : i) * bp->ref_size;
            perry_plist *value = bplist_object(bp, read_be(ref, bp->ref_size), depth + 1);
            if (!value) {
                free(key);
                perry_plist_free(node);
                return NULL;
            }
            container_append(node, key, value);
        }
        return node;
    }
    default:
        break;
    }
    bp->error = bp->error ? bp->error : "malformed binary plist object";
    return NULL;
}

static perry_plist *parse_binary(const uint8_t *bytes, size_t length, const char **error) {
    if (length < 8 + 32) {
        *error = "binary plist too short";
        return NULL;
    }
    const uint8_t *trailer = bytes + length - 32;
    bplist bp = {
        .bytes = bytes,
        .length = length,
        .offset_size = trailer[6],
        .ref_size = trailer[7],
        .object_count = read_be(trailer + 8, 8),
    };
    uint64_t top = read_be(trailer + 16, 8);
    uint64_t table = read_be(trailer + 24, 8);
    if (bp.offset_size == 0 || bp.offset_size > 8 || bp.ref_size == 0 || bp.ref_size > 8 ||
        table >= length || bp.object_count > (length - table) / bp.offset_size) {
        *error = "invalid binary plist trailer";
        return NULL;
    }
    bp.offsets = bytes + table;
    perry_plist *root = bplist_object(&bp, top, 0);
    if (!root)
        *error = bp.error;
    return root;
}

// MARK: - XML plist

typedef struct xml {
    const char *p;
    const char *end;
    const char *error;
} xml;

static void xml_skip_space(xml *x) {
    while (x->p < x->end && isspace((unsigned char)*x->p))
        x->p++;
}

static bool xml_starts(xml *x, const char *s) {
    size_t n = strlen(s);
    return (size_t)(x->end - x->p) >= n && memcmp(x->p, s, n) == 0;
}

static bool xml_skip_past(xml *x, const char *s) {
    const char *found = memmem(x->p, (size_t)(x->end - x->p), s, strlen(s));
    if (!found)
        return false;
    x->p = found + strlen(s);
    return true;
}

// Skips the prolog, comments, doctype and processing instructions.
static void xml_skip_misc(xml *x) {
    for (;;) {
        xml_skip_space(x);
        if (xml_starts(x, "<?")) {
            if (!xml_skip_past(x, "?>"))
                return;
        } else if (xml_starts(x, "<!--")) {
            if (!xml_skip_past(x, "-->"))
                return;
        } else if (xml_starts(x, "<!")) {
            if (!xml_skip_past(x, ">"))
                return;
        } else {
            return;
        }
    }
}

// Reads a tag like <name>, <name/> or </name>. Attributes are ignored.
static bool xml_tag(xml *x, char *name, size_t size, bool *closing, bool *empty) {
    xml_skip_misc(x);
    if (x->p >= x->end || *x->p != '<')
        return false;
    x->p++;
    *closing = x->p < x->end && *x->p == '/';
    if (*closing)
        x->p++;
    size_t n = 0;
    while (x->p < x->end && (isalnum((unsigned char)*x->p) || *x->p == '_' || *x->p == '-')) {
        if (n + 1 < size)
            name[n++] = *x->p;
        x->p++;
    }
    name[n] = 0;
    const char *gt = memchr(x->p, '>', (size_t)(x->end - x->p));
    if (!gt)
        return false;
    *empty = gt > x->p && gt[-1] == '/';
    x->p = gt + 1;
    return n > 0;
}

// Reads character data up to the next '<' and decodes entities.
static char *xml_text(xml *x) {
    char *buf = NULL;
    size_t len = 0, cap = 0;
    append_utf8(&buf, &len, &cap, 0);
    len = 0;
    while (x->p < x->end && *x->p != '<') {
        if (*x->p == '&') {
            const char *semi = memchr(x->p, ';', (size_t)(x->end - x->p));
            if (!semi) {
                x->error = "unterminated entity";
                free(buf);
                return NULL;
            }
            size_t n = (size_t)(semi - x->p - 1);
            const char *e = x->p + 1;
            uint32_t cp = 0;
            if (n == 3 && memcmp(e, "amp", 3) == 0) cp = '&';
            else if (n == 2 && memcmp(e, "lt", 2) == 0) cp = '<';
            else if (n == 2 && memcmp(e, "gt", 2) == 0) cp = '>';
            else if (n == 4 && memcmp(e, "quot", 4) == 0) cp = '"';
            else if (n == 4 && memcmp(e, "apos", 4) == 0) cp = '\'';
            else if (n > 1 && e[0] == '#')
                cp = (uint32_t)(e[1] == 'x' ? strtoul(e + 2, NULL, 16) : strtoul(e + 1, NULL, 10));
            else {
                x->error = "unknown entity";
                free(buf);
                return NULL;
            }
            append_utf8(&buf, &len, &cap, cp);
            x->p = semi + 1;
        } else {
            // The document is UTF-8 already; copy bytes through.
            append_byte(&buf, &len, &cap, *x->p++);
        }
    }
    return buf;
}

static bool xml_expect_close(xml *x, const char *name) {
    char tag[32];
    bool closing, empty;
    if (!xml_tag(x, tag, sizeof(tag), &closing, &empty) || !closing || strcmp(tag, name) != 0) {
        x->error = "mismatched closing tag";
        return false;
    }
    return true;
}

static size_t base64_decode(const char *in, uint8_t *out) {
    uint32_t acc = 0;
    int bits = 0;
    size_t n = 0;
    for (; *in; in++) {
        int v;
        char c = *in;
        if (c >= 'A' && c <= 'Z') v = c - 'A';
        else if (c >= 'a' && c <= 'z') v = c - 'a' + 26;
        else if (c >= '0' && c <= '9') v = c - '0' + 52;
        else if (c == '+') v = 62;
        else if (c == '/') v = 63;
        else continue;
        acc = (acc << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out[n++] = (uint8_t)(acc >> bits);
        }
    }
    return n;
}

static perry_plist *xml_value(xml *x, const char *tag, bool empty, int depth);

static perry_plist *xml_next_value(xml *x, int depth) {
    char tag[32];
    bool closing, empty;
    if (!xml_tag(x, tag, sizeof(tag), &closing, &empty) || closing) {
        x->error = x->error ? x->error : "expected a value";
        return NULL;
    }
    return xml_value(x, tag, empty, depth);
}

static perry_plist *xml_value(xml *x, const char *tag, bool empty, int depth) {
    if (depth > 64) {
        x->error = "plist nested too deeply";
        return NULL;
    }
    if (strcmp(tag, "true") == 0 || strcmp(tag, "false") == 0) {
        if (!empty && !xml_expect_close(x, tag))
            return NULL;
        perry_plist *node = new_node(PERRY_PLIST_BOOL);
        node->boolean = tag[0] == 't';
        return node;
    }
    if (strcmp(tag, "array") == 0 || strcmp(tag, "dict") == 0) {
        bool dict = tag[0] == 'd';
        perry_plist *node = new_node(dict ? PERRY_PLIST_DICT : PERRY_PLIST_ARRAY);
        if (empty)
            return node;
        for (;;) {
            char child[32];
            bool closing, child_empty;
            if (!xml_tag(x, child, sizeof(child), &closing, &child_empty)) {
                x->error = x->error ? x->error : "unterminated container";
                perry_plist_free(node);
                return NULL;
            }
            if (closing) {
                if (strcmp(child, tag) != 0) {
                    x->error = "mismatched closing tag";
                    perry_plist_free(node);
                    return NULL;
                }
                return node;
            }
            char *key = NULL;
            if (dict) {
                if (strcmp(child, "key") != 0) {
                    x->error = "expected <key> in dictionary";
                    perry_plist_free(node);
                    return NULL;
                }
                key = child_empty ? strdup("") : xml_text(x);
                if (!key || (!child_empty && !xml_expect_close(x, "key"))) {
                    free(key);
                    perry_plist_free(node);
                    return NULL;
                }
                perry_plist *value = xml_next_value(x, depth + 1);
                if (!value) {
                    free(key);
                    perry_plist_free(node);
                    return NULL;
                }
                container_append(node, key, value);
            } else {
                perry_plist *value = xml_value(x, child, child_empty, depth + 1);
                if (!value) {
                    perry_plist_free(node);
                    return NULL;
                }
                container_append(node, NULL, value);
            }
        }
    }

    // Scalar elements with text content.
    char *text = empty ? strdup("") : xml_text(x);
    if (!text || (!empty && !xml_expect_close(x, tag))) {
        free(text);
        return NULL;
    }
    perry_plist *node;
    if (strcmp(tag, "string") == 0) {
        node = new_node(PERRY_PLIST_STRING);
        node->string = text;
        return node;
    }
    if (strcmp(tag, "integer") == 0) {
        node = new_node(PERRY_PLIST_INTEGER);
        node->integer = strtoll(text, NULL, 0);
    } else if (strcmp(tag, "real") == 0) {
        node = new_node(PERRY_PLIST_REAL);
        node->real = strtod(text, NULL);
    } else if (strcmp(tag, "date") == 0) {
        // ISO 8601 (YYYY-MM-DDTHH:MM:SSZ) converted to seconds since 2001-01-01.
        int y = 0, mo = 0, d = 0, h = 0, mi = 0, s = 0;
        sscanf(text, "%d-%d-%dT%d:%d:%d", &y, &mo, &d, &h, &mi, &s);
        long days = 0;
        for (int year = 2001; year < y; year++)
            days += (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 366 : 365;
        static const int month_days[] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        for (int m = 1; m < mo && m <= 12; m++)
            days += month_days[m - 1] + (m == 2 && y % 4 == 0 && (y % 100 != 0 || y % 400 == 0));
        days += d - 1;
        node = new_node(PERRY_PLIST_DATE);
        node->real = (double)days * 86400 + h * 3600 + mi * 60 + s;
    } else if (strcmp(tag, "data") == 0) {
        node = new_node(PERRY_PLIST_DATA);
        node->data.bytes = malloc(strlen(text) + 1);
        node->data.length = base64_decode(text, node->data.bytes);
    } else {
        free(text);
        x->error = "unknown plist element";
        return NULL;
    }
    free(text);
    return node;
}

static perry_plist *parse_xml(const uint8_t *bytes, size_t length, const char **error) {
    xml x = { (const char *)bytes, (const char *)bytes + length, NULL };
    char tag[32];
    bool closing, empty;
    if (!xml_tag(&x, tag, sizeof(tag), &closing, &empty) || closing) {
        *error = "not a property list";
        return NULL;
    }
    perry_plist *root;
    if (strcmp(tag, "plist") == 0) {
        root = xml_next_value(&x, 0);
        if (root && !xml_expect_close(&x, "plist")) {
            perry_plist_free(root);
            root = NULL;
        }
    } else {
        root = xml_value(&x, tag, empty, 0);
    }
    if (!root)
        *error = x.error ? x.error : "malformed XML plist";
    return root;
}

// MARK: - Entry points

perry_plist *perry_plist_parse(const uint8_t *bytes, size_t length, const char **error) {
    const char *ignored;
    if (!error)
        error = &ignored;
    *error = NULL;
    if (length >= 8 && memcmp(bytes, "bplist00", 8) == 0)
        return parse_binary(bytes, length, error);
    return parse_xml(bytes, length, error);
}

perry_plist *perry_plist_load(const char *path, const char **error) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        if (error)
            *error = "cannot open file";
        return NULL;
    }
    uint8_t *buf = NULL;
    size_t len = 0, cap = 0, n;
    do {
        if (len == cap) {
            cap = cap ? cap * 2 : 4096;
            buf = realloc(buf, cap);
        }
        n = fread(buf + len, 1, cap - len, f);
        len += n;
    } while (n > 0);
    fclose(f);
    perry_plist *plist = perry_plist_parse(buf, len, error);
    free(buf);
    return plist;
}
