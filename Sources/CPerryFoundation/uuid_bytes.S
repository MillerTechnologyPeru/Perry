// CFUUIDCreateWithBytes and CFUUIDGetConstantUUIDWithBytes, for arm64 ELF.
//
// Each takes an allocator and sixteen bytes. Apple's arm64 ABI passes the
// first seven bytes in w1-w7 and packs the other nine into consecutive
// bytes at the caller's sp, where Linux's would give each a slot of 8. So
// these entry points gather all sixteen into a buffer and pass the Swift
// functions a pointer to it. The other architectures pass each byte in a
// slot of its own on Darwin too, and Swift exports the functions there.

#if defined(__aarch64__) && defined(__ELF__)

    .text

.macro UUID_BYTES name, target
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    strb w1, [sp, #16]
    strb w2, [sp, #17]
    strb w3, [sp, #18]
    strb w4, [sp, #19]
    strb w5, [sp, #20]
    strb w6, [sp, #21]
    strb w7, [sp, #22]
    ldr x9, [x29, #32]              // bytes 7 to 14, at the caller's sp
    str x9, [sp, #23]
    ldrb w9, [x29, #40]             // byte 15
    strb w9, [sp, #31]
    add x1, sp, #16
    bl \target
    ldp x29, x30, [sp], #32
    ret
    .size \name, . - \name
.endm

UUID_BYTES _CFUUIDCreateWithBytes, perry_foundation_cf_uuid_create_with_bytes
UUID_BYTES _CFUUIDGetConstantUUIDWithBytes, perry_foundation_cf_uuid_constant_with_bytes

#endif
