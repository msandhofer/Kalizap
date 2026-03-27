// SPDX-License-Identifier: MIT OR Apache-2.0
// Generated from DeepFilterNet libDF/src/capi.rs

#ifndef DEEP_FILTER_H
#define DEEP_FILTER_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct DFState DFState;

/// Create a DeepFilterNet Model.
/// - path: File path to a DeepFilterNet tar.gz onnx model
/// - atten_lim: Attenuation limit in dB (100.0 = no limit)
/// - log_level: C string like "info", "debug", "warn", or NULL
DFState *df_create(const char *path, float atten_lim, const char *log_level);

/// Get DeepFilterNet frame size in samples.
size_t df_get_frame_length(DFState *st);

/// Process a chunk of samples.
/// - input: Input buffer of length df_get_frame_length()
/// - output: Output buffer of length df_get_frame_length()
/// Returns: Local SNR of the current frame in dB.
float df_process_frame(DFState *st, float *input, float *output);

/// Set attenuation limit in dB.
void df_set_atten_lim(DFState *st, float lim_db);

/// Set post filter beta (0 disables, range 0-0.05).
void df_set_post_filter_beta(DFState *st, float beta);

/// Get next log message. Must be freed via df_free_log_msg().
char *df_next_log_msg(DFState *st);

/// Free a log message returned by df_next_log_msg().
void df_free_log_msg(char *ptr);

/// Free a DeepFilterNet Model.
void df_free(DFState *model);

#endif /* DEEP_FILTER_H */
