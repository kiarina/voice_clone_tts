# Publish 0.1.0 to pub.dev

Done when: `voice_clone_tts` 0.1.0 is on pub.dev, and Spirits Garden depends on it by version instead of `path: ../../../../voice_clone_tts`.

The owner wants to publish it (2026-11-17). The earlier note that the owner had decided "not yet" (2026-10-23) has no source the owner recognizes, and is withdrawn.

## Steps

1. Show the owner the name, version and contents before publishing (`dart pub publish --dry-run`: the file list and the size, compressed about 4 MB on 2026-10-23). Publish only after the owner approves.
2. Bring `CHANGELOG.md`, `README.md` and `pubspec.yaml` (version, description, repository, topics) up to date with the current code.
3. Run `dart pub publish --dry-run` again and resolve its warnings. On 2026-10-23 the only one was a qwentts.cpp example/test record that `.gitignore` excludes and the build does not need.
   `.pubignore` replaces `.gitignore` for publishing: keep the two in step.
4. Publish and check the package page (score, platforms, that the build hook fetches nothing missing from the archive).
5. In Spirits Garden, switch the dependency to `voice_clone_tts: ^0.1.0`, build on macOS and Windows, and confirm the cloned voice still speaks. That change belongs to Spirits Garden's own tasks.

## Progress

- 2026-11-17 (MacBook Pro M1 Max, G-GEAR-2022): step 2 done (`ecdce79`): README installs `^0.1.0` and tells Windows
  users to `flutter clean` if an upgrade fails with "failed to delete file"; pubspec has topics. CHANGELOG already
  matches the code (including `open(cancel:)`). `flutter analyze` is clean.
- Step 3: the dry-run (4 MB compressed, 2,496 files) leaves one warning that cannot be removed without changing the
  qwentts.cpp submodule: 52 checked-in files ignored by a `.gitignore` (qwentts.cpp's `tests/*.log`, `examples/freeman.wav`,
  ggml's `examples/mnist/web/`). They are left out of the archive, which is what we want; publish will ask to confirm it.
- The archive alone builds and speaks: the files the dry-run lists were copied to a fresh folder (no `.dart_tool`, no
  submodule git data) and `test/real_test.dart` was run from there. macOS (M1 Max, Metal): passed, RTF about 0.48,
  cancel 11 ms. Windows (RTX 3080 Ti, CUDA 13.4, `cuda_architectures: "86-real"` added only to the copy): passed in
  5 min including the build, RTF 0.17–0.24, first audio 24–29 ms, cancel 5 ms.
- Published 2026-11-17 after the owner approved the name, version, contents and the remaining warning
  (https://pub.dev/packages/voice_clone_tts, tag `v0.1.0`). pub.dev analysis: 160/160. It lists Android, iOS and Linux
  as platforms too, because the pubspec declares none; add `platforms: {macos:, windows:}` in the next version.

## Left

- [x] Moved to the publisher `kiarina.dev` (the owner, 2026-11-17; the API answers `kiarina.dev`).
- [ ] Spirits Garden (blocked on `tasks/cmake-build-dir-source-change.md`: every checkout that built from the path
  dependency fails at CMake configure after the switch, so the switch must wait for a fixed version). Tried on
  2026-11-17 with the change uncommitted in the shared checkout: macOS, `probes/voice_route.dart` from a separate
  worktree, first audio 94–110 ms, cancel 11–16 ms (as on 2026-10-24). Windows (G-GEAR), Release build passed and
  bundled `voice_clone_tts.dll` and the cuBLAS DLLs, the engine loaded on CUDA0 and made the voice, but the probe's
  3 s wait for the first audio ran out: the stg and prd apps already held 10.8 of the GPU's 12 GB, so it says nothing
  about the package. Debug builds on Windows fail in speaker_aec (AEC3), unrelated. The step: switch `projects/spirits/app/pubspec.yaml` from `path: ../../../../voice_clone_tts` to
  `voice_clone_tts: ^0.1.0`, keep its `cuda_architectures` user define, `flutter clean` on Windows (the app once bundled
  cudart), build on macOS and Windows, and confirm the cloned voice speaks. Spirits Garden owns that change.

## Open points

- Whether a Windows PC without an NVIDIA GPU gets `support()` saying it is unavailable (no such PC at hand; see `first-version.md`).
  The code catches a failed library load and returns `supported: false` with "native library unavailable" (`lib/src/engine.dart`).
- Flutter (3.47.2) tries to delete the source of a bundled file when a hook bundles fewer files (`first-version.md`, handover).
  The README tells users to `flutter clean`; the upstream report is tracked outside this repo.
