# voice_clone_tts

Voice cloning text-to-speech for Flutter on the desktop. Give it a few seconds of a reference voice and its
transcript, then it speaks new text in that voice, streaming 24 kHz PCM as it is generated.

- Model: [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) 12Hz 1.7B Base (BF16), in-context voice cloning from the
  reference audio and its transcript. Ten languages, including English, Chinese and Japanese
- Engine: [qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp) (C++17 on ggml), built from source by a build
  hook and called with `dart:ffi`
- Platforms: macOS (Metal) and Windows (NVIDIA GPU, CUDA). Elsewhere, and on a PC without a usable GPU,
  `VoiceCloneTts.support()` says so, and the app can fall back to another voice

```dart
final tts = await VoiceCloneTts.open(onProgress: print); // downloads the model (about 4.5 GB) on first use
final voice = await tts.createVoice(
  reference: Pcm16(samples, sampleRate: 48000), // a few seconds to 20 s of the voice
  transcript: 'What the reference says, word for word.',
);
final speech = tts.speak('Hello there.', voice: voice, language: 'en');
await for (final pcm in speech.pcm) {
  // 16-bit mono PCM at 24 kHz
}
speech.cancel(); // stops within one 80 ms frame
```

For text that arrives a piece at a time (a live transcript), `tts.utter(...)` cuts it into short spans and speaks them
in order as one stream (`append`, `close`, `cancel`). A voice can be saved with `voice.toBytes()` and loaded with
`tts.loadVoice(bytes)`, so the reference is processed once. The [example](example/) speaks a sentence in the voice of
a WAV file.

## Getting started

Not on pub.dev yet. Depend on the repository; the native sources come from git submodules, so use a local clone made
with `git clone --recurse-submodules`:

```yaml
dependencies:
  voice_clone_tts:
    path: ../voice_clone_tts
```

Building compiles qwentts.cpp and ggml from source:

- macOS: Xcode's command line tools and CMake (`brew install cmake`). The library uses Metal; measured on Apple
  silicon
- Windows: Visual Studio 2022 with "Desktop development with C++" (it provides CMake and Ninja) and the
  [CUDA Toolkit](https://developer.nvidia.com/cuda-downloads) (13.x). Without the CUDA Toolkit it builds for the CPU,
  which is far too slow to speak in real time

On Windows the CUDA kernels are built for several GPU generations by default (RTX 20 series and later), which takes a
long time (about 40 minutes on a Core i9-12900K). To build only for the GPUs you target, set
[`CMAKE_CUDA_ARCHITECTURES`](https://cmake.org/cmake/help/latest/variable/CMAKE_CUDA_ARCHITECTURES.html) in the app's
`pubspec.yaml`:

```yaml
hooks:
  user_defines:
    voice_clone_tts:
      cuda_architectures: "86-real" # RTX 30 series; 89-real for RTX 40, 120a-real for RTX 50
```

The app bundles the cuBLAS DLLs from the CUDA Toolkit (about 550 MB), so users need only an NVIDIA driver, not the
toolkit. A macOS app in the App Sandbox needs the `com.apple.security.network.client` entitlement for the download.

The model is downloaded from [Hugging Face](https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF) (a fixed revision,
verified by SHA-256, resumed if interrupted) into the app's support directory, or the `cacheDirectory` given to
`open`. `VoiceCloneTts.support()` tells whether it is there yet, without downloading or loading anything (give it
the same `cacheDirectory`, or it looks in the default place and answers that the model is missing). To stop a download midway (a pause), pass a `PrepareCancel` to `open` and call its `cancel()`; the partial file is
kept and the next `open` resumes it.

## Performance

Time to make the audio ÷ its length (lower is faster; below 1 keeps up with playback), and the first audio after the
request:

| GPU | One voice | First audio | At once, in real time |
| --- | --- | --- | --- |
| Apple M1 Max (Metal) | 0.5–0.7 | 0.09–0.14 s | 4 (0.95 each) |
| GeForce RTX 3080 Ti 12 GB (CUDA) | 0.16–0.2 | 0.03 s | 6 (0.31 each); 8 runs out of memory |

`open(maxConcurrent: n)` lets `n` voices be made at once. Canceling stops within 5–10 ms. The measurements and the
comparison with other runtimes (MLX, ONNX Runtime) are in [kiarina/labs](https://github.com/kiarina/labs):
`2026/10/23/qwen3-tts-ggml-compare`, `2026/10/23/qwen3-tts-ggml-call-segments` and
`2026/10/23/qwen3-tts-onnx-runtime-compare`.

## Responsible use

Only clone voices whose owner has agreed to it. The package does not check consent; the app using it is responsible
for that, and for telling listeners when a voice is synthetic where that is expected.

## License

MIT (this package). qwentts.cpp and ggml are MIT; the Qwen3-TTS weights are Apache-2.0. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
