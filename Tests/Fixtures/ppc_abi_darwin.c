/* The Darwin side of Scripts/test-ppc-abi.sh, compiled by Apple's ppc GCC:
   it calls Linux functions through pointers the test fills with the
   loader's Darwin entries. */
typedef struct { float x, y, w, h; } Rect;
typedef struct { double a; } OneDouble;
void (*p_rect)(int a, Rect r, int b);
int (*p_mixed)(int a, double d, float f, long long q, int b);
void (*p_one)(int a, OneDouble o, int b);
double (*p_ret_double)(int a);
float (*p_ret_float)(float a);
Rect (*p_ret_rect)(int a, double scale);
void (*p_many)(int a, int b, int c, int d, int e, int f, int g, int h, int i, double x, float y, long long z);
double got_double;
float got_float;
Rect got_rect;
int got_int;
void darwin_calls(void) {
    Rect r = {1.5f, 2.5f, 3.5f, 4.5f};
    OneDouble o = {6.25};
    p_rect(7, r, 8);
    got_int = p_mixed(1, 2.75, 3.5f, 0x100000002LL, 9);
    p_one(10, o, 11);
    got_double = p_ret_double(12);
    got_float = p_ret_float(1.25f);
    got_rect = p_ret_rect(13, 2.0);
    p_many(1, 2, 3, 4, 5, 6, 7, 8, 9, 10.5, 11.5f, 0x300000004LL);
}
/* And Darwin functions the test calls from Linux, through
   perry_ppc_call_darwin. */
double darwin_scale(double a, int b, float c, Rect r, long long q) {
    return a * b + c + r.x + r.y + r.w + r.h + (double)q;
}
float darwin_halve(float a) { return a / 2; }
/* A method, as Darwin code implements one. */
double darwin_method(void *self, void *sel, double a, int b, float c, Rect r, long long q) {
    return darwin_scale(a, b, c, r, q) + (self != 0) + (sel != 0);
}
Rect darwin_rect_method(void *self, void *sel, float scale) {
    Rect r = {scale, 2 * scale, 3 * scale, 4 * scale};
    return r;
}
/* A function of words, which changes r2 (Darwin's code may: it is Linux's
   thread pointer) and calls another, so it saves its lr in its caller's
   frame. */
int darwin_words(int a, int b, int c, int d, int e, int f, int g) {
    __asm__ volatile("li r2, 0x1234" : : : "r2");
    return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + (int)darwin_halve(2.0f);
}
