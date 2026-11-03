// System sounds: IDs for the files apps register, completions called as if
// each sound had played.

#include "PerryAudioToolbox.h"

#include <pthread.h>
#include <stddef.h>

typedef void (*completion_proc)(SystemSoundID sound, void *data);

/// kAudioServicesUnsupportedPropertyError, 'pty?'.
#define UNSUPPORTED_PROPERTY 0x7074793f

static SystemSoundID next_id = 4096;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

struct completion {
    SystemSoundID sound;
    completion_proc proc;
    void *data;
};
static struct completion completions[64];
static int completion_count;

OSStatus darwin_AudioServicesCreateSystemSoundID(const void *url, SystemSoundID *sound) DARWIN_SYMBOL(AudioServicesCreateSystemSoundID);
OSStatus darwin_AudioServicesCreateSystemSoundID(const void *url, SystemSoundID *sound) {
    if (!url || !sound) return -50; // paramErr
    pthread_mutex_lock(&lock);
    *sound = next_id++;
    pthread_mutex_unlock(&lock);
    return 0;
}

OSStatus darwin_AudioServicesDisposeSystemSoundID(SystemSoundID sound) DARWIN_SYMBOL(AudioServicesDisposeSystemSoundID);
OSStatus darwin_AudioServicesDisposeSystemSoundID(SystemSoundID sound) { return 0; }

/// The sound's completion, as if it had finished playing.
static void finished(SystemSoundID sound) {
    pthread_mutex_lock(&lock);
    struct completion found = {0};
    for (int i = 0; i < completion_count; i++)
        if (completions[i].sound == sound) found = completions[i];
    pthread_mutex_unlock(&lock);
    if (found.proc) found.proc(sound, found.data);
}

void darwin_AudioServicesPlaySystemSound(SystemSoundID sound) DARWIN_SYMBOL(AudioServicesPlaySystemSound);
void darwin_AudioServicesPlaySystemSound(SystemSoundID sound) { finished(sound); }

void darwin_AudioServicesPlayAlertSound(SystemSoundID sound) DARWIN_SYMBOL(AudioServicesPlayAlertSound);
void darwin_AudioServicesPlayAlertSound(SystemSoundID sound) { finished(sound); }

/// A block's invoke function is its third pointer.
static void call_block(void *block) {
    if (!block) return;
    void (*invoke)(void *) = ((void (**)(void *))block)[2];
    invoke(block);
}

void darwin_AudioServicesPlaySystemSoundWithCompletion(SystemSoundID sound, void *block) DARWIN_SYMBOL(AudioServicesPlaySystemSoundWithCompletion);
void darwin_AudioServicesPlaySystemSoundWithCompletion(SystemSoundID sound, void *block) { call_block(block); }

void darwin_AudioServicesPlayAlertSoundWithCompletion(SystemSoundID sound, void *block) DARWIN_SYMBOL(AudioServicesPlayAlertSoundWithCompletion);
void darwin_AudioServicesPlayAlertSoundWithCompletion(SystemSoundID sound, void *block) { call_block(block); }

OSStatus darwin_AudioServicesAddSystemSoundCompletion(SystemSoundID sound, void *run_loop, void *mode, completion_proc proc, void *data)
    DARWIN_SYMBOL(AudioServicesAddSystemSoundCompletion);
OSStatus darwin_AudioServicesAddSystemSoundCompletion(SystemSoundID sound, void *run_loop, void *mode, completion_proc proc, void *data) {
    pthread_mutex_lock(&lock);
    OSStatus status = -50;
    if (completion_count < 64) {
        completions[completion_count++] = (struct completion){ sound, proc, data };
        status = 0;
    }
    pthread_mutex_unlock(&lock);
    return status;
}

void darwin_AudioServicesRemoveSystemSoundCompletion(SystemSoundID sound) DARWIN_SYMBOL(AudioServicesRemoveSystemSoundCompletion);
void darwin_AudioServicesRemoveSystemSoundCompletion(SystemSoundID sound) {
    pthread_mutex_lock(&lock);
    for (int i = 0; i < completion_count; i++) {
        if (completions[i].sound == sound) completions[i--] = completions[--completion_count];
    }
    pthread_mutex_unlock(&lock);
}

OSStatus darwin_AudioServicesGetProperty(AudioServicesPropertyID property, uint32_t specifier_size, const void *specifier,
                                         uint32_t *size, void *data) DARWIN_SYMBOL(AudioServicesGetProperty);
OSStatus darwin_AudioServicesGetProperty(AudioServicesPropertyID property, uint32_t specifier_size, const void *specifier,
                                         uint32_t *size, void *data) {
    return UNSUPPORTED_PROPERTY;
}

OSStatus darwin_AudioServicesSetProperty(AudioServicesPropertyID property, uint32_t specifier_size, const void *specifier,
                                         uint32_t size, const void *data) DARWIN_SYMBOL(AudioServicesSetProperty);
OSStatus darwin_AudioServicesSetProperty(AudioServicesPropertyID property, uint32_t specifier_size, const void *specifier,
                                         uint32_t size, const void *data) {
    return UNSUPPORTED_PROPERTY;
}
