## 0.1.0

First release.

- Dart API: `VoiceCloneTts` (`support`, `open`, `createVoice`, `loadVoice`, `primeVoice`, `speak`, `utter`, `close`),
  `Speech`, `Utterance`, `Voice`, `Sampling`, `SpanRule`.
- Native library built by a build hook (`hook/build.dart`) from qwentts.cpp with ggml linked statically. Runs on macOS
  (Metal) and Windows (CUDA; built with Ninja inside the Visual Studio developer environment).
- `VoiceCloneTts.open(maxConcurrent:)` makes several voices at once.
- The model (Qwen3-TTS 1.7B Base, BF16 GGUF) is downloaded from a fixed Hugging Face revision, verified by SHA-256 and
  resumed if interrupted. `open(cancel:)` stops a download (a `PrepareCancel`); the next `open` resumes it.
- On Windows the cuBLAS DLLs are bundled with the app; the CUDA kernels' GPU generations can be set with the
  `cuda_architectures` user define. On macOS the library exports only its `vct_*` functions.
- Example app that speaks a sentence in the voice of a WAV file.
