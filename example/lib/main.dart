import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:voice_clone_tts/voice_clone_tts.dart';

/// Speaks a sentence in the voice of a reference WAV (16-bit mono) and writes the result next to it.
/// Run with --dart-define=REFERENCE=<wav> --dart-define=TRANSCRIPT=<what it says>.
void main() => runApp(const MaterialApp(home: Demo()));

class Demo extends StatefulWidget {
  const Demo({super.key});

  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  final _log = <String>[];
  final _text = TextEditingController(text: 'こんにちは。今日はいい天気ですね。');
  VoiceCloneTts? _tts;
  Voice? _voice;

  void _say(String line) => setState(() => _log.add(line));

  Future<void> _open() async {
    final support = await VoiceCloneTts.support();
    _say('support: ${support.supported} ${support.device} ${support.modelState} ${support.reason ?? ''}');
    if (!support.supported) return;
    _tts = await VoiceCloneTts.open(onProgress: (p) => _say('$p'));
    const path = String.fromEnvironment('REFERENCE');
    const transcript = String.fromEnvironment('TRANSCRIPT');
    final wav = File(path).readAsBytesSync();
    final pcm = Int16List.sublistView(wav, 44); // canonical 44-byte header
    final rate = ByteData.sublistView(wav).getUint32(24, Endian.little);
    _voice = await _tts!.createVoice(reference: Pcm16(Int16List.fromList(pcm), sampleRate: rate), transcript: transcript);
    _say('voice: ${_voice!.frames} frames');
  }

  Future<void> _speak() async {
    final speech = _tts!.speak(_text.text, voice: _voice!, language: 'ja');
    final chunks = <Int16List>[];
    await for (final c in speech.pcm) {
      chunks.add(c);
    }
    final r = await speech.done;
    _say('audio ${r.audio.inMilliseconds} ms, first ${r.firstAudio?.inMilliseconds} ms, total ${r.elapsed.inMilliseconds} ms');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              ElevatedButton(onPressed: _open, child: const Text('Open')),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: () => _voice == null ? null : _speak(), child: const Text('Speak')),
            ]),
            TextField(controller: _text),
            Expanded(child: ListView(children: [for (final l in _log) Text(l)])),
          ]),
        ),
      );
}
