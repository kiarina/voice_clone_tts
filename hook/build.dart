// Builds the native library with CMake: qwentts.cpp's own project plus src/vct.cpp (src/vct.cmake), ggml linked
// statically. macOS: Metal (shaders embedded). Windows: CUDA when the CUDA Toolkit is installed, otherwise CPU only, and
// the CUDA runtime DLLs it needs are bundled next to it.
//
// Environment (optional, for the developer building the app):
//   VCT_CUDA_ARCHITECTURES  CMAKE_CUDA_ARCHITECTURES for Windows (default: qwentts.cpp's list; e.g. "86-real" builds faster)
//   VCT_CMAKE               path to cmake (default: cmake on PATH)

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _assetName = 'src/native.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final os = code.targetOS;
    if (os != OS.macOS && os != OS.windows)
      return; // other platforms: the Dart side reports "unsupported"

    final root = input.packageRoot;
    final source = root.resolve('third_party/qwentts.cpp/');
    final vct = root.resolve('src/');
    final arch = code.targetArchitecture.name;
    final buildDir = Directory.fromUri(
      input.outputDirectoryShared.resolve('cmake-${os.name}-$arch/'),
    );
    await buildDir.create(recursive: true);
    final cmake = Platform.environment['VCT_CMAKE'] ?? 'cmake';

    final configure = <String>[
      '-S',
      source.toFilePath(),
      '-B',
      buildDir.path,
      '-DCMAKE_BUILD_TYPE=Release',
      '-DBUILD_SHARED_LIBS=OFF',
      '-DCMAKE_PROJECT_qwentts-ggml_INCLUDE=${vct.resolve('vct.cmake').toFilePath()}',
      '-DVCT_SOURCE_DIR=${vct.toFilePath()}',
      '-DGGML_NATIVE=OFF',
    ];
    final cuda = os == OS.windows ? _cudaRoot() : null;
    if (os == OS.macOS) {
      configure.addAll([
        '-DGGML_METAL=ON',
        '-DGGML_METAL_EMBED_LIBRARY=ON',
        '-DCMAKE_OSX_ARCHITECTURES=${arch == 'arm64' ? 'arm64' : 'x86_64'}',
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=${code.macOS.targetVersion}',
      ]);
    } else {
      configure.addAll(['-G', 'Visual Studio 17 2022', '-A', 'x64']);
      if (cuda != null) {
        configure.add('-DGGML_CUDA=ON');
        final archs = Platform.environment['VCT_CUDA_ARCHITECTURES'];
        if (archs != null) configure.add('-DCMAKE_CUDA_ARCHITECTURES=$archs');
      }
    }
    await _run(cmake, configure);
    await _run(cmake, [
      '--build',
      buildDir.path,
      '--config',
      'Release',
      '--target',
      'voice_clone_tts',
      '--parallel',
    ]);

    final library = os == OS.macOS
        ? File('${buildDir.path}/libvoice_clone_tts.dylib')
        : File('${buildDir.path}/Release/voice_clone_tts.dll');
    if (!library.existsSync())
      throw StateError('CMake did not produce ${library.path}');
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
    if (cuda != null) {
      // ggml-cuda links the CUDA runtime and cuBLAS dynamically: bundle the DLLs it loads.
      for (final dll in _cudaRuntimeDlls(cuda)) {
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: 'src/cuda/${dll.uri.pathSegments.last}',
            linkMode: DynamicLoadingBundled(),
            file: dll.uri,
          ),
        );
      }
    }
    output.dependencies.addAll([
      vct.resolve('vct.cpp'),
      vct.resolve('vct.h'),
      vct.resolve('vct.cmake'),
    ]);
  });
}

String? _cudaRoot() {
  final env = Platform.environment['CUDA_PATH'];
  if (env != null && Directory(env).existsSync()) return env;
  final base = Directory(r'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA');
  if (!base.existsSync()) return null;
  final versions = base.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return versions.isEmpty ? null : versions.last.path;
}

Iterable<File> _cudaRuntimeDlls(String cudaRoot) sync* {
  for (final dir in [
    Directory('$cudaRoot\\bin\\x64'),
    Directory('$cudaRoot\\bin'),
  ]) {
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last.toLowerCase();
      if (name.startsWith('cudart64_') ||
          name.startsWith('cublas64_') ||
          name.startsWith('cublaslt64_'))
        yield f;
    }
  }
}

Future<void> _run(String exe, List<String> args) async {
  final result = await Process.run(exe, args, runInShell: Platform.isWindows);
  if (result.exitCode != 0) {
    throw ProcessException(
      exe,
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}
