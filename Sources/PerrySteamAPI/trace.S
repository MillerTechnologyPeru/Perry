// Traced Steam interfaces, for PERRY_STEAM_TRACE_CALLS.
//
// A traced interface is an object of the provider's whose vtable is these
// stubs. Each stub names its slot and goes to one entry, which keeps the
// arguments, asks perry_steam_trace_enter for the method (it points the
// call at the client's own object), calls it with the caller's stack as it
// was, then tells perry_steam_trace_leave what it returned, which gives
// back the caller's return address.

#if defined(__aarch64__) && defined(__ELF__)

    .text

    .p2align 2
    .type perry_steam_trace_entry, %function
perry_steam_trace_entry:
    sub sp, sp, #208
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    stp x8, x30, [sp, #64]
    stp q0, q1, [sp, #80]
    stp q2, q3, [sp, #112]
    stp q4, q5, [sp, #144]
    stp q6, q7, [sp, #176]
    mov x1, x16
    mov x2, x30
    mov x3, sp
    bl perry_steam_trace_enter
    mov x16, x0
    ldp x0, x1, [sp, #0]
    ldp x2, x3, [sp, #16]
    ldp x4, x5, [sp, #32]
    ldp x6, x7, [sp, #48]
    ldr x8, [sp, #64]
    ldp q0, q1, [sp, #80]
    ldp q2, q3, [sp, #112]
    ldp q4, q5, [sp, #144]
    ldp q6, q7, [sp, #176]
    add sp, sp, #208
    blr x16
    sub sp, sp, #96
    stp x0, x1, [sp, #0]
    stp q0, q1, [sp, #16]
    stp q2, q3, [sp, #48]
    bl perry_steam_trace_leave
    mov x30, x0
    ldp x0, x1, [sp, #0]
    ldp q0, q1, [sp, #16]
    ldp q2, q3, [sp, #48]
    add sp, sp, #96
    ret
    .size perry_steam_trace_entry, . - perry_steam_trace_entry

// 128 stubs of 8 bytes: slot i is perry_steam_trace_stubs + 8 * i.
    .p2align 3
    .globl perry_steam_trace_stubs
    .hidden perry_steam_trace_stubs
    .type perry_steam_trace_stubs, %function
perry_steam_trace_stubs:
    .set slot, 0
    .rept 128
    mov x16, #slot
    b perry_steam_trace_entry
    .set slot, slot + 1
    .endr
    .size perry_steam_trace_stubs, . - perry_steam_trace_stubs

#endif

    .section .note.GNU-stack, "", %progbits
