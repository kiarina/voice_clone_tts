# AGENTS.md

このリポジトリで作業するエージェント向けのガイドラインです。

## 作業前に読むもの

- `README.md`（公開向けの説明）
- `docs/concepts/architecture.md`（作りと決まりの正典。なぜこの形かも）
- `tasks/`（残っている作業。1 タスク 1 ファイル）
- `CHANGELOG.md`

実測の来歴は labs の `2026/10/23/qwen3-tts-onnx-runtime-compare`（ONNX Runtime を外した理由）・`2026/10/23/qwen3-tts-ggml-compare`（qwentts.cpp を選んだ理由）・
`2026/10/23/qwen3-tts-ggml-call-segments`（通話の短区間の形が成り立つこと）。この repo はそこから写して所有し、lab とは同期しない。

## 設計の決まり

- エンジンは qwentts.cpp 1 本（`third_party/qwentts.cpp`、submodule で commit を固定）。Mac は Metal、Windows は CUDA。モデルは Qwen3-TTS 1.7B Base の BF16 で、
  参照の音声と文字起こしで似せる（ICL）（オーナー、2026-10-23）。上げるときは、上げた後に labs と同じ入力で速さと音を確かめる
- Dart からは qwentts.cpp の C の ABI（`qwen.h`）を `dart:ffi` で呼ぶ。C の構造体の版（`QT_ABI_VERSION`）が合わないときは読み込みで断る
- 重みは同梱せず、使うときに Hugging Face から revision と hash を固定して取る
- 声をまねる道具なので、README と API の説明に「声の持ち主の同意がある声だけ使う」を書く。同意の確認はアプリの責任
- 認証値・録音・個人の声・個人環境のパスやマシン名を公開物に混ぜない。例題とテストの音声は共有素材（`kiarina/test-assets`）だけ

## 検証

- `flutter analyze` と `flutter test`
- 実機の速さと音は labs と同じ入力（共有素材の話者 1、7 文、seed）で確かめる。対応表に書く OS は実機で確かめたものだけ

## 公開

pub.dev への公開は取り消せない（discontinue しかできない）。公開の前に名前・version・公開内容・対応範囲をオーナーに示し、
`flutter pub publish --dry-run` の結果を見せる。`publish_to: none` は公開の直前まで外さない。`.pubignore` があると `.gitignore` は見られない。
publisher は `kiarina.dev`。commit メッセージは英語。
