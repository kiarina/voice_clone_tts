import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:voice_clone_tts/voice_clone_tts.dart';

/// Speaks a sentence in the voice of a reference recording.
///
/// Give a WAV (16-bit PCM, mono or stereo, any rate; a few seconds to 20 s of clear speech) and what it says. The
/// first start downloads the model (about 4.5 GB). The voice is written to a WAV in the temporary folder and played
/// with the system's player (`afplay` on macOS, PowerShell's `SoundPlayer` on Windows).
///
/// Only clone a voice whose owner agreed to it.
void main() => runApp(
  MaterialApp(
    title: 'voice_clone_tts',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: const Demo(),
  ),
);

class Demo extends StatefulWidget {
  const Demo({super.key});

  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  final _reference = TextEditingController();
  final _transcript = TextEditingController();
  final _text = TextEditingController(text: 'こんにちは。今日はいい天気ですね。');
  final _language = TextEditingController(text: 'ja');
  final _log = <String>[];
  VoiceCloneSupport? _support;
  double? _download;
  VoiceCloneTts? _tts;
  Voice? _voice;
  String? _voiceOf;
  Speech? _speech;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void dispose() {
    _speech?.cancel();
    unawaited(_tts?.close());
    super.dispose();
  }

  void _say(String line) {
    if (mounted) setState(() => _log.insert(0, line));
  }

  Future<void> _check() async {
    final support = await VoiceCloneTts.support();
    setState(() => _support = support);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _say('error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<VoiceCloneTts> _engine() async {
    if (_tts case final tts?) return tts;
    final clock = Stopwatch()..start();
    final tts = await VoiceCloneTts.open(
      onProgress: (p) {
        if (mounted) {
          setState(
            () => _download = p.phase == PreparePhase.download ? p.fraction : null,
          );
        }
      },
    );
    setState(() => _download = null);
    _say('model ready on ${tts.device} in ${clock.elapsed.inSeconds} s');
    return _tts = tts;
  }

  /// The voice of the reference and transcript in the fields, made again when they change.
  Future<Voice> _voiceNow(VoiceCloneTts tts) async {
    final key = '${_reference.text}\n${_transcript.text}';
    if (_voice case final voice? when _voiceOf == key) return voice;
    final clock = Stopwatch()..start();
    final voice = await tts.createVoice(
      reference: readWav(File(_reference.text.trim()).readAsBytesSync()),
      transcript: _transcript.text.trim(),
    );
    _say('voice made in ${clock.elapsed.inMilliseconds} ms');
    _voiceOf = key;
    return _voice = voice;
  }

  Future<void> _speak() async {
    final tts = await _engine();
    final voice = await _voiceNow(tts);
    final speech = _speech = tts.speak(
      _text.text,
      voice: voice,
      language: _language.text.trim().isEmpty ? null : _language.text.trim(),
    );
    final chunks = <Int16List>[];
    await for (final c in speech.pcm) {
      chunks.add(c);
    }
    final r = await speech.done;
    _speech = null;
    if (r.cancelled) return _say('stopped');
    _say(
      'audio ${r.audio.inMilliseconds} ms, first in ${r.firstAudio?.inMilliseconds} ms, '
      'made in ${r.elapsed.inMilliseconds} ms',
    );
    final out = File('${Directory.systemTemp.path}/voice_clone_tts_example.wav');
    out.writeAsBytesSync(writeWav(chunks, 24000));
    _say('wrote ${out.path}');
    await _play(out);
  }

  Future<void> _play(File wav) async {
    if (Platform.isMacOS) {
      await Process.run('afplay', [wav.path]);
    } else if (Platform.isWindows) {
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "(New-Object Media.SoundPlayer '${wav.path}').PlaySync()",
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final support = _support;
    final ready = support?.supported == true;
    final canSpeak =
        ready &&
        !_busy &&
        _reference.text.trim().isNotEmpty &&
        _transcript.text.trim().isNotEmpty &&
        _text.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('voice_clone_tts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(switch (support) {
            null => 'Checking this device…',
            VoiceCloneSupport(supported: false) => 'Not supported here: ${support.reason}',
            _ =>
              'Runs on ${support.device}. Model: '
                  '${support.modelState == ModelState.downloaded ? 'downloaded' : 'downloaded on first use (about 4.5 GB)'}.',
          }),
          if (_download case final d?) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: d),
            Text('Downloading the model: ${(d * 100).toStringAsFixed(1)}%'),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _reference,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Reference recording (path to a 16-bit PCM WAV)',
              helperText: 'A few seconds to 20 s of clear speech, from someone who agreed to it.',
            ),
          ),
          TextField(
            controller: _transcript,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'What the recording says'),
          ),
          TextField(
            controller: _text,
            onChanged: (_) => setState(() {}),
            maxLines: null,
            decoration: const InputDecoration(labelText: 'Text to speak'),
          ),
          TextField(
            controller: _language,
            decoration: const InputDecoration(
              labelText: 'Language (BCP 47, e.g. ja, en; empty: detect)',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                onPressed: canSpeak ? () => _run(_speak) : null,
                child: const Text('Speak'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _speech == null ? null : () => _speech?.cancel(),
                child: const Text('Stop'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final line in _log) Text(line),
        ],
      ),
    );
  }
}

/// A WAV's 16-bit PCM, its channels averaged to mono.
Pcm16 readWav(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes, 0, 4) != 'RIFF' ||
      String.fromCharCodes(bytes, 8, 12) != 'WAVE') {
    throw const FormatException('not a WAV file');
  }
  int? channels, rate, bits;
  for (var i = 12; i + 8 <= bytes.length;) {
    final id = String.fromCharCodes(bytes, i, i + 4);
    final size = data.getUint32(i + 4, Endian.little);
    final body = i + 8;
    if (id == 'fmt ') {
      if (data.getUint16(body, Endian.little) != 1) {
        throw const FormatException('the WAV is not PCM');
      }
      channels = data.getUint16(body + 2, Endian.little);
      rate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (channels == null || rate == null || bits != 16) {
        throw const FormatException('the WAV is not 16-bit PCM');
      }
      final end = (body + size).clamp(body, bytes.length);
      final frames = (end - body) ~/ (2 * channels);
      final out = Int16List(frames);
      for (var f = 0; f < frames; f++) {
        var sum = 0;
        for (var c = 0; c < channels; c++) {
          sum += data.getInt16(body + (f * channels + c) * 2, Endian.little);
        }
        out[f] = sum ~/ channels;
      }
      return Pcm16(out, sampleRate: rate);
    }
    i = body + size + (size & 1);
  }
  throw const FormatException('the WAV has no data');
}

/// [chunks] of mono 16-bit PCM at [rate] as a WAV file.
Uint8List writeWav(List<Int16List> chunks, int rate) {
  final samples = chunks.fold<int>(0, (a, c) => a + c.length);
  final out = ByteData(44 + samples * 2);
  void text(int at, String s) {
    for (var i = 0; i < 4; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  out.setUint32(4, 36 + samples * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  out
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  text(36, 'data');
  out.setUint32(40, samples * 2, Endian.little);
  var at = 44;
  for (final c in chunks) {
    for (final s in c) {
      out.setInt16(at, s, Endian.little);
      at += 2;
    }
  }
  return out.buffer.asUint8List();
}
