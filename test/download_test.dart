// ignore_for_file: avoid_print
// Downloads the weights from Hugging Face into an empty cache: a resumed partial file, a corrupt partial file, then
// the whole model (about 4.5 GB). Skipped unless VCT_DOWNLOAD is set:
//   VCT_DOWNLOAD=1 VCT_CACHE=<empty dir> flutter test test/download_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_clone_tts/src/weights.dart';
import 'package:voice_clone_tts/voice_clone_tts.dart';

const model = VoiceCloneModel.base17bBf16;

void main() {
  final env = Platform.environment;
  final skip = env['VCT_DOWNLOAD'] == null
      ? 'set VCT_DOWNLOAD=1 to download the weights'
      : null;

  test(
    'download, resume and verify',
    () async {
      final cache = Directory(env['VCT_CACHE']!)..createSync(recursive: true);
      final store = WeightStore(cache);
      final codec = weightFiles(model)[1];
      store.directory.createSync(recursive: true);
      final part = File('${store.file(codec).path}.part');

      // A corrupt partial file: the rest is fetched, the whole fails its SHA-256 and is removed.
      part.writeAsBytesSync(List.filled(1 << 20, 0x55));
      Object? failed;
      try {
        await store.ensure(model, null);
      } catch (e) {
        failed = e;
      }
      print('corrupt partial: $failed');
      expect(failed, isA<VoiceCloneException>());
      expect(part.existsSync(), isFalse);
      expect(store.has(model), isFalse);

      // A true partial file (the first 64 MB, fetched with a range): the rest is appended and it verifies.
      final client = HttpClient();
      final request = await client.getUrl(codec.url);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${(64 << 20) - 1}');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.partialContent);
      await response.pipe(part.openWrite());
      client.close();
      print('partial: ${part.lengthSync()} bytes');

      final clock = Stopwatch()..start();
      var last = -1;
      await store.ensure(model, (f) {
        final p = (f * 10).floor();
        if (p != last) {
          last = p;
          print('${(f * 100).toStringAsFixed(0)}% at ${clock.elapsed.inSeconds} s');
        }
      });
      print('all weights in ${clock.elapsed.inSeconds} s');
      expect(store.has(model), isTrue);
      final support = await VoiceCloneTts.support(cacheDirectory: cache);
      expect(support.modelState, ModelState.downloaded);
    },
    skip: skip,
    timeout: const Timeout(Duration(hours: 2)),
  );
}
