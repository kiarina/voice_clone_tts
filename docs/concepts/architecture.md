# 作りと決まり

参照の声（数秒の音声と、その文字起こし）をまねて文を話し、24 kHz の PCM を生成しながら流す、Flutter のパッケージ。
Spirits Garden の声（brain の `speak` と通話）を、Mac と Windows のどちらでも同じ声質で作るために作る。

## 形

```
Dart の API（voice_clone_tts）
  声を登録（参照の音声 + 文字起こし → 話者の埋め込みと参照の符号）
  文を渡す → PCM が少しずつ流れて出る／途中で止める
   └─ dart:ffi → qwentts.cpp の C の ABI（qwen.h）
        ├─ macOS:   ggml の Metal
        └─ Windows: ggml の CUDA（NVIDIA の GPU）
   ほかの OS・GPU の無い PC: 「使えない」と返す（アプリは OS の声などに戻す）
```

使う側は Spirits Garden の試作。まず GPU のある body がこの package を直接使い、次に TTS ノード（メッシュの参加者）として
GPU の無い body にも声を配る（Spirits Garden の `tasks/`）。kiapi と同じ HTTP の口（サーバー）は作らない（オーナー、2026-10-23。最終形のノードでは使わない回り道。Spirits 以外から HTTP で使う需要が出たら考える）。

- **モデル**: Qwen3-TTS 12Hz 1.7B Base、BF16（talker 3.88 GB ＋ codec 0.65 GB）。参照の符号と文字起こしで似せる（ICL）
- **エンジン**: qwentts.cpp（MIT、C++17、ggml）。1 フレーム（80 ms）ずつ復号して流せ、取り消しは 1 フレームごとに確かめる
- **文が少しずつ届く形（通話）**: `utter` が、受け取った文字を短い区間（日本語は 8 文字以上で句読点、無ければ 24 文字。英語は 14 文字以上で句読点、無ければ 6 語）に分け、
  区間ごとに 1 回生成して 1 つの発話としてつなぐ。qwentts.cpp には文を少しずつ足しながら生成する口が無いが、区間ごとの生成で今の通話と同じ体験になると確かめた
- **呼び出し側の責任**: 再生（最初の音から 1 秒待つなど）、エコー除去、声の持ち主の同意

## Dart の API（2026-10-23、オーナーと合意）

正典は `lib/src/types.dart`（型）と `lib/src/engine.dart`（`VoiceCloneTts`・`Speech`・`Utterance`）。

- `VoiceCloneTts.support()`: `supported`・`engine`・`device`（`MTL0`・`CUDA0`）・`modelState`・`reason` を別々に返す。落とさない・読み込まない
- `VoiceCloneTts.open()`: 無ければ重みを落とし（revision と SHA-256 を固定、`.part` から再開）、読み込み、暖機する（`PreparePhase` の download / load / warmup）
- `createVoice(reference: Pcm16, transcript:)` → `Voice`（話者の埋め込み・参照の符号・文字起こし）。`toBytes()`／`loadVoice()` で保存して登録し直さない。参照の音声は持たない
- `speak(text, voice:, language:, sampling:)` → `Speech`（`pcm`: `Stream<Int16List>`、24 kHz・mono。`done`、`cancel()`）
- `utter(voice:, language:, rule:)` → `Utterance`（`append`・`close`・`cancel`・`pcm`・`done`）。区切りの規則 `SpanRule` で区間に分け、区間ごとに `speak` して順につなぐ
- `VoiceCloneModel`: 既定は 1.7B BF16。1.7B Q8_0・0.6B Q8_0 も選べる
- `language` は BCP 47（`ja`・`en`）で受け、qwentts.cpp の名前（`japanese`）に変える。省けば自動

決めた 4 点（オーナー、2026-10-23）: PCM は `Int16List`・24 kHz（48 kHz への変換はアプリ）、通話用の `utter` をこの package に入れる、声は埋め込みと符号を `toBytes()` で保存する、重みは 1.7B BF16 を既定に Q8_0 と 0.6B も選べる。

## build

- Flutter の build hook（native assets、`hook/build.dart`）で、qwentts.cpp の CMake の project をそのまま構成し、`src/vct.cmake` を `CMAKE_PROJECT_qwentts-ggml_INCLUDE` で差し込んで
  `voice_clone_tts` の共有ライブラリ（`src/vct.cpp`＋qwen-core＋静的な ggml）を作る。Mac は Metal（シェーダーは埋め込み）、Windows は CUDA Toolkit があれば CUDA で、
  使う CUDA の実行時の DLL（cudart・cuBLAS）も一緒に bundle する。Dart は `@Native` でこのライブラリ（code asset `src/native.dart`）を呼ぶ
- qwentts.cpp は CMake の中で `CMAKE_SOURCE_DIR` を前提にしているので、`add_subdirectory` で取り込まず、その project に差し込む
- Windows は Visual Studio の開発者環境（vswhere で探した vcvars64）の中で Ninja を使う。Visual Studio の生成方式では CMake が CUDA のコンパイラを見つけられなかった。
  hook には PATH などわずかな環境変数しか渡らないので、CUDA の世代（`cuda_architectures`）と cmake の場所はアプリの pubspec の `hooks.user_defines.voice_clone_tts` で渡す。CMake に渡すパスは前向きの斜線にする（円記号はエスケープとして読まれる）
- Windows の CMake の作業フォルダは TEMP の下の短い名前（`vct-<出力先の hash>-cmake-…`、`build_root` で変えられる）に置く。nvcc は MAX_PATH（260 文字）を超えて書けず、アプリの `.dart_tool` の下の hook の出力先はそれだけで約 200 文字ある
- 入れ子の submodule（qwentts.cpp の中の ggml）が要る。clone は `--recurse-submodules`
- `src/vct.cpp` は qwentts.cpp の流しの callback（中のスレッドから呼ばれる）を受け、PCM を 16 bit にコピーして `NativeCallable.listener` に渡す。取り消しは要求ごとの atomic の旗を cancel の callback が見る

## なぜこの形か

- ONNX Runtime は、Mac では CPU でしか動かず（CoreML の EP は talker と code predictor を受け付けない）、1.7B は実時間の 3.6 倍以上かかった（labs `2026/10/23/qwen3-tts-onnx-runtime-compare`）
- qwentts.cpp は、1.7B・ICL のまま Mac（Apple M1 Max、Metal）で実時間の 0.40〜0.46 倍・最初の音 0.09〜0.12 秒、Windows（RTX 3080 Ti、CUDA）で 0.15〜0.20 倍・0.03 秒。
  MLX bf16（0.56 倍・0.58 秒）より速く、Mac と Windows で同じ実装・同じモデルになる（labs `2026/10/23/qwen3-tts-ggml-compare`）
- 通話の形（文字起こしが少しずつ届く → 短区間 → 区間ごとに生成 → 1 秒待って鳴らす）は、区間ごとに 1 回生成するだけで、1 秒待てば Mac・Windows とも途切れ 0
  （labs `2026/10/23/qwen3-tts-ggml-call-segments`）

## 気をつけること

- **ggml の二重**: 同じアプリが別の plugin で ggml（whisper.cpp など。例: pcm_asr の Windows）を build すると、CMake の target と DLL の名前（`ggml.dll`）がぶつかる。
  qwentts.cpp は独立した build（ExternalProject など）で 1 つの共有ライブラリに閉じ、ggml は静的にリンクして `qt_*` だけを出す（`QWEN_SHARED=ON`）
- **割り込みの速さ**: C の ABI の取り消し（1 フレームごとに確かめる）を直接使い、止まるまで Mac 10 ms・Windows 5 ms、次の返事の最初の音まで Mac 96 ms・Windows 32 ms
  （HTTP のサーバーで接続を切る形は Mac 0.7 秒・Windows 0.25 秒だった。サーバーが切断に気づくまで数フレーム余分に作るため）
- **声ごとの初回の準備**: qwentts.cpp は声の参照の符号で流しの復号器を温め、その状態を声ごとに覚える。初回は Mac で約 0.5 秒かかるので、`createVoice` と `primeVoice` で前もって済ませる
- 同時に話す本数は GPU のメモリで決まる。12 GB の RTX 3080 Ti で Q8_0 は 4 本まで実時間、8 本で崩れた。BF16 は測っていない
- 乱数は Philox。同じ機械・同じ seed なら同じ音になる（Mac と Windows では同じにならない）

## 決まりの出どころ

| 決まり | 決めた人 | 理由 |
|---|---|---|
| エンジンを qwentts.cpp 1 本にする | オーナー（2026-10-23） | Mac・Windows とも最速で、聞いて採用できる品質 |
| 1.7B BF16 | オーナー（2026-10-23） | 可愛い声の参照で聞き比べて「いいね」。並列はそこまで求めない |
| 区間ごとの生成で通話の形を作る（`utter`） | オーナー（2026-10-23） | つなぎ目を聞いて問題なし |
| kiapi 互換のサーバーは作らない。Spirits の body が直接使い、次に TTS ノード | オーナー（2026-10-23） | サーバーは最終形で使わない回り道 |
| 名前 `voice_clone_tts`、public | オーナー（2026-10-23） | できることで名付ける（エンジンを替えても嘘にならない）。兄弟の plugin と同じく public |
| ggml を共有ライブラリに閉じる | エージェント | pcm_asr と同じアプリに入れたときの衝突を避ける |
