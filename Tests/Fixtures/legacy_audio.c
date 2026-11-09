// Sound the way old Mac games and audio libraries play it: straight to the
// device through the HAL's I/O procs, and through the stereo mixer and
// varispeed audio units.
#include "darwin.h"

int usleep(unsigned);

typedef int OSStatus;
typedef struct { unsigned channels, bytes; void *data; } AudioBuffer;
typedef struct { unsigned count; AudioBuffer buffers[2]; } AudioBufferList;
typedef struct { unsigned char bytes[64]; } AudioTimeStamp;
typedef struct { unsigned type, subtype, manufacturer, flags, mask; } Description;
typedef OSStatus (*IOProc)(unsigned, const AudioTimeStamp *, const AudioBufferList *, const AudioTimeStamp *, AudioBufferList *,
                           const AudioTimeStamp *, void *);
typedef OSStatus (*Render)(void *, unsigned *, const AudioTimeStamp *, unsigned, unsigned, AudioBufferList *);
typedef struct { Render proc; void *refcon; } RenderCallback;

OSStatus AudioHardwareGetProperty(unsigned, unsigned *, void *);
OSStatus AudioDeviceAddIOProc(unsigned, IOProc, void *);
OSStatus AudioDeviceRemoveIOProc(unsigned, IOProc);
OSStatus AudioDeviceStart(unsigned, IOProc);
OSStatus AudioDeviceStop(unsigned, IOProc);
OSStatus AudioDeviceGetCurrentTime(unsigned, AudioTimeStamp *);
void *AudioComponentFindNext(void *, const Description *);
OSStatus AudioComponentInstanceNew(void *, void **);
OSStatus AudioUnitInitialize(void *);
OSStatus AudioUnitSetProperty(void *, unsigned, unsigned, unsigned, const void *, unsigned);
OSStatus AudioUnitSetParameter(void *, unsigned, unsigned, unsigned, float, unsigned);
OSStatus AudioUnitGetParameter(void *, unsigned, unsigned, unsigned, float *);
OSStatus AudioUnitRender(void *, unsigned *, const AudioTimeStamp *, unsigned, unsigned, AudioBufferList *);

#define FOURCC(a, b, c, d) ((unsigned)(a) << 24 | (b) << 16 | (c) << 8 | (d))

static volatile int calls;
static unsigned seen_buffers, seen_channels, seen_bytes, seen_input;
static int client_matches;

static OSStatus proc(unsigned device, const AudioTimeStamp *now, const AudioBufferList *input, const AudioTimeStamp *input_time,
                     AudioBufferList *output, const AudioTimeStamp *output_time, void *client) {
    seen_buffers = output->count;
    seen_channels = output->buffers[0].channels;
    seen_bytes = output->buffers[0].bytes;
    seen_input = input->count;
    client_matches = client == (void *)&calls && device == 2;
    calls++;
    return 0;
}

static unsigned pulled;
static float level;

static OSStatus source(void *refcon, unsigned *flags, const AudioTimeStamp *time, unsigned bus, unsigned frames, AudioBufferList *data) {
    pulled = frames;
    for (unsigned b = 0; b < data->count; b++) {
        float *samples = data->buffers[b].data;
        for (unsigned i = 0; i < frames; i++) samples[i] = level;
    }
    return 0;
}

static float left[1024], right[1024];

static void *unit(unsigned type, unsigned subtype, float input) {
    Description description = { type, subtype, FOURCC('a', 'p', 'p', 'l'), 0, 0 };
    void *found = AudioComponentFindNext(NULL, &description), *instance = NULL;
    if (!found || AudioComponentInstanceNew(found, &instance)) return NULL;
    RenderCallback callback = { source, NULL };
    AudioUnitSetProperty(instance, 23, 1, 0, &callback, sizeof callback);
    AudioUnitInitialize(instance);
    level = input;
    return instance;
}

static void render(void *instance, unsigned frames) {
    AudioBufferList list = { 2, { { 1, frames * 4, left }, { 1, frames * 4, right } } };
    AudioTimeStamp time = { { 0 } };
    unsigned flags = 0;
    AudioUnitRender(instance, &flags, &time, 0, frames, &list);
}

int main(void) {
    unsigned device = 0, size = sizeof device;
    AudioHardwareGetProperty(FOURCC('d', 'O', 'u', 't'), &size, &device);
    printf("device %u\n", device);

    AudioTimeStamp now;
    printf("before start %d\n", AudioDeviceGetCurrentTime(device, &now) == (int)FOURCC('s', 't', 'o', 'p'));
    AudioDeviceAddIOProc(device, proc, (void *)&calls);
    AudioDeviceStart(device, proc);
    for (int i = 0; i < 500 && calls < 3; i++) usleep(10000);
    printf("playing %d buffers %u channels %u bytes %u input %u client %d\n", calls >= 3, seen_buffers, seen_channels, seen_bytes, seen_input,
           client_matches);
    printf("time %d\n", AudioDeviceGetCurrentTime(device, &now));
    AudioDeviceStop(device, proc);
    int stopped = calls;
    usleep(100000);
    printf("stopped %d\n", calls == stopped);
    printf("removed %d\n", AudioDeviceRemoveIOProc(device, proc));

    void *varispeed = unit(FOURCC('a', 'u', 'f', 'c'), FOURCC('v', 'a', 'r', 'i'), 0.5f);
    float cents = 0;
    AudioUnitSetParameter(varispeed, 0, 0, 0, 2, 0);
    AudioUnitGetParameter(varispeed, 1, 0, 0, &cents);
    render(varispeed, 256);
    printf("varispeed cents %.0f pulled %u out %.2f %.2f\n", cents, pulled, left[32], right[32]);

    void *mixer = unit(FOURCC('a', 'u', 'm', 'x'), FOURCC('s', 'm', 'x', 'r'), 1);
    AudioUnitSetParameter(mixer, 1, 1, 0, 0, 0);
    render(mixer, 64);
    printf("mixer panned left %.2f %.2f\n", left[32], right[32]);
    return 0;
}
