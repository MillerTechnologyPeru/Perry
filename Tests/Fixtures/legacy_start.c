// How i386 Mac programs begin: an LC_UNIXTHREAD entry at crt1's start, with
// argc on top of the stack, and __TEXT at the default 0x1000.
#include "darwin.h"

__asm__(
    ".text\n.globl start\nstart:\n"
    "    pushl $0\n"
    "    movl %esp, %ebp\n"
    "    andl $-16, %esp\n"
    "    subl $16, %esp\n"
    "    movl 4(%ebp), %ebx\n"
    "    movl %ebx, 0(%esp)\n"
    "    leal 8(%ebp), %ecx\n"
    "    movl %ecx, 4(%esp)\n"
    "    addl $1, %ebx\n"
    "    sall $2, %ebx\n"
    "    addl %ecx, %ebx\n"
    "    movl %ebx, 8(%esp)\n"
    "    call _main\n"
    "    movl %eax, (%esp)\n"
    "    call _exit\n"
    "    hlt\n");

char *getenv(const char *);

int main(int argc, char **argv, char **envp) {
    int stack;
    printf("loaded at %p aligned %d\n", (void *)main < (void *)0x10000 ? (void *)0x1000 : (void *)0, ((unsigned long)&stack & 3) == 0);
    printf("argc %d last %s\n", argc, argv[argc - 1]);
    int found = 0;
    for (char **e = envp; *e; e++)
        if (strcmp(*e, "PERRY_LEGACY_START=1") == 0) found = 1;
    printf("envp %d getenv %s\n", found, getenv("PERRY_LEGACY_START"));
    return 5;
}
