#include "Gain.h"
#include <stdatomic.h>
static _Atomic(float) target = 1.0f;
// Only the single audio callback accesses current.
static float current = 1.0f;
void probe_set_gain(float value) {
    atomic_store_explicit(&target, value, memory_order_relaxed);
}
void probe_copy_gain(const float *input, float *output, size_t count) {
    float goal = atomic_load_explicit(&target, memory_order_relaxed);
    // A short smoothing ramp avoids a discontinuity on slider changes.
    for (size_t i = 0; i < count; i++) {
        current += (goal - current) * 0.002f;
        output[i] = input[i] * current;
    }
}
