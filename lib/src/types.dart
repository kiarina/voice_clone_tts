import 'dart:convert';
import 'dart:typed_data';

/// The weights to load: a talker GGUF and the 12 Hz codec GGUF from the
/// qwentts.cpp conversion of Qwen3-TTS Base, pinned by revision and hash.
enum VoiceCloneModel {
  /// Qwen3-TTS 12Hz 1.7B Base, BF16 talker (about 4.5 GB with the codec).
  /// The default: the quality the package is tuned for.
  base17bBf16(
    'qwen-talker-1.7b-base-BF16.gguf',
    3876199616,
    '7f4567113f3aa07e842fac6d17a10a98cf3d0068c0871ac245ac9befc63affa5',
  ),

  /// 1.7B Base, Q8_0 talker (about 2.7 GB). For GPUs with less memory.
  base17bQ8(
    'qwen-talker-1.7b-base-Q8_0.gguf',
    2079448256,
    '4b9a33a236908dd9435a42f7a396e38038329d053b704342a6413c08544c4fda',
  ),

  /// 0.6B Base, Q8_0 talker (about 1.6 GB).
  base06bQ8(
    'qwen-talker-0.6b-base-Q8_0.gguf',
    992615488,
    'd54dbaf10591421fa764ed630d764efa717ae40cd959bd48c66d4eb1af226426',
  );

  const VoiceCloneModel(this.talkerFile, this.talkerBytes, this.talkerSha256);

  /// File name in the Hugging Face repository.
  final String talkerFile;
  final int talkerBytes;
  final String talkerSha256;

  /// The Hugging Face repository and the revision every file is pinned to.
  static const repository = 'Serveurperso/Qwen3-TTS-GGUF';
  static const revision = 'b7ee2e8c7459c3bea99da23e3d178125a7d1713c';

  /// The 12 Hz codec, shared by every talker (F32: its RVQ paths stay F32).
  static const codecFile = 'qwen-tokenizer-12hz-F32.gguf';
  static const codecBytes = 647263104;
  static const codecSha256 =
      'b16b95557c7c7340a121757bd6855b9609e1cf4ad3fad0778b89393293ae5f3d';
}

/// Whether the model files are on disk.
enum ModelState { missing, downloaded }

/// What this device can do, without downloading or loading anything.
///
/// Each field answers one question; they are not folded into one flag.
class VoiceCloneSupport {
  const VoiceCloneSupport({
    required this.supported,
    required this.engine,
    required this.device,
    required this.modelState,
    this.reason,
  });

  /// True when [VoiceCloneTts.open] can run here.
  final bool supported;

  /// The inference engine, `qwentts.cpp`.
  final String engine;

  /// The ggml device that would run the model (`MTL0`, `CUDA0`), or null
  /// when there is none.
  final String? device;

  /// Whether the requested model's files are already downloaded.
  final ModelState modelState;

  /// Why [supported] is false (platform, no GPU, ...). Null when supported.
  final String? reason;
}

/// A phase of [VoiceCloneTts.open].
enum PreparePhase { download, load, warmup }

class PrepareProgress {
  const PrepareProgress(this.phase, this.fraction);

  final PreparePhase phase;

  /// 0..1 within the phase, or null when unknown.
  final double? fraction;

  @override
  String toString() => 'PrepareProgress($phase, $fraction)';
}

/// Mono 16-bit PCM owned by the caller, at any sample rate (resampled to
/// 24 kHz inside the package).
class Pcm16 {
  Pcm16(this.samples, {required this.sampleRate}) {
    if (samples.isEmpty) throw ArgumentError('samples is empty');
    if (sampleRate <= 0) throw ArgumentError('sampleRate must be positive');
  }

  final Int16List samples;
  final int sampleRate;

  Duration get duration =>
      Duration(microseconds: samples.length * 1000000 ~/ sampleRate);
}

/// A cloned voice: the speaker embedding and the reference codes extracted
/// from a reference recording, plus the recording's transcript.
///
/// Only clone voices whose owner has agreed to it. The package does not
/// keep the reference audio.
class Voice {
  Voice({
    required this.transcript,
    required this.speakerEmbedding,
    required this.codes,
    required this.codebooks,
  });

  /// What the reference recording says, word for word.
  final String transcript;

  /// The speaker embedding (as many values as the talker's hidden size).
  final Float32List speakerEmbedding;

  /// Reference codes, `[codebooks, frames]` row-major.
  final Int32List codes;

  final int codebooks;

  int get frames => codes.length ~/ codebooks;

  /// Serializes the voice so it can be stored and loaded with
  /// [VoiceCloneTts.loadVoice] without extracting it again.
  Uint8List toBytes() {
    final text = utf8.encode(transcript);
    final header = ByteData(20)
      ..setUint32(0, _magic, Endian.little)
      ..setUint32(4, 1, Endian.little) // format version
      ..setUint32(8, speakerEmbedding.length, Endian.little)
      ..setUint32(12, codebooks, Endian.little)
      ..setUint32(16, text.length, Endian.little);
    final out = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(
        speakerEmbedding.buffer.asUint8List(
          speakerEmbedding.offsetInBytes,
          speakerEmbedding.lengthInBytes,
        ),
      )
      ..add(codes.buffer.asUint8List(codes.offsetInBytes, codes.lengthInBytes))
      ..add(text);
    return out.toBytes();
  }

  /// The inverse of [toBytes].
  static Voice fromBytes(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 20 || data.getUint32(0, Endian.little) != _magic) {
      throw const FormatException('not a voice_clone_tts voice');
    }
    if (data.getUint32(4, Endian.little) != 1) {
      throw const FormatException('unsupported voice format version');
    }
    final dim = data.getUint32(8, Endian.little);
    final codebooks = data.getUint32(12, Endian.little);
    final textLength = data.getUint32(16, Endian.little);
    final codesBytes = bytes.length - 20 - dim * 4 - textLength;
    if (codesBytes < 0 || codesBytes % (4 * codebooks) != 0) {
      throw const FormatException('truncated voice');
    }
    var offset = 20;
    final embedding = Float32List.fromList(
      Float32List.sublistView(
        Uint8List.fromList(bytes.sublist(offset, offset + dim * 4)),
      ),
    );
    offset += dim * 4;
    final codes = Int32List.fromList(
      Int32List.sublistView(
        Uint8List.fromList(bytes.sublist(offset, offset + codesBytes)),
      ),
    );
    offset += codesBytes;
    final transcript = utf8.decode(bytes.sublist(offset, offset + textLength));
    return Voice(
      transcript: transcript,
      speakerEmbedding: embedding,
      codes: codes,
      codebooks: codebooks,
    );
  }

  static const _magic = 0x31544356; // "VCT1"
}

/// Sampling of the talker and the code predictor. The defaults are the
/// checkpoint's generation_config.json.
class Sampling {
  const Sampling({
    this.seed,
    this.temperature = 0.9,
    this.topK = 50,
    this.topP = 1.0,
    this.repetitionPenalty = 1.05,
    this.subtalkerTemperature = 0.9,
    this.subtalkerTopK = 50,
    this.subtalkerTopP = 1.0,
    this.maxFrames = 2048,
  });

  /// Fixed seed for a reproducible result on the same machine, or null for
  /// a random one.
  final int? seed;
  final double temperature;
  final int topK;
  final double topP;
  final double repetitionPenalty;
  final double subtalkerTemperature;
  final int subtalkerTopK;
  final double subtalkerTopP;

  /// Upper bound of generated 12.5 Hz frames (80 ms each).
  final int maxFrames;
}

/// How [Utterance] cuts incoming text into spans, each synthesized as one
/// request. The defaults are the rule measured for calls: a span ends at
/// punctuation once it is long enough, or at a length limit.
class SpanRule {
  const SpanRule({
    this.minimumCharacters = 8,
    this.maximumCharacters = 24,
    this.minimumCharactersSpaced = 14,
    this.maximumWordsSpaced = 6,
  });

  /// Japanese, Chinese and other unspaced text: end at punctuation from this
  /// many characters on.
  final int minimumCharacters;

  /// Unspaced text without punctuation: end here.
  final int maximumCharacters;

  /// Spaced text (English and the like): end at punctuation from this many
  /// characters on.
  final int minimumCharactersSpaced;

  /// Spaced text without punctuation: end after this many words.
  final int maximumWordsSpaced;
}

/// How one synthesis ended.
class SpeechResult {
  const SpeechResult({
    required this.audio,
    required this.firstAudio,
    required this.elapsed,
    required this.cancelled,
  });

  /// Length of the PCM produced.
  final Duration audio;

  /// From the request to the first PCM, or null when none came.
  final Duration? firstAudio;

  /// From the request to the end.
  final Duration elapsed;

  final bool cancelled;
}

/// Stops [VoiceCloneTts.open] while it downloads the weights. The partial
/// file is kept, so the next open resumes it.
class PrepareCancel {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

enum VoiceCloneErrorCode {
  unsupported,
  modelMissing,
  outOfMemory,
  invalidInput,
  generateFailed,
  cancelled,
  closed,
}

class VoiceCloneException implements Exception {
  const VoiceCloneException(this.code, this.message);

  final VoiceCloneErrorCode code;

  /// The engine's diagnostic (qwentts.cpp's `qt_last_error`) or the reason.
  final String message;

  @override
  String toString() => 'VoiceCloneException(${code.name}): $message';
}
