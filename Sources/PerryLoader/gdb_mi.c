// A stand-in for Apple's gdb, which Xcode starts to run every program, even
// with breakpoints off, and drives over GDB/MI. Apple's gdb controls the
// program through Mach, which perry doesn't give, so when perry is asked to
// run it, this answers instead: enough of GDB/MI to run the program under
// perry, on the terminal Xcode gives it for its console, and to report its
// exit. Breakpoints are accepted and never hit; there's no stepping or
// variables. PERRY_GDB=native runs Apple's gdb as any other program;
// PERRY_GDB_LOG=<path> writes the conversation there.

#define _GNU_SOURCE
#include "gdb_mi.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static FILE *conversation;

static void note(const char *direction, const char *text) {
    if (!conversation) return;
    fprintf(conversation, "%s %s", direction, text);
    if (!*text || text[strlen(text) - 1] != '\n') fputc('\n', conversation);
    fflush(conversation);
}

// A line to Xcode.
static void say(const char *format, ...) {
    char *line = NULL;
    va_list arguments;
    va_start(arguments, format);
    if (vasprintf(&line, format, arguments) < 0) line = NULL;
    va_end(arguments);
    if (!line) return;
    fputs(line, stdout);
    fflush(stdout);
    note(">", line);
    free(line);
}

static void prompt(void) { say("(gdb) \n"); }

bool perry_gdb_mi_wanted(const char *executable) {
    const char *native = getenv("PERRY_GDB");
    if (native && strcmp(native, "native") == 0) return false;
    const char *name = strrchr(executable, '/');
    name = name ? name + 1 : executable;
    return strstr(executable, "/libexec/gdb/") && strncmp(name, "gdb-", 4) == 0;
}

// MARK: - The program

static char *program;        // -file-exec-and-symbols
static char *arguments;      // -exec-arguments, as one string
static char *terminal;       // tty
static pid_t child = -1;

// The environment the program gets: this process's (Xcode's), with what
// Xcode sets and unsets. Perry's scripted input for Xcode isn't passed on.
static void set_variable(const char *line) {
    char *copy = strdup(line);
    char *name = copy;
    while (*name == ' ') name++;
    char *value = strchr(name, ' ');
    if (value) *value++ = '\0';
    if (*name) setenv(name, value ? value : "", 1);
    free(copy);
}

static void unset_variable(const char *line) {
    while (*line == ' ') line++;
    if (*line) unsetenv(line);
}

// A quoted MI argument's text, or the rest of the line.
static char *unquoted(const char *text) {
    while (*text == ' ') text++;
    if (*text != '"') return strdup(text);
    char *out = malloc(strlen(text) + 1), *o = out;
    for (const char *c = text + 1; *c && *c != '"'; c++) {
        if (*c == '\\' && c[1]) c++;
        *o++ = *c;
    }
    *o = '\0';
    return out;
}

// The bundle an executable inside one is the program of: perry runs it as
// an app (its resources, its container).
static char *runnable(const char *path) {
    const char *marker = strstr(path, ".app/Contents/MacOS/");
    if (!marker) return strdup(path);
    return strndup(path, (size_t)(marker - path) + 4);
}

static void split_arguments(const char *text, char ***out, int *count) {
    *count = 0;
    *out = calloc(strlen(text ? text : "") + 2, sizeof(char *));
    if (!text) return;
    const char *c = text;
    while (*c) {
        while (*c == ' ') c++;
        if (!*c) break;
        char *word = malloc(strlen(c) + 1), *w = word;
        char quote = 0;
        for (; *c && (quote || *c != ' '); c++) {
            if (quote && *c == quote) quote = 0;
            else if (!quote && (*c == '"' || *c == '\'')) quote = *c;
            else if (*c == '\\' && c[1]) *w++ = *++c;
            else *w++ = *c;
        }
        *w = '\0';
        (*out)[(*count)++] = word;
    }
}

static bool run_program(void) {
    if (!program) return false;
    char self[PATH_MAX];
    ssize_t length = readlink("/proc/self/exe", self, sizeof self - 1);
    if (length <= 0) return false;
    self[length] = '\0';

    char **words;
    int count;
    split_arguments(arguments, &words, &count);
    char **argv = calloc((size_t)count + 3, sizeof(char *));
    argv[0] = self;
    argv[1] = runnable(program);
    for (int i = 0; i < count; i++) argv[2 + i] = words[i];

    pid_t pid = fork();
    if (pid < 0) return false;
    if (pid == 0) {
        setsid();
        if (terminal) {
            int fd = open(terminal, O_RDWR);
            if (fd >= 0) {
                ioctl(fd, TIOCSCTTY, 0);
                dup2(fd, 0);
                dup2(fd, 1);
                dup2(fd, 2);
                if (fd > 2) close(fd);
            }
        }
        unsetenv("PERRY_APPKIT_CLICKS");
        unsetenv("PERRY_APPKIT_TYPE");
        unsetenv("PERRY_APPKIT_OPEN");
        unsetenv("PERRY_APPKIT_SNAPSHOT");
        execv(self, argv);
        _exit(127);
    }
    child = pid;
    return true;
}

// The program has ended: Xcode is told how, as gdb tells it.
static void report_exit(int status) {
    child = -1;
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0)
        say("*stopped,reason=\"exited-normally\"\n");
    else if (WIFEXITED(status))
        say("*stopped,reason=\"exited\",exit-code=\"%o\"\n", WEXITSTATUS(status));
    else if (WIFSIGNALED(status))
        say("*stopped,reason=\"exited-signalled\",signal-name=\"SIG%s\",signal-meaning=\"%s\"\n",
            sigabbrev_np(WTERMSIG(status)) ? sigabbrev_np(WTERMSIG(status)) : "UNKNOWN",
            strsignal(WTERMSIG(status)));
    prompt();
}

static void stop_program(void) {
    if (child <= 0) return;
    kill(-child, SIGKILL);
    kill(child, SIGKILL);
    int status = 0;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
    child = -1;
}

// MARK: - Commands

static bool starts(const char *command, const char *name) {
    size_t length = strlen(name);
    return strncmp(command, name, length) == 0 && (command[length] == '\0' || command[length] == ' ' || command[length] == '\n');
}

// Answers one command; false when gdb is to exit.
static bool answer(char *line) {
    line[strcspn(line, "\r\n")] = '\0';
    const char *command = line;
    while (*command >= '0' && *command <= '9') command++;
    int token = (int)(command - line);
    const char *rest = strchr(command, ' ');
    rest = rest ? rest + 1 : "";

    if (starts(command, "-gdb-exit") || starts(command, "quit")) {
        stop_program();
        // Apple's gdb answers ^done; Xcode's parser knows no ^exit.
        say("%.*s^done\n", token, line);
        return false;
    }
    if (starts(command, "-gdb-version")) {
        say("~\"GNU gdb 6.3.50-20050815 (Apple version gdb-1518) (perry)\\n\"\n");
    } else if (starts(command, "-gdb-set") && strncmp(rest, "env ", 4) == 0) {
        set_variable(rest + 4);
    } else if (starts(command, "-gdb-unset") && strncmp(rest, "env ", 4) == 0) {
        unset_variable(rest + 4);
    } else if (starts(command, "tty") || starts(command, "-inferior-tty-set")) {
        free(terminal);
        terminal = unquoted(rest);
    } else if (starts(command, "-file-exec-and-symbols") || starts(command, "-file-exec-file") || starts(command, "file")) {
        free(program);
        program = unquoted(rest);
    } else if (starts(command, "-exec-arguments")) {
        free(arguments);
        arguments = strdup(rest);
    } else if (starts(command, "-exec-run") || starts(command, "run")) {
        if (!run_program()) {
            say("%.*s^error,msg=\"perry could not run %s\"\n", token, line, program ? program : "the program");
            prompt();
            return true;
        }
        say("%.*s^running\n", token, line);
        prompt();
        return true;
    } else if (starts(command, "-exec-interrupt") || starts(command, "kill") || starts(command, "-target-kill")
               || starts(command, "-exec-abort")) {
        if (child > 0) {
            stop_program();
            say("%.*s^done\n", token, line);
            say("*stopped,reason=\"exited-signalled\",signal-name=\"SIGKILL\",signal-meaning=\"Killed\"\n");
            prompt();
            return true;
        }
    } else if (starts(command, "-mi-verify-command")) {
        say("%.*s^done,command={exists=\"false\"}\n", token, line);
        prompt();
        return true;
    } else if (starts(command, "-data-list-register-names")) {
        say("%.*s^done,register-names=[]\n", token, line);
        prompt();
        return true;
    }
    say("%.*s^done\n", token, line);
    prompt();
    return true;
}

int perry_gdb_mi(int argc, char **argv) {
    const char *log = getenv("PERRY_GDB_LOG");
    if (log) conversation = fopen(log, "a");
    for (int i = 0; i < argc; i++) note("#", argv[i]);
    signal(SIGPIPE, SIG_IGN);

    prompt();
    char *line = NULL;
    size_t size = 0;
    FILE *input = stdin;
    for (;;) {
        // While the program runs, its end is looked for between commands.
        struct pollfd file = { .fd = fileno(input), .events = POLLIN };
        int ready = poll(&file, 1, child > 0 ? 200 : -1);
        if (child > 0) {
            int status = 0;
            if (waitpid(child, &status, WNOHANG) == child) report_exit(status);
        }
        if (ready <= 0) continue;
        if (getline(&line, &size, input) <= 0) break;
        note("<", line);
        if (!answer(line)) break;
    }
    stop_program();
    free(line);
    return 0;
}
