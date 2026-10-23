// ignore_for_file: avoid_print
// How many voices this machine speaks at once in real time. Skipped unless VCT_REAL is set:
//   VCT_REAL=1 VCT_CACHE=<dir with the weights> VCT_REFERENCE=<16-bit mono wav> [VCT_STREAMS=1,2,4] \
//     flutter test test/concurrency_test.dart
// For each count, the engine opens with that maxConcurrent and speaks that many sentences together. A stream keeps up
// when, played from its first audio plus a 1 s hold (as a call does), no chunk arrives after it is needed.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_clone_tts/voice_clone_tts.dart';

const transcript = 'もしもし、もう駅に着いた？こっちはまだ電車。あと5分くらいかな。助かる。今日は結構寒いね。';
const text = 'こんにちは。今日はいい天気ですね。少し散歩してから、駅前のカフェでコーヒーを飲みませんか？';
const hold = Duration(seconds: 1);

void main() {
  final env = Platform.environment;
  final skip = env['VCT_REAL'] == null
      ? 'set VCT_REAL=1 to run the real engine'
      : null;

  test(
    'streams at once',
    () async {
      final cache = Directory(env['VCT_CACHE']!);
      final wav = File(env['VCT_REFERENCE']!).readAsBytesSync();
      final pcm = Int16List.fromList(Int16List.sublistView(wav, 44));
      final rate = ByteData.sublistView(wav).getUint32(24, Endian.little);
      final counts = (env['VCT_STREAMS'] ?? '1,2,4')
          .split(',')
          .map(int.parse);
      for (final n in counts) {
        final tts = await VoiceCloneTts.open(
          cacheDirectory: cache,
          maxConcurrent: n,
        );
        final voice = await tts.createVoice(
          reference: Pcm16(pcm, sampleRate: rate),
          transcript: transcript,
        );
        // Warm the graphs at this batch size.
        await tts.speak('あ。', voice: voice, language: 'ja').done;

        Future<String> one(int i) async {
          final clock = Stopwatch()..start();
          final speech = tts.speak(
            text,
            voice: voice,
            language: 'ja',
            sampling: Sampling(seed: i),
          );
          Duration? first;
          var audio = Duration.zero;
          var late = Duration.zero;
          await for (final chunk in speech.pcm) {
            final now = clock.elapsed;
            first ??= now;
            // When this chunk starts to play: first audio + hold + what came before it.
            final due = first + hold + audio;
            if (now > due && now - due > late) late = now - due;
            audio += Duration(microseconds: chunk.length * 1000000 ~/ 24000);
          }
          final r = await speech.done;
          final rtf = r.elapsed.inMicroseconds / r.audio.inMicroseconds;
          return 'first ${first!.inMilliseconds} ms, audio ${audio.inMilliseconds} ms, '
              'RTF ${rtf.toStringAsFixed(2)}, late ${late.inMilliseconds} ms';
        }

        final results = await Future.wait([for (var i = 0; i < n; i++) one(i)]);
        print('$n at once on ${tts.device}:');
        for (final r in results) {
          print('  $r');
        }
        await tts.close();
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
