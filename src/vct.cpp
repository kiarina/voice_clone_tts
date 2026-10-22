// vct.cpp: see vct.h.

#include "vct.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "ggml-backend.h"
#include "qwen.h"

struct vct_engine {
    qt_context * q;
};

namespace {

thread_local std::string last_error;

std::mutex                                                requests_mutex;
std::unordered_map<int64_t, std::shared_ptr<std::atomic<bool>>> requests;
std::atomic<int64_t>                                      next_request{ 1 };

char * copy_string(const std::string & s) {
    char * out = static_cast<char *>(std::malloc(s.size() + 1));
    std::memcpy(out, s.c_str(), s.size() + 1);
    return out;
}

struct job {
    int64_t                            id;
    vct_event_cb                       callback;
    std::shared_ptr<std::atomic<bool>> cancelled;
};

bool on_cancel(void * user_data) {
    return static_cast<job *>(user_data)->cancelled->load(std::memory_order_acquire);
}

bool on_chunk(const float * samples, int n, void * user_data) {
    auto * j = static_cast<job *>(user_data);
    if (j->cancelled->load(std::memory_order_acquire)) {
        return false;
    }
    auto * pcm = static_cast<int16_t *>(std::malloc(sizeof(int16_t) * static_cast<size_t>(std::max(n, 1))));
    for (int i = 0; i < n; i++) {
        float v = std::clamp(samples[i], -1.0f, 1.0f) * 32767.0f;
        pcm[i]  = static_cast<int16_t>(std::lrintf(v));
    }
    j->callback(j->id, VCT_EVENT_PCM, pcm, n, 0, nullptr);
    return true;
}

}  // namespace

extern "C" {

const char * vct_engine_version(void) {
    return qt_version();
}

int32_t vct_best_gpu(char * buf, int32_t size) {
    ggml_backend_load_all();
    for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
        ggml_backend_dev_t dev = ggml_backend_dev_get(i);
        if (ggml_backend_dev_type(dev) == GGML_BACKEND_DEVICE_TYPE_GPU) {
            std::snprintf(buf, static_cast<size_t>(size), "%s", ggml_backend_dev_name(dev));
            return 1;
        }
    }
    return 0;
}

vct_engine * vct_open(const char * talker_path, const char * codec_path, const char * device, int32_t max_batch) {
    qt_init_params params;
    qt_init_default_params(&params);
    params.talker_path = talker_path;
    params.codec_path  = codec_path;
    params.device      = device;
    params.max_batch   = max_batch;
    qt_context * q     = qt_init(&params);
    if (!q) {
        last_error = qt_last_error();
        return nullptr;
    }
    return new vct_engine{ q };
}

void vct_close(vct_engine * engine) {
    if (engine) {
        qt_free(engine->q);
        delete engine;
    }
}

const char * vct_last_error(void) {
    return last_error.c_str();
}

int32_t vct_extract_voice(vct_engine * engine, const float * pcm24k, int32_t n, float ** spk_emb, int32_t * spk_dim,
                          int32_t ** codes, int32_t * frames, int32_t * codebooks) {
    qt_voice_ref ref = {};
    qt_status    rc  = qt_extract_voice_ref(engine->q, pcm24k, n, &ref);
    if (rc != QT_STATUS_OK) {
        last_error = qt_last_error();
        return rc;
    }
    size_t spk_bytes   = sizeof(float) * static_cast<size_t>(ref.ref_spk_dim);
    size_t codes_bytes = sizeof(int32_t) * static_cast<size_t>(ref.num_codebooks) * static_cast<size_t>(ref.ref_T);
    *spk_emb           = static_cast<float *>(std::malloc(spk_bytes));
    *codes             = static_cast<int32_t *>(std::malloc(codes_bytes));
    std::memcpy(*spk_emb, ref.ref_spk_emb, spk_bytes);
    std::memcpy(*codes, ref.ref_codes, codes_bytes);
    *spk_dim   = ref.ref_spk_dim;
    *frames    = ref.ref_T;
    *codebooks = ref.num_codebooks;
    qt_voice_ref_free(&ref);
    return QT_STATUS_OK;
}

int64_t vct_start(vct_engine * engine, const vct_request * request, vct_event_cb callback) {
    // Copy everything the thread reads: the caller frees its buffers as soon as this returns.
    std::string          text = request->text ? request->text : "";
    std::string          lang = request->lang ? request->lang : "";
    std::string          ref_text = request->ref_text ? request->ref_text : "";
    std::vector<float>   spk(request->spk_emb, request->spk_emb + (request->spk_emb ? request->spk_dim : 0));
    int32_t              codebooks = qt_num_codebooks(engine->q);
    std::vector<int32_t> codes;
    if (request->codes) {
        codes.assign(request->codes, request->codes + static_cast<size_t>(codebooks) * static_cast<size_t>(request->frames));
    }
    vct_request settings = *request;

    int64_t id        = next_request.fetch_add(1);
    auto    cancelled = std::make_shared<std::atomic<bool>>(false);
    {
        std::lock_guard<std::mutex> lock(requests_mutex);
        requests[id] = cancelled;
    }
    qt_context * q = engine->q;
    std::thread([=]() mutable {
        job          j{ id, callback, cancelled };
        qt_tts_params p;
        qt_tts_default_params(&p);
        p.text                  = text.c_str();
        p.lang                  = lang.empty() ? nullptr : lang.c_str();
        p.seed                  = settings.seed;
        p.max_new_tokens        = settings.max_frames;
        p.temperature           = settings.temperature;
        p.top_k                 = settings.top_k;
        p.top_p                 = settings.top_p;
        p.repetition_penalty    = settings.repetition_penalty;
        p.subtalker_temperature = settings.subtalker_temperature;
        p.subtalker_top_k       = settings.subtalker_top_k;
        p.subtalker_top_p       = settings.subtalker_top_p;
        if (!spk.empty()) {
            p.ref_spk_emb = spk.data();
            p.ref_spk_dim = static_cast<int>(spk.size());
        }
        if (!codes.empty() && !ref_text.empty()) {
            p.ref_codes = codes.data();
            p.ref_T     = settings.frames;
            p.ref_text  = ref_text.c_str();
        }
        p.cancel             = on_cancel;
        p.cancel_user_data   = &j;
        p.on_chunk           = on_chunk;
        p.on_chunk_user_data = &j;
        qt_audio  out        = {};
        qt_status rc         = qt_synthesize(q, &p, &out);
        qt_audio_free(&out);
        {
            std::lock_guard<std::mutex> lock(requests_mutex);
            requests.erase(id);
        }
        if (rc == QT_STATUS_OK) {
            callback(id, VCT_EVENT_DONE, nullptr, 0, 0, nullptr);
        } else if (rc == QT_STATUS_CANCELLED || cancelled->load()) {
            callback(id, VCT_EVENT_CANCELLED, nullptr, 0, rc, nullptr);
        } else {
            callback(id, VCT_EVENT_ERROR, nullptr, 0, rc, copy_string(qt_last_error()));
        }
    }).detach();
    return id;
}

void vct_cancel(int64_t request) {
    std::lock_guard<std::mutex> lock(requests_mutex);
    auto                        it = requests.find(request);
    if (it != requests.end()) {
        it->second->store(true, std::memory_order_release);
    }
}

void vct_free(void * p) {
    std::free(p);
}

}  // extern "C"
