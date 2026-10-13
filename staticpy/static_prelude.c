#include <stdlib.h>
#include <string.h>
#include <stdint.h>

// Float array operations
void* make_float_array(int n) {
    float* arr = (float*)malloc(n * sizeof(float));
    if (arr) memset(arr, 0, n * sizeof(float));
    return arr;
}
void float_array_set(void* arr, int i, float val) {
    ((float*)arr)[i] = val;
}
float float_array_ref(void* arr, int i) {
    return ((float*)arr)[i];
}
void float_array_free(void* arr) { free(arr); }

// Ptr (void*) array operations  
void* make_ptr_array(int n) {
    void** arr = (void**)calloc(n, sizeof(void*));
    return arr;
}
void ptr_array_set(void* arr, int i, void* val) {
    ((void**)arr)[i] = val;
}
void* ptr_array_ref(void* arr, int i) {
    return ((void**)arr)[i];
}

// Int64 array operations
void* make_int_array(int n) {
    int64_t* arr = (int64_t*)malloc(n * sizeof(int64_t));
    if (arr) memset(arr, 0, n * sizeof(int64_t));
    return arr;
}
void int_array_set(void* arr, int i, int64_t val) {
    ((int64_t*)arr)[i] = val;
}
int64_t int_array_ref(void* arr, int i) {
    return ((int64_t*)arr)[i];
}
