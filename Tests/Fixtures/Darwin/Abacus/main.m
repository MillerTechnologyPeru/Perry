// Accelerate: vDSP's vector arithmetic, reductions, conversions, matrices,
// convolution, windows and FFTs with Apple's scaling; vForce; vImage's
// buffers and channel operations; BLAS and LAPACK. Values print rounded,
// so only the arithmetic, not its last bits, is compared.

#import <Accelerate/Accelerate.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdio.h>

static NSString *list(const float *values, int count) {
    NSMutableArray *parts = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        float v = fabsf(values[i]) < 5e-4f ? 0 : values[i];
        [parts addObject:[NSString stringWithFormat:@"%.3f", v]];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSString *dlist(const double *values, int count) {
    NSMutableArray *parts = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        double v = fabs(values[i]) < 5e-7 ? 0 : values[i];
        [parts addObject:[NSString stringWithFormat:@"%.6f", v]];
    }
    return [parts componentsJoinedByString:@" "];
}

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        float a[] = {1, 2, 3, 4, 5, 6, 7, 8}, b[] = {8, 7, 6, 5, 4, 3, 2, 1}, out[16];
        vDSP_vadd(a, 1, b, 1, out, 1, 8);
        say([@"vadd: " stringByAppendingString:list(out, 8)]);
        vDSP_vsub(a, 1, b, 1, out, 1, 8);
        say([@"vsub: " stringByAppendingString:list(out, 8)]);
        vDSP_vmul(a, 1, b, 1, out, 1, 8);
        say([@"vmul: " stringByAppendingString:list(out, 8)]);
        vDSP_vdiv(a, 1, b, 1, out, 1, 8);
        say([@"vdiv: " stringByAppendingString:list(out, 8)]);
        float scalar = 2.5f, low = 2, high = 6;
        vDSP_vsmul(a, 1, &scalar, out, 1, 8);
        say([@"vsmul: " stringByAppendingString:list(out, 8)]);
        vDSP_vsadd(a, 2, &scalar, out, 1, 4);
        say([@"vsadd stride 2: " stringByAppendingString:list(out, 4)]);
        vDSP_vsma(a, 1, &scalar, b, 1, out, 1, 8);
        say([@"vsma: " stringByAppendingString:list(out, 8)]);
        vDSP_vma(a, 1, b, 1, a, 1, out, 1, 8);
        say([@"vma: " stringByAppendingString:list(out, 8)]);
        vDSP_vclip(a, 1, &low, &high, out, 1, 8);
        say([@"vclip: " stringByAppendingString:list(out, 8)]);
        vDSP_vthr(a, 1, &high, out, 1, 8);
        say([@"vthr: " stringByAppendingString:list(out, 8)]);
        float start = 0.5f, step = 0.25f;
        vDSP_vramp(&start, &step, out, 1, 5);
        say([@"vramp: " stringByAppendingString:list(out, 5)]);
        vDSP_vfill(&scalar, out, 1, 3);
        say([@"vfill: " stringByAppendingString:list(out, 3)]);
        vDSP_vclr(out, 1, 3);
        say([@"vclr: " stringByAppendingString:list(out, 3)]);
        float mixed[] = {-3, 1.5f, -0.5f, 4, -2};
        vDSP_vabs(mixed, 1, out, 1, 5);
        say([@"vabs: " stringByAppendingString:list(out, 5)]);
        vDSP_vneg(mixed, 1, out, 1, 5);
        say([@"vneg: " stringByAppendingString:list(out, 5)]);
        vDSP_vsq(mixed, 1, out, 1, 5);
        say([@"vsq: " stringByAppendingString:list(out, 5)]);
        vDSP_vrvrs(mixed, 1, 5);
        say([@"vrvrs: " stringByAppendingString:list(mixed, 5)]);
        vDSP_vsort(mixed, 5, 1);
        say([@"vsort up: " stringByAppendingString:list(mixed, 5)]);
        vDSP_vsort(mixed, 5, -1);
        say([@"vsort down: " stringByAppendingString:list(mixed, 5)]);

        float sum, mean, rms, maximum, minimum, dot, squares, magnitudes, meanSquare, meanMagnitude;
        vDSP_Length maxIndex, minIndex;
        float signed5[] = {3, -7, 2, 9, -1};
        vDSP_sve(signed5, 1, &sum, 5);
        vDSP_meanv(signed5, 1, &mean, 5);
        vDSP_rmsqv(signed5, 1, &rms, 5);
        vDSP_maxv(signed5, 1, &maximum, 5);
        vDSP_minv(signed5, 1, &minimum, 5);
        vDSP_maxvi(signed5, 1, &maximum, &maxIndex, 5);
        vDSP_minvi(signed5, 1, &minimum, &minIndex, 5);
        vDSP_dotpr(a, 1, b, 1, &dot, 8);
        vDSP_svesq(signed5, 1, &squares, 5);
        vDSP_svemg(signed5, 1, &magnitudes, 5);
        vDSP_measqv(signed5, 1, &meanSquare, 5);
        vDSP_meamgv(signed5, 1, &meanMagnitude, 5);
        say([NSString stringWithFormat:@"reductions: sum %.3f mean %.3f rms %.3f max %.1f@%lu min %.1f@%lu dot %.1f squares %.1f mag %.1f measq %.2f meamg %.2f",
             sum, mean, rms, maximum, (unsigned long)maxIndex, minimum, (unsigned long)minIndex, dot, squares, magnitudes, meanSquare, meanMagnitude]);
        float maxMagnitude;
        vDSP_maxmgv(signed5, 1, &maxMagnitude, 5);
        float distance;
        vDSP_distancesq(a, 1, b, 1, &distance, 8);
        say([NSString stringWithFormat:@"magnitude %.1f distance %.1f", maxMagnitude, distance]);

        float fractions[] = {1.4f, 1.5f, 2.5f, -1.5f, -2.7f, 300.6f};
        short shorts[6];
        int ints[6];
        vDSP_vfix16(fractions, 1, shorts, 1, 6);
        say([NSString stringWithFormat:@"vfix16: %d %d %d %d %d %d", shorts[0], shorts[1], shorts[2], shorts[3], shorts[4], shorts[5]]);
        vDSP_vfixr32(fractions, 1, ints, 1, 6);
        say([NSString stringWithFormat:@"vfixr32: %d %d %d %d %d %d", ints[0], ints[1], ints[2], ints[3], ints[4], ints[5]]);
        unsigned char bytes[] = {0, 128, 255};
        vDSP_vfltu8(bytes, 1, out, 1, 3);
        say([@"vfltu8: " stringByAppendingString:list(out, 3)]);
        double doubles[3];
        vDSP_vspdp(fractions, 1, doubles, 1, 3);
        say([@"vspdp: " stringByAppendingString:dlist(doubles, 3)]);
        float powers[] = {1, 10, 100, 0.5f}, reference = 1;
        vDSP_vdbcon(powers, 1, &reference, out, 1, 4, 0);
        say([@"vdbcon power: " stringByAppendingString:list(out, 4)]);
        vDSP_vdbcon(powers, 1, &reference, out, 1, 4, 1);
        say([@"vdbcon amplitude: " stringByAppendingString:list(out, 4)]);

        // Matrices: 2x3 times 3x2, and a transpose.
        float m1[] = {1, 2, 3, 4, 5, 6}, m2[] = {7, 8, 9, 10, 11, 12}, product[4], transposed[6];
        vDSP_mmul(m1, 1, m2, 1, product, 1, 2, 2, 3);
        say([@"mmul: " stringByAppendingString:list(product, 4)]);
        vDSP_mtrans(m1, 1, transposed, 1, 3, 2);
        say([@"mtrans: " stringByAppendingString:list(transposed, 6)]);

        // Correlation and convolution.
        float signal[] = {1, 2, 3, 4, 5, 6, 7}, filter[] = {1, 0, -1}, filtered[5];
        vDSP_conv(signal, 1, filter, 1, filtered, 1, 5, 3);
        say([@"correlate: " stringByAppendingString:list(filtered, 5)]);
        vDSP_conv(signal, 1, filter + 2, -1, filtered, 1, 5, 3);
        say([@"convolve: " stringByAppendingString:list(filtered, 5)]);

        float window[8];
        vDSP_hann_window(window, 8, vDSP_HANN_NORM);
        say([@"hann: " stringByAppendingString:list(window, 8)]);
        vDSP_hann_window(window, 8, vDSP_HANN_DENORM);
        say([@"hann denorm: " stringByAppendingString:list(window, 8)]);
        vDSP_hamm_window(window, 8, 0);
        say([@"hamming: " stringByAppendingString:list(window, 8)]);
        vDSP_blkman_window(window, 8, 0);
        say([@"blackman: " stringByAppendingString:list(window, 8)]);

        // A real FFT of 8 samples, packed, and back.
        float samples[8] = {1, 0, -1, 0, 1, 2, 3, 4}, realp[4], imagp[4];
        DSPSplitComplex split = {realp, imagp};
        vDSP_ctoz((const DSPComplex *)samples, 2, &split, 1, 4);
        say([NSString stringWithFormat:@"ctoz: %@ / %@", list(realp, 4), list(imagp, 4)]);
        FFTSetup setup = vDSP_create_fftsetup(3, kFFTRadix2);
        vDSP_fft_zrip(setup, &split, 1, 3, kFFTDirection_Forward);
        say([NSString stringWithFormat:@"fft_zrip forward: %@ / %@", list(realp, 4), list(imagp, 4)]);
        float magnitudesq[4];
        vDSP_zvmags(&split, 1, magnitudesq, 1, 4);
        say([@"zvmags: " stringByAppendingString:list(magnitudesq, 4)]);
        vDSP_zvabs(&split, 1, magnitudesq, 1, 4);
        say([@"zvabs: " stringByAppendingString:list(magnitudesq, 4)]);
        vDSP_fft_zrip(setup, &split, 1, 3, kFFTDirection_Inverse);
        float restored[8];
        vDSP_ztoc(&split, 1, (DSPComplex *)restored, 2, 4);
        say([@"fft_zrip inverse: " stringByAppendingString:list(restored, 8)]);

        // A complex FFT of 4 points.
        float cr[] = {1, 2, 3, 4}, ci[] = {0, 0, 0, 0};
        DSPSplitComplex complex = {cr, ci};
        vDSP_fft_zip(setup, &complex, 1, 2, kFFTDirection_Forward);
        say([NSString stringWithFormat:@"fft_zip forward: %@ / %@", list(cr, 4), list(ci, 4)]);
        vDSP_fft_zip(setup, &complex, 1, 2, kFFTDirection_Inverse);
        say([NSString stringWithFormat:@"fft_zip inverse: %@ / %@", list(cr, 4), list(ci, 4)]);
        vDSP_destroy_fftsetup(setup);

        // The DFT interface.
        float inR[] = {1, 2, 3, 4, 5, 6, 7, 8}, inI[8] = {0}, outR[8], outI[8];
        vDSP_DFT_Setup dft = vDSP_DFT_zop_CreateSetup(NULL, 8, vDSP_DFT_FORWARD);
        vDSP_DFT_Execute(dft, inR, inI, outR, outI);
        say([NSString stringWithFormat:@"dft: %@ / %@", list(outR, 8), list(outI, 8)]);
        vDSP_DFT_DestroySetup(dft);

        double da[] = {1.5, -2.25, 3}, dout[3], dsum;
        vDSP_vaddD(da, 1, da, 1, dout, 1, 3);
        vDSP_sveD(da, 1, &dsum, 3);
        say([NSString stringWithFormat:@"double: %@ sum %.4f", dlist(dout, 3), dsum]);

        // vForce.
        float vin[] = {0.25f, 1, 4, 9}, vout[4];
        int n = 4;
        vvsqrtf(vout, vin, &n);
        say([@"vvsqrtf: " stringByAppendingString:list(vout, 4)]);
        vvlogf(vout, vin, &n);
        say([@"vvlogf: " stringByAppendingString:list(vout, 4)]);
        vvexpf(vout, vin, &n);
        // To two places: the last digit of exp(9) in single precision is
        // where implementations round differently.
        say([NSString stringWithFormat:@"vvexpf: %.2f %.2f %.2f %.2f", vout[0], vout[1], vout[2], vout[3]]);
        vvsinf(vout, vin, &n);
        say([@"vvsinf: " stringByAppendingString:list(vout, 4)]);
        float exponents[] = {2, 0.5f, -1, 3};
        vvpowf(vout, exponents, vin, &n);
        say([@"vvpowf: " stringByAppendingString:list(vout, 4)]);
        vvfloorf(vout, fractions, &n);
        say([@"vvfloorf: " stringByAppendingString:list(vout, 4)]);
        double dvin[] = {1, 2}, dvout[2];
        int two = 2;
        vvexp(dvout, dvin, &two);
        say([@"vvexp: " stringByAppendingString:dlist(dvout, 2)]);

        // vImage.
        vImage_Buffer buffer;
        vImage_Error error = vImageBuffer_Init(&buffer, 3, 5, 32, kvImageNoFlags);
        say([NSString stringWithFormat:@"buffer: error %ld %lux%lu row %lu data %d", error, (unsigned long)buffer.width,
             (unsigned long)buffer.height, (unsigned long)buffer.rowBytes, buffer.data != NULL]);
        uint8_t *pixels = buffer.data;
        for (unsigned long y = 0; y < buffer.height; y++)
            for (unsigned long x = 0; x < buffer.width; x++) {
                uint8_t *p = pixels + y * buffer.rowBytes + x * 4;
                p[0] = 255; p[1] = (uint8_t)(x * 50); p[2] = (uint8_t)(y * 60); p[3] = 7;
            }
        const uint8_t order[4] = {3, 2, 1, 0};
        error = vImagePermuteChannels_ARGB8888(&buffer, &buffer, order, kvImageNoFlags);
        uint8_t *q = (uint8_t *)buffer.data + buffer.rowBytes + 4;
        say([NSString stringWithFormat:@"permute: error %ld %d %d %d %d", error, q[0], q[1], q[2], q[3]]);
        vImage_Buffer rgb;
        vImageBuffer_Init(&rgb, 3, 5, 24, kvImageNoFlags);
        error = vImageConvert_ARGB8888toRGB888(&buffer, &rgb, kvImageNoFlags);
        uint8_t *r = (uint8_t *)rgb.data + rgb.rowBytes + 3;
        say([NSString stringWithFormat:@"to rgb: error %ld row %lu %d %d %d", error, (unsigned long)rgb.rowBytes, r[0], r[1], r[2]]);
        vImage_Buffer small = {calloc(4, 1), 1, 1, 4};
        error = vImageScale_ARGB8888(&buffer, &small, NULL, kvImageNoFlags);
        say([NSString stringWithFormat:@"scale to 1x1: error %ld", error]);
        free(buffer.data);
        free(rgb.data);
        free(small.data);
        say([NSString stringWithFormat:@"bad buffer: %ld", vImageBuffer_Init(&buffer, 0, 0, 32, kvImageNoFlags)]);

        // BLAS and LAPACK.
        float x[] = {1, 2, 3}, y[] = {4, 5, 6};
        say([NSString stringWithFormat:@"blas: dot %.1f nrm2 %.4f asum %.1f", cblas_sdot(3, x, 1, y, 1), cblas_snrm2(3, x, 1),
             cblas_sasum(3, x, 1)]);
        cblas_saxpy(3, 2, x, 1, y, 1);
        say([@"saxpy: " stringByAppendingString:list(y, 3)]);
        double A[] = {1, 2, 3, 4}, B[] = {5, 6, 7, 8}, C[4] = {0};
        cblas_dgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, 2, 2, 2, 1, A, 2, B, 2, 0, C, 2);
        say([@"dgemm: " stringByAppendingString:dlist(C, 4)]);
        cblas_dgemv(CblasRowMajor, CblasNoTrans, 2, 2, 1, A, 2, B, 1, 0, C, 1);
        say([@"dgemv: " stringByAppendingString:dlist(C, 2)]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // Solve [[2, 1], [1, 3]] x = [3, 5], column-major.
        __CLPK_doublereal M[] = {2, 1, 1, 3}, rhs[] = {3, 5};
        __CLPK_integer order2 = 2, nrhs = 1, lda = 2, ldb = 2, pivots[2], info = 0;
        dgesv_(&order2, &nrhs, M, &lda, pivots, rhs, &ldb, &info);
        say([NSString stringWithFormat:@"dgesv: info %d x %@", (int)info, dlist(rhs, 2)]);
#pragma clang diagnostic pop
    }
    return 0;
}
