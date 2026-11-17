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

## Open points

- Whether a Windows PC without an NVIDIA GPU gets `support()` saying it is unavailable (no such PC at hand; see `first-version.md`).
- Flutter (3.47.2) tries to delete the source of a bundled file when a hook bundles fewer files (`first-version.md`, handover). Users may hit it after an upgrade that bundles fewer files; mention `flutter clean` in the README or report it upstream first.
