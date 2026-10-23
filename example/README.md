# voice_clone_tts example

Speaks a sentence in the voice of a reference recording (macOS with Apple silicon, Windows with an NVIDIA GPU).

```sh
flutter run -d macos   # or -d windows
```

Give the path to a WAV (16-bit PCM; a few seconds to 20 s of clear speech, from someone who agreed to have their
voice cloned), what it says, and the text to speak. The first start downloads the model (about 4.5 GB). The result is
written to `voice_clone_tts_example.wav` in the temporary folder and played with the system's player.

The example turns the macOS App Sandbox off so it can read any path and run `afplay`. A sandboxed app needs the
`com.apple.security.network.client` entitlement for the download, and reads the reference through a file the user
picks.

On Windows, building needs Visual Studio 2022 (C++) and the CUDA Toolkit. To build only for your GPU, add to the app's
`pubspec.yaml`:

```yaml
hooks:
  user_defines:
    voice_clone_tts:
      cuda_architectures: "86-real"   # RTX 30 series; 89-real for RTX 40, 120a-real for RTX 50
```
