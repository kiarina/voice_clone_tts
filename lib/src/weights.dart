import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'types.dart';

/// One weight file: where it comes from and how to verify it.
class WeightFile {
  const WeightFile(this.name, this.bytes, this.sha256);

  final String name;
  final int bytes;
  final String sha256;

  Uri get url => Uri.parse(
    'https://huggingface.co/${VoiceCloneModel.repository}/resolve/${VoiceCloneModel.revision}/$name',
  );
}

List<WeightFile> weightFiles(VoiceCloneModel model) => [
  WeightFile(model.talkerFile, model.talkerBytes, model.talkerSha256),
  const WeightFile(
    VoiceCloneModel.codecFile,
    VoiceCloneModel.codecBytes,
    VoiceCloneModel.codecSha256,
  ),
];

/// The model directory: `<cache>/<revision>/`. A file counts as downloaded once it has been verified (the `.ok`
/// marker next to it), so a half-written file is never loaded.
class WeightStore {
  WeightStore(Directory cache)
    : directory = Directory('${cache.path}/${VoiceCloneModel.revision}');

  final Directory directory;

  File file(WeightFile w) => File('${directory.path}/${w.name}');
  File _marker(WeightFile w) => File('${directory.path}/${w.name}.ok');

  bool has(VoiceCloneModel model) =>
      weightFiles(model)
          .every((w) => _marker(w).existsSync() && file(w).existsSync());

  /// Downloads the missing files, verifying size and SHA-256. Resumes a partial `.part` file.
  Future<void> ensure(
    VoiceCloneModel model,
    void Function(double fraction)? onProgress,
  ) async {
    await directory.create(recursive: true);
    final files = weightFiles(model);
    final total = files.fold<int>(0, (a, w) => a + w.bytes);
    var done = 0;
    for (final w in files) {
      if (_marker(w).existsSync() && file(w).existsSync()) {
        done += w.bytes;
        onProgress?.call(done / total);
        continue;
      }
      final base = done;
      await _download(w, (got) => onProgress?.call((base + got) / total));
      done += w.bytes;
    }
  }

  Future<void> _download(WeightFile w, void Function(int got) progress) async {
    final part = File('${file(w).path}.part');
    final client = HttpClient();
    try {
      var have = part.existsSync() ? part.lengthSync() : 0;
      if (have > w.bytes) {
        part.deleteSync();
        have = 0;
      }
      if (have < w.bytes) {
        final request = await client.getUrl(w.url);
        if (have > 0)
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
        final response = await request.close();
        if (response.statusCode == HttpStatus.ok) {
          have = 0; // the server ignored the range
        } else if (response.statusCode != HttpStatus.partialContent) {
          throw VoiceCloneException(
            VoiceCloneErrorCode.modelMissing,
            'download of ${w.name} failed: HTTP ${response.statusCode}',
          );
        }
        final sink = part.openWrite(
          mode: have > 0 ? FileMode.append : FileMode.write,
        );
        var got = have;
        await for (final chunk in response) {
          sink.add(chunk);
          got += chunk.length;
          progress(got);
        }
        await sink.close();
      }
      if (part.lengthSync() != w.bytes) {
        throw VoiceCloneException(
          VoiceCloneErrorCode.modelMissing,
          '${w.name}: size ${part.lengthSync()} != ${w.bytes}',
        );
      }
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != w.sha256) {
        part.deleteSync();
        throw VoiceCloneException(
          VoiceCloneErrorCode.modelMissing,
          '${w.name}: SHA-256 mismatch',
        );
      }
      part.renameSync(file(w).path);
      _marker(w).writeAsStringSync(w.sha256);
    } finally {
      client.close(force: true);
    }
  }
}
