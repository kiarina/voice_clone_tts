// vct.h: the thin C layer between Dart and qwentts.cpp (qwen.h).
//
// qt_synthesize blocks and calls its streaming and cancel callbacks from qwentts.cpp's own worker thread, which Dart
// cannot answer synchronously. This layer runs each synthesis on its own thread, copies every PCM chunk (as 16-bit) into
// a malloc'd buffer handed to an asynchronous Dart callback (NativeCallable.listener), and keeps a per-request atomic flag
// that the cancel callback reads.
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#    define VCT_API __declspec(dllexport)
#else
#    define VCT_API __attribute__((visibility("default")))
#endif

typedef struct vct_engine vct_engine;

// Event kinds delivered to vct_event_cb.
enum vct_event {
    VCT_EVENT_PCM       = 0,  // pcm/n: 16-bit mono PCM at 24 kHz (malloc'd, free with vct_free)
    VCT_EVENT_DONE      = 1,  // finished normally
    VCT_EVENT_CANCELLED = 2,  // stopped by vct_cancel
    VCT_EVENT_ERROR     = 3,  // message: malloc'd UTF-8 (free with vct_free); status: the qt_status
};

// Called from a native thread; with NativeCallable.listener the Dart side runs later on its isolate.
typedef void (*vct_event_cb)(int64_t request, int32_t kind, int16_t * pcm, int32_t n, int32_t status, char * message);

typedef struct vct_request {
    const char *    text;
    const char *    lang;      // qwen3-tts language name ("japanese"), NULL = auto
    const char *    ref_text;  // transcript of the reference (ICL); NULL = x-vector only
    const float *   spk_emb;
    int32_t         spk_dim;
    const int32_t * codes;     // [codebooks, frames] row-major, NULL = x-vector only
    int32_t         frames;
    int64_t         seed;      // -1 = random
    int32_t         max_frames;
    float           temperature;
    int32_t         top_k;
    float           top_p;
    float           repetition_penalty;
    float           subtalker_temperature;
    int32_t         subtalker_top_k;
    float           subtalker_top_p;
} vct_request;

// "<git-hash> (<date>)" of the bundled qwentts.cpp.
VCT_API const char * vct_engine_version(void);

// Name of the best ggml device that is a GPU ("MTL0", "CUDA0", ...), written to buf; returns 0 when there is none.
VCT_API int32_t vct_best_gpu(char * buf, int32_t size);

// Loads the model. NULL on failure (see vct_last_error). device NULL = best available.
VCT_API vct_engine * vct_open(const char * talker_path, const char * codec_path, const char * device, int32_t max_batch);
VCT_API void         vct_close(vct_engine * engine);

// The last error message of vct_open / vct_extract_voice on the calling thread.
VCT_API const char * vct_last_error(void);

// Speaker embedding and reference codes from mono float PCM at 24 kHz. Outputs are malloc'd (free with vct_free).
// Returns the qt_status (0 = OK).
VCT_API int32_t vct_extract_voice(vct_engine * engine, const float * pcm24k, int32_t n, float ** spk_emb, int32_t * spk_dim,
                                  int32_t ** codes, int32_t * frames, int32_t * codebooks);

// Starts a synthesis on a new thread. The request is copied; returns its id (> 0).
VCT_API int64_t vct_start(vct_engine * engine, const vct_request * request, vct_event_cb callback);

// Asks the synthesis to stop at the next frame (about 80 ms). Safe on finished ids.
VCT_API void vct_cancel(int64_t request);

VCT_API void vct_free(void * p);

#ifdef __cplusplus
}
#endif
