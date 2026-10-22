# 最初の版（Mac と Windows で、Spirits Garden の試作から使える）

完了条件: Mac（Metal）と Windows（CUDA）で、声の登録・文を渡して PCM を流して受け取る・止める が Dart から使え、
kiapi 互換の口（`packages/voice_clone_tts_server`）で Spirits Garden の試作の body が `speak` と通話の clone に使えて、オーナーが声を聞いて確かめた。

## やること

- [ ] Dart の API を決める（オーナーに案を見せる）。qwentts.cpp の `qwen.h`（`qt_init`・`qt_extract_voice_ref`・`qt_synthesize`・流しの callback・取り消しの callback）に合わせる
- [ ] build: qwentts.cpp を `QWEN_SHARED=ON` の共有ライブラリにし、ggml は静的にリンクして閉じる（`docs/concepts/architecture.md` の「ggml の二重」）。
  macOS は Metal、Windows は CUDA（CUDA Toolkit が要る。利用者の PC には CUDA の実行時の DLL を同梱するか、無ければ「使えない」と返す）
- [ ] 重みの取得（Hugging Face `Serveurperso/Qwen3-TTS-GGUF` の `qwen-talker-1.7b-base-BF16.gguf`・`qwen-tokenizer-12hz-F32.gguf`、revision `b7ee2e8c7459c3bea99da23e3d178125a7d1713c`、hash を固定）と進み具合の通知
- [ ] 例題アプリ（共有素材の話者 1 で 1 文を話す）と、labs と同じ入力で速さを確かめる道具（`tool/`）
- [ ] 取り消しの速さを測る（C の ABI の取り消しで、次の返事の最初の音まで）
- [ ] `packages/voice_clone_tts_server`: 声の登録・`POST /v1/audio/speech`（pcm）・版 2 の WebSocket（受け取った文字を区間に分けて、区間ごとに生成）
- [ ] Spirits Garden の試作の body を Mac と Windows でこの口につなぎ、オーナーに聞いてもらう
- [ ] flutter create の雛形のサンプル（`sum`）を消す

## 申し送り

- 実測の入力と手順は labs の 3 つの lab（`AGENTS.md`）。qwentts.cpp の commit は `5916bf7c79dbb4e66fc059cdc507a79a23a28bb4`（2026-10-16）
- Windows の build は、Visual Studio 2022（C++）と CUDA Toolkit 13.4、`-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86`（RTX 30 系）で通った。配るなら対象の GPU の世代を決める
