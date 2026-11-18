// The rest of Carbon's File Manager, over CoreServices' FSRefs (which name
// paths): FSSpecs, which name an item by its volume, its folder's ID and its
// name; files opened by reference number and read and written through it,
// as forks or the original way; folders' items, one by one or in bulk; and
// the parameter-block calls of the original File Manager. There is one
// volume, "Macintosh HD" (-100), the root of the file system, and folder
// IDs are folders' inodes, as CoreServices' catalog information gives them
// (the root's is 2, as HFS's is). There are no resource forks: a resource
// fork opens empty.

#include "PerryCarbon.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <time.h>
#include <unistd.h>

enum {
    dirFulErr = -33, dskFulErr = -34, nsvErr = -35, ioErr = -36, bdNamErr = -37, fnOpnErr = -38, eofErr = -39,
    posErr = -40, tmfoErr = -42, fnfErr = -43, wPrErr = -44, fLckdErr = -45, fBsyErr = -47, dupFNErr = -48,
    opWrErr = -49, rfNumErr = -51, permErr = -54, wrPermErr = -61, dirNFErr = -120, errFSForkNotFound = -1424,
    afpAccessDenied = -5000, errFSNoMoreItems = -1417,
};

#define ROOT_VOLUME (-100)
#define ROOT_DIRECTORY 2

#pragma pack(push, 2)
typedef struct {
    int16_t vRefNum;
    int32_t parID;
    unsigned char name[64];
} FSSpec;

typedef struct {
    uint16_t length;
    uint16_t unicode[255];
} HFSUniStr255;
#pragma pack(pop)

typedef struct { uint8_t hidden[80]; } FSRef;

// CoreServices' FSRef functions.
static int32_t make_ref(const char *path, FSRef *ref, Boolean *isDirectory) {
    static int32_t (*function)(const char *, FSRef *, Boolean *);
    if (!function) function = (int32_t (*)(const char *, FSRef *, Boolean *))carbon_function(CORESERVICES, "_FSPathMakeRef");
    return function ? function(path, ref, isDirectory) : unimpErr;
}

static bool ref_path(const FSRef *ref, char *path, size_t size) {
    static int32_t (*function)(const FSRef *, char *, uint32_t);
    if (!function) function = (int32_t (*)(const FSRef *, char *, uint32_t))carbon_function(CORESERVICES, "_FSRefMakePath");
    return ref && function && function(ref, path, (uint32_t)size) == noErr;
}

/// A new item's FSRef, which FSPathMakeRef makes only for items that exist.
static void store_ref(const char *path, FSRef *ref) { if (ref) make_ref(path, ref, NULL); }

static OSErr error_for(int error) {
    switch (error) {
    case ENOENT: return fnfErr;
    case ENOTDIR: return dirNFErr;
    case EEXIST: return dupFNErr;
    case EACCES: case EPERM: return permErr;
    case EROFS: return wPrErr;
    case ENOSPC: return dskFulErr;
    case EMFILE: case ENFILE: return tmfoErr;
    case EBUSY: return fBsyErr;
    case ENAMETOOLONG: return bdNamErr;
    default: return ioErr;
    }
}

// MARK: - Folder IDs

typedef struct { uint32_t id; char *path; } known_directory;
static known_directory *directories;
static size_t directory_count;

static uint32_t directory_id(const char *path) {
    struct stat info;
    if (stat(path, &info) != 0) return 0;
    uint32_t id = (uint32_t)info.st_ino;
    for (size_t index = 0; index < directory_count; index++)
        if (directories[index].id == id) return id;
    known_directory *grown = realloc(directories, (directory_count + 1) * sizeof *grown);
    if (!grown) return id;
    directories = grown;
    directories[directory_count++] = (known_directory){id, strdup(path)};
    return id;
}

/// A folder `depth` levels below `folder` whose inode is `identifier`, as
/// a path to free; symbolic links to folders are followed.
static char *find_directory(const char *folder, uint32_t identifier, int depth) {
    if (strcmp(folder, "/") == 0) return NULL;   // too much to look through
    DIR *listing = opendir(folder);
    if (!listing) return NULL;
    char *found = NULL;
    for (struct dirent *entry; !found && (entry = readdir(listing));) {
        if (entry->d_name[0] == '.') continue;
        char path[PATH_MAX];
        if (snprintf(path, sizeof path, "%s/%s", folder, entry->d_name) >= (int)sizeof path) continue;
        struct stat info;
        if (stat(path, &info) != 0 || !S_ISDIR(info.st_mode)) continue;
        if (depth == 1) {
            if ((uint32_t)info.st_ino == identifier) found = strdup(path);
        } else {
            found = find_directory(path, identifier, depth - 1);
        }
    }
    closedir(listing);
    return found;
}

/// The folder an ID is, of those seen: the root's, the program's working
/// folder's, its bundle's and their parents' are seen from the start.
static const char *directory_path(uint32_t identifier) {
    if (identifier == ROOT_DIRECTORY || identifier == 1) return "/";
    static bool seeded;
    if (!seeded) {
        seeded = true;
        char here[PATH_MAX];
        if (getcwd(here, sizeof here))
            for (char *slash; (directory_id(here), (slash = strrchr(here, '/'))) && slash != here;) *slash = 0;
        // The bundle's: programs find their data beside it by its parent's
        // ID, from GetProcessBundleLocation and FSGetCatalogInfo.
        id bundle_path = SEND(SEND(CLASS("NSBundle"), "mainBundle"), "bundlePath");
        const char *bundle = bundle_path ? ((const char *(*)(id, SEL))objc_send)(bundle_path, SELECTOR("UTF8String")) : NULL;
        if (bundle && snprintf(here, sizeof here, "%s", bundle) < (int)sizeof here)
            for (char *slash; (directory_id(here), (slash = strrchr(here, '/'))) && slash != here;) *slash = 0;
        const char *home = getenv("HOME");
        if (home) directory_id(home);
    }
    for (size_t index = 0; index < directory_count; index++)
        if (directories[index].id == identifier) return directories[index].path;
    // An ID given by CoreServices (a folder's node ID from its catalog
    // information), which this hasn't seen: looked for in the folders
    // below those it has.
    size_t known = directory_count;
    for (int depth = 1; depth <= 3; depth++)
        for (size_t index = 0; index < known; index++) {
            char *found = find_directory(directories[index].path, identifier, depth);
            if (found) {
                directory_id(found);
                free(found);
                for (size_t again = 0; again < directory_count; again++)
                    if (directories[again].id == identifier) return directories[again].path;
            }
        }
    return NULL;
}

/// The folder of a volume and folder ID: the default folder for 0s.
static int default_volume = ROOT_VOLUME;
static uint32_t default_directory;

static const char *folder_of(int16_t volume, int32_t directory) {
    if (directory == 0) {
        if (volume != 0 && volume != default_volume) return "/";
        if (default_directory == 0) {
            static char here[PATH_MAX];
            if (!getcwd(here, sizeof here)) strcpy(here, "/");
            default_directory = directory_id(here);
        }
        directory = (int32_t)default_directory;
    }
    return directory_path((uint32_t)directory);
}

/// A Pascal name, which may be a path of its own: "a:b" from the folder,
/// ":a:b" too, "Volume:a:b" from the volume's root.
static bool join(const char *folder, const unsigned char *name, char *path, size_t size) {
    char leaf[256] = "";
    if (name) {
        memcpy(leaf, name + 1, name[0]);
        leaf[name[0]] = 0;
    }
    char converted[256];
    size_t out = 0;
    const char *cursor = leaf;
    bool absolute = leaf[0] && leaf[0] != ':' && strchr(leaf, ':');
    if (absolute) {
        // The volume's name, then its path: the one volume is the root.
        cursor = strchr(leaf, ':') + 1;
        folder = "/";
    } else if (*cursor == ':') {
        cursor++;
    }
    for (; *cursor && out + 1 < sizeof converted; cursor++) {
        // "::" goes up a folder; ':' parts the names, '/' in a name is ':'.
        if (*cursor == ':') {
            if (cursor[1] == ':') {
                memcpy(converted + out, "/..", 3);
                out += 3;
                cursor++;
                continue;
            }
            converted[out++] = '/';
        } else {
            converted[out++] = *cursor == '/' ? ':' : *cursor;
        }
    }
    converted[out] = 0;
    if (!converted[0]) return (size_t)snprintf(path, size, "%s", folder) < size;
    return (size_t)snprintf(path, size, "%s%s%s", folder, strcmp(folder, "/") == 0 ? "" : "/", converted) < size;
}

static void pascal(const char *string, unsigned char *out, size_t capacity) {
    size_t length = strlen(string);
    if (length > capacity - 1) length = capacity - 1;
    out[0] = (unsigned char)length;
    for (size_t index = 0; index < length; index++) out[1 + index] = string[index] == ':' ? '/' : (unsigned char)string[index];
}

/// An FSSpec for a path: its folder's ID and its name.
static void spec_for(const char *path, FSSpec *spec) {
    memset(spec, 0, sizeof *spec);
    spec->vRefNum = ROOT_VOLUME;
    if (strcmp(path, "/") == 0) {
        spec->parID = 1;
        pascal("Macintosh HD", spec->name, sizeof spec->name);
        return;
    }
    char folder[PATH_MAX];
    snprintf(folder, sizeof folder, "%s", path);
    char *slash = strrchr(folder, '/');
    const char *leaf = slash + 1;
    if (slash == folder) folder[1] = 0;
    else *slash = 0;
    spec->parID = (int32_t)directory_id(folder);
    pascal(path + (leaf - folder), spec->name, sizeof spec->name);
}

static bool spec_path(const FSSpec *spec, char *path, size_t size) {
    if (!spec) return false;
    if (spec->parID == 1) return snprintf(path, size, "/") > 0;
    const char *folder = folder_of(spec->vRefNum, spec->parID);
    return folder && join(folder, spec->name, path, size);
}

// MARK: - FSSpecs

OSErr carbon_FSMakeFSSpec(int16_t volume, int32_t directory, const unsigned char *name, FSSpec *spec) CARBON_SYMBOL(FSMakeFSSpec);
OSErr carbon_FSMakeFSSpec(int16_t volume, int32_t directory, const unsigned char *name, FSSpec *spec) {
    if (!spec) return paramErr;
    const char *folder = folder_of(volume, directory);
    if (!folder) return dirNFErr;
    char path[PATH_MAX], resolved[PATH_MAX];
    if (!join(folder, name, path, sizeof path)) return bdNamErr;
    if (realpath(path, resolved)) {
        spec_for(resolved, spec);
        return noErr;
    }
    // A spec for an item that isn't there yet, in a folder that is.
    char parent[PATH_MAX];
    snprintf(parent, sizeof parent, "%s", path);
    char *slash = strrchr(parent, '/');
    if (!slash) return bdNamErr;
    *slash = 0;
    if (!realpath(parent[0] ? parent : "/", resolved)) return dirNFErr;
    char full[PATH_MAX + 256];
    snprintf(full, sizeof full, "%s/%s", strcmp(resolved, "/") == 0 ? "" : resolved, slash + 1);
    spec_for(full, spec);
    return fnfErr;
}

OSErr carbon_FSpMakeFSRef(const FSSpec *spec, FSRef *ref) CARBON_SYMBOL(FSpMakeFSRef);
OSErr carbon_FSpMakeFSRef(const FSSpec *spec, FSRef *ref) {
    char path[PATH_MAX];
    if (!spec_path(spec, path, sizeof path)) return paramErr;
    return (OSErr)make_ref(path, ref, NULL);
}

OSErr carbon_FSGetCatalogInfoSpec(const FSRef *ref, FSSpec *spec) {
    char path[PATH_MAX];
    if (!ref_path(ref, path, sizeof path)) return paramErr;
    spec_for(path, spec);
    return noErr;
}

OSErr carbon_FSpCreate(const FSSpec *spec, OSType creator, OSType type, int16_t script) CARBON_SYMBOL(FSpCreate);
OSErr carbon_FSpCreate(const FSSpec *spec, OSType creator, OSType type, int16_t script) {
    (void)creator; (void)type; (void)script;
    char path[PATH_MAX];
    if (!spec_path(spec, path, sizeof path)) return paramErr;
    int descriptor = open(path, O_CREAT | O_EXCL | O_WRONLY, 0644);
    if (descriptor < 0) return error_for(errno);
    close(descriptor);
    return noErr;
}

OSErr carbon_FSpDirCreate(const FSSpec *spec, int16_t script, int32_t *created) CARBON_SYMBOL(FSpDirCreate);
OSErr carbon_FSpDirCreate(const FSSpec *spec, int16_t script, int32_t *created) {
    (void)script;
    char path[PATH_MAX];
    if (!spec_path(spec, path, sizeof path)) return paramErr;
    if (mkdir(path, 0755) != 0) return error_for(errno);
    if (created) *created = (int32_t)directory_id(path);
    return noErr;
}

OSErr carbon_FSpDelete(const FSSpec *spec) CARBON_SYMBOL(FSpDelete);
OSErr carbon_FSpDelete(const FSSpec *spec) {
    char path[PATH_MAX];
    if (!spec_path(spec, path, sizeof path)) return paramErr;
    if (unlink(path) == 0 || (errno == EISDIR && rmdir(path) == 0)) return noErr;
    return error_for(errno);
}

OSErr carbon_FSpRename(const FSSpec *spec, const unsigned char *name) CARBON_SYMBOL(FSpRename);
OSErr carbon_FSpRename(const FSSpec *spec, const unsigned char *name) {
    char path[PATH_MAX], target[PATH_MAX];
    if (!spec_path(spec, path, sizeof path)) return paramErr;
    FSSpec renamed = *spec;
    memcpy(renamed.name, name, (size_t)name[0] + 1);
    if (!spec_path(&renamed, target, sizeof target)) return bdNamErr;
    return rename(path, target) == 0 ? noErr : error_for(errno);
}

// MARK: - Open files

// Reference numbers are file descriptors' slots here, from 2 up, as the
// File Manager's are small positive numbers.
#define MAX_FILES 512
static struct { int descriptor; char *path; } files[MAX_FILES];

static int16_t file_add(int descriptor, const char *path) {
    for (int index = 2; index < MAX_FILES; index++)
        if (!files[index].path) {
            files[index].descriptor = descriptor;
            files[index].path = strdup(path);
            return (int16_t)index;
        }
    return 0;
}

static int file_descriptor(int16_t reference) {
    return reference >= 2 && reference < MAX_FILES && files[reference].path ? files[reference].descriptor : -1;
}

static int open_flags(int8_t permission) {
    switch (permission) {
    case 1: return O_RDONLY;               // fsRdPerm
    case 2: return O_WRONLY;               // fsWrPerm
    default: return O_RDWR;                // fsCurPerm, fsRdWrPerm, fsRdWrShPerm
    }
}

static OSErr open_path(const char *path, int8_t permission, int16_t *reference) {
    int flags = open_flags(permission);
    int descriptor = open(path, flags);
    // fsCurPerm: as much as is allowed.
    if (descriptor < 0 && permission == 0 && (errno == EACCES || errno == EROFS)) descriptor = open(path, O_RDONLY);
    if (descriptor < 0) return error_for(errno);
    int16_t number = file_add(descriptor, path);
    if (!number) {
        close(descriptor);
        return tmfoErr;
    }
    *reference = number;
    return noErr;
}

OSErr carbon_FSpOpenDF(const FSSpec *spec, int8_t permission, int16_t *reference) CARBON_SYMBOL(FSpOpenDF);
OSErr carbon_FSpOpenDF(const FSSpec *spec, int8_t permission, int16_t *reference) {
    char path[PATH_MAX];
    if (!spec_path(spec, path, sizeof path) || !reference) return paramErr;
    return open_path(path, permission, reference);
}

/// A resource fork: none here, so an empty file.
OSErr carbon_FSpOpenRF(const FSSpec *spec, int8_t permission, int16_t *reference) CARBON_SYMBOL(FSpOpenRF);
OSErr carbon_FSpOpenRF(const FSSpec *spec, int8_t permission, int16_t *reference) {
    (void)permission;
    char path[PATH_MAX];
    if (!spec_path(spec, path, sizeof path) || !reference) return paramErr;
    if (access(path, F_OK) != 0) return fnfErr;
    int descriptor = open("/dev/null", O_RDONLY);
    int16_t number = descriptor < 0 ? 0 : file_add(descriptor, path);
    if (!number) return tmfoErr;
    *reference = number;
    return noErr;
}

OSErr carbon_FSClose(int16_t reference) CARBON_SYMBOL(FSClose);
OSErr carbon_FSClose(int16_t reference) {
    int descriptor = file_descriptor(reference);
    if (descriptor < 0) return rfNumErr;
    close(descriptor);
    free(files[reference].path);
    files[reference].path = NULL;
    return noErr;
}

OSErr carbon_FSRead(int16_t reference, int32_t *count, void *buffer) CARBON_SYMBOL(FSRead);
OSErr carbon_FSRead(int16_t reference, int32_t *count, void *buffer) {
    int descriptor = file_descriptor(reference);
    if (descriptor < 0) return rfNumErr;
    if (!count || *count < 0) return paramErr;
    int32_t wanted = *count, got = 0;
    while (got < wanted) {
        ssize_t read_now = read(descriptor, (char *)buffer + got, (size_t)(wanted - got));
        if (read_now < 0) {
            if (errno == EINTR) continue;
            *count = got;
            return ioErr;
        }
        if (read_now == 0) break;
        got += (int32_t)read_now;
    }
    *count = got;
    return got < wanted ? eofErr : noErr;
}

OSErr carbon_FSWrite(int16_t reference, int32_t *count, const void *buffer) CARBON_SYMBOL(FSWrite);
OSErr carbon_FSWrite(int16_t reference, int32_t *count, const void *buffer) {
    int descriptor = file_descriptor(reference);
    if (descriptor < 0) return rfNumErr;
    if (!count || *count < 0) return paramErr;
    int32_t wanted = *count, written = 0;
    while (written < wanted) {
        ssize_t now = write(descriptor, (const char *)buffer + written, (size_t)(wanted - written));
        if (now < 0) {
            if (errno == EINTR) continue;
            *count = written;
            return errno == EBADF ? wrPermErr : error_for(errno);
        }
        written += (int32_t)now;
    }
    *count = written;
    return noErr;
}

OSErr carbon_GetEOF(int16_t reference, int32_t *size) CARBON_SYMBOL(GetEOF);
OSErr carbon_GetEOF(int16_t reference, int32_t *size) {
    int descriptor = file_descriptor(reference);
    struct stat info;
    if (descriptor < 0 || fstat(descriptor, &info) != 0) return rfNumErr;
    if (size) *size = (int32_t)info.st_size;
    return noErr;
}

OSErr carbon_SetEOF(int16_t reference, int32_t size) CARBON_SYMBOL(SetEOF);
OSErr carbon_SetEOF(int16_t reference, int32_t size) {
    int descriptor = file_descriptor(reference);
    if (descriptor < 0) return rfNumErr;
    return ftruncate(descriptor, size) == 0 ? noErr : error_for(errno);
}

/// fsAtMark, fsFromStart, fsFromLEOF, fsFromMark.
static off_t seek(int descriptor, uint16_t mode, int64_t offset) {
    switch (mode & 3) {
    case 0: return lseek(descriptor, 0, SEEK_CUR);
    case 1: return lseek(descriptor, offset, SEEK_SET);
    case 2: return lseek(descriptor, offset, SEEK_END);
    default: return lseek(descriptor, offset, SEEK_CUR);
    }
}

// MARK: - Reads by parameter block

#pragma pack(push, 2)
typedef struct io_block {
    struct io_block *qLink;
    int16_t qType, ioTrap;
    void *ioCmdAddr;
    void (*ioCompletion)(struct io_block *);
    volatile int16_t ioResult;
    unsigned char *ioNamePtr;
    int16_t ioVRefNum, ioRefNum;
    int8_t ioVersNum, ioPermssn;
    void *ioMisc, *ioBuffer;
    int32_t ioReqCount, ioActCount;
    int16_t ioPosMode;
    int32_t ioPosOffset;
} IOParam;
#pragma pack(pop)

static off_t seek(int descriptor, uint16_t mode, int64_t offset);

/// A block's read: from where its mode says, its count, leaving the mark
/// after what was read in its offset.
static OSErr read_block(IOParam *block) {
    int descriptor = file_descriptor(block->ioRefNum);
    block->ioActCount = 0;
    if (descriptor < 0) return rfNumErr;
    if (block->ioReqCount < 0) return paramErr;
    if (seek(descriptor, (uint16_t)block->ioPosMode, block->ioPosOffset) < 0) return posErr;
    int32_t got = 0;
    while (got < block->ioReqCount) {
        ssize_t read_now = read(descriptor, (char *)block->ioBuffer + got, (size_t)(block->ioReqCount - got));
        if (read_now < 0) {
            if (errno == EINTR) continue;
            block->ioActCount = got;
            return ioErr;
        }
        if (read_now == 0) break;
        got += (int32_t)read_now;
    }
    block->ioActCount = got;
    block->ioPosOffset = (int32_t)lseek(descriptor, 0, SEEK_CUR);
    return got < block->ioReqCount ? eofErr : noErr;
}

OSErr carbon_PBReadSync(IOParam *block) CARBON_SYMBOL(PBReadSync);
OSErr carbon_PBReadSync(IOParam *block) {
    if (!block) return paramErr;
    return block->ioResult = read_block(block);
}

// Asynchronous reads: in order, on a thread of their own, each block's
// result set and then its completion routine called, as a Mac's are.
static pthread_mutex_t reads_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t reads_waiting = PTHREAD_COND_INITIALIZER;
static IOParam *reads_first, *reads_last;

static void *run_reads(void *unused) {
    (void)unused;
    for (;;) {
        pthread_mutex_lock(&reads_lock);
        while (!reads_first) pthread_cond_wait(&reads_waiting, &reads_lock);
        IOParam *block = reads_first;
        reads_first = block->qLink;
        if (!reads_first) reads_last = NULL;
        pthread_mutex_unlock(&reads_lock);
        block->qLink = NULL;
        OSErr result = read_block(block);
        __atomic_store_n(&block->ioResult, result, __ATOMIC_SEQ_CST);
        if (block->ioCompletion) block->ioCompletion(block);
    }
    return NULL;
}

static void start_reads(void) {
    pthread_t thread;
    if (pthread_create(&thread, NULL, run_reads, NULL) == 0) pthread_detach(thread);
}

OSErr carbon_PBReadAsync(IOParam *block) CARBON_SYMBOL(PBReadAsync);
OSErr carbon_PBReadAsync(IOParam *block) {
    if (!block) return paramErr;
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, start_reads);
    block->ioResult = 1;   // ioInProgress
    block->qLink = NULL;
    pthread_mutex_lock(&reads_lock);
    if (reads_last) reads_last->qLink = block; else reads_first = block;
    reads_last = block;
    pthread_cond_signal(&reads_waiting);
    pthread_mutex_unlock(&reads_lock);
    return noErr;
}

OSErr carbon_SetFPos(int16_t reference, int16_t mode, int32_t offset) CARBON_SYMBOL(SetFPos);
OSErr carbon_SetFPos(int16_t reference, int16_t mode, int32_t offset) {
    int descriptor = file_descriptor(reference);
    if (descriptor < 0) return rfNumErr;
    off_t position = seek(descriptor, (uint16_t)mode, offset);
    struct stat info;
    if (position < 0) return posErr;
    if (fstat(descriptor, &info) == 0 && position > info.st_size) {
        lseek(descriptor, info.st_size, SEEK_SET);
        return eofErr;
    }
    return noErr;
}

OSErr carbon_GetFPos(int16_t reference, int32_t *position) CARBON_SYMBOL(GetFPos);
OSErr carbon_GetFPos(int16_t reference, int32_t *position) {
    int descriptor = file_descriptor(reference);
    if (descriptor < 0) return rfNumErr;
    if (position) *position = (int32_t)lseek(descriptor, 0, SEEK_CUR);
    return noErr;
}

// MARK: - Forks

void carbon_FSGetDataForkName(HFSUniStr255 *name) CARBON_SYMBOL(FSGetDataForkName);
void carbon_FSGetDataForkName(HFSUniStr255 *name) { if (name) name->length = 0; }

void carbon_FSGetResourceForkName(HFSUniStr255 *name) CARBON_SYMBOL(FSGetResourceForkName);
void carbon_FSGetResourceForkName(HFSUniStr255 *name) {
    static const char fork[] = "RESOURCE_FORK";
    if (!name) return;
    name->length = sizeof fork - 1;
    for (size_t index = 0; index < sizeof fork - 1; index++) name->unicode[index] = (uint16_t)fork[index];
}

OSErr carbon_FSOpenFork(const FSRef *ref, size_t nameLength, const uint16_t *name, int8_t permission, int16_t *reference)
    CARBON_SYMBOL(FSOpenFork);
OSErr carbon_FSOpenFork(const FSRef *ref, size_t nameLength, const uint16_t *name, int8_t permission, int16_t *reference) {
    char path[PATH_MAX];
    if (!ref_path(ref, path, sizeof path) || !reference) return paramErr;
    if (nameLength != 0) {
        (void)name;
        // The resource fork: empty.
        int descriptor = open("/dev/null", O_RDONLY);
        int16_t number = descriptor < 0 ? 0 : file_add(descriptor, path);
        if (!number) return tmfoErr;
        *reference = number;
        return noErr;
    }
    return open_path(path, permission, reference);
}

OSErr carbon_FSCloseFork(int16_t reference) CARBON_SYMBOL(FSCloseFork);
OSErr carbon_FSCloseFork(int16_t reference) { return carbon_FSClose(reference); }

OSErr carbon_FSReadFork(int16_t reference, uint16_t mode, int64_t offset, uint32_t count, void *buffer, uint32_t *actual)
    CARBON_SYMBOL(FSReadFork);
OSErr carbon_FSReadFork(int16_t reference, uint16_t mode, int64_t offset, uint32_t count, void *buffer, uint32_t *actual) {
    int descriptor = file_descriptor(reference);
    if (actual) *actual = 0;
    if (descriptor < 0) return rfNumErr;
    if (seek(descriptor, mode, offset) < 0) return posErr;
    int32_t length = (int32_t)count;
    OSErr error = carbon_FSRead(reference, &length, buffer);
    if (actual) *actual = (uint32_t)length;
    return error;
}

OSErr carbon_FSWriteFork(int16_t reference, uint16_t mode, int64_t offset, uint32_t count, const void *buffer, uint32_t *actual)
    CARBON_SYMBOL(FSWriteFork);
OSErr carbon_FSWriteFork(int16_t reference, uint16_t mode, int64_t offset, uint32_t count, const void *buffer, uint32_t *actual) {
    int descriptor = file_descriptor(reference);
    if (actual) *actual = 0;
    if (descriptor < 0) return rfNumErr;
    if (seek(descriptor, mode, offset) < 0) return posErr;
    int32_t length = (int32_t)count;
    OSErr error = carbon_FSWrite(reference, &length, buffer);
    if (actual) *actual = (uint32_t)length;
    return error;
}

OSErr carbon_FSGetForkSize(int16_t reference, int64_t *size) CARBON_SYMBOL(FSGetForkSize);
OSErr carbon_FSGetForkSize(int16_t reference, int64_t *size) {
    int descriptor = file_descriptor(reference);
    struct stat info;
    if (descriptor < 0 || fstat(descriptor, &info) != 0) return rfNumErr;
    if (size) *size = info.st_size;
    return noErr;
}

OSErr carbon_FSSetForkSize(int16_t reference, uint16_t mode, int64_t offset) CARBON_SYMBOL(FSSetForkSize);
OSErr carbon_FSSetForkSize(int16_t reference, uint16_t mode, int64_t offset) {
    int descriptor = file_descriptor(reference);
    if (descriptor < 0) return rfNumErr;
    off_t here = lseek(descriptor, 0, SEEK_CUR);
    off_t size = seek(descriptor, mode, offset);
    lseek(descriptor, here, SEEK_SET);
    if (size < 0) return posErr;
    return ftruncate(descriptor, size) == 0 ? noErr : error_for(errno);
}

OSErr carbon_FSGetForkPosition(int16_t reference, int64_t *position) CARBON_SYMBOL(FSGetForkPosition);
OSErr carbon_FSGetForkPosition(int16_t reference, int64_t *position) {
    int descriptor = file_descriptor(reference);
    if (descriptor < 0) return rfNumErr;
    if (position) *position = lseek(descriptor, 0, SEEK_CUR);
    return noErr;
}

OSErr carbon_FSSetForkPosition(int16_t reference, uint16_t mode, int64_t offset) CARBON_SYMBOL(FSSetForkPosition);
OSErr carbon_FSSetForkPosition(int16_t reference, uint16_t mode, int64_t offset) {
    int descriptor = file_descriptor(reference);
    if (descriptor < 0) return rfNumErr;
    return seek(descriptor, mode, offset) < 0 ? posErr : noErr;
}

OSErr carbon_FSFlushFork(int16_t reference) CARBON_SYMBOL(FSFlushFork);
OSErr carbon_FSFlushFork(int16_t reference) {
    int descriptor = file_descriptor(reference);
    if (descriptor < 0) return rfNumErr;
    fsync(descriptor);
    return noErr;
}

// MARK: - Making, moving and deleting

static bool unicode_name(size_t length, const uint16_t *name, char *out, size_t size) {
    size_t used = 0;
    for (size_t index = 0; index < length; index++) {
        uint32_t code = name[index];
        if (code >= 0xd800 && code < 0xdc00 && index + 1 < length) {
            code = 0x10000 + ((code - 0xd800) << 10) + (name[++index] - 0xdc00);
        }
        if (code == '/') code = ':';
        char bytes[4];
        size_t count;
        if (code < 0x80) { bytes[0] = (char)code; count = 1; }
        else if (code < 0x800) { bytes[0] = (char)(0xc0 | code >> 6); bytes[1] = (char)(0x80 | (code & 0x3f)); count = 2; }
        else if (code < 0x10000) {
            bytes[0] = (char)(0xe0 | code >> 12); bytes[1] = (char)(0x80 | ((code >> 6) & 0x3f));
            bytes[2] = (char)(0x80 | (code & 0x3f)); count = 3;
        } else {
            bytes[0] = (char)(0xf0 | code >> 18); bytes[1] = (char)(0x80 | ((code >> 12) & 0x3f));
            bytes[2] = (char)(0x80 | ((code >> 6) & 0x3f)); bytes[3] = (char)(0x80 | (code & 0x3f)); count = 4;
        }
        if (used + count + 1 > size) return false;
        memcpy(out + used, bytes, count);
        used += count;
    }
    out[used] = 0;
    return used > 0;
}

static bool child_path(const FSRef *parent, size_t length, const uint16_t *name, char *path, size_t size) {
    char folder[PATH_MAX], leaf[NAME_MAX * 4 + 1];
    if (!ref_path(parent, folder, sizeof folder) || !unicode_name(length, name, leaf, sizeof leaf)) return false;
    return (size_t)snprintf(path, size, "%s/%s", strcmp(folder, "/") == 0 ? "" : folder, leaf) < size;
}

OSErr carbon_FSCreateFileUnicode(const FSRef *parent, size_t length, const uint16_t *name, uint32_t which, const void *info,
                                 FSRef *ref, FSSpec *spec) CARBON_SYMBOL(FSCreateFileUnicode);
OSErr carbon_FSCreateFileUnicode(const FSRef *parent, size_t length, const uint16_t *name, uint32_t which, const void *info,
                                 FSRef *ref, FSSpec *spec) {
    (void)which; (void)info;
    char path[PATH_MAX];
    if (!child_path(parent, length, name, path, sizeof path)) return paramErr;
    int descriptor = open(path, O_CREAT | O_EXCL | O_WRONLY, 0644);
    if (descriptor < 0) return error_for(errno);
    close(descriptor);
    store_ref(path, ref);
    if (spec) spec_for(path, spec);
    return noErr;
}

OSErr carbon_FSCreateDirectoryUnicode(const FSRef *parent, size_t length, const uint16_t *name, uint32_t which, const void *info,
                                      FSRef *ref, FSSpec *spec, uint32_t *directory) CARBON_SYMBOL(FSCreateDirectoryUnicode);
OSErr carbon_FSCreateDirectoryUnicode(const FSRef *parent, size_t length, const uint16_t *name, uint32_t which, const void *info,
                                      FSRef *ref, FSSpec *spec, uint32_t *directory) {
    (void)which; (void)info;
    char path[PATH_MAX];
    if (!child_path(parent, length, name, path, sizeof path)) return paramErr;
    if (mkdir(path, 0755) != 0) return error_for(errno);
    store_ref(path, ref);
    if (spec) spec_for(path, spec);
    if (directory) *directory = directory_id(path);
    return noErr;
}

OSErr carbon_FSDeleteObject(const FSRef *ref) CARBON_SYMBOL(FSDeleteObject);
OSErr carbon_FSDeleteObject(const FSRef *ref) {
    char path[PATH_MAX];
    if (!ref_path(ref, path, sizeof path)) return paramErr;
    if (unlink(path) == 0) return noErr;
    if (errno == EISDIR || errno == EPERM) {
        if (rmdir(path) == 0) return noErr;
        if (errno == ENOTEMPTY) return -47;   // fBsyErr: a folder that isn't empty
    }
    return error_for(errno);
}

OSErr carbon_FSMoveObject(const FSRef *ref, const FSRef *destination, FSRef *moved) CARBON_SYMBOL(FSMoveObject);
OSErr carbon_FSMoveObject(const FSRef *ref, const FSRef *destination, FSRef *moved) {
    char path[PATH_MAX], folder[PATH_MAX], target[PATH_MAX * 2];
    if (!ref_path(ref, path, sizeof path) || !ref_path(destination, folder, sizeof folder)) return paramErr;
    const char *leaf = strrchr(path, '/');
    snprintf(target, sizeof target, "%s%s", strcmp(folder, "/") == 0 ? "" : folder, leaf ? leaf : "/");
    if (rename(path, target) != 0) return error_for(errno);
    store_ref(target, moved);
    return noErr;
}

OSErr carbon_FSRenameUnicode(const FSRef *ref, size_t length, const uint16_t *name, uint32_t hint, FSRef *renamed)
    CARBON_SYMBOL(FSRenameUnicode);
OSErr carbon_FSRenameUnicode(const FSRef *ref, size_t length, const uint16_t *name, uint32_t hint, FSRef *renamed) {
    (void)hint;
    char path[PATH_MAX], leaf[NAME_MAX * 4 + 1], target[PATH_MAX * 2];
    if (!ref_path(ref, path, sizeof path) || !unicode_name(length, name, leaf, sizeof leaf)) return paramErr;
    char *slash = strrchr(path, '/');
    if (!slash) return paramErr;
    *slash = 0;
    snprintf(target, sizeof target, "%s/%s", path, leaf);
    *slash = '/';
    if (rename(path, target) != 0) return error_for(errno);
    store_ref(target, renamed);
    return noErr;
}

/// Dates and Finder information aren't kept: setting them changes nothing.
OSErr carbon_FSSetCatalogInfo(const FSRef *ref, uint32_t which, const void *info) CARBON_SYMBOL(FSSetCatalogInfo);
OSErr carbon_FSSetCatalogInfo(const FSRef *ref, uint32_t which, const void *info) {
    (void)which; (void)info;
    char path[PATH_MAX];
    if (!ref_path(ref, path, sizeof path)) return paramErr;
    return access(path, F_OK) == 0 ? noErr : fnfErr;
}

// MARK: - Folders' items

typedef struct {
    DIR *directory;
    char path[PATH_MAX];
} carbon_iterator;

OSErr carbon_FSOpenIterator(const FSRef *container, uint32_t options, carbon_iterator **out) CARBON_SYMBOL(FSOpenIterator);
OSErr carbon_FSOpenIterator(const FSRef *container, uint32_t options, carbon_iterator **out) {
    (void)options;
    if (!out) return paramErr;
    carbon_iterator *iterator = calloc(1, sizeof *iterator);
    if (!iterator) return memFullErr;
    if (!ref_path(container, iterator->path, sizeof iterator->path) || !(iterator->directory = opendir(iterator->path))) {
        free(iterator);
        return dirNFErr;
    }
    *out = iterator;
    return noErr;
}

OSErr carbon_FSCloseIterator(carbon_iterator *iterator) CARBON_SYMBOL(FSCloseIterator);
OSErr carbon_FSCloseIterator(carbon_iterator *iterator) {
    if (!iterator) return paramErr;
    closedir(iterator->directory);
    free(iterator);
    return noErr;
}

typedef OSErr (*catalog_function)(const FSRef *, uint32_t, void *, HFSUniStr255 *, FSSpec *, FSRef *);

OSErr carbon_FSGetCatalogInfoBulk(carbon_iterator *iterator, size_t maximum, size_t *count, Boolean *changed, uint32_t which,
                                  uint8_t *infos, FSRef *refs, FSSpec *specs, HFSUniStr255 *names) CARBON_SYMBOL(FSGetCatalogInfoBulk);
OSErr carbon_FSGetCatalogInfoBulk(carbon_iterator *iterator, size_t maximum, size_t *count, Boolean *changed, uint32_t which,
                                  uint8_t *infos, FSRef *refs, FSSpec *specs, HFSUniStr255 *names) {
    static catalog_function catalog;
    if (!catalog) catalog = (catalog_function)carbon_function(CORESERVICES, "_FSGetCatalogInfo");
    if (!iterator || !count) return paramErr;
    if (changed) *changed = 0;
    size_t found = 0;
    struct dirent *entry;
    while (found < maximum && (entry = readdir(iterator->directory))) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        char path[PATH_MAX * 2];
        snprintf(path, sizeof path, "%s/%s", strcmp(iterator->path, "/") == 0 ? "" : iterator->path, entry->d_name);
        FSRef ref;
        if (make_ref(path, &ref, NULL) != noErr) continue;
        if (refs) refs[found] = ref;
        if (specs) spec_for(path, &specs[found]);
        if (catalog && (infos || names))
            catalog(&ref, which, infos ? infos + found * 144 : NULL, names ? &names[found] : NULL, NULL, NULL);
        found++;
    }
    *count = found;
    return found == 0 ? errFSNoMoreItems : noErr;
}

// MARK: - The default folder

OSErr carbon_HGetVol(unsigned char *name, int16_t *volume, int32_t *directory) CARBON_SYMBOL(HGetVol);
OSErr carbon_HGetVol(unsigned char *name, int16_t *volume, int32_t *directory) {
    if (name) pascal("Macintosh HD", name, 28);
    if (volume) *volume = (int16_t)default_volume;
    if (directory) {
        folder_of(0, 0);
        *directory = (int32_t)default_directory;
    }
    return noErr;
}

OSErr carbon_HSetVol(const unsigned char *name, int16_t volume, int32_t directory) CARBON_SYMBOL(HSetVol);
OSErr carbon_HSetVol(const unsigned char *name, int16_t volume, int32_t directory) {
    (void)name;
    if (volume != 0 && volume != ROOT_VOLUME) return nsvErr;
    if (directory && !directory_path((uint32_t)directory)) return dirNFErr;
    if (directory) default_directory = (uint32_t)directory;
    return noErr;
}

/// The classic FindFolder: the folder's volume and ID.
OSErr carbon_FindFolder(int16_t volume, OSType type, Boolean create, int16_t *foundVolume, int32_t *foundDirectory)
    CARBON_SYMBOL(FindFolder);
OSErr carbon_FindFolder(int16_t volume, OSType type, Boolean create, int16_t *foundVolume, int32_t *foundDirectory) {
    static OSErr (*find)(int16_t, OSType, Boolean, FSRef *);
    if (!find) find = (OSErr (*)(int16_t, OSType, Boolean, FSRef *))carbon_function(CORESERVICES, "_FSFindFolder");
    FSRef ref;
    char path[PATH_MAX];
    OSErr error = find ? find(volume, type, create, &ref) : unimpErr;
    if (error) return error;
    if (!ref_path(&ref, path, sizeof path)) return fnfErr;
    if (foundVolume) *foundVolume = ROOT_VOLUME;
    if (foundDirectory) *foundDirectory = (int32_t)directory_id(path);
    return noErr;
}

// MARK: - Parameter blocks

// The original File Manager's parameter blocks, 2-byte packed: the common
// header (qLink, qType, ioTrap, ioCmdAddr, ioCompletion, ioResult,
// ioNamePtr, ioVRefNum) is 24 bytes.
#pragma pack(push, 2)
typedef struct {
    void *qLink;
    int16_t qType;
    int16_t ioTrap;
    void *ioCmdAddr;
    void *ioCompletion;
    OSErr ioResult;
    unsigned char *ioNamePtr;
    int16_t ioVRefNum;
} ParamHeader;

typedef struct {
    ParamHeader header;
    int16_t ioFRefNum;
    int8_t ioFVersNum;
    int8_t filler1;
    int16_t ioFDirIndex;
    int8_t ioFlAttrib;
    int8_t ioACUser;
    // A file's: Finder info, then its ID and its forks' sizes; a folder's
    // the same 16 bytes of Finder info, its ID and its count of items.
    uint8_t ioFlFndrInfo[16];
    int32_t ioDirID;            // ioDrDirID for a folder
    uint16_t ioFlStBlk;         // ioDrNmFls for a folder
    int32_t ioFlLgLen;
    int32_t ioFlPyLen;
    uint16_t ioFlRStBlk;
    int32_t ioFlRLgLen;
    int32_t ioFlRPyLen;
    uint32_t ioFlCrDat;
    uint32_t ioFlMdDat;
    uint32_t ioFlBkDat;
    uint8_t ioFlXFndrInfo[16];
    int32_t ioFlParID;          // ioDrParID for a folder
    int32_t ioFlClpSiz;
} CInfoPB;

typedef struct {
    ParamHeader header;
    int32_t filler1;
    int16_t ioVolIndex;
    uint32_t ioVCrDate;
    uint32_t ioVLsMod;
    int16_t ioVAtrb;
    uint16_t ioVNmFls;
    uint16_t ioVBitMap;
    uint16_t ioAllocPtr;
    uint16_t ioVNmAlBlks;
    uint32_t ioVAlBlkSiz;
    uint32_t ioVClpSiz;
    uint16_t ioAlBlSt;
    uint32_t ioVNxtCNID;
    uint16_t ioVFrBlk;
    uint16_t ioVSigWord;
    int16_t ioVDrvInfo;
    int16_t ioVDRefNum;
    int16_t ioVFSID;
    uint32_t ioVBkUp;
    int16_t ioVSeqNum;
    uint32_t ioVWrCnt;
    uint32_t ioVFilCnt;
    uint32_t ioVDirCnt;
    int32_t ioVFndrInfo[8];
} HVolumeParam;

typedef struct {
    ParamHeader header;
    int16_t ioRefNum;
    int8_t ioVersNum;
    int8_t ioPermssn;
    void *ioMisc;
    void *ioBuffer;
    int32_t ioReqCount;
    int32_t ioActCount;
} HIOParam;

typedef struct {
    ParamHeader header;
    int16_t ioDTRefNum;
    int16_t ioIndex;
    int32_t ioTagInfo;
    void *ioDTBuffer;
    int32_t ioDTReqCount;
    int32_t ioDTActCount;
    int8_t ioFiller1;
    uint8_t ioIconType;
    int16_t ioFiller2;
    int32_t ioDirID;
    OSType ioFileCreator;
    OSType ioFileType;
    int32_t ioFiller3;
    int32_t ioDTLgLen;
    int32_t ioDTPyLen;
    int16_t ioFiller4[14];
    int32_t ioAPPLParID;
} DTPB;
#pragma pack(pop)

static uint32_t mac_time(time_t seconds) { return (uint32_t)((int64_t)seconds + 2082844800LL); }

/// An item by name (index 0), by position in its folder (index > 0), or
/// the folder itself (index < 0).
OSErr carbon_PBGetCatInfoSync(CInfoPB *block) CARBON_SYMBOL(PBGetCatInfoSync);
OSErr carbon_PBGetCatInfoSync(CInfoPB *block) {
    if (!block) return paramErr;
    const char *folder = folder_of(block->header.ioVRefNum, block->ioDirID);
    char path[PATH_MAX];
    OSErr error = noErr;
    if (!folder) error = dirNFErr;
    else if (block->ioFDirIndex < 0 || (block->ioFDirIndex == 0 && (!block->header.ioNamePtr || block->header.ioNamePtr[0] == 0))) {
        snprintf(path, sizeof path, "%s", folder);
    } else if (block->ioFDirIndex > 0) {
        DIR *directory = opendir(folder);
        struct dirent *entry = NULL;
        int index = 0;
        while (directory && (entry = readdir(directory)))
            if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0 && entry->d_name[0] != '.' &&
                ++index == block->ioFDirIndex) break;
        if (entry) snprintf(path, sizeof path, "%s/%s", strcmp(folder, "/") == 0 ? "" : folder, entry->d_name);
        else error = fnfErr;
        if (directory) closedir(directory);
    } else if (!join(folder, block->header.ioNamePtr, path, sizeof path)) {
        error = bdNamErr;
    }
    struct stat info;
    if (!error && stat(path, &info) != 0) error = error_for(errno);
    if (error) return block->header.ioResult = error;
    char resolved[PATH_MAX];
    if (realpath(path, resolved)) snprintf(path, sizeof path, "%s", resolved);
    bool directory = S_ISDIR(info.st_mode);
    // The item's name back, when the caller gave room for it.
    if (block->header.ioNamePtr && block->ioFDirIndex != 0) {
        const char *leaf = strcmp(path, "/") == 0 ? "Macintosh HD" : strrchr(path, '/') + 1;
        pascal(leaf, block->header.ioNamePtr, 64);
    }
    block->header.ioVRefNum = ROOT_VOLUME;
    block->ioFlAttrib = (int8_t)(directory ? 0x10 : 0);
    memset(block->ioFlFndrInfo, 0, sizeof block->ioFlFndrInfo);
    memset(block->ioFlXFndrInfo, 0, sizeof block->ioFlXFndrInfo);
    char parent[PATH_MAX];
    snprintf(parent, sizeof parent, "%s", path);
    char *slash = strrchr(parent, '/');
    if (slash == parent) parent[1] = 0;
    else if (slash) *slash = 0;
    block->ioFlParID = strcmp(path, "/") == 0 ? 1 : (int32_t)directory_id(parent);
    block->ioFlCrDat = mac_time(info.st_ctime);
    block->ioFlMdDat = mac_time(info.st_mtime);
    block->ioFlBkDat = 0;
    if (directory) {
        block->ioDirID = (int32_t)directory_id(path);
        uint16_t items = 0;
        DIR *folderItems = opendir(path);
        for (struct dirent *entry; folderItems && (entry = readdir(folderItems));)
            if (entry->d_name[0] != '.') items++;
        if (folderItems) closedir(folderItems);
        block->ioFlStBlk = items;
    } else {
        block->ioDirID = (int32_t)(uint32_t)info.st_ino;
        block->ioFlStBlk = 0;
        block->ioFlLgLen = (int32_t)info.st_size;
        block->ioFlPyLen = (int32_t)(info.st_blocks * 512);
        block->ioFlRStBlk = 0;
        block->ioFlRLgLen = 0;
        block->ioFlRPyLen = 0;
    }
    return block->header.ioResult = noErr;
}

OSErr carbon_PBGetCatInfoAsync(CInfoPB *block) CARBON_SYMBOL(PBGetCatInfoAsync);
OSErr carbon_PBGetCatInfoAsync(CInfoPB *block) { return carbon_PBGetCatInfoSync(block); }

/// The one volume, by its number, its name or its index (1).
OSErr carbon_PBHGetVInfoSync(HVolumeParam *block) CARBON_SYMBOL(PBHGetVInfoSync);
OSErr carbon_PBHGetVInfoSync(HVolumeParam *block) {
    if (!block) return paramErr;
    if (block->ioVolIndex > 1 || (block->ioVolIndex == 0 && block->header.ioVRefNum != 0 &&
                                  block->header.ioVRefNum != ROOT_VOLUME && block->header.ioVRefNum != -1))
        return block->header.ioResult = nsvErr;
    struct statvfs stats;
    uint64_t total = 0, available = 0;
    if (statvfs("/", &stats) == 0) {
        total = (uint64_t)stats.f_blocks * stats.f_frsize;
        available = (uint64_t)stats.f_bavail * stats.f_frsize;
    }
    // As the File Manager reports a volume over 2 GB here: its sizes at most
    // 2 GB, so that blocks times their size fits a program's 32 bits; the
    // blocks large enough for their counts to fit 16.
    const uint64_t limit = 0x7fffffffu;
    if (total > limit) total = limit;
    if (available > limit) available = limit;
    uint32_t size = 512;
    while (total / size > 0xffff) size *= 2;
    if (block->header.ioNamePtr) pascal("Macintosh HD", block->header.ioNamePtr, 28);
    block->header.ioVRefNum = ROOT_VOLUME;
    block->ioVCrDate = mac_time(0);
    block->ioVLsMod = mac_time(time(NULL));
    block->ioVAtrb = 0;
    block->ioVNmFls = 0;
    block->ioVNmAlBlks = (uint16_t)(total / size);
    block->ioVAlBlkSiz = size;
    block->ioVClpSiz = size;
    block->ioVFrBlk = (uint16_t)(available / size);
    block->ioVSigWord = 0x482b;   // 'H+'
    block->ioVDrvInfo = 1;
    block->ioVDRefNum = -1;
    block->ioVFSID = 0;
    block->ioVFilCnt = 0;
    block->ioVDirCnt = 0;
    memset(block->ioVFndrInfo, 0, sizeof block->ioVFndrInfo);
    CARBON_TRACE("volume info: index %d, %u blocks of %u, %u free", block->ioVolIndex, block->ioVNmAlBlks, size, block->ioVFrBlk);
    return block->header.ioResult = noErr;
}

/// The volume's parameters: version 4's GetVolParmsInfoBuffer, of a local,
/// fixed disk that keeps no desktop database.
OSErr carbon_PBHGetVolParmsSync(HIOParam *block) CARBON_SYMBOL(PBHGetVolParmsSync);
OSErr carbon_PBHGetVolParmsSync(HIOParam *block) {
    if (!block) return paramErr;
    if (block->header.ioVRefNum != 0 && block->header.ioVRefNum != ROOT_VOLUME && block->header.ioVRefNum != -1)
        return block->header.ioResult = nsvErr;
#pragma pack(push, 2)
    struct {
        int16_t vMVersion;
        int32_t vMAttrib;
        void *vMLocalHand;
        int32_t vMServerAdr;
        int32_t vMVolumeGrade;
        int16_t vMForeignPrivID;
        int32_t vMExtendedAttributes;
        void *vMDeviceID;
        uint32_t vMMaxNameLength;
    } parameters = {4, (int32_t)(1u << 31 | 1u << 20 | 1u << 17), NULL, 0, 0, 0, 0, NULL, 255};
#pragma pack(pop)
    int32_t size = block->ioReqCount < (int32_t)sizeof parameters ? block->ioReqCount : (int32_t)sizeof parameters;
    if (block->ioBuffer && size > 0) memcpy(block->ioBuffer, &parameters, (size_t)size);
    block->ioActCount = size > 0 ? size : 0;
    return block->header.ioResult = noErr;
}

/// There is no desktop database: its reference number is the volume's, and
/// an application looked up in it isn't there.
OSErr carbon_PBDTGetPath(DTPB *block) CARBON_SYMBOL(PBDTGetPath);
OSErr carbon_PBDTGetPath(DTPB *block) {
    if (!block) return paramErr;
    block->ioDTRefNum = ROOT_VOLUME;
    return block->header.ioResult = noErr;
}

OSErr carbon_PBDTGetAPPLSync(DTPB *block) CARBON_SYMBOL(PBDTGetAPPLSync);
OSErr carbon_PBDTGetAPPLSync(DTPB *block) {
    if (!block) return paramErr;
    return block->header.ioResult = -1302;   // afpItemNotFound
}

// MARK: - Launch Services

/// Applications aren't found by creator or URL: there is no Finder's
/// database of them here.
OSStatus carbon_LSFindApplicationForInfo(OSType creator, void *bundle, void *name, FSRef *ref, void **url)
    CARBON_SYMBOL(LSFindApplicationForInfo);
OSStatus carbon_LSFindApplicationForInfo(OSType creator, void *bundle, void *name, FSRef *ref, void **url) {
    (void)creator; (void)bundle; (void)name; (void)ref;
    if (url) *url = NULL;
    return -10814;   // kLSApplicationNotFoundErr
}

OSStatus carbon_LSGetApplicationForURL(void *url, uint32_t roles, FSRef *ref, void **out) CARBON_SYMBOL(LSGetApplicationForURL);
OSStatus carbon_LSGetApplicationForURL(void *url, uint32_t roles, FSRef *ref, void **out) {
    (void)url; (void)roles; (void)ref;
    if (out) *out = NULL;
    return -10814;
}

OSStatus carbon_LSCanURLAcceptURL(void *item, void *target, uint32_t roles, uint32_t flags, Boolean *accepts)
    CARBON_SYMBOL(LSCanURLAcceptURL);
OSStatus carbon_LSCanURLAcceptURL(void *item, void *target, uint32_t roles, uint32_t flags, Boolean *accepts) {
    (void)item; (void)target; (void)roles; (void)flags;
    if (accepts) *accepts = 0;
    return noErr;
}

/// Opening a file: with the desktop's opener, xdg-open.
OSStatus carbon_LSOpenFSRef(const FSRef *ref, FSRef *launched) CARBON_SYMBOL(LSOpenFSRef);
OSStatus carbon_LSOpenFSRef(const FSRef *ref, FSRef *launched) {
    char path[PATH_MAX];
    if (!ref_path(ref, path, sizeof path)) return paramErr;
    pid_t child = fork();
    if (child == 0) {
        execlp("xdg-open", "xdg-open", path, (char *)NULL);
        _exit(127);
    }
    if (launched) memset(launched, 0, sizeof *launched);
    return child > 0 ? noErr : -10810;   // kLSUnknownErr
}

// MARK: - Catalog information

/// CoreServices' catalog information, with the item's FSSpec, whose folder
/// is kept by its ID here so that the spec names it again.
OSErr carbon_FSGetCatalogInfo(const FSRef *ref, uint32_t which, void *info, HFSUniStr255 *name, FSSpec *spec, FSRef *parent)
    CARBON_SYMBOL(FSGetCatalogInfo);
OSErr carbon_FSGetCatalogInfo(const FSRef *ref, uint32_t which, void *info, HFSUniStr255 *name, FSSpec *spec, FSRef *parent) {
    static catalog_function catalog;
    if (!catalog) catalog = (catalog_function)carbon_function(CORESERVICES, "_FSGetCatalogInfo");
    if (!catalog) return unimpErr;
    OSErr error = catalog(ref, which, info, name, NULL, parent);
    char path[PATH_MAX];
    if (error == noErr && ref_path(ref, path, sizeof path)) {
        // The IDs given (a folder's own, its parent's) name it again: as
        // an FSSpec's folder, which programs make of them.
        struct stat item;
        if (stat(path, &item) == 0 && S_ISDIR(item.st_mode)) directory_id(path);
        char folder[PATH_MAX];
        snprintf(folder, sizeof folder, "%s", path);
        char *slash = strrchr(folder, '/');
        if (slash && slash != folder) {
            *slash = 0;
            directory_id(folder);
        }
        if (spec) spec_for(path, spec);
    }
    return error;
}
