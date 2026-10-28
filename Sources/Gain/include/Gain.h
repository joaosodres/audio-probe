#pragma once
#include <stddef.h>
void probe_set_gain(float value);
void probe_copy_gain(const float *input, float *output, size_t count);
