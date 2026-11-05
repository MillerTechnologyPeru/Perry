// Audio processing graphs, over the audio units here: a node is a unit,
// made when it is added; connecting nodes and setting input callbacks set
// the units' connection and callback properties at once; starting the
// graph starts its output units.

#include "PerryAudioToolbox.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

typedef struct AudioComponentDescription {
    uint32_t componentType, componentSubType, componentManufacturer, componentFlags, componentFlagsMask;
} AudioComponentDescription;

typedef struct AURenderCallbackStruct {
    void *inputProc;
    void *inputProcRefCon;
} AURenderCallbackStruct;

typedef struct AudioUnitConnection {
    void *sourceAudioUnit;
    uint32_t sourceOutputNumber;
    uint32_t destInputNumber;
} AudioUnitConnection;

void *darwin_AudioComponentFindNext(const void *after, const AudioComponentDescription *description) DARWIN_SYMBOL(AudioComponentFindNext);
OSStatus darwin_AudioComponentInstanceNew(const void *component, void **out) DARWIN_SYMBOL(AudioComponentInstanceNew);
OSStatus darwin_AudioComponentInstanceDispose(void *unit) DARWIN_SYMBOL(AudioComponentInstanceDispose);
OSStatus darwin_AudioUnitInitialize(void *unit) DARWIN_SYMBOL(AudioUnitInitialize);
OSStatus darwin_AudioUnitUninitialize(void *unit) DARWIN_SYMBOL(AudioUnitUninitialize);
OSStatus darwin_AudioUnitSetProperty(void *unit, uint32_t id, uint32_t scope, uint32_t element, const void *value, uint32_t size) DARWIN_SYMBOL(AudioUnitSetProperty);
OSStatus darwin_AudioOutputUnitStart(void *unit) DARWIN_SYMBOL(AudioOutputUnitStart);
OSStatus darwin_AudioOutputUnitStop(void *unit) DARWIN_SYMBOL(AudioOutputUnitStop);
OSStatus darwin_AudioUnitAddRenderNotify(void *unit, void *proc, void *refcon) DARWIN_SYMBOL(AudioUnitAddRenderNotify);
OSStatus darwin_AudioUnitRemoveRenderNotify(void *unit, void *proc, void *refcon) DARWIN_SYMBOL(AudioUnitRemoveRenderNotify);

#define kAUGraphErr_NodeNotFound (-10860)
#define kAUGraphErr_InvalidConnection (-10861)
#define kAUGraphErr_OutputNodeErr (-10862)
#define kAUGraphErr_CannotDoInCurrentContext (-10863)
#define kAUGraphErr_InvalidAudioUnit (-10864)
#define kAudioUnitProperty_MakeConnection 1
#define kAudioUnitProperty_SetRenderCallback 23
#define kAudioUnitScope_Input 1
#define kAudioUnitType_Output FOURCC('a', 'u', 'o', 'u')

typedef struct node {
    int32_t id;
    AudioComponentDescription description;
    void *unit;
} node;

typedef struct graph {
    uint32_t magic;
    pthread_mutex_t lock;
    node *nodes;
    uint32_t count, capacity;
    int32_t next_id;
    bool open, initialized, running;
} graph;

#define GRAPH_MAGIC FOURCC('p', 'a', 'g', 'r')

static graph *valid(void *handle) {
    graph *g = handle;
    return g && g->magic == GRAPH_MAGIC ? g : NULL;
}

static node *find(graph *g, int32_t id) {
    for (uint32_t i = 0; i < g->count; i++) if (g->nodes[i].id == id) return &g->nodes[i];
    return NULL;
}

OSStatus darwin_NewAUGraph(void **out) DARWIN_SYMBOL(NewAUGraph);
OSStatus darwin_NewAUGraph(void **out) {
    if (!out) return kAudio_ParamError;
    graph *g = calloc(1, sizeof *g);
    if (!g) return kAudio_MemFullError;
    g->magic = GRAPH_MAGIC;
    g->next_id = 1;
    pthread_mutex_init(&g->lock, NULL);
    *out = g;
    perry_audio_trace("AUGraph %p: new", (void *)g);
    return 0;
}

OSStatus darwin_AUGraphAddNode(void *handle, const AudioComponentDescription *description, int32_t *out) DARWIN_SYMBOL(AUGraphAddNode);
OSStatus darwin_AUGraphAddNode(void *handle, const AudioComponentDescription *description, int32_t *out) {
    graph *g = valid(handle);
    if (!g || !description || !out) return kAudio_ParamError;
    const void *component = darwin_AudioComponentFindNext(NULL, description);
    if (!component) {
        perry_audio_trace("AUGraph %p: no unit for '%.4s'/'%.4s'", handle, (const char *)&description->componentType,
                          (const char *)&description->componentSubType);
        return kAUGraphErr_InvalidAudioUnit;
    }
    void *unit = NULL;
    OSStatus status = darwin_AudioComponentInstanceNew(component, &unit);
    if (status) return status;
    pthread_mutex_lock(&g->lock);
    if (g->count == g->capacity) {
        uint32_t capacity = g->capacity ? g->capacity * 2 : 8;
        node *grown = realloc(g->nodes, capacity * sizeof *grown);
        if (!grown) { pthread_mutex_unlock(&g->lock); darwin_AudioComponentInstanceDispose(unit); return kAudio_MemFullError; }
        g->nodes = grown;
        g->capacity = capacity;
    }
    node *n = &g->nodes[g->count++];
    *n = (node){ g->next_id++, *description, unit };
    *out = n->id;
    pthread_mutex_unlock(&g->lock);
    return 0;
}

OSStatus darwin_AUGraphRemoveNode(void *handle, int32_t id) DARWIN_SYMBOL(AUGraphRemoveNode);
OSStatus darwin_AUGraphRemoveNode(void *handle, int32_t id) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    node *n = find(g, id);
    if (!n) { pthread_mutex_unlock(&g->lock); return kAUGraphErr_NodeNotFound; }
    void *unit = n->unit;
    *n = g->nodes[--g->count];
    pthread_mutex_unlock(&g->lock);
    darwin_AudioOutputUnitStop(unit);
    darwin_AudioComponentInstanceDispose(unit);
    return 0;
}

OSStatus darwin_AUGraphGetNodeCount(void *handle, uint32_t *count) DARWIN_SYMBOL(AUGraphGetNodeCount);
OSStatus darwin_AUGraphGetNodeCount(void *handle, uint32_t *count) {
    graph *g = valid(handle);
    if (!g || !count) return kAudio_ParamError;
    *count = g->count;
    return 0;
}

OSStatus darwin_AUGraphGetIndNode(void *handle, uint32_t index, int32_t *out) DARWIN_SYMBOL(AUGraphGetIndNode);
OSStatus darwin_AUGraphGetIndNode(void *handle, uint32_t index, int32_t *out) {
    graph *g = valid(handle);
    if (!g || !out) return kAudio_ParamError;
    if (index >= g->count) return kAUGraphErr_NodeNotFound;
    *out = g->nodes[index].id;
    return 0;
}

OSStatus darwin_AUGraphNodeInfo(void *handle, int32_t id, AudioComponentDescription *description, void **unit)
    DARWIN_SYMBOL(AUGraphNodeInfo);
OSStatus darwin_AUGraphNodeInfo(void *handle, int32_t id, AudioComponentDescription *description, void **unit) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    node *n = find(g, id);
    if (n) {
        if (description) *description = n->description;
        if (unit) *unit = n->unit;
    }
    pthread_mutex_unlock(&g->lock);
    if (!n) perry_audio_trace("AUGraph %p: no node %d", handle, id);
    return n ? 0 : kAUGraphErr_NodeNotFound;
}

static void *unit_of(graph *g, int32_t id) {
    pthread_mutex_lock(&g->lock);
    node *n = find(g, id);
    void *unit = n ? n->unit : NULL;
    pthread_mutex_unlock(&g->lock);
    return unit;
}

OSStatus darwin_AUGraphConnectNodeInput(void *handle, int32_t source, uint32_t output, int32_t destination, uint32_t input)
    DARWIN_SYMBOL(AUGraphConnectNodeInput);
OSStatus darwin_AUGraphConnectNodeInput(void *handle, int32_t source, uint32_t output, int32_t destination, uint32_t input) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    void *from = unit_of(g, source), *to = unit_of(g, destination);
    if (!from || !to) return kAUGraphErr_NodeNotFound;
    AudioUnitConnection connection = { from, output, input };
    OSStatus status = darwin_AudioUnitSetProperty(to, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, input,
                                                  &connection, sizeof connection);
    return status ? kAUGraphErr_InvalidConnection : 0;
}

OSStatus darwin_AUGraphDisconnectNodeInput(void *handle, int32_t destination, uint32_t input) DARWIN_SYMBOL(AUGraphDisconnectNodeInput);
OSStatus darwin_AUGraphDisconnectNodeInput(void *handle, int32_t destination, uint32_t input) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    void *to = unit_of(g, destination);
    if (!to) return kAUGraphErr_NodeNotFound;
    return darwin_AudioUnitSetProperty(to, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, input, NULL, 0);
}

OSStatus darwin_AUGraphSetNodeInputCallback(void *handle, int32_t id, uint32_t input, const AURenderCallbackStruct *callback)
    DARWIN_SYMBOL(AUGraphSetNodeInputCallback);
OSStatus darwin_AUGraphSetNodeInputCallback(void *handle, int32_t id, uint32_t input, const AURenderCallbackStruct *callback) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    void *unit = unit_of(g, id);
    if (!unit) return kAUGraphErr_NodeNotFound;
    return darwin_AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, input,
                                       callback, callback ? sizeof *callback : 0);
}

OSStatus darwin_AUGraphClearConnections(void *handle) DARWIN_SYMBOL(AUGraphClearConnections);
OSStatus darwin_AUGraphClearConnections(void *handle) {
    return valid(handle) ? 0 : kAudio_ParamError;
}

OSStatus darwin_AUGraphOpen(void *handle) DARWIN_SYMBOL(AUGraphOpen);
OSStatus darwin_AUGraphOpen(void *handle) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    g->open = true;
    return 0;
}

OSStatus darwin_AUGraphClose(void *handle) DARWIN_SYMBOL(AUGraphClose);
OSStatus darwin_AUGraphClose(void *handle) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    g->open = false;
    return 0;
}

OSStatus darwin_AUGraphInitialize(void *handle) DARWIN_SYMBOL(AUGraphInitialize);
OSStatus darwin_AUGraphInitialize(void *handle) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    for (uint32_t i = 0; i < g->count; i++) darwin_AudioUnitInitialize(g->nodes[i].unit);
    g->initialized = true;
    return 0;
}

OSStatus darwin_AUGraphUninitialize(void *handle) DARWIN_SYMBOL(AUGraphUninitialize);
OSStatus darwin_AUGraphUninitialize(void *handle) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    for (uint32_t i = 0; i < g->count; i++) darwin_AudioUnitUninitialize(g->nodes[i].unit);
    g->initialized = false;
    return 0;
}

/// Starting starts the output units, which pull the rest.
OSStatus darwin_AUGraphStart(void *handle) DARWIN_SYMBOL(AUGraphStart);
OSStatus darwin_AUGraphStart(void *handle) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    bool output = false;
    for (uint32_t i = 0; i < g->count; i++) {
        if (g->nodes[i].description.componentType == kAudioUnitType_Output) {
            darwin_AudioOutputUnitStart(g->nodes[i].unit);
            output = true;
        }
    }
    if (!output) return kAUGraphErr_OutputNodeErr;
    g->running = true;
    return 0;
}

OSStatus darwin_AUGraphStop(void *handle) DARWIN_SYMBOL(AUGraphStop);
OSStatus darwin_AUGraphStop(void *handle) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    for (uint32_t i = 0; i < g->count; i++) {
        if (g->nodes[i].description.componentType == kAudioUnitType_Output) darwin_AudioOutputUnitStop(g->nodes[i].unit);
    }
    g->running = false;
    return 0;
}

OSStatus darwin_AUGraphIsRunning(void *handle, uint8_t *running) DARWIN_SYMBOL(AUGraphIsRunning);
OSStatus darwin_AUGraphIsRunning(void *handle, uint8_t *running) {
    graph *g = valid(handle);
    if (!g || !running) return kAudio_ParamError;
    *running = g->running;
    return 0;
}

OSStatus darwin_AUGraphIsInitialized(void *handle, uint8_t *initialized) DARWIN_SYMBOL(AUGraphIsInitialized);
OSStatus darwin_AUGraphIsInitialized(void *handle, uint8_t *initialized) {
    graph *g = valid(handle);
    if (!g || !initialized) return kAudio_ParamError;
    *initialized = g->initialized;
    return 0;
}

OSStatus darwin_AUGraphIsOpen(void *handle, uint8_t *open) DARWIN_SYMBOL(AUGraphIsOpen);
OSStatus darwin_AUGraphIsOpen(void *handle, uint8_t *open) {
    graph *g = valid(handle);
    if (!g || !open) return kAudio_ParamError;
    *open = g->open;
    return 0;
}

/// Changes take effect when made, so there is nothing to apply.
OSStatus darwin_AUGraphUpdate(void *handle, uint8_t *updated) DARWIN_SYMBOL(AUGraphUpdate);
OSStatus darwin_AUGraphUpdate(void *handle, uint8_t *updated) {
    if (!valid(handle)) return kAudio_ParamError;
    if (updated) *updated = 1;
    return 0;
}

OSStatus darwin_AUGraphGetCPULoad(void *handle, float *load) DARWIN_SYMBOL(AUGraphGetCPULoad);
OSStatus darwin_AUGraphGetCPULoad(void *handle, float *load) {
    if (!valid(handle) || !load) return kAudio_ParamError;
    *load = 0;
    return 0;
}

/// The graph's render notifications are its output units'.
OSStatus darwin_AUGraphAddRenderNotify(void *handle, void *proc, void *refcon) DARWIN_SYMBOL(AUGraphAddRenderNotify);
OSStatus darwin_AUGraphAddRenderNotify(void *handle, void *proc, void *refcon) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    for (uint32_t i = 0; i < g->count; i++) {
        if (g->nodes[i].description.componentType == kAudioUnitType_Output) darwin_AudioUnitAddRenderNotify(g->nodes[i].unit, proc, refcon);
    }
    return 0;
}

OSStatus darwin_AUGraphRemoveRenderNotify(void *handle, void *proc, void *refcon) DARWIN_SYMBOL(AUGraphRemoveRenderNotify);
OSStatus darwin_AUGraphRemoveRenderNotify(void *handle, void *proc, void *refcon) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    for (uint32_t i = 0; i < g->count; i++) {
        if (g->nodes[i].description.componentType == kAudioUnitType_Output) darwin_AudioUnitRemoveRenderNotify(g->nodes[i].unit, proc, refcon);
    }
    return 0;
}

OSStatus darwin_DisposeAUGraph(void *handle) DARWIN_SYMBOL(DisposeAUGraph);
OSStatus darwin_DisposeAUGraph(void *handle) {
    graph *g = valid(handle);
    if (!g) return kAudio_ParamError;
    perry_audio_trace("AUGraph %p: disposed", handle);
    darwin_AUGraphStop(g);
    for (uint32_t i = 0; i < g->count; i++) darwin_AudioComponentInstanceDispose(g->nodes[i].unit);
    g->magic = 0;
    free(g->nodes);
    pthread_mutex_destroy(&g->lock);
    free(g);
    return 0;
}
