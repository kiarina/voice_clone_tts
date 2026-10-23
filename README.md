# voice_clone_tts

Voice cloning text-to-speech for Flutter. Give it a few seconds of a reference voice and its
transcript, then it speaks new text in that voice, streaming 24 kHz PCM as it is generated.

**Status: early.** Works on macOS (Metal) and Windows (NVIDIA GPU, CUDA); the API may still
change, and it is not published on pub.dev.

```dart
final tts = await VoiceCloneTts.open(onProgress: print); // downloads about 4.5 GB on first use
final voice = await tts.createVoice(
  reference: Pcm16(samples, sampleRate: 48000), // a few seconds of the voice
  transcript: 'What the reference says, word for word.',
);
final speech = tts.speak('Hello there.', voice: voice, language: 'en');
await for (final pcm in speech.pcm) {
  // 16-bit mono PCM at 24 kHz, the first chunk about 0.1 s (Metal) / 0.03 s (CUDA) after the request
}
speech.cancel(); // stops within one 80 ms frame
```

For text that arrives a piece at a time (a live transcript), `tts.utter(...)` cuts it into short
spans and speaks them in order as one stream.

- Model: [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) 12Hz 1.7B Base (BF16), in-context
  voice cloning from the reference audio and its transcript
- Engine: [qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp) (C++17 on ggml), built by
  a build hook and called with `dart:ffi`
- Platforms: macOS (Metal) and Windows (NVIDIA GPU, CUDA). Elsewhere `VoiceCloneTts.support()`
  reports "unsupported" so that apps can fall back to another voice
- Building needs CMake; on Windows also Visual Studio 2022 (C++) and the CUDA Toolkit. Clone with
  `--recurse-submodules`

Measurements behind these choices are in [kiarina/labs](https://github.com/kiarina/labs):
`2026/10/23/qwen3-tts-ggml-compare` and `2026/10/23/qwen3-tts-ggml-call-segments`.

## Responsible use

Only clone voices whose owner has agreed to it. The package does not check consent; the app
using it is responsible for that.

## License

MIT (this package). qwentts.cpp and ggml are MIT; the Qwen3-TTS weights are Apache-2.0. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
