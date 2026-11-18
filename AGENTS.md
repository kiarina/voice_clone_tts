# AGENTS.md

このリポジトリで作業するエージェント向けのガイドラインです。

## 作業前に読むもの

- `README.md`（公開向けの説明）
- `doc/concepts/architecture.md`（作りと決まりの正典。なぜこの形かも）
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

## build

- `git clone --recurse-submodules`（qwentts.cpp の中の ggml も submodule）。build は Flutter の build hook（`hook/build.dart`）が CMake で行う
- 本物のエンジンの通しは `VCT_REAL=1 VCT_CACHE=<重みの置き場所> VCT_REFERENCE=<24 kHz 16 bit mono の WAV> flutter test test/real_test.dart`

## 検証

- `flutter analyze` と `flutter test`
- 実機の速さと音は labs と同じ入力（共有素材の話者 1、7 文、seed）で確かめる。対応表に書く OS は実機で確かめたものだけ

## 公開

pub.dev への公開は取り消せない（retract は 7 日以内、それ以降は discontinue しかできない）。publisher は `kiarina.dev`。commit メッセージは英語。

1. `pubspec.yaml` の version と `CHANGELOG.md` を上げ、`flutter analyze` を通す
2. `dart pub publish --dry-run` で中身と警告を見る。`.pubignore` があると `.gitignore` は見られない（変えたら両方に）。
   qwentts.cpp の中の `.gitignore` で外れる commit 済みのファイル（テストのログ・例の WAV など）の警告は、submodule を変えずには消えず、公開物に入らないので残してよい
3. 公開物だけで動くかを確かめる。dry-run が挙げるファイルだけを空の場所へ写し（`tool/dry_run_copy.py`。`.dart_tool`・submodule の git 情報は無い状態）、
   そこで `test/real_test.dart` を macOS と Windows で流す。hook が要るのに `.pubignore` で外したファイルは、公開してからでは直せない
4. 名前・version・公開内容（大きさ・ファイル数・変わったもの）・残る警告・3 の結果をオーナーに示し、承認を得てから `dart pub publish`
5. 公開した commit に注釈付きの tag `v<version>` を付けて push し、pub.dev の解析（点数・対応 OS の表示）を確かめる
