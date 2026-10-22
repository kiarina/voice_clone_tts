# 最初の版（Mac と Windows で、Spirits Garden の試作から使える）

完了条件: Mac（Metal）と Windows（CUDA）で、声の登録・文を渡して PCM を流して受け取る・止める が Dart から使え、
kiapi 互換の口（`packages/voice_clone_tts_server`）で Spirits Garden の試作の body が `speak` と通話の clone に使えて、オーナーが声を聞いて確かめた。

## やること

- [x] Dart の API（2026-10-23、オーナーと合意。`docs/concepts/architecture.md` の「Dart の API」）
- [x] build: build hook（`hook/build.dart`）で qwentts.cpp の project に `src/vct.cmake` を差し込み、1 つの共有ライブラリにする（ggml は静的）。Mac（Metal）で確かめた
- [ ] Windows（CUDA）の build と実機。hook は Visual Studio 2022 と CUDA Toolkit を前提にし、cudart・cuBLAS の DLL を bundle する（未確認）
- [x] 重みの取得（revision と SHA-256 を固定、`.part` から再開、`.ok` の印）。実際の download は通していない（Mac は Hugging Face のキャッシュから置いた）
- [ ] 例題アプリ（共有素材の話者 1 で 1 文を話す）と、labs と同じ入力で速さを確かめる道具（`tool/`）
- [x] Mac で通した（2026-10-23、`test/real_test.dart`、Apple M1 Max）: 読み込み 1.6 秒、声の登録 1.2 秒（初回の準備込み）、`speak` の最初の音 85〜94 ms・実時間の 0.50〜0.54 倍、
  `utter` で 3 区間、**取り消しは 10 ms で止まり次の返事の最初の音まで 96 ms**（HTTP のサーバーの 0.7 秒から縮んだ）
- [ ] `packages/voice_clone_tts_server`: 声の登録・`POST /v1/audio/speech`（pcm）・版 2 の WebSocket（受け取った文字を区間に分けて、区間ごとに生成）
- [ ] Spirits Garden の試作の body を Mac と Windows でこの口につなぎ、オーナーに聞いてもらう
- [x] 雛形のサンプルを消した（plugin の形をやめ、build hook の package にした）

## 申し送り

- 実測の入力と手順は labs の 3 つの lab（`AGENTS.md`）。qwentts.cpp の commit は `5916bf7c79dbb4e66fc059cdc507a79a23a28bb4`（2026-10-16）
- Windows の build は、Visual Studio 2022（C++）と CUDA Toolkit 13.4、`-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86`（RTX 30 系）で通った。配るなら対象の GPU の世代を決める
