/// Voice cloning text-to-speech for Flutter: Qwen3-TTS through qwentts.cpp (ggml), Metal on macOS and CUDA on Windows.
///
/// Only clone voices whose owner has agreed to it.
library;

export 'src/engine.dart'
    show Speech, Utterance, VoiceCloneTts, spanEnd, qwenLanguage;
export 'src/types.dart';
