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

- [ ] Move the package to the publisher `kiarina.dev` (the owner does it on pub.dev; it is still under the uploader).
- [ ] Spirits Garden: switch `projects/spirits/app/pubspec.yaml` from `path: ../../../../voice_clone_tts` to
  `voice_clone_tts: ^0.1.0`, keep its `cuda_architectures` user define, `flutter clean` on Windows (the app once bundled
  cudart), build on macOS and Windows, and confirm the cloned voice speaks. Spirits Garden owns that change.

## Open points

- Whether a Windows PC without an NVIDIA GPU gets `support()` saying it is unavailable (no such PC at hand; see `first-version.md`).
- Flutter (3.47.2) tries to delete the source of a bundled file when a hook bundles fewer files (`first-version.md`, handover). Users may hit it after an upgrade that bundles fewer files; mention `flutter clean` in the README or report it upstream first.
