# Rebuild when the package's source directory changes

Done when: an app that already built `voice_clone_tts` from one place (a path dependency, or one version in the pub
cache) builds again without a manual clean after it switches to another (pub.dev, or a newer version), on macOS and
Windows.

## The problem

The hook builds qwentts.cpp in a CMake build directory named only by OS, architecture and generator
(`cmake-macos-arm64-default` under the app's `outputDirectoryShared`; on Windows `vct-<hash of that directory>-…`
under TEMP). The package's own location is not part of the name. CMake remembers the source directory in that build
directory's cache and refuses another one, so the configure step fails:

```text
CMake Error: The source ".../.pub-cache/hosted/pub.dev/voice_clone_tts-0.1.0/third_party/qwentts.cpp/CMakeLists.txt"
does not match the source ".../voice_clone_tts/third_party/qwentts.cpp/CMakeLists.txt" used to generate cache.
```

Seen on 2026-11-17 (MacBook Pro M1 Max) in Spirits Garden's app, when its pubspec moved from
`path: ../../../../voice_clone_tts` to `voice_clone_tts: ^0.1.0` with the old build directory still in
`.dart_tool/hooks_runner/shared/voice_clone_tts/build/`. Every `flutter test` and build of the app failed.

The same will happen to every app on the first version upgrade: the pub cache path carries the version
(`voice_clone_tts-0.1.0` → `voice_clone_tts-0.1.1`).

## Next

1. Put the source directory into the build directory's name (a short hash of `input.packageRoot`, as Windows already
   hashes the output directory), or read `CMAKE_HOME_DIRECTORY` from the existing `CMakeCache.txt` and start the
   directory over when it differs. The first keeps old directories around; the second rebuilds in place.
2. Reproduce with a path dependency, then switch to the pub.dev version (and to a local copy at another path), on
   macOS and Windows.
3. Ship in the next release and note it in `CHANGELOG.md`. Until then, deleting the app's
   `.dart_tool/hooks_runner/shared/voice_clone_tts/build/` (or `flutter clean`) works around it.
