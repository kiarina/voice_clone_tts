## Unreleased

- Dart API: `VoiceCloneTts` (`support`, `open`, `createVoice`, `loadVoice`, `primeVoice`, `speak`, `utter`, `close`),
  `Speech`, `Utterance`, `Voice`, `Sampling`, `SpanRule`.
- Native library built by a build hook (`hook/build.dart`) from qwentts.cpp with ggml linked statically. Runs on macOS
  (Metal); Windows (CUDA) is not verified yet.
