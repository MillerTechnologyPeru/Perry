// Exercise Darwin libc++ plus the libSystem ABI bridges it imports.
#include <atomic>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cwchar>
#include <filesystem>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_map>
#include <copyfile.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <xlocale.h>

int main() {
    std::unordered_map<std::string, int> values;
    values.reserve(100);
    values["answer"] = 42;
    assert(values.at("answer") == 42);
    std::atomic<unsigned long long> value{0};
    std::thread thread([&] { value.wait(0); assert(value.load() == (1ULL << 32)); });
    value.store(1ULL << 32);
    value.notify_one();
    thread.join();

    char *text = nullptr;
    assert(asprintf_l(&text, nullptr, "%s %d %.1f", "value", 42, 1.5) > 0);
    assert(std::string(text) == "value 42 1.5");
    free(text);
    int number = 0;
    assert(sscanf_l("42", nullptr, "%d", &number) == 1 && number == 42);
    wchar_t wide[32];
    assert(swprintf(wide, 32, L"%d", 42) == 2 && wcscmp(wide, L"42") == 0);
    FILE *stream = tmpfile();
    assert(stream);
    assert(fputwc(L'A', stream) == L'A');
    rewind(stream);
    assert(getwc(stream) == L'A');
    assert(ungetwc(L'B', stream) == L'B' && getwc(stream) == L'B');
    fclose(stream);

    char path[] = "/tmp/perry-libcxx-XXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0);
    const timespec times[2] = {{0, UTIME_OMIT}, {0, UTIME_NOW}};
    assert(utimensat(AT_FDCWD, path, times, 0) == 0);
    copyfile_state_t state = copyfile_state_alloc();
    assert(state && copyfile_state_free(state) == 0);
    close(fd);
    unlink(path);
    std::ostringstream output;
    output << "libc++: " << values.at("answer");
    puts(output.str().c_str());
}
