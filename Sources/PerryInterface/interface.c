#include "perry_interface.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

// The file an address is mapped from, and its offset in the file.
static void describe_frame(int index, uintptr_t address) {
    FILE *maps = fopen("/proc/self/maps", "r");
    char line[1024];
    while (maps && fgets(line, sizeof(line), maps)) {
        unsigned long start, end, offset;
        char path[768] = "";
        if (sscanf(line, "%lx-%lx %*s %lx %*s %*s %767[^\n]", &start, &end, &offset, path) < 3)
            continue;
        if (address < start || address >= end)
            continue;
        const char *name = strrchr(path, '/');
        fprintf(stderr, "  #%-2d 0x%016lx %s+0x%lx\n", index, (unsigned long)address, name ? name + 1 : path,
                (unsigned long)(address - start + offset));
        fclose(maps);
        return;
    }
    if (maps)
        fclose(maps);
    fprintf(stderr, "  #%-2d 0x%016lx\n", index, (unsigned long)address);
}

void perry_print_frames(const char *title) {
    fprintf(stderr, "%s\n", title);
    // Frame records are {previous fp, return address}, ascending the stack.
    uintptr_t fp = (uintptr_t)__builtin_frame_address(0), low = fp;
    for (int frame = 0; frame < 32 && fp && (fp & 7) == 0 && fp >= low && fp - low < (64 << 20); frame++) {
        uintptr_t *record = (uintptr_t *)fp;
        uintptr_t next = record[0], ret = record[1];
        if (!ret)
            break;
        describe_frame(frame, ret);
        low = fp;
        fp = next;
    }
}
