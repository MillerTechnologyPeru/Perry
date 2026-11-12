// Darwin's i386 calls into Linux's steamclient.so, for interfaces handed
// out as proxies: { vtable, object }, whose vtable is these stubs.
//
// A forward stub puts the client's object where the proxy was (the first
// argument, `this`) and goes on to the client's method in the same slot.
//
// A struct-return stub is for the methods that return a CSteamID: Darwin
// returns an 8-byte struct in eax:edx, Linux through a pointer passed
// before `this`, which the callee pops. It calls the client's method with a
// pointer to its own result, passing on the caller's next four words (as
// many as any of those methods take), and returns the result in eax:edx.
// The call is made with the stack aligned to 16 bytes.

#if defined(__i386__) && defined(__ELF__)

    .text

    .globl perry_steam_forward_stubs
    .hidden perry_steam_forward_stubs
    .p2align 5
perry_steam_forward_stubs:
    .set slot, 0
    .rept 128
    .p2align 5
    movl 4(%esp), %eax          // the proxy
    movl 4(%eax), %eax          // the client's object
    movl %eax, 4(%esp)
    movl (%eax), %eax
    jmp *(slot * 4)(%eax)
    .set slot, slot + 1
    .endr

    .globl perry_steam_sret_stubs
    .hidden perry_steam_sret_stubs
    .p2align 6
perry_steam_sret_stubs:
    .set slot, 0
    .rept 128
    .p2align 6
    pushl %ebp
    movl %esp, %ebp
    subl $16, %esp              // the result, at -8(%ebp)
    pushl 24(%ebp)
    pushl 20(%ebp)
    pushl 16(%ebp)
    pushl 12(%ebp)
    movl 8(%ebp), %eax
    movl 4(%eax), %eax          // the client's object, as `this`
    pushl %eax
    leal -8(%ebp), %ecx
    pushl %ecx                  // where the result goes
    movl (%eax), %eax
    call *(slot * 4)(%eax)
    movl -8(%ebp), %eax
    movl -4(%ebp), %edx
    leave
    ret
    .set slot, slot + 1
    .endr

#endif

#if defined(__ELF__)
    .section .note.GNU-stack, "", %progbits
#endif
