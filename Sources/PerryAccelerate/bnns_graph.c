// BNNSGraph: compiled Core ML graphs. Perry cannot compile .mlmodelc
// models, so compiling fails (a null graph); the compile options and
// contexts are real objects so callers can make, set and destroy them.

#include "bnns.h"

typedef struct {
    bool single_thread;
    bool debug_info;
    BNNSGraphOptimizationPreference preference;
} bnns_graph_options;

bnns_graph_compile_options_t BNNSGraphCompileOptionsMakeDefault(void) {
    bnns_graph_compile_options_t o = { calloc(1, sizeof(bnns_graph_options)), sizeof(bnns_graph_options) };
    if (!o.data) o.size = 0;
    return o;
}

void BNNSGraphCompileOptionsDestroy(bnns_graph_compile_options_t options) {
    if (options.data && options.size == sizeof(bnns_graph_options)) free(options.data);
}

static bnns_graph_options *bnns_options(bnns_graph_compile_options_t o) {
    return o.data && o.size == sizeof(bnns_graph_options) ? o.data : NULL;
}

void BNNSGraphCompileOptionsSetTargetSingleThread(bnns_graph_compile_options_t options, bool value) {
    bnns_graph_options *o = bnns_options(options);
    if (o) o->single_thread = value;
}

void BNNSGraphCompileOptionsSetGenerateDebugInfo(bnns_graph_compile_options_t options, bool value) {
    bnns_graph_options *o = bnns_options(options);
    if (o) o->debug_info = value;
}

void BNNSGraphCompileOptionsSetOptimizationPreference(bnns_graph_compile_options_t options, BNNSGraphOptimizationPreference preference) {
    bnns_graph_options *o = bnns_options(options);
    if (o) o->preference = preference;
}

bnns_graph_t BNNSGraphCompileFromFile_v2(const char *filename, const char *function, bnns_graph_compile_options_t options) {
    (void)filename; (void)function; (void)options;
    bnns_graph_t g = { NULL, 0 };
    return g;
}

size_t BNNSGraphGetArgumentCount(bnns_graph_t graph, const char *function) {
    (void)graph; (void)function;
    return 0;
}

size_t BNNSGraphGetFunctionCount(bnns_graph_t graph) {
    (void)graph;
    return 0;
}

int BNNSGraphGetArgumentNames(bnns_graph_t graph, const char *function, size_t count, const char **names) {
    (void)graph; (void)function;
    if (names) for (size_t i = 0; i < count; i++) names[i] = NULL;
    return -1;
}

int BNNSGraphGetFunctionNames(bnns_graph_t graph, size_t count, const char **names) {
    (void)graph;
    if (names) for (size_t i = 0; i < count; i++) names[i] = NULL;
    return -1;
}

size_t BNNSGraphGetArgumentPosition(bnns_graph_t graph, const char *function, const char *argument) {
    (void)graph; (void)function; (void)argument;
    return SIZE_MAX;
}

// A context records its settings; with no compiled graph nothing can run.
typedef struct {
    BNNSGraphArgumentType argument_type;
    uint64_t batch_size;
    size_t advance_count;
    bool nan_checks;
} bnns_graph_context;

bnns_graph_context_t BNNSGraphContextMake(bnns_graph_t graph) {
    bnns_graph_context_t c = { NULL, 0 };
    if (!graph.data) return c;
    c.data = calloc(1, sizeof(bnns_graph_context));
    c.size = c.data ? sizeof(bnns_graph_context) : 0;
    return c;
}

static bnns_graph_context *bnns_context(bnns_graph_context_t c) {
    return c.data && c.size == sizeof(bnns_graph_context) ? c.data : NULL;
}

void BNNSGraphContextDestroy_v2(bnns_graph_context_t context) {
    free(bnns_context(context));
}

int BNNSGraphContextSetDynamicShapes_v2(bnns_graph_context_t context, const char *function, size_t shapes_count, bnns_graph_shape_t *shapes) {
    (void)function; (void)shapes_count; (void)shapes;
    (void)context;
    return -1;
}

int BNNSGraphContextSetBatchSize_v2(bnns_graph_context_t context, const char *function, uint64_t batch_size) {
    (void)function;
    bnns_graph_context *c = bnns_context(context);
    if (!c) return -1;
    c->batch_size = batch_size;
    return 0;
}

int BNNSGraphContextSetArgumentType(bnns_graph_context_t context, BNNSGraphArgumentType argument_type) {
    bnns_graph_context *c = bnns_context(context);
    if (!c || (argument_type != BNNSGraphArgumentTypePointer && argument_type != BNNSGraphArgumentTypeTensor)) return -1;
    c->argument_type = argument_type;
    return 0;
}

void BNNSGraphContextEnableNanAndInfChecks(bnns_graph_context_t context, bool enable) {
    bnns_graph_context *c = bnns_context(context);
    if (c) c->nan_checks = enable;
}

int BNNSGraphContextSetStreamingAdvanceCount(bnns_graph_context_t context, size_t advance_count) {
    bnns_graph_context *c = bnns_context(context);
    if (!c) return -1;
    c->advance_count = advance_count;
    return 0;
}

int BNNSGraphContextExecute_v2(bnns_graph_context_t context, const char *function, size_t argument_count, bnns_graph_argument_t *arguments,
                               size_t workspace_size, char *workspace) {
    (void)context; (void)function; (void)argument_count; (void)arguments; (void)workspace_size; (void)workspace;
    return -1;
}

int BNNSGraphContextGetTensor(bnns_graph_context_t context, const char *function, const char *argument, bool fill_known_dynamic_shapes,
                              BNNSTensor *tensor) {
    (void)context; (void)function; (void)argument; (void)fill_known_dynamic_shapes;
    if (tensor) memset(tensor, 0, sizeof *tensor);
    return -1;
}

int BNNSGraphTensorFillStrides(bnns_graph_t graph, const char *function, const char *argument, BNNSTensor *tensor) {
    (void)function; (void)argument;
    if (!tensor || tensor->rank > BNNS_MAX_TENSOR_DIMENSION) return -1;
    // Packed first-major strides from the shape; this needs no graph.
    ssize_t stride = 1;
    for (int k = tensor->rank - 1; k >= 0; k--) {
        if (tensor->shape[k] < 0) return -1;
        tensor->stride[k] = stride;
        stride *= tensor->shape[k];
    }
    (void)graph;
    return 0;
}
