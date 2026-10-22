import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import 'native.dart';
import 'resample.dart';
import 'types.dart';
import 'weights.dart';

/// Voice cloning text-to-speech: Qwen3-TTS through qwentts.cpp.
///
/// Only clone voices whose owner has agreed to it.
class VoiceCloneTts {
  VoiceCloneTts._(this._engine, this.model, this.device) {
    _callback = NativeCallable<VctEventCallback>.listener(_onEvent);
  }

  final Pointer<Void> _engine;
  late final NativeCallable<VctEventCallback> _callback;
  final _jobs = <int, Speech>{};
  bool _closed = false;

  final VoiceCloneModel model;

  /// The ggml device the model runs on (`MTL0`, `CUDA0`).
  final String device;

  /// What this device can do, without downloading or loading anything.
  static Future<VoiceCloneSupport> support({
    VoiceCloneModel model = VoiceCloneModel.base17bBf16,
    Directory? cacheDirectory,
  }) async {
    final state =
        WeightStore(cacheDirectory ?? await _defaultCache()).has(model)
        ? ModelState.downloaded
        : ModelState.missing;
    if (!Platform.isMacOS && !Platform.isWindows) {
      return VoiceCloneSupport(
        supported: false,
        engine: 'qwentts.cpp',
        device: null,
        modelState: state,
        reason: 'only macOS (Metal) and Windows (CUDA) are supported',
      );
    }
    String? gpu;
    try {
      gpu = await Isolate.run(_bestGpu);
    } on Object catch (e) {
      return VoiceCloneSupport(
        supported: false,
        engine: 'qwentts.cpp',
        device: null,
        modelState: state,
        reason: 'native library unavailable: $e',
      );
    }
    return VoiceCloneSupport(
      supported: gpu != null,
      engine: 'qwentts.cpp',
      device: gpu,
      modelState: state,
      reason: gpu == null
          ? (Platform.isWindows ? 'no NVIDIA GPU (CUDA)' : 'no Metal device')
          : null,
    );
  }

  /// Downloads the weights when missing, loads them and warms the engine up.
  static Future<VoiceCloneTts> open({
    VoiceCloneModel model = VoiceCloneModel.base17bBf16,
    Directory? cacheDirectory,
    int maxConcurrent = 1,
    void Function(PrepareProgress progress)? onProgress,
  }) async {
    final cache = cacheDirectory ?? await _defaultCache();
    final support = await VoiceCloneTts.support(
      model: model,
      cacheDirectory: cache,
    );
    if (!support.supported) {
      throw VoiceCloneException(
        VoiceCloneErrorCode.unsupported,
        support.reason ?? 'unsupported',
      );
    }
    final store = WeightStore(cache);
    await store.ensure(
      model,
      (f) => onProgress?.call(PrepareProgress(PreparePhase.download, f)),
    );
    onProgress?.call(const PrepareProgress(PreparePhase.load, null));
    final files = weightFiles(model);
    final talker = store.file(files[0]).path;
    final codec = store.file(files[1]).path;
    final device = support.device!;
    final (address, error) = await Isolate.run(
      () => _open(talker, codec, device, maxConcurrent),
    );
    if (address == 0) {
      throw VoiceCloneException(
        error.contains('alloc')
            ? VoiceCloneErrorCode.outOfMemory
            : VoiceCloneErrorCode.generateFailed,
        error,
      );
    }
    final tts = VoiceCloneTts._(
      Pointer<Void>.fromAddress(address),
      model,
      device,
    );
    onProgress?.call(const PrepareProgress(PreparePhase.warmup, null));
    await tts._warmUp();
    return tts;
  }

  /// Extracts a voice from a reference recording and its transcript (a few seconds to about 15 s works best).
  ///
  /// The voice is primed with a tiny synthesis so its first reply starts as fast as the rest ([warm]).
  Future<Voice> createVoice({
    required Pcm16 reference,
    required String transcript,
    bool warm = true,
  }) async {
    _checkOpen();
    if (transcript.trim().isEmpty) {
      throw const VoiceCloneException(
        VoiceCloneErrorCode.invalidInput,
        'transcript is empty',
      );
    }
    final pcm = resampleTo24k(reference.samples, reference.sampleRate);
    final address = _engine.address;
    final result = await Isolate.run(() => _extract(address, pcm));
    if (result.error != null) {
      throw VoiceCloneException(
        VoiceCloneErrorCode.generateFailed,
        result.error!,
      );
    }
    final voice = Voice(
      transcript: transcript,
      speakerEmbedding: result.speakerEmbedding!,
      codes: result.codes!,
      codebooks: result.codebooks,
    );
    if (warm) await _prime(voice);
    return voice;
  }

  /// qwentts.cpp primes the streaming codec with the voice's reference codes on its first request and keeps that state
  /// (an LRU keyed by the codes), which costs about 0.5 s on Metal. A two-frame synthesis pays it here instead of in
  /// the first real reply.
  Future<void> _prime(Voice voice) async {
    final speech = speak(
      '。',
      voice: voice,
      sampling: const Sampling(seed: 0, maxFrames: 2),
    );
    await speech.pcm.drain<void>();
    await speech.done;
  }

  /// A voice stored with [Voice.toBytes].
  ///
  /// Call [primeVoice] to make its first reply as fast as the rest.
  Voice loadVoice(Uint8List bytes) => Voice.fromBytes(bytes);

  /// Pays a voice's one-time set-up (about 0.5 s on Metal) now instead of in its first reply.
  Future<void> primeVoice(Voice voice) {
    _checkOpen();
    return _prime(voice);
  }

  /// Speaks [text] in [voice], streaming 16-bit mono PCM at 24 kHz.
  ///
  /// [language] is a BCP 47 tag (`ja`, `en`, ...) or null to let the model infer it.
  Speech speak(
    String text, {
    required Voice voice,
    String? language,
    Sampling sampling = const Sampling(),
  }) {
    _checkOpen();
    if (text.trim().isEmpty) {
      throw const VoiceCloneException(
        VoiceCloneErrorCode.invalidInput,
        'text is empty',
      );
    }
    final speech = Speech._();
    final id = _start(text, voice, language, sampling);
    speech._id = id;
    _jobs[id] = speech;
    return speech;
  }

  /// Speaks text that arrives a piece at a time (a live transcript): it is cut into short spans by [rule], each span
  /// synthesized as one request, and the spans come out in order as one stream.
  Utterance utter({
    required Voice voice,
    String? language,
    Sampling sampling = const Sampling(),
    SpanRule rule = const SpanRule(),
  }) {
    _checkOpen();
    return Utterance._(this, voice, language, sampling, rule);
  }

  /// Stops every synthesis and releases the model.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final pending = _jobs.values.toList();
    for (final s in pending) {
      s.cancel();
    }
    await Future.wait(pending.map((s) => s.done.catchError((_) => s._result)));
    vctClose(_engine);
    _callback.close();
  }

  void _checkOpen() {
    if (_closed)
      throw const VoiceCloneException(VoiceCloneErrorCode.closed, 'closed');
  }

  /// Runs one tiny synthesis so the first real request does not pay the GPU kernel set-up (about 1 s on Metal).
  /// The voice comes from one second of quiet noise; nothing is kept.
  Future<void> _warmUp() async {
    final noise = Int16List(24000);
    var seed = 1;
    for (var i = 0; i < noise.length; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      noise[i] = (seed % 200) - 100;
    }
    final voice = await createVoice(
      reference: Pcm16(noise, sampleRate: 24000),
      transcript: 'あ',
      warm: false,
    );
    final speech = speak(
      'あ。',
      voice: voice,
      language: 'ja',
      sampling: const Sampling(seed: 0, maxFrames: 4),
    );
    await speech.pcm.drain<void>();
    await speech.done;
  }

  int _start(String text, Voice voice, String? language, Sampling sampling) {
    return using((arena) {
      final request = arena<VctRequest>();
      final spk = arena<Float>(voice.speakerEmbedding.length);
      spk
          .asTypedList(voice.speakerEmbedding.length)
          .setAll(0, voice.speakerEmbedding);
      final codes = arena<Int32>(voice.codes.length);
      codes.asTypedList(voice.codes.length).setAll(0, voice.codes);
      final lang = qwenLanguage(language);
      request.ref
        ..text = text.toNativeUtf8(allocator: arena)
        ..lang = lang == null ? nullptr : lang.toNativeUtf8(allocator: arena)
        ..refText = voice.transcript.toNativeUtf8(allocator: arena)
        ..spkEmb = spk
        ..spkDim = voice.speakerEmbedding.length
        ..codes = codes
        ..frames = voice.frames
        ..seed = sampling.seed ?? -1
        ..maxFrames = sampling.maxFrames
        ..temperature = sampling.temperature
        ..topK = sampling.topK
        ..topP = sampling.topP
        ..repetitionPenalty = sampling.repetitionPenalty
        ..subtalkerTemperature = sampling.subtalkerTemperature
        ..subtalkerTopK = sampling.subtalkerTopK
        ..subtalkerTopP = sampling.subtalkerTopP;
      return vctStart(_engine, request, _callback.nativeFunction);
    });
  }

  void _onEvent(
    int id,
    int kind,
    Pointer<Int16> pcm,
    int n,
    int status,
    Pointer<Utf8> message,
  ) {
    final speech = _jobs[id];
    Int16List? samples;
    String? text;
    if (pcm != nullptr) {
      samples = Int16List.fromList(pcm.asTypedList(n));
      vctFree(pcm.cast());
    }
    if (message != nullptr) {
      text = message.toDartString();
      vctFree(message.cast());
    }
    if (speech == null) return;
    switch (kind) {
      case vctEventPcm:
        speech._add(samples!);
      case vctEventDone:
        _jobs.remove(id);
        speech._finish(cancelled: false);
      case vctEventCancelled:
        _jobs.remove(id);
        speech._finish(cancelled: true);
      default:
        _jobs.remove(id);
        speech._fail(
          VoiceCloneException(
            status == -4
                ? VoiceCloneErrorCode.outOfMemory
                : VoiceCloneErrorCode.generateFailed,
            text ?? 'synthesis failed ($status)',
          ),
        );
    }
  }

  static Future<Directory> _defaultCache() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/voice_clone_tts',
  );
}

/// One synthesis in progress.
class Speech {
  Speech._() : _started = DateTime.now();

  final DateTime _started;
  late final int _id;
  final _pcm = StreamController<Int16List>();
  final _done = Completer<SpeechResult>();
  var _samples = 0;
  Duration? _firstAudio;
  SpeechResult? _resultValue;

  /// 16-bit mono PCM at 24 kHz, as it is generated (the first chunk is one 80 ms frame).
  Stream<Int16List> get pcm => _pcm.stream;

  /// Completes when the synthesis ends (normally or cancelled); errors with [VoiceCloneException].
  Future<SpeechResult> get done => _done.future;

  /// Stops the synthesis at the next frame (about 80 ms).
  void cancel() {
    if (!_done.isCompleted) vctCancel(_id);
  }

  SpeechResult get _result => _resultValue ?? _summary(cancelled: true);

  void _add(Int16List samples) {
    _firstAudio ??= DateTime.now().difference(_started);
    _samples += samples.length;
    if (!_pcm.isClosed) _pcm.add(samples);
  }

  SpeechResult _summary({required bool cancelled}) => SpeechResult(
    audio: Duration(microseconds: _samples * 1000000 ~/ 24000),
    firstAudio: _firstAudio,
    elapsed: DateTime.now().difference(_started),
    cancelled: cancelled,
  );

  void _finish({required bool cancelled}) {
    _resultValue = _summary(cancelled: cancelled);
    _pcm.close();
    if (!_done.isCompleted) _done.complete(_resultValue);
  }

  void _fail(VoiceCloneException error) {
    _resultValue = _summary(cancelled: false);
    _pcm.addError(error);
    _pcm.close();
    if (!_done.isCompleted) _done.completeError(error);
  }
}

/// Text that arrives a piece at a time, spoken span by span as one stream.
class Utterance {
  Utterance._(
    this._tts,
    this._voice,
    this._language,
    this._sampling,
    this._rule,
  ) : _started = DateTime.now();

  final VoiceCloneTts _tts;
  final Voice _voice;
  final String? _language;
  final Sampling _sampling;
  final SpanRule _rule;
  final DateTime _started;
  final _pcm = StreamController<Int16List>();
  final _done = Completer<SpeechResult>();
  final _spans = <String>[];
  var _text = '';
  var _cursor = 0;
  var _closed = false;
  var _cancelled = false;
  var _samples = 0;
  Duration? _firstAudio;
  Speech? _current;

  /// The spans' PCM in order (16-bit mono, 24 kHz).
  Stream<Int16List> get pcm => _pcm.stream;

  Future<SpeechResult> get done => _done.future;

  /// The spans cut so far.
  List<String> get spans => List.unmodifiable(_spans);

  /// Adds the next piece of text.
  void append(String text) {
    if (_closed || _cancelled) throw StateError('utterance already closed');
    _text += text;
    _cut();
  }

  /// No more text: the rest becomes the last span.
  void close() {
    if (_closed || _cancelled) return;
    _closed = true;
    _cut();
    _pump();
  }

  /// Stops the current span and drops the rest (barge-in).
  void cancel() {
    if (_cancelled || _done.isCompleted) return;
    _cancelled = true;
    _queue.clear();
    _current?.cancel();
    if (_current == null) _finish();
  }

  final _queue = <String>[];

  void _cut() {
    while (true) {
      final n = spanEnd(_text.substring(_cursor), _language, _closed, _rule);
      if (n == 0) break;
      final piece = _text.substring(_cursor, _cursor + n);
      _cursor += n;
      if (piece.trim().isEmpty) continue;
      _spans.add(piece);
      _queue.add(piece);
    }
    _pump();
  }

  void _pump() {
    if (_current != null || _cancelled) return;
    if (_queue.isEmpty) {
      if (_closed) _finish();
      return;
    }
    final piece = _queue.removeAt(0);
    final speech = _tts.speak(
      piece,
      voice: _voice,
      language: _language,
      sampling: _sampling,
    );
    _current = speech;
    speech.pcm.listen(
      (samples) {
        _firstAudio ??= DateTime.now().difference(_started);
        _samples += samples.length;
        _pcm.add(samples);
      },
      onError: (Object e) {
        if (!_done.isCompleted) _done.completeError(e);
        _pcm.addError(e);
      },
    );
    speech.done.then(
      (_) {
        _current = null;
        if (_cancelled) {
          _finish();
        } else {
          _pump();
        }
      },
      onError: (_) {
        _current = null;
        _cancelled = true;
        _finish();
      },
    );
  }

  void _finish() {
    if (_done.isCompleted) return;
    _pcm.close();
    _done.complete(
      SpeechResult(
        audio: Duration(microseconds: _samples * 1000000 ~/ 24000),
        firstAudio: _firstAudio,
        elapsed: DateTime.now().difference(_started),
        cancelled: _cancelled,
      ),
    );
  }
}

/// Where the next span ends in [text], or 0 when it is not complete yet. The rule measured for calls.
int spanEnd(String text, String? language, bool closed, SpanRule rule) {
  final spaced = !_isUnspaced(language, text);
  final minimum = spaced
      ? rule.minimumCharactersSpaced
      : rule.minimumCharacters;
  for (final m in RegExp(r'[、。！？!?.,;:]\s*').allMatches(text)) {
    if (m.end >= minimum) return m.end;
  }
  if (spaced) {
    final spaces = RegExp(r'\s+').allMatches(text).toList();
    if (spaces.length >= rule.maximumWordsSpaced)
      return spaces[rule.maximumWordsSpaced - 1].end;
  } else if (text.length >= rule.maximumCharacters) {
    return rule.maximumCharacters;
  }
  return closed ? text.length : 0;
}

bool _isUnspaced(String? language, String text) {
  final tag = language?.toLowerCase().split(RegExp('[-_]')).first;
  if (tag != null)
    return tag == 'ja' || tag == 'zh' || tag == 'japanese' || tag == 'chinese';
  return RegExp(r'[぀-ヿ一-鿿]').hasMatch(text);
}

/// The qwen3-tts language name for a BCP 47 tag, or null (auto).
String? qwenLanguage(String? language) {
  if (language == null) return null;
  final tag = language.toLowerCase().split(RegExp('[-_]')).first;
  const names = {
    'ja': 'japanese',
    'en': 'english',
    'zh': 'chinese',
    'ko': 'korean',
    'de': 'german',
    'fr': 'french',
    'ru': 'russian',
    'pt': 'portuguese',
    'es': 'spanish',
    'it': 'italian',
  };
  if (tag == 'auto') return null;
  return names[tag] ?? (names.containsValue(tag) ? tag : null);
}

// ── blocking native calls, run on a helper isolate ──────────────────────────

String? _bestGpu() {
  return using((arena) {
    final buf = arena<Uint8>(64).cast<Utf8>();
    return vctBestGpu(buf, 64) == 0 ? null : buf.toDartString();
  });
}

(int, String) _open(String talker, String codec, String device, int maxBatch) {
  return using((arena) {
    final engine = vctOpen(
      talker.toNativeUtf8(allocator: arena),
      codec.toNativeUtf8(allocator: arena),
      device.toNativeUtf8(allocator: arena),
      maxBatch,
    );
    return (
      engine.address,
      engine == nullptr ? vctLastError().toDartString() : '',
    );
  });
}

class _Extracted {
  _Extracted({
    this.speakerEmbedding,
    this.codes,
    this.codebooks = 0,
    this.error,
  });
  final Float32List? speakerEmbedding;
  final Int32List? codes;
  final int codebooks;
  final String? error;
}

_Extracted _extract(int engine, Float32List pcm) {
  return using((arena) {
    final input = arena<Float>(pcm.length);
    input.asTypedList(pcm.length).setAll(0, pcm);
    final spk = arena<Pointer<Float>>();
    final spkDim = arena<Int32>();
    final codes = arena<Pointer<Int32>>();
    final frames = arena<Int32>();
    final codebooks = arena<Int32>();
    final rc = vctExtractVoice(
      Pointer.fromAddress(engine),
      input,
      pcm.length,
      spk,
      spkDim,
      codes,
      frames,
      codebooks,
    );
    if (rc != 0) return _Extracted(error: vctLastError().toDartString());
    final out = _Extracted(
      speakerEmbedding: Float32List.fromList(
        spk.value.asTypedList(spkDim.value),
      ),
      codes: Int32List.fromList(
        codes.value.asTypedList(frames.value * codebooks.value),
      ),
      codebooks: codebooks.value,
    );
    vctFree(spk.value.cast());
    vctFree(codes.value.cast());
    return out;
  });
}
