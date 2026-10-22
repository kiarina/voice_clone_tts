// Builds the native library with CMake: qwentts.cpp's own project plus src/vct.cpp (src/vct.cmake), ggml linked
// statically. macOS: Metal (shaders embedded). Windows: CUDA when the CUDA Toolkit is installed, otherwise CPU only, and
// the CUDA runtime DLLs it needs are bundled next to it.
//
// Hooks see only a few environment variables (PATH, PROGRAMDATA, ...), so the settings come from the app's pubspec:
//   hooks:
//     user_defines:
//       voice_clone_tts:
//         cuda_architectures: "86-real"   # CMAKE_CUDA_ARCHITECTURES (default: qwentts.cpp's list, slow to build)
//         cmake: C:\path\to\cmake.exe   # default: cmake on PATH, else the one bundled with Visual Studio (vswhere)

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
    final cmake = input.userDefines['cmake'] as String? ?? await _findCmake();

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
        final archs = input.userDefines['cuda_architectures'] as String?;
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

/// cmake on PATH, else the one bundled with Visual Studio (found with vswhere).
Future<String> _findCmake() async {
  final probe = await Process.run(Platform.isWindows ? 'where' : 'which', [
    'cmake',
  ], runInShell: Platform.isWindows);
  if (probe.exitCode == 0) return 'cmake';
  if (Platform.isWindows) {
    final vswhere = File(
      r'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe',
    );
    if (vswhere.existsSync()) {
      final r = await Process.run(vswhere.path, [
        '-latest',
        '-products',
        '*',
        '-property',
        'installationPath',
      ]);
      final root = (r.stdout as String).trim();
      final cmake = File(
        '$root\\Common7\\IDE\\CommonExtensions\\Microsoft\\CMake\\CMake\\bin\\cmake.exe',
      );
      if (root.isNotEmpty && cmake.existsSync()) return cmake.path;
    }
}

Future<void> _run(String exe, List<String> args) async {
  final result = await Process.run(exe, args); // no shell: paths with spaces (Program Files) stay one argument
  if (result.exitCode != 0) {
    throw ProcessException(
      exe,
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}
