# voice_clone_tts

Voice cloning text-to-speech for Flutter. Give it a few seconds of a reference voice and its
transcript, then it speaks new text in that voice, streaming 24 kHz PCM as it is generated.

**Status: under construction.** The Dart API and the native backends are being designed; nothing
here is usable yet, and it is not published on pub.dev.

## Plan

- Model: [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) 12Hz 1.7B Base (BF16), in-context
  voice cloning from the reference audio and its transcript
- Engine: [qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp) (C++17 on ggml), called
  through its C ABI with `dart:ffi`
- Platforms: macOS (Metal) and Windows (NVIDIA GPU, CUDA). Other platforms report "unsupported"
  so that apps can fall back to another voice
- Weights are downloaded on first use (about 4.5 GB), not bundled
- A server package on top (`packages/voice_clone_tts_server`) will expose an
  OpenAI-compatible `POST /v1/audio/speech`, voice registration and a streaming WebSocket

Measurements behind these choices (speed on Apple M1 Max and RTX 3080 Ti, streaming latency,
call-style short spans, barge-in) are in
[kiarina/labs](https://github.com/kiarina/labs): `2026/10/23/qwen3-tts-ggml-compare` and
`2026/10/23/qwen3-tts-ggml-call-segments`.

## Responsible use

Only clone voices whose owner has agreed to it. The package does not check consent; the app
using it is responsible for that.

## License

MIT (this package). qwentts.cpp and ggml are MIT; the Qwen3-TTS weights are Apache-2.0. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
