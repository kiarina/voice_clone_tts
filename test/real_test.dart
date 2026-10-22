// ignore_for_file: avoid_print
// Runs the real engine on this machine. Skipped unless VCT_REAL is set:
//   VCT_REAL=1 VCT_CACHE=<dir with the weights> VCT_REFERENCE=<24 kHz 16-bit mono wav> flutter test test/real_test.dart
// The reference used in the labs is speaker 1 of the shared asset conversation_2speaker_14s_16k.mp3 (README).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_clone_tts/voice_clone_tts.dart';

const transcript = 'もしもし、もう駅に着いた？こっちはまだ電車。あと5分くらいかな。助かる。今日は結構寒いね。';
const texts = [
  'こんにちは。今日はいい天気ですね。少し散歩してから、駅前のカフェでコーヒーを飲みませんか？',
  'ちょっと待って。チケットはもう買ってあるから、ゆっくり行こうよ。',
  '明日の朝、七時三十分に、東京駅の八重洲口で待ち合わせしましょう。',
];

void main() {
  final env = Platform.environment;
  final skip = env['VCT_REAL'] == null
      ? 'set VCT_REAL=1 to run the real engine'
      : null;

  test(
    'speak, utter and cancel on the real engine',
    () async {
      final cache = Directory(env['VCT_CACHE']!);
      final support = await VoiceCloneTts.support(cacheDirectory: cache);
      print(
        'support: ${support.supported} ${support.device} ${support.modelState} ${support.reason}',
      );
      expect(support.supported, isTrue);
      final opened = Stopwatch()..start();
      final tts = await VoiceCloneTts.open(
        cacheDirectory: cache,
        onProgress: (p) => print(p),
      );
      print('open ${opened.elapsedMilliseconds} ms on ${tts.device}');

      final wav = File(env['VCT_REFERENCE']!).readAsBytesSync();
      final pcm = Int16List.fromList(Int16List.sublistView(wav, 44));
      final rate = ByteData.sublistView(wav).getUint32(24, Endian.little);
      final made = Stopwatch()..start();
      final voice = await tts.createVoice(
        reference: Pcm16(pcm, sampleRate: rate),
        transcript: transcript,
      );
      print(
        'voice ${voice.frames} frames x ${voice.codebooks}, ${voice.speakerEmbedding.length}-dim, ${made.elapsedMilliseconds} ms',
      );
      expect(Voice.fromBytes(voice.toBytes()).codes, voice.codes);

      final out = Directory(env['VCT_OUT'] ?? Directory.systemTemp.path);
      for (var i = 0; i < texts.length; i++) {
        final speech = tts.speak(
          texts[i],
          voice: voice,
          language: 'ja',
          sampling: const Sampling(seed: 0),
        );
        final chunks = <Int16List>[];
        await for (final c in speech.pcm) {
          chunks.add(c);
        }
        final r = await speech.done;
        final rtf = r.elapsed.inMicroseconds / r.audio.inMicroseconds;
        print(
          'speak $i: audio ${r.audio.inMilliseconds} ms, first ${r.firstAudio!.inMilliseconds} ms, RTF ${rtf.toStringAsFixed(3)}',
        );
        _writeWav(File('${out.path}/speak-$i.wav'), chunks);
        expect(r.cancelled, isFalse);
        expect(r.audio.inMilliseconds, greaterThan(1000));
      }

      // utter: the Japanese text arriving one character every 130 ms, as in the call lab.
      final u = tts.utter(
        voice: voice,
        language: 'ja',
        sampling: const Sampling(seed: 0),
      );
      final collected = u.pcm.toList(); // listen before the first span arrives
      final started = Stopwatch()..start();
      for (final ch in texts[0].split('')) {
        u.append(ch);
        await Future<void>.delayed(const Duration(milliseconds: 130));
      }
      u.close();
      final r = await u.done;
      final chunks = await collected;
      print(
        'utter: spans ${u.spans}, audio ${r.audio.inMilliseconds} ms, first ${r.firstAudio!.inMilliseconds} ms, '
        'total ${started.elapsedMilliseconds} ms',
      );
      _writeWav(File('${out.path}/utter.wav'), chunks);
      expect(u.spans.join(), texts[0]);

      // cancel: stop after about 1 s of audio, then the next reply's first audio.
      final long = tts.speak(texts[0] + texts[1], voice: voice, language: 'ja');
      var got = 0;
      final stopwatch = Stopwatch();
      await for (final c in long.pcm) {
        got += c.length;
        if (got >= 24000 && !stopwatch.isRunning) {
          stopwatch.start();
          long.cancel();
        }
      }
      final cancelled = await long.done;
      final stopped = stopwatch.elapsedMilliseconds;
      final next = tts.speak('はい、どうしましたか？', voice: voice, language: 'ja');
      await next.pcm.first;
      print(
        'cancel: stopped ${stopped} ms after cancel(), next first audio ${stopwatch.elapsedMilliseconds} ms after cancel()',
      );
      expect(cancelled.cancelled, isTrue);
      await next.done;
      print('closing');
      await tts.close();
      print('closed');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

void _writeWav(File file, List<Int16List> chunks) {
  final n = chunks.fold<int>(0, (a, c) => a + c.length);
  final header = ByteData(44)
    ..setUint32(0, 0x46464952, Endian.little)
    ..setUint32(4, 36 + n * 2, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little)
    ..setUint32(12, 0x20746d66, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 24000, Endian.little)
    ..setUint32(28, 48000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x61746164, Endian.little)
    ..setUint32(40, n * 2, Endian.little);
  final b = BytesBuilder()..add(header.buffer.asUint8List());
  for (final c in chunks) {
    b.add(c.buffer.asUint8List(c.offsetInBytes, c.lengthInBytes));
  }
  file.writeAsBytesSync(b.toBytes());
}
