#ifndef PERRY_BNNS_H
#define PERRY_BNNS_H

// BNNS (Basic Neural Network Subroutines): its types with Darwin's LP64
// layouts, the functions Perry exports, and the helpers bnns.c,
// bnns_filters.c and bnns_graph.c share.
//
// Arrays: a BNNSNDArrayDescriptor's layout gives its rank. Helpers here see
// every array "logically": dimension k has size[k] and the stride the layout
// pairs with it (first-major layouts pair size[k] with stride[rank-1-k]).
// A stride of 0 means packed. bnns_read and bnns_write move an array to and
// from a dense float buffer whose dimension 0 varies fastest.

#include "PerryAccelerate.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#define BNNS_HIDDEN __attribute__((visibility("hidden")))

// MARK: - Constants

typedef uint32_t BNNSDataType;
enum {
    BNNSDataTypeFloatBit = 0x10000,
    BNNSDataTypeFloat16 = 0x10010,
    BNNSDataTypeFloat32 = 0x10020,
    BNNSDataTypeBFloat16 = 0x18010,
    BNNSDataTypeIntBit = 0x20000,
    BNNSDataTypeInt1 = 0x20001,
    BNNSDataTypeInt2 = 0x20002,
    BNNSDataTypeInt4 = 0x20004,
    BNNSDataTypeInt8 = 0x20008,
    BNNSDataTypeInt16 = 0x20010,
    BNNSDataTypeInt32 = 0x20020,
    BNNSDataTypeInt64 = 0x20040,
    BNNSDataTypeUIntBit = 0x40000,
    BNNSDataTypeUInt1 = 0x40001,
    BNNSDataTypeUInt2 = 0x40002,
    BNNSDataTypeUInt3 = 0x40003,
    BNNSDataTypeUInt4 = 0x40004,
    BNNSDataTypeUInt6 = 0x40006,
    BNNSDataTypeUInt8 = 0x40008,
    BNNSDataTypeUInt16 = 0x40010,
    BNNSDataTypeUInt32 = 0x40020,
    BNNSDataTypeUInt64 = 0x40040,
    BNNSDataTypeIndexedBit = 0x80000,
    BNNSDataTypeIndexed1 = 0x80001,
    BNNSDataTypeIndexed2 = 0x80002,
    BNNSDataTypeIndexed4 = 0x80004,
    BNNSDataTypeIndexed8 = 0x80008,
    BNNSDataTypeMiscellaneousBit = 0x100000,
    BNNSDataTypeBoolean = 0x100008,
};

typedef uint32_t BNNSPoolingFunction;
enum {
    BNNSPoolingFunctionMax = 0,
    BNNSPoolingFunctionAverageCountIncludePadding = 1,
    BNNSPoolingFunctionAverageCountExcludePadding = 2,
    BNNSPoolingFunctionUnMax = 3,
    BNNSPoolingFunctionL2Norm = 4,
};

typedef uint32_t BNNSActivationFunction;
enum {
    BNNSActivationFunctionIdentity = 0,
    BNNSActivationFunctionRectifiedLinear = 1,
    BNNSActivationFunctionLeakyRectifiedLinear = 2,
    BNNSActivationFunctionSigmoid = 3,
    BNNSActivationFunctionTanh = 4,
    BNNSActivationFunctionScaledTanh = 5,
    BNNSActivationFunctionAbs = 6,
    BNNSActivationFunctionLinear = 7,
    BNNSActivationFunctionClamp = 8,
    BNNSActivationFunctionIntegerLinearSaturate = 9,
    BNNSActivationFunctionIntegerLinearSaturatePerChannel = 10,
    BNNSActivationFunctionSoftmax = 11,
    BNNSActivationFunctionGELUApproximation = 12,
    BNNSActivationFunctionGumbel = 13,
    BNNSActivationFunctionGumbelMax = 14,
    BNNSActivationFunctionHardSigmoid = 15,
    BNNSActivationFunctionSoftplus = 16,
    BNNSActivationFunctionSoftsign = 17,
    BNNSActivationFunctionELU = 18,
    BNNSActivationFunctionClampedLeakyRectifiedLinear = 19,
    BNNSActivationFunctionLinearWithBias = 20,
    BNNSActivationFunctionLogSoftmax = 21,
    BNNSActivationFunctionLogSigmoid = 22,
    BNNSActivationFunctionSELU = 23,
    BNNSActivationFunctionCELU = 24,
    BNNSActivationFunctionHardShrink = 25,
    BNNSActivationFunctionSoftShrink = 26,
    BNNSActivationFunctionTanhShrink = 27,
    BNNSActivationFunctionThreshold = 28,
    BNNSActivationFunctionPReLUPerChannel = 29,
    BNNSActivationFunctionGELUApproximation2 = 30,
    BNNSActivationFunctionHardSwish = 30,
    BNNSActivationFunctionSiLU = 31,
    BNNSActivationFunctionReLU6 = 32,
    BNNSActivationFunctionErf = 33,
    BNNSActivationFunctionGELU = 34,
    BNNSActivationFunctionGELUApproximationSigmoid = 35,
};

typedef uint32_t BNNSFlags;
enum { BNNSFlagsUseClientPtr = 1 };

typedef uint32_t BNNSLossFunction;
enum {
    BNNSLossFunctionSoftmaxCrossEntropy = 1,
    BNNSLossFunctionSigmoidCrossEntropy = 2,
    BNNSLossFunctionMeanSquareError = 3,
    BNNSLossFunctionHuber = 4,
    BNNSLossFunctionYolo = 5,
    BNNSLossFunctionLog = 6,
    BNNSLossFunctionCosineDistance = 7,
    BNNSLossFunctionHinge = 8,
    BNNSLossFunctionMeanAbsoluteError = 9,
    BNNSLossFunctionCategoricalCrossEntropy = 10,
};

typedef uint32_t BNNSLossReductionFunction;
enum {
    BNNSLossReductionNone = 0,
    BNNSLossReductionSum = 1,
    BNNSLossReductionWeightedMean = 2,
    BNNSLossReductionMean = 3,
    BNNSLossReductionNonZeroWeightMean = 4,
};

typedef uint32_t BNNSArithmeticFunction;
enum {
    BNNSArithmeticAdd = 0, BNNSArithmeticSubtract = 1, BNNSArithmeticMultiply = 2, BNNSArithmeticDivide = 3,
    BNNSArithmeticSquareRoot = 4, BNNSArithmeticReciprocalSquareRoot = 5, BNNSArithmeticCeil = 6,
    BNNSArithmeticFloor = 7, BNNSArithmeticRound = 8, BNNSArithmeticSin = 9, BNNSArithmeticCos = 10,
    BNNSArithmeticTan = 11, BNNSArithmeticAsin = 12, BNNSArithmeticAcos = 13, BNNSArithmeticAtan = 14,
    BNNSArithmeticSinh = 15, BNNSArithmeticCosh = 16, BNNSArithmeticTanh = 17, BNNSArithmeticAsinh = 18,
    BNNSArithmeticAcosh = 19, BNNSArithmeticAtanh = 20, BNNSArithmeticPow = 21, BNNSArithmeticExp = 22,
    BNNSArithmeticExp2 = 23, BNNSArithmeticLog = 24, BNNSArithmeticLog2 = 25, BNNSArithmeticMultiplyNoNaN = 26,
    BNNSArithmeticDivideNoNaN = 27, BNNSArithmeticMultiplyAdd = 28, BNNSArithmeticMinimum = 29,
    BNNSArithmeticMaximum = 30, BNNSArithmeticSelect = 31, BNNSArithmeticAbs = 32, BNNSArithmeticSign = 33,
    BNNSArithmeticNegate = 34, BNNSArithmeticReciprocal = 35, BNNSArithmeticSquare = 36,
    BNNSArithmeticFloorDivide = 37, BNNSArithmeticTruncDivide = 38, BNNSArithmeticTruncRemainder = 39,
    BNNSArithmeticErf = 40,
};

typedef uint32_t BNNSDescriptorType;
enum { BNNSConstant = 0, BNNSSample = 1, BNNSParameter = 2 };

typedef uint32_t BNNSOptimizerFunction;
enum {
    BNNSOptimizerFunctionSGDMomentum = 1,
    BNNSOptimizerFunctionAdam = 2,
    BNNSOptimizerFunctionRMSProp = 3,
    BNNSOptimizerFunctionAdamW = 4,
    BNNSOptimizerFunctionAdamAMSGrad = 5,
    BNNSOptimizerFunctionAdamWAMSGrad = 6,
    BNNSOptimizerFunctionSGDMomentumWithClipping = 7,
    BNNSOptimizerFunctionAdamWithClipping = 8,
    BNNSOptimizerFunctionRMSPropWithClipping = 9,
    BNNSOptimizerFunctionAdamWWithClipping = 10,
    BNNSOptimizerFunctionAdamAMSGradWithClipping = 11,
    BNNSOptimizerFunctionAdamWAMSGradWithClipping = 12,
};

typedef uint32_t BNNSOptimizerRegularizationFunction;
enum { BNNSOptimizerRegularizationNone = 0, BNNSOptimizerRegularizationL1 = 1, BNNSOptimizerRegularizationL2 = 2 };

typedef uint32_t BNNSOptimizerSGDMomentumVariant;
enum { BNNSSGDMomentumVariant0 = 0, BNNSSGDMomentumVariant1 = 1, BNNSSGDMomentumVariant2 = 2 };

typedef uint32_t BNNSOptimizerClippingFunction;
enum {
    BNNSOptimizerClippingNone = 0,
    BNNSOptimizerClippingByValue = 1,
    BNNSOptimizerClippingByNorm = 2,
    BNNSOptimizerClippingByGlobalNorm = 3,
};

typedef uint32_t BNNSNormType;
enum { BNNSL2Norm = 1 };

typedef uint32_t BNNSFilterType;
enum {
    BNNSConvolution = 0, BNNSFullyConnected = 1, BNNSBatchNorm = 2, BNNSInstanceNorm = 3, BNNSLayerNorm = 4,
    BNNSGroupNorm = 5, BNNSTransposedConvolution = 6, BNNSQuantization = 7, BNNSArithmetic = 8,
};

typedef uint32_t BNNSReduceFunction;
enum {
    BNNSReduceFunctionMax = 0, BNNSReduceFunctionMin = 1, BNNSReduceFunctionArgMax = 2,
    BNNSReduceFunctionArgMin = 3, BNNSReduceFunctionMean = 4, BNNSReduceFunctionMeanNonZero = 5,
    BNNSReduceFunctionSum = 6, BNNSReduceFunctionSumSquare = 7, BNNSReduceFunctionSumLog = 8,
    BNNSReduceFunctionL1Norm = 9, BNNSReduceFunctionLogicalOr = 10, BNNSReduceFunctionLogicalAnd = 11,
    BNNSReduceFunctionL2Norm = 12, BNNSReduceFunctionLogSumExp = 13, BNNSReduceFunctionProduct = 14,
    BNNSReduceFunctionNone = 15, BNNSReduceFunctionLogSum = 16,
};

typedef uint32_t BNNSDataLayout;
enum {
    BNNSDataLayoutVector = 0x10000,
    BNNSDataLayout1DLastMajor = 0x18000,
    BNNSDataLayout1DFirstMajor = 0x18001,
    BNNSDataLayoutRowMajorMatrix = 0x20000,
    BNNSDataLayoutColumnMajorMatrix = 0x20001,
    BNNSDataLayout2DLastMajor = 0x28000,
    BNNSDataLayout2DFirstMajor = 0x28001,
    BNNSDataLayoutFullyConnectedSparse = 0x21001,
    BNNSDataLayoutImageCHW = 0x30000,
    BNNSDataLayoutSNE = 0x30001,
    BNNSDataLayoutNSE = 0x30002,
    BNNSDataLayoutMHA_DHK = 0x30003,
    BNNSDataLayout3DLastMajor = 0x38000,
    BNNSDataLayout3DFirstMajor = 0x38001,
    BNNSDataLayoutConvolutionWeightsOIHW = 0x40000,
    BNNSDataLayoutConvolutionWeightsOIHrWr = 0x40001,
    BNNSDataLayoutConvolutionWeightsIOHrWr = 0x40002,
    BNNSDataLayoutConvolutionWeightsOIHW_Pack32 = 0x40010,
    BNNSDataLayout4DLastMajor = 0x48000,
    BNNSDataLayout4DFirstMajor = 0x48001,
    BNNSDataLayout5DLastMajor = 0x58000,
    BNNSDataLayout5DFirstMajor = 0x58001,
    BNNSDataLayout6DLastMajor = 0x68000,
    BNNSDataLayout6DFirstMajor = 0x68001,
    BNNSDataLayout7DLastMajor = 0x78000,
    BNNSDataLayout7DFirstMajor = 0x78001,
    BNNSDataLayout8DLastMajor = 0x88000,
    BNNSDataLayout8DFirstMajor = 0x88001,
};

typedef uint32_t BNNSInterpolationMethod;
enum { BNNSInterpolationMethodNearest = 0, BNNSInterpolationMethodLinear = 1 };

typedef uint32_t BNNSLinearSamplingMode;
enum {
    BNNSLinearSamplingDefault = 0, BNNSLinearSamplingAlignCorners = 1, BNNSLinearSamplingUnalignCorners = 2,
    BNNSLinearSamplingStrictAlignCorners = 3, BNNSLinearSamplingOffsetCorners = 4,
};

typedef uint32_t BNNSBoxCoordinateMode;
enum { BNNSCornersHeightFirst = 0, BNNSCornersWidthFirst = 1, BNNSCenterSizeHeightFirst = 2, BNNSCenterSizeWidthFirst = 3 };

typedef uint32_t BNNSPaddingMode;
enum { BNNSPaddingModeConstant = 0, BNNSPaddingModeReflect = 1, BNNSPaddingModeSymmetric = 2 };

typedef uint32_t BNNSRelationalOperator;
enum {
    BNNSRelationalOperatorEqual = 0, BNNSRelationalOperatorLess = 1, BNNSRelationalOperatorLessEqual = 2,
    BNNSRelationalOperatorGreater = 3, BNNSRelationalOperatorGreaterEqual = 4, BNNSRelationalOperatorNotEqual = 5,
    BNNSRelationalOperatorLogicalAND = 6, BNNSRelationalOperatorLogicalOR = 7, BNNSRelationalOperatorLogicalNOT = 8,
    BNNSRelationalOperatorLogicalNAND = 9, BNNSRelationalOperatorLogicalNOR = 10, BNNSRelationalOperatorLogicalXOR = 11,
};

typedef uint32_t BNNSNDArrayFlags;
enum { BNNSNDArrayFlagBackpropSet = 0, BNNSNDArrayFlagBackpropAccumulate = 1 };

typedef uint32_t BNNSEmbeddingFlags;
enum { BNNSEmbeddingFlagScaleGradientByFrequency = 1 };

typedef uint32_t BNNSQuantizerFunction;
enum { BNNSQuantizerFunctionQuantize = 0, BNNSQuantizerFunctionDequantize = 1 };

typedef uint32_t BNNSRandomGeneratorMethod;
enum { BNNSRandomGeneratorMethodAES_CTR = 0 };

typedef uint32_t BNNSSparsityType;
typedef uint32_t BNNSTargetSystem;

typedef uint32_t BNNSShuffleType;
enum {
    BNNSShuffleTypePixelShuffleNCHW = 0, BNNSShuffleTypePixelUnshuffleNCHW = 1,
    BNNSShuffleTypeDepthToSpaceNCHW = 2, BNNSShuffleTypeSpaceToDepthNCHW = 3,
};

// MARK: - Structures

typedef int (*BNNSAlloc)(void **memptr, size_t alignment, size_t size);
typedef void (*BNNSFree)(void *ptr);

typedef struct {
    BNNSActivationFunction function;
    float alpha;
    float beta;
    int32_t iscale;
    int32_t ioffset;
    int32_t ishift;
    const int32_t *iscale_per_channel;
    const int32_t *ioffset_per_channel;
    const int32_t *ishift_per_channel;
} BNNSActivation;

#define BNNS_MAX_TENSOR_DIMENSION 8

typedef struct {
    BNNSNDArrayFlags flags;
    BNNSDataLayout layout;
    size_t size[BNNS_MAX_TENSOR_DIMENSION];
    size_t stride[BNNS_MAX_TENSOR_DIMENSION];
    void *data;
    BNNSDataType data_type;
    void *table_data;
    BNNSDataType table_data_type;
    float data_scale;
    float data_bias;
} BNNSNDArrayDescriptor;

typedef struct {
    BNNSDataType data_type;
    uint8_t rank;
    ssize_t shape[BNNS_MAX_TENSOR_DIMENSION];
    ssize_t stride[BNNS_MAX_TENSOR_DIMENSION];
    void *data;
    size_t data_size_in_bytes;
    const char *name;
} BNNSTensor;

typedef struct {
    BNNSNDArrayDescriptor in;
    BNNSDescriptorType in_type;
    BNNSNDArrayDescriptor out;
    BNNSDescriptorType out_type;
} BNNSArithmeticUnary;

typedef struct {
    BNNSNDArrayDescriptor in1;
    BNNSDescriptorType in1_type;
    BNNSNDArrayDescriptor in2;
    BNNSDescriptorType in2_type;
    BNNSNDArrayDescriptor out;
    BNNSDescriptorType out_type;
} BNNSArithmeticBinary;

typedef struct {
    BNNSNDArrayDescriptor in1;
    BNNSDescriptorType in1_type;
    BNNSNDArrayDescriptor in2;
    BNNSDescriptorType in2_type;
    BNNSNDArrayDescriptor in3;
    BNNSDescriptorType in3_type;
    BNNSNDArrayDescriptor out;
    BNNSDescriptorType out_type;
} BNNSArithmeticTernary;

typedef struct {
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor w_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSNDArrayDescriptor bias;
    BNNSActivation activation;
    size_t x_stride;
    size_t y_stride;
    size_t x_dilation_stride;
    size_t y_dilation_stride;
    size_t x_padding;
    size_t y_padding;
    size_t groups;
    size_t pad[4];
} BNNSLayerParametersConvolution;

typedef struct {
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor w_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSNDArrayDescriptor bias;
    BNNSActivation activation;
} BNNSLayerParametersFullyConnected;

typedef struct {
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSNDArrayDescriptor bias;
    BNNSActivation activation;
    BNNSPoolingFunction pooling_function;
    size_t k_width;
    size_t k_height;
    size_t x_stride;
    size_t y_stride;
    size_t x_dilation_stride;
    size_t y_dilation_stride;
    size_t x_padding;
    size_t y_padding;
    size_t pad[4];
} BNNSLayerParametersPooling;

typedef struct {
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSActivation activation;
    uint32_t axis_flags;
} BNNSLayerParametersActivation;

typedef struct {
    BNNSLossFunction function;
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSLossReductionFunction reduction;
} BNNSLayerParametersLossBase;

typedef struct {
    BNNSLossFunction function;
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSLossReductionFunction reduction;
    float label_smooth;
} BNNSLayerParametersLossSoftmaxCrossEntropy;

typedef BNNSLayerParametersLossSoftmaxCrossEntropy BNNSLayerParametersLossSigmoidCrossEntropy;

typedef struct {
    BNNSLossFunction function;
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSLossReductionFunction reduction;
    float huber_delta;
} BNNSLayerParametersLossHuber;

typedef struct {
    BNNSLossFunction function;
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSLossReductionFunction reduction;
    float huber_delta;
    size_t number_of_grid_columns;
    size_t number_of_grid_rows;
    size_t number_of_anchor_boxes;
    size_t anchor_box_size;
    bool rescore;
    float scale_xy;
    float scale_wh;
    float scale_object;
    float scale_no_object;
    float scale_classification;
    float object_minimum_iou;
    float no_object_maximum_iou;
    float *anchors_data;
} BNNSLayerParametersLossYolo;

typedef struct {
    float learning_rate;
    float momentum;
    float gradient_scale;
    float regularization_scale;
    bool clip_gradients;
    float clip_gradients_min;
    float clip_gradients_max;
    bool nesterov;
    BNNSOptimizerRegularizationFunction regularization_func;
    BNNSOptimizerSGDMomentumVariant sgd_momentum_variant;
} BNNSOptimizerSGDMomentumFields;

typedef struct {
    float learning_rate;
    float momentum;
    float gradient_scale;
    float regularization_scale;
    bool nesterov;
    BNNSOptimizerRegularizationFunction regularization_func;
    BNNSOptimizerSGDMomentumVariant sgd_momentum_variant;
    BNNSOptimizerClippingFunction clipping_func;
    float clip_gradients_min;
    float clip_gradients_max;
    float clip_gradients_max_norm;
    float clip_gradients_use_norm;
} BNNSOptimizerSGDMomentumWithClippingFields;

typedef struct {
    float learning_rate;
    float beta1;
    float beta2;
    float time_step;
    float epsilon;
    float gradient_scale;
    float regularization_scale;
    bool clip_gradients;
    float clip_gradients_min;
    float clip_gradients_max;
    BNNSOptimizerRegularizationFunction regularization_func;
} BNNSOptimizerAdamFields;

typedef struct {
    float learning_rate;
    float beta1;
    float beta2;
    float time_step;
    float epsilon;
    float gradient_scale;
    float regularization_scale;
    BNNSOptimizerRegularizationFunction regularization_func;
    BNNSOptimizerClippingFunction clipping_func;
    float clip_gradients_min;
    float clip_gradients_max;
    float clip_gradients_max_norm;
    float clip_gradients_use_norm;
} BNNSOptimizerAdamWithClippingFields;

typedef struct {
    float learning_rate;
    float alpha;
    float epsilon;
    bool centered;
    float momentum;
    float gradient_scale;
    float regularization_scale;
    bool clip_gradients;
    float clip_gradients_min;
    float clip_gradients_max;
    BNNSOptimizerRegularizationFunction regularization_func;
} BNNSOptimizerRMSPropFields;

typedef struct {
    float learning_rate;
    float alpha;
    float epsilon;
    bool centered;
    float momentum;
    float gradient_scale;
    float regularization_scale;
    BNNSOptimizerRegularizationFunction regularization_func;
    BNNSOptimizerClippingFunction clipping_func;
    float clip_gradients_min;
    float clip_gradients_max;
    float clip_gradients_max_norm;
    float clip_gradients_use_norm;
} BNNSOptimizerRMSPropWithClippingFields;

typedef struct {
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSNDArrayDescriptor beta_desc;
    BNNSNDArrayDescriptor gamma_desc;
    BNNSNDArrayDescriptor moving_mean_desc;
    BNNSNDArrayDescriptor moving_variance_desc;
    float momentum;
    float epsilon;
    BNNSActivation activation;
    size_t num_groups;
    size_t normalization_axis;
} BNNSLayerParametersNormalization;

typedef struct {
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    float rate;
    uint32_t seed;
    uint8_t control;
} BNNSLayerParametersDropout;

typedef struct {
    BNNSArithmeticFunction arithmetic_function;
    void *arithmetic_function_fields;
    BNNSActivation activation;
} BNNSLayerParametersArithmetic;

typedef struct {
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    size_t permutation[BNNS_MAX_TENSOR_DIMENSION];
} BNNSLayerParametersPermute;

typedef struct {
    float alpha;
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
} BNNSLayerParametersGram;

typedef struct {
    BNNSInterpolationMethod method;
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    bool align_corners;
} BNNSLayerParametersResize;

typedef struct {
    bool normalized_coordinates;
    float spatial_scale;
    float extrapolation_value;
    BNNSLinearSamplingMode sampling_mode;
    BNNSBoxCoordinateMode box_coordinate_mode;
    BNNSInterpolationMethod method;
} BNNSLayerParametersCropResize;

typedef struct {
    float alpha;
    float beta;
    bool transA;
    bool transB;
    bool quadratic;
    bool a_is_weights;
    bool b_is_weights;
    BNNSNDArrayDescriptor iA_desc;
    BNNSNDArrayDescriptor iB_desc;
    BNNSNDArrayDescriptor o_desc;
} BNNSLayerParametersBroadcastMatMul;

typedef struct {
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSNDArrayDescriptor w_desc;
    BNNSReduceFunction reduce_func;
    float epsilon;
} BNNSLayerParametersReduction;

typedef struct {
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    size_t padding_size[BNNS_MAX_TENSOR_DIMENSION][2];
    BNNSPaddingMode padding_mode;
    uint32_t padding_value;
} BNNSLayerParametersPadding;

typedef struct {
    BNNSEmbeddingFlags flags;
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSNDArrayDescriptor dictionary;
    size_t padding_idx;
    float max_norm;
    float norm_type;
} BNNSLayerParametersEmbedding;

typedef struct {
    size_t axis_mask;
    BNNSQuantizerFunction function;
    BNNSNDArrayDescriptor i_desc;
    BNNSNDArrayDescriptor o_desc;
    BNNSNDArrayDescriptor scale;
    BNNSNDArrayDescriptor bias;
} BNNSLayerParametersQuantization;

typedef struct {
    uint64_t flags;
    uint32_t sparsity_ratio[2];
    BNNSSparsityType sparsity_type;
    BNNSTargetSystem target_system;
} BNNSSparsityParameters;

typedef struct {
    uint32_t flags;
    size_t n_threads;
    BNNSAlloc alloc_memory;
    BNNSFree free_memory;
} BNNSFilterParameters;

typedef void *BNNSFilter;
typedef void *BNNSRandomGenerator;
typedef void *BNNSNearestNeighbors;

// MARK: - Graph structures

typedef struct { void *data; size_t size; } bnns_graph_t;
typedef struct { void *data; size_t size; } bnns_graph_context_t;
typedef struct { void *data; size_t size; } bnns_graph_compile_options_t;
typedef struct { size_t rank; uint64_t *shape; } bnns_graph_shape_t;

typedef struct {
    union {
        BNNSTensor *tensor;
        BNNSNDArrayDescriptor *descriptor;
        void *data_ptr;
    };
    size_t data_ptr_size;
} bnns_graph_argument_t;

typedef uint32_t BNNSGraphOptimizationPreference;
typedef uint32_t BNNSGraphArgumentType;
enum { BNNSGraphArgumentTypePointer = 0, BNNSGraphArgumentTypeTensor = 2 };

// MARK: - Layouts (Darwin LP64, checked against the macOS SDK)

#define BNNS_CHECK_SIZE(T, n) _Static_assert(sizeof(T) == (n), "size of " #T)
#define BNNS_CHECK_OFFSET(T, f, n) _Static_assert(offsetof(T, f) == (n), "offset of " #T "." #f)

BNNS_CHECK_SIZE(BNNSActivation, 48);
BNNS_CHECK_OFFSET(BNNSActivation, iscale, 12);
BNNS_CHECK_OFFSET(BNNSActivation, iscale_per_channel, 24);
BNNS_CHECK_OFFSET(BNNSActivation, ishift_per_channel, 40);
BNNS_CHECK_SIZE(BNNSNDArrayDescriptor, 176);
BNNS_CHECK_OFFSET(BNNSNDArrayDescriptor, size, 8);
BNNS_CHECK_OFFSET(BNNSNDArrayDescriptor, stride, 72);
BNNS_CHECK_OFFSET(BNNSNDArrayDescriptor, data, 136);
BNNS_CHECK_OFFSET(BNNSNDArrayDescriptor, data_type, 144);
BNNS_CHECK_OFFSET(BNNSNDArrayDescriptor, table_data, 152);
BNNS_CHECK_OFFSET(BNNSNDArrayDescriptor, table_data_type, 160);
BNNS_CHECK_OFFSET(BNNSNDArrayDescriptor, data_scale, 164);
BNNS_CHECK_OFFSET(BNNSNDArrayDescriptor, data_bias, 168);
BNNS_CHECK_SIZE(BNNSTensor, 160);
BNNS_CHECK_OFFSET(BNNSTensor, rank, 4);
BNNS_CHECK_OFFSET(BNNSTensor, shape, 8);
BNNS_CHECK_OFFSET(BNNSTensor, stride, 72);
BNNS_CHECK_OFFSET(BNNSTensor, data, 136);
BNNS_CHECK_OFFSET(BNNSTensor, data_size_in_bytes, 144);
BNNS_CHECK_OFFSET(BNNSTensor, name, 152);
BNNS_CHECK_SIZE(BNNSArithmeticUnary, 368);
BNNS_CHECK_OFFSET(BNNSArithmeticUnary, in_type, 176);
BNNS_CHECK_OFFSET(BNNSArithmeticUnary, out, 184);
BNNS_CHECK_OFFSET(BNNSArithmeticUnary, out_type, 360);
BNNS_CHECK_SIZE(BNNSArithmeticBinary, 552);
BNNS_CHECK_OFFSET(BNNSArithmeticBinary, in2, 184);
BNNS_CHECK_OFFSET(BNNSArithmeticBinary, in2_type, 360);
BNNS_CHECK_OFFSET(BNNSArithmeticBinary, out, 368);
BNNS_CHECK_OFFSET(BNNSArithmeticBinary, out_type, 544);
BNNS_CHECK_SIZE(BNNSArithmeticTernary, 736);
BNNS_CHECK_OFFSET(BNNSArithmeticTernary, in3, 368);
BNNS_CHECK_OFFSET(BNNSArithmeticTernary, in3_type, 544);
BNNS_CHECK_OFFSET(BNNSArithmeticTernary, out, 552);
BNNS_CHECK_OFFSET(BNNSArithmeticTernary, out_type, 728);
BNNS_CHECK_SIZE(BNNSLayerParametersConvolution, 840);
BNNS_CHECK_OFFSET(BNNSLayerParametersConvolution, w_desc, 176);
BNNS_CHECK_OFFSET(BNNSLayerParametersConvolution, bias, 528);
BNNS_CHECK_OFFSET(BNNSLayerParametersConvolution, activation, 704);
BNNS_CHECK_OFFSET(BNNSLayerParametersConvolution, x_stride, 752);
BNNS_CHECK_OFFSET(BNNSLayerParametersConvolution, groups, 800);
BNNS_CHECK_OFFSET(BNNSLayerParametersConvolution, pad, 808);
BNNS_CHECK_SIZE(BNNSLayerParametersFullyConnected, 752);
BNNS_CHECK_OFFSET(BNNSLayerParametersFullyConnected, activation, 704);
BNNS_CHECK_SIZE(BNNSLayerParametersPooling, 680);
BNNS_CHECK_OFFSET(BNNSLayerParametersPooling, activation, 528);
BNNS_CHECK_OFFSET(BNNSLayerParametersPooling, pooling_function, 576);
BNNS_CHECK_OFFSET(BNNSLayerParametersPooling, k_width, 584);
BNNS_CHECK_OFFSET(BNNSLayerParametersPooling, pad, 648);
BNNS_CHECK_SIZE(BNNSLayerParametersActivation, 408);
BNNS_CHECK_OFFSET(BNNSLayerParametersActivation, activation, 352);
BNNS_CHECK_OFFSET(BNNSLayerParametersActivation, axis_flags, 400);
BNNS_CHECK_SIZE(BNNSLayerParametersLossBase, 368);
BNNS_CHECK_OFFSET(BNNSLayerParametersLossBase, i_desc, 8);
BNNS_CHECK_OFFSET(BNNSLayerParametersLossBase, o_desc, 184);
BNNS_CHECK_OFFSET(BNNSLayerParametersLossBase, reduction, 360);
BNNS_CHECK_SIZE(BNNSLayerParametersLossSoftmaxCrossEntropy, 368);
BNNS_CHECK_OFFSET(BNNSLayerParametersLossSoftmaxCrossEntropy, label_smooth, 364);
BNNS_CHECK_SIZE(BNNSLayerParametersLossHuber, 368);
BNNS_CHECK_OFFSET(BNNSLayerParametersLossHuber, huber_delta, 364);
BNNS_CHECK_SIZE(BNNSLayerParametersLossYolo, 440);
BNNS_CHECK_OFFSET(BNNSLayerParametersLossYolo, number_of_grid_columns, 368);
BNNS_CHECK_OFFSET(BNNSLayerParametersLossYolo, rescore, 400);
BNNS_CHECK_OFFSET(BNNSLayerParametersLossYolo, scale_xy, 404);
BNNS_CHECK_OFFSET(BNNSLayerParametersLossYolo, anchors_data, 432);
BNNS_CHECK_SIZE(BNNSOptimizerSGDMomentumFields, 40);
BNNS_CHECK_OFFSET(BNNSOptimizerSGDMomentumFields, clip_gradients, 16);
BNNS_CHECK_OFFSET(BNNSOptimizerSGDMomentumFields, clip_gradients_min, 20);
BNNS_CHECK_OFFSET(BNNSOptimizerSGDMomentumFields, nesterov, 28);
BNNS_CHECK_OFFSET(BNNSOptimizerSGDMomentumFields, regularization_func, 32);
BNNS_CHECK_OFFSET(BNNSOptimizerSGDMomentumFields, sgd_momentum_variant, 36);
BNNS_CHECK_SIZE(BNNSOptimizerSGDMomentumWithClippingFields, 48);
BNNS_CHECK_OFFSET(BNNSOptimizerSGDMomentumWithClippingFields, nesterov, 16);
BNNS_CHECK_OFFSET(BNNSOptimizerSGDMomentumWithClippingFields, regularization_func, 20);
BNNS_CHECK_OFFSET(BNNSOptimizerSGDMomentumWithClippingFields, clipping_func, 28);
BNNS_CHECK_OFFSET(BNNSOptimizerSGDMomentumWithClippingFields, clip_gradients_use_norm, 44);
BNNS_CHECK_SIZE(BNNSOptimizerAdamFields, 44);
BNNS_CHECK_OFFSET(BNNSOptimizerAdamFields, clip_gradients, 28);
BNNS_CHECK_OFFSET(BNNSOptimizerAdamFields, clip_gradients_min, 32);
BNNS_CHECK_OFFSET(BNNSOptimizerAdamFields, regularization_func, 40);
BNNS_CHECK_SIZE(BNNSOptimizerAdamWithClippingFields, 52);
BNNS_CHECK_OFFSET(BNNSOptimizerAdamWithClippingFields, regularization_func, 28);
BNNS_CHECK_OFFSET(BNNSOptimizerAdamWithClippingFields, clip_gradients_use_norm, 48);
BNNS_CHECK_SIZE(BNNSOptimizerRMSPropFields, 44);
BNNS_CHECK_OFFSET(BNNSOptimizerRMSPropFields, centered, 12);
BNNS_CHECK_OFFSET(BNNSOptimizerRMSPropFields, momentum, 16);
BNNS_CHECK_OFFSET(BNNSOptimizerRMSPropFields, clip_gradients, 28);
BNNS_CHECK_OFFSET(BNNSOptimizerRMSPropFields, clip_gradients_min, 32);
BNNS_CHECK_OFFSET(BNNSOptimizerRMSPropFields, regularization_func, 40);
BNNS_CHECK_SIZE(BNNSOptimizerRMSPropWithClippingFields, 52);
BNNS_CHECK_OFFSET(BNNSOptimizerRMSPropWithClippingFields, centered, 12);
BNNS_CHECK_OFFSET(BNNSOptimizerRMSPropWithClippingFields, momentum, 16);
BNNS_CHECK_OFFSET(BNNSOptimizerRMSPropWithClippingFields, clip_gradients_use_norm, 48);
BNNS_CHECK_SIZE(BNNSLayerParametersNormalization, 1128);
BNNS_CHECK_OFFSET(BNNSLayerParametersNormalization, momentum, 1056);
BNNS_CHECK_OFFSET(BNNSLayerParametersNormalization, epsilon, 1060);
BNNS_CHECK_OFFSET(BNNSLayerParametersNormalization, activation, 1064);
BNNS_CHECK_OFFSET(BNNSLayerParametersNormalization, num_groups, 1112);
BNNS_CHECK_OFFSET(BNNSLayerParametersNormalization, normalization_axis, 1120);
BNNS_CHECK_SIZE(BNNSLayerParametersDropout, 368);
BNNS_CHECK_OFFSET(BNNSLayerParametersDropout, rate, 352);
BNNS_CHECK_OFFSET(BNNSLayerParametersDropout, seed, 356);
BNNS_CHECK_OFFSET(BNNSLayerParametersDropout, control, 360);
BNNS_CHECK_SIZE(BNNSLayerParametersArithmetic, 64);
BNNS_CHECK_OFFSET(BNNSLayerParametersArithmetic, arithmetic_function_fields, 8);
BNNS_CHECK_OFFSET(BNNSLayerParametersArithmetic, activation, 16);
BNNS_CHECK_SIZE(BNNSLayerParametersPermute, 416);
BNNS_CHECK_OFFSET(BNNSLayerParametersPermute, permutation, 352);
BNNS_CHECK_SIZE(BNNSLayerParametersGram, 360);
BNNS_CHECK_OFFSET(BNNSLayerParametersGram, i_desc, 8);
BNNS_CHECK_OFFSET(BNNSLayerParametersGram, o_desc, 184);
BNNS_CHECK_SIZE(BNNSLayerParametersResize, 368);
BNNS_CHECK_OFFSET(BNNSLayerParametersResize, i_desc, 8);
BNNS_CHECK_OFFSET(BNNSLayerParametersResize, align_corners, 360);
BNNS_CHECK_SIZE(BNNSLayerParametersCropResize, 24);
BNNS_CHECK_OFFSET(BNNSLayerParametersCropResize, spatial_scale, 4);
BNNS_CHECK_OFFSET(BNNSLayerParametersCropResize, method, 20);
BNNS_CHECK_SIZE(BNNSLayerParametersBroadcastMatMul, 544);
BNNS_CHECK_OFFSET(BNNSLayerParametersBroadcastMatMul, transA, 8);
BNNS_CHECK_OFFSET(BNNSLayerParametersBroadcastMatMul, b_is_weights, 12);
BNNS_CHECK_OFFSET(BNNSLayerParametersBroadcastMatMul, iA_desc, 16);
BNNS_CHECK_OFFSET(BNNSLayerParametersBroadcastMatMul, o_desc, 368);
BNNS_CHECK_SIZE(BNNSLayerParametersReduction, 536);
BNNS_CHECK_OFFSET(BNNSLayerParametersReduction, w_desc, 352);
BNNS_CHECK_OFFSET(BNNSLayerParametersReduction, reduce_func, 528);
BNNS_CHECK_OFFSET(BNNSLayerParametersReduction, epsilon, 532);
BNNS_CHECK_SIZE(BNNSLayerParametersPadding, 488);
BNNS_CHECK_OFFSET(BNNSLayerParametersPadding, padding_size, 352);
BNNS_CHECK_OFFSET(BNNSLayerParametersPadding, padding_mode, 480);
BNNS_CHECK_OFFSET(BNNSLayerParametersPadding, padding_value, 484);
BNNS_CHECK_SIZE(BNNSLayerParametersEmbedding, 552);
BNNS_CHECK_OFFSET(BNNSLayerParametersEmbedding, i_desc, 8);
BNNS_CHECK_OFFSET(BNNSLayerParametersEmbedding, dictionary, 360);
BNNS_CHECK_OFFSET(BNNSLayerParametersEmbedding, padding_idx, 536);
BNNS_CHECK_OFFSET(BNNSLayerParametersEmbedding, max_norm, 544);
BNNS_CHECK_OFFSET(BNNSLayerParametersEmbedding, norm_type, 548);
BNNS_CHECK_SIZE(BNNSLayerParametersQuantization, 720);
BNNS_CHECK_OFFSET(BNNSLayerParametersQuantization, function, 8);
BNNS_CHECK_OFFSET(BNNSLayerParametersQuantization, i_desc, 16);
BNNS_CHECK_OFFSET(BNNSLayerParametersQuantization, scale, 368);
BNNS_CHECK_OFFSET(BNNSLayerParametersQuantization, bias, 544);
BNNS_CHECK_SIZE(BNNSSparsityParameters, 24);
BNNS_CHECK_OFFSET(BNNSSparsityParameters, sparsity_type, 16);
BNNS_CHECK_SIZE(BNNSFilterParameters, 32);
BNNS_CHECK_OFFSET(BNNSFilterParameters, n_threads, 8);
BNNS_CHECK_OFFSET(BNNSFilterParameters, alloc_memory, 16);
BNNS_CHECK_OFFSET(BNNSFilterParameters, free_memory, 24);
BNNS_CHECK_SIZE(bnns_graph_t, 16);
BNNS_CHECK_SIZE(bnns_graph_context_t, 16);
BNNS_CHECK_SIZE(bnns_graph_compile_options_t, 16);
BNNS_CHECK_SIZE(bnns_graph_shape_t, 16);
BNNS_CHECK_SIZE(bnns_graph_argument_t, 16);
BNNS_CHECK_OFFSET(bnns_graph_argument_t, data_ptr_size, 8);

// MARK: - Shared helpers (bnns.c)

// A descriptor's logical shape: size and element stride of each dimension.
typedef struct {
    int rank;
    size_t n[BNNS_MAX_TENSOR_DIMENSION];
    ptrdiff_t s[BNNS_MAX_TENSOR_DIMENSION];
} bnns_shape;

BNNS_HIDDEN int bnns_layout_rank(BNNSDataLayout layout);
BNNS_HIDDEN size_t bnns_type_size(BNNSDataType type);
BNNS_HIDDEN bool bnns_float_type(BNNSDataType type);
// Logical shape (size[] order), or physical (memory order: smallest stride first).
BNNS_HIDDEN int bnns_shape_of(const BNNSNDArrayDescriptor *d, bnns_shape *shape);
BNNS_HIDDEN int bnns_shape_phys(const BNNSNDArrayDescriptor *d, bnns_shape *shape);
BNNS_HIDDEN size_t bnns_count(const BNNSNDArrayDescriptor *d);
BNNS_HIDDEN size_t bnns_shape_count(const bnns_shape *shape);
BNNS_HIDDEN bool bnns_next(size_t *idx, const size_t *n, int rank);
BNNS_HIDDEN ptrdiff_t bnns_index_offset(const bnns_shape *shape, const size_t *idx);
BNNS_HIDDEN double bnns_load(const BNNSNDArrayDescriptor *d, const void *base, ptrdiff_t i);
BNNS_HIDDEN int64_t bnns_load_index(const BNNSNDArrayDescriptor *d, const void *base, ptrdiff_t i);
BNNS_HIDDEN void bnns_store(const BNNSNDArrayDescriptor *d, void *base, ptrdiff_t i, double v);
// Dense float copy of d's elements (from base, or d->data if base is NULL), or NULL.
BNNS_HIDDEN float *bnns_read(const BNNSNDArrayDescriptor *d, const void *base);
BNNS_HIDDEN float *bnns_read_phys(const BNNSNDArrayDescriptor *d, const void *base);
// Writes dense floats into d's elements; accumulate adds to what is there.
BNNS_HIDDEN int bnns_write(const BNNSNDArrayDescriptor *d, void *base, const float *src, bool accumulate);
BNNS_HIDDEN int bnns_write_phys(const BNNSNDArrayDescriptor *d, void *base, const float *src, bool accumulate);
// Writes a gradient, accumulating if d->flags is BNNSNDArrayFlagBackpropAccumulate.
BNNS_HIDDEN int bnns_write_delta(const BNNSNDArrayDescriptor *d, void *base, const float *src);
BNNS_HIDDEN int bnns_write_delta_phys(const BNNSNDArrayDescriptor *d, void *base, const float *src);
BNNS_HIDDEN void *bnns_offset(const BNNSNDArrayDescriptor *d, const void *base, size_t batch, size_t stride);
BNNS_HIDDEN void *bnns_alloc(const BNNSFilterParameters *fp, size_t size);
BNNS_HIDDEN void bnns_release(BNNSFree free_memory, void *p);

BNNS_HIDDEN bool bnns_activation_supported(BNNSActivationFunction f);
BNNS_HIDDEN float bnns_activation_value(const BNNSActivation *a, float x);
BNNS_HIDDEN float bnns_activation_derivative(const BNNSActivation *a, const float *x, const float *y);
// x: batch dense arrays of shape sh; softmax kinds normalize over the axes in
// axis_flags (0: axis 0; bit rank: the batch).
BNNS_HIDDEN int bnns_activate(const BNNSActivation *a, uint32_t axis_flags, const bnns_shape *sh, float *x, size_t batch);
// Turns dy into the input gradient, given the forward input x and/or output y.
BNNS_HIDDEN int bnns_activate_backward(const BNNSActivation *a, uint32_t axis_flags, const bnns_shape *sh,
                                       const float *x, const float *y, float *dy, size_t batch);

BNNS_HIDDEN void bnns_sgemm(bool transA, bool transB, int M, int N, int K, float alpha, const float *A, int lda,
                            const float *B, int ldb, float beta, float *C, int ldc);
BNNS_HIDDEN uint64_t bnns_random_next(uint64_t *state);
BNNS_HIDDEN int bnns_matmul(bool transA, bool transB, float alpha, float beta,
                            const BNNSNDArrayDescriptor *a, const void *a_data,
                            const BNNSNDArrayDescriptor *b, const void *b_data,
                            const BNNSNDArrayDescriptor *c, void *c_data);
BNNS_HIDDEN int bnns_reduce(const BNNSNDArrayDescriptor *in, const void *in_data,
                            const BNNSNDArrayDescriptor *out, void *out_data,
                            const BNNSNDArrayDescriptor *w, BNNSReduceFunction f, float epsilon);

// MARK: - Exported functions

#define BNNS_API(name) DARWIN_SYMBOL(name)

size_t BNNSDataLayoutGetRank(BNNSDataLayout layout) BNNS_API(BNNSDataLayoutGetRank);
size_t BNNSNDArrayGetDataSize(const BNNSNDArrayDescriptor *array) BNNS_API(BNNSNDArrayGetDataSize);
size_t BNNSTensorGetAllocationSize(const BNNSTensor *tensor) BNNS_API(BNNSTensorGetAllocationSize);
int BNNSCopy(BNNSNDArrayDescriptor *dest, const BNNSNDArrayDescriptor *src, const BNNSFilterParameters *fp) BNNS_API(BNNSCopy);
int BNNSTranspose(BNNSNDArrayDescriptor *dest, const BNNSNDArrayDescriptor *src, size_t axis0, size_t axis1, const BNNSFilterParameters *fp) BNNS_API(BNNSTranspose);
int BNNSTile(const BNNSNDArrayDescriptor *input, BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) BNNS_API(BNNSTile);
int BNNSTileBackward(BNNSNDArrayDescriptor *in_delta, const BNNSNDArrayDescriptor *out_delta, const BNNSFilterParameters *fp) BNNS_API(BNNSTileBackward);
int BNNSGather(size_t axis, const BNNSNDArrayDescriptor *input, const BNNSNDArrayDescriptor *indices, BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) BNNS_API(BNNSGather);
int BNNSGatherND(const BNNSNDArrayDescriptor *input, const BNNSNDArrayDescriptor *indices, BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) BNNS_API(BNNSGatherND);
int BNNSScatter(size_t axis, BNNSReduceFunction op, const BNNSNDArrayDescriptor *input, const BNNSNDArrayDescriptor *indices, BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) BNNS_API(BNNSScatter);
int BNNSScatterND(BNNSReduceFunction op, const BNNSNDArrayDescriptor *input, const BNNSNDArrayDescriptor *indices, BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) BNNS_API(BNNSScatterND);
int BNNSShuffle(BNNSShuffleType type, const BNNSNDArrayDescriptor *input, BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) BNNS_API(BNNSShuffle);
int BNNSBandPart(int num_lower, int num_upper, const BNNSNDArrayDescriptor *input, BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) BNNS_API(BNNSBandPart);
int BNNSCompareTensor(const BNNSNDArrayDescriptor *in0, const BNNSNDArrayDescriptor *in1, BNNSRelationalOperator op, BNNSNDArrayDescriptor *out) BNNS_API(BNNSCompareTensor);
int BNNSClipByValue(BNNSNDArrayDescriptor *dest, const BNNSNDArrayDescriptor *src, float min_val, float max_val) BNNS_API(BNNSClipByValue);
int BNNSClipByNorm(BNNSNDArrayDescriptor *dest, const BNNSNDArrayDescriptor *src, float max_norm, uint32_t axis_flags) BNNS_API(BNNSClipByNorm);
int BNNSClipByGlobalNorm(BNNSNDArrayDescriptor **dest, const BNNSNDArrayDescriptor **src, size_t count, float max_norm, float use_norm) BNNS_API(BNNSClipByGlobalNorm);
int BNNSComputeNorm(BNNSNDArrayDescriptor *dest, const BNNSNDArrayDescriptor *src, BNNSNormType norm_type, uint32_t axis_flags) BNNS_API(BNNSComputeNorm);
int BNNSComputeNormBackward(const void *in, BNNSNDArrayDescriptor *in_delta, const void *out, const BNNSNDArrayDescriptor *out_delta, BNNSNormType norm_type, uint32_t axis_flags) BNNS_API(BNNSComputeNormBackward);
int BNNSDirectApplyTopK(size_t K, size_t axis, size_t batch_size, const BNNSNDArrayDescriptor *input, size_t input_batch_stride, BNNSNDArrayDescriptor *best_values, size_t best_values_batch_stride, BNNSNDArrayDescriptor *best_indices, size_t best_indices_batch_stride, const BNNSFilterParameters *fp) BNNS_API(BNNSDirectApplyTopK);
int BNNSDirectApplyInTopK(size_t K, size_t axis, size_t batch_size, const BNNSNDArrayDescriptor *input, size_t input_batch_stride, const BNNSNDArrayDescriptor *test_indices, size_t test_indices_batch_stride, BNNSNDArrayDescriptor *output, size_t output_batch_stride, const BNNSFilterParameters *fp) BNNS_API(BNNSDirectApplyInTopK);
int BNNSDirectApplyReduction(const BNNSLayerParametersReduction *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSDirectApplyReduction);
int BNNSDirectApplyQuantizer(const BNNSLayerParametersQuantization *layer_params, const BNNSFilterParameters *fp, size_t batch_size, size_t input_stride, size_t output_stride) BNNS_API(BNNSDirectApplyQuantizer);
int BNNSDirectApplyActivationBatch(const BNNSLayerParametersActivation *layer_params, const BNNSFilterParameters *fp, size_t batch_size, size_t in_stride, size_t out_stride) BNNS_API(BNNSDirectApplyActivationBatch);
ssize_t BNNSMatMulWorkspaceSize(bool transA, bool transB, float alpha, const BNNSNDArrayDescriptor *inputA, const BNNSNDArrayDescriptor *inputB, const BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) BNNS_API(BNNSMatMulWorkspaceSize);
int BNNSMatMul(bool transA, bool transB, float alpha, const BNNSNDArrayDescriptor *inputA, const BNNSNDArrayDescriptor *inputB, const BNNSNDArrayDescriptor *output, void *workspace, const BNNSFilterParameters *fp) BNNS_API(BNNSMatMul);
int BNNSCropResize(const BNNSLayerParametersCropResize *layer_params, const BNNSNDArrayDescriptor *input, const BNNSNDArrayDescriptor *roi, BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) BNNS_API(BNNSCropResize);
int BNNSCropResizeBackward(const BNNSLayerParametersCropResize *layer_params, BNNSNDArrayDescriptor *in_delta, const BNNSNDArrayDescriptor *roi, const BNNSNDArrayDescriptor *out_delta, const BNNSFilterParameters *fp) BNNS_API(BNNSCropResizeBackward);
int BNNSOptimizerStep(BNNSOptimizerFunction function, const void *fields, size_t number_of_parameters, BNNSNDArrayDescriptor **parameters, const BNNSNDArrayDescriptor **gradients, BNNSNDArrayDescriptor **accumulators, const BNNSFilterParameters *fp) BNNS_API(BNNSOptimizerStep);
int BNNSNDArrayFullyConnectedSparsifySparseCOO(const BNNSNDArrayDescriptor *in_dense_shape, const BNNSNDArrayDescriptor *in_indices, const BNNSNDArrayDescriptor *in_values, BNNSNDArrayDescriptor *out, const BNNSSparsityParameters *sparse_params, size_t batch_size, void *workspace, size_t workspace_size, const BNNSFilterParameters *fp) BNNS_API(BNNSNDArrayFullyConnectedSparsifySparseCOO);
int BNNSNDArrayFullyConnectedSparsifySparseCSR(const BNNSNDArrayDescriptor *in_dense_shape, const BNNSNDArrayDescriptor *in_column_indices, const BNNSNDArrayDescriptor *in_row_starts, const BNNSNDArrayDescriptor *in_values, BNNSNDArrayDescriptor *out, const BNNSSparsityParameters *sparse_params, size_t batch_size, void *workspace, size_t workspace_size, const BNNSFilterParameters *fp) BNNS_API(BNNSNDArrayFullyConnectedSparsifySparseCSR);

BNNSRandomGenerator BNNSCreateRandomGenerator(BNNSRandomGeneratorMethod method, const BNNSFilterParameters *fp) BNNS_API(BNNSCreateRandomGenerator);
BNNSRandomGenerator BNNSCreateRandomGeneratorWithSeed(BNNSRandomGeneratorMethod method, uint64_t seed, const BNNSFilterParameters *fp) BNNS_API(BNNSCreateRandomGeneratorWithSeed);
void BNNSDestroyRandomGenerator(BNNSRandomGenerator generator) BNNS_API(BNNSDestroyRandomGenerator);
size_t BNNSRandomGeneratorStateSize(BNNSRandomGenerator generator) BNNS_API(BNNSRandomGeneratorStateSize);
int BNNSRandomGeneratorGetState(BNNSRandomGenerator generator, size_t state_size, void *state) BNNS_API(BNNSRandomGeneratorGetState);
int BNNSRandomGeneratorSetState(BNNSRandomGenerator generator, size_t state_size, void *state) BNNS_API(BNNSRandomGeneratorSetState);
int BNNSRandomFillUniformFloat(BNNSRandomGenerator generator, BNNSNDArrayDescriptor *desc, float a, float b) BNNS_API(BNNSRandomFillUniformFloat);
int BNNSRandomFillUniformInt(BNNSRandomGenerator generator, BNNSNDArrayDescriptor *desc, int64_t a, int64_t b) BNNS_API(BNNSRandomFillUniformInt);
int BNNSRandomFillNormalFloat(BNNSRandomGenerator generator, BNNSNDArrayDescriptor *desc, float mean, float stddev) BNNS_API(BNNSRandomFillNormalFloat);

BNNSNearestNeighbors BNNSCreateNearestNeighbors(unsigned int max_n_samples, unsigned int n_features, unsigned int n_neighbors, BNNSDataType data_type, const BNNSFilterParameters *fp) BNNS_API(BNNSCreateNearestNeighbors);
void BNNSDestroyNearestNeighbors(BNNSNearestNeighbors knn) BNNS_API(BNNSDestroyNearestNeighbors);
int BNNSNearestNeighborsLoad(BNNSNearestNeighbors knn, unsigned int n_new_samples, const void *data_ptr) BNNS_API(BNNSNearestNeighborsLoad);
int BNNSNearestNeighborsGetInfo(BNNSNearestNeighbors knn, int sample_number, int *indices, void *distances) BNNS_API(BNNSNearestNeighborsGetInfo);

// Filters (bnns_filters.c)
BNNSFilter BNNSFilterCreateLayerConvolution(const BNNSLayerParametersConvolution *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerConvolution);
BNNSFilter BNNSFilterCreateLayerTransposedConvolution(const BNNSLayerParametersConvolution *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerTransposedConvolution);
BNNSFilter BNNSFilterCreateLayerFullyConnected(const BNNSLayerParametersFullyConnected *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerFullyConnected);
BNNSFilter BNNSFilterCreateLayerPooling(const BNNSLayerParametersPooling *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerPooling);
BNNSFilter BNNSFilterCreateLayerActivation(const BNNSLayerParametersActivation *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerActivation);
BNNSFilter BNNSFilterCreateLayerLoss(const void *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerLoss);
BNNSFilter BNNSFilterCreateLayerNormalization(BNNSFilterType type, const BNNSLayerParametersNormalization *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerNormalization);
BNNSFilter BNNSFilterCreateLayerArithmetic(const BNNSLayerParametersArithmetic *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerArithmetic);
BNNSFilter BNNSFilterCreateLayerPermute(const BNNSLayerParametersPermute *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerPermute);
BNNSFilter BNNSFilterCreateLayerDropout(const BNNSLayerParametersDropout *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerDropout);
BNNSFilter BNNSFilterCreateLayerPadding(const BNNSLayerParametersPadding *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerPadding);
BNNSFilter BNNSFilterCreateLayerBroadcastMatMul(const BNNSLayerParametersBroadcastMatMul *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerBroadcastMatMul);
BNNSFilter BNNSFilterCreateLayerGram(const BNNSLayerParametersGram *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerGram);
BNNSFilter BNNSFilterCreateLayerResize(const BNNSLayerParametersResize *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerResize);
BNNSFilter BNNSFilterCreateLayerReduction(const BNNSLayerParametersReduction *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerReduction);
BNNSFilter BNNSFilterCreateLayerEmbedding(const BNNSLayerParametersEmbedding *layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateLayerEmbedding);
BNNSFilter BNNSFilterCreateFusedLayer(size_t number_of_fused_filters, const BNNSFilterType *filter_type, const void **layer_params, const BNNSFilterParameters *fp) BNNS_API(BNNSFilterCreateFusedLayer);
void BNNSFilterDestroy(BNNSFilter filter) BNNS_API(BNNSFilterDestroy);

int BNNSFilterApplyBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, void *out, size_t out_stride) BNNS_API(BNNSFilterApplyBatch);
int BNNSFilterApplyTwoInputBatch(BNNSFilter filter, size_t batch_size, const void *inA, size_t inA_stride, const void *inB, size_t inB_stride, void *out, size_t out_stride) BNNS_API(BNNSFilterApplyTwoInputBatch);
int BNNSFilterApply(BNNSFilter filter, const void *in, void *out) BNNS_API(BNNSFilterApply);
int BNNSFilterApplyTwoInput(BNNSFilter filter, const void *inA, const void *inB, void *out) BNNS_API(BNNSFilterApplyTwoInput);
int BNNSPoolingFilterApplyBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, void *out, size_t out_stride, size_t *indices, size_t idx_stride) BNNS_API(BNNSPoolingFilterApplyBatch);
int BNNSPoolingFilterApplyBatchEx(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, void *out, size_t out_stride, BNNSDataType indices_data_type, void *indices, size_t idx_stride) BNNS_API(BNNSPoolingFilterApplyBatchEx);
int BNNSNormalizationFilterApplyBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, void *out, size_t out_stride, bool training) BNNS_API(BNNSNormalizationFilterApplyBatch);
int BNNSFusedFilterApplyBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, void *out, size_t out_stride, bool training) BNNS_API(BNNSFusedFilterApplyBatch);
int BNNSFusedFilterApplyMultiInputBatch(BNNSFilter filter, size_t batch_size, size_t number_of_inputs, const void **in, const size_t *in_stride, void *out, size_t out_stride, bool training) BNNS_API(BNNSFusedFilterApplyMultiInputBatch);
int BNNSArithmeticFilterApplyBatch(BNNSFilter filter, size_t batch_size, size_t number_of_inputs, const void **in, const size_t *in_stride, void *out, size_t out_stride) BNNS_API(BNNSArithmeticFilterApplyBatch);
int BNNSLossFilterApplyBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, const void *labels, size_t labels_stride, const void *weights, size_t weights_size, void *out, BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride) BNNS_API(BNNSLossFilterApplyBatch);

int BNNSFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride, const void *out, size_t out_stride, const BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride, BNNSNDArrayDescriptor *weights_delta, BNNSNDArrayDescriptor *bias_delta) BNNS_API(BNNSFilterApplyBackwardBatch);
int BNNSFilterApplyBackwardTwoInputBatch(BNNSFilter filter, size_t batch_size, const void *inA, size_t inA_stride, BNNSNDArrayDescriptor *inA_delta, size_t inA_delta_stride, const void *inB, size_t inB_stride, BNNSNDArrayDescriptor *inB_delta, size_t inB_delta_stride, const void *out, size_t out_stride, const BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride, BNNSNDArrayDescriptor *weights_delta, BNNSNDArrayDescriptor *bias_delta) BNNS_API(BNNSFilterApplyBackwardTwoInputBatch);
int BNNSPoolingFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride, const void *out, size_t out_stride, BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride, BNNSNDArrayDescriptor *bias_delta, const size_t *indices, size_t idx_stride) BNNS_API(BNNSPoolingFilterApplyBackwardBatch);
int BNNSPoolingFilterApplyBackwardBatchEx(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride, const void *out, size_t out_stride, BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride, BNNSNDArrayDescriptor *bias_delta, BNNSDataType indices_data_type, const void *indices, size_t idx_stride) BNNS_API(BNNSPoolingFilterApplyBackwardBatchEx);
int BNNSNormalizationFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride, const void *out, size_t out_stride, BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride, BNNSNDArrayDescriptor *beta_delta, BNNSNDArrayDescriptor *gamma_delta) BNNS_API(BNNSNormalizationFilterApplyBackwardBatch);
int BNNSFusedFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride, const void *out, size_t out_stride, BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride, BNNSNDArrayDescriptor **delta_parameters) BNNS_API(BNNSFusedFilterApplyBackwardBatch);
int BNNSFusedFilterApplyBackwardMultiInputBatch(BNNSFilter filter, size_t batch_size, size_t number_of_inputs, const void **in, const size_t *in_stride, BNNSNDArrayDescriptor **in_delta, const size_t *in_delta_stride, const void *out, size_t out_stride, BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride, BNNSNDArrayDescriptor **delta_parameters) BNNS_API(BNNSFusedFilterApplyBackwardMultiInputBatch);
int BNNSArithmeticFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, size_t number_of_inputs, const void **in, const size_t *in_stride, BNNSNDArrayDescriptor **in_delta, const size_t *in_delta_stride, const void *out, size_t out_stride, BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride) BNNS_API(BNNSArithmeticFilterApplyBackwardBatch);
int BNNSPermuteFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride, const BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride) BNNS_API(BNNSPermuteFilterApplyBackwardBatch);

// Graphs (bnns_graph.c)
bnns_graph_compile_options_t BNNSGraphCompileOptionsMakeDefault(void) BNNS_API(BNNSGraphCompileOptionsMakeDefault);
void BNNSGraphCompileOptionsDestroy(bnns_graph_compile_options_t options) BNNS_API(BNNSGraphCompileOptionsDestroy);
void BNNSGraphCompileOptionsSetTargetSingleThread(bnns_graph_compile_options_t options, bool value) BNNS_API(BNNSGraphCompileOptionsSetTargetSingleThread);
void BNNSGraphCompileOptionsSetGenerateDebugInfo(bnns_graph_compile_options_t options, bool value) BNNS_API(BNNSGraphCompileOptionsSetGenerateDebugInfo);
void BNNSGraphCompileOptionsSetOptimizationPreference(bnns_graph_compile_options_t options, BNNSGraphOptimizationPreference preference) BNNS_API(BNNSGraphCompileOptionsSetOptimizationPreference);
bnns_graph_t BNNSGraphCompileFromFile_v2(const char *filename, const char *function, bnns_graph_compile_options_t options) BNNS_API(BNNSGraphCompileFromFile_v2);
size_t BNNSGraphGetArgumentCount(bnns_graph_t graph, const char *function) BNNS_API(BNNSGraphGetArgumentCount);
size_t BNNSGraphGetFunctionCount(bnns_graph_t graph) BNNS_API(BNNSGraphGetFunctionCount);
int BNNSGraphGetArgumentNames(bnns_graph_t graph, const char *function, size_t count, const char **names) BNNS_API(BNNSGraphGetArgumentNames);
int BNNSGraphGetFunctionNames(bnns_graph_t graph, size_t count, const char **names) BNNS_API(BNNSGraphGetFunctionNames);
size_t BNNSGraphGetArgumentPosition(bnns_graph_t graph, const char *function, const char *argument) BNNS_API(BNNSGraphGetArgumentPosition);
bnns_graph_context_t BNNSGraphContextMake(bnns_graph_t graph) BNNS_API(BNNSGraphContextMake);
void BNNSGraphContextDestroy_v2(bnns_graph_context_t context) BNNS_API(BNNSGraphContextDestroy_v2);
int BNNSGraphContextSetDynamicShapes_v2(bnns_graph_context_t context, const char *function, size_t shapes_count, bnns_graph_shape_t *shapes) BNNS_API(BNNSGraphContextSetDynamicShapes_v2);
int BNNSGraphContextSetBatchSize_v2(bnns_graph_context_t context, const char *function, uint64_t batch_size) BNNS_API(BNNSGraphContextSetBatchSize_v2);
int BNNSGraphContextSetArgumentType(bnns_graph_context_t context, BNNSGraphArgumentType argument_type) BNNS_API(BNNSGraphContextSetArgumentType);
void BNNSGraphContextEnableNanAndInfChecks(bnns_graph_context_t context, bool enable) BNNS_API(BNNSGraphContextEnableNanAndInfChecks);
int BNNSGraphContextSetStreamingAdvanceCount(bnns_graph_context_t context, size_t advance_count) BNNS_API(BNNSGraphContextSetStreamingAdvanceCount);
int BNNSGraphContextExecute_v2(bnns_graph_context_t context, const char *function, size_t argument_count, bnns_graph_argument_t *arguments, size_t workspace_size, char *workspace) BNNS_API(BNNSGraphContextExecute_v2);
int BNNSGraphContextGetTensor(bnns_graph_context_t context, const char *function, const char *argument, bool fill_known_dynamic_shapes, BNNSTensor *tensor) BNNS_API(BNNSGraphContextGetTensor);
int BNNSGraphTensorFillStrides(bnns_graph_t graph, const char *function, const char *argument, BNNSTensor *tensor) BNNS_API(BNNSGraphTensorFillStrides);

#endif
