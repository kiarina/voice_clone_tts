# 最初の版を仕上げる（Mac と Windows の利用者の PC で動く）

完了条件: GPU のある Mac と Windows の PC で、重みを実際に落とすところから `speak`・`utter`・取り消しまで動き、Windows は CUDA の PATH が無い PC でもアプリとして起動して、
README の手順で他の人が使える。Spirits Garden の試作に組み込むのは Spirits Garden の `tasks/`（この package を使う側）。

## 済んだこと（2026-10-23）

- Dart の API（オーナーと合意。`doc/concepts/architecture.md`）と、build hook による native の build（Mac は Metal、Windows は Ninja＋CUDA）
- 本物のエンジンの通し（`test/real_test.dart`）: Mac（M1 Max）は `speak` の最初の音 85〜94 ms・実時間の 0.5 倍、取り消し 10 ms・次の返事 96 ms。
  Windows（RTX 3080 Ti）は 26〜32 ms・0.18 倍、取り消し 5 ms・次の返事 32 ms。`utter` は両方で 3 区間に分かれて順に出た

## 残り

- [x] Windows の配布で DLL が読めるか（2026-10-23、Spirits Garden の試作で）: release の build で `voice_clone_tts.dll` と cuBLAS・cudart の DLL が exe の隣に入り、PATH から CUDA を外して起動しても、プロセスは exe の隣の `cublas64_13.dll`・`cublasLt64_13.dll` を読んで CUDA で開いた。
  cudart は ggml に静的に入っていて読まれないので、bundle から外せる（未対応）。声が出るところはアプリの側で確かめる
- [x] cudart を同梱から外した（2026-10-23）。同梱は cuBLAS の 2 つ（約 550 MB）。大きさを減らすなら cuBLAS も重みと同じく後から取る形があるが、0.1.0 ではしない
- [x] 重みの実際の download（2026-10-23、MacBook Pro M1 Max、`test/download_test.dart`）: 空の置き場所に 4.5 GB を約 4 分で取った。本物の先頭 64 MB の `.part` からは続きを取って照合に通り、壊れた `.part` は SHA-256 の照合で消えてエラーになった
- [x] 例題アプリ（`example/`、2026-10-23）: 参照の WAV のパス・文字起こし・文を入れて話し、一時フォルダの WAV に書いて OS の道具で鳴らす。Mac で build と起動（Metal を認める表示）、Windows（RTX 3080 Ti）で統合テスト（`example/integration_test/speak_test.dart`）が欄を埋めて話すまで通った。Mac で話すところは本物のエンジンのテスト（`test/real_test.dart`）だけで、例題の画面からは鳴らしていない
- [x] 既定の CUDA の世代は qwentts.cpp の一覧のまま（CUDA 13 では RTX 20 系〜50 系）にし、アプリが `cuda_architectures` で絞る（README）。例題の release の build は Core i9-12900K で約 13.5 分（2026-10-23）
- [x] macOS の共有ライブラリが外に出す記号を `vct_*` の 9 個に絞った（`src/vct.cmake` の `-exported_symbol`、2026-10-23。前は約 1,500）
- [x] `flutter analyze` の残り（2026-10-23、`dart fix`）
- [ ] pub.dev に 0.1.0 を出す（`dart pub publish --dry-run` は通る。警告は gitignore で外れる qwentts.cpp の例題・試験の記録の 1 つだけで、build には要らない。圧縮で 4 MB）。出す前に名前・版・中身をオーナーに見せる
- [ ] NVIDIA の GPU の無い Windows の PC で `support()` が使えないと答えるか（そういう PC が手元に無い。`nvcuda.dll` が無いと共有ライブラリが読めず「native library unavailable」になる見込み）

## 申し送り

- 本物のエンジンの通し: `VCT_REAL=1 VCT_CACHE=<重みの置き場所> VCT_REFERENCE=<24 kHz 16 bit mono の WAV> flutter test test/real_test.dart`。重みの置き場所は `<cache>/<revision>/` に 2 つのファイルと、SHA-256 を書いた `.ok`
- Windows で通すときは、アプリ（またはこの repo）の pubspec に `hooks: user_defines: voice_clone_tts: cuda_architectures: "86-real"` を置くと build が短い（RTX 30 系）。この repo には commit していない
- build hook には PATH・PROGRAMDATA などわずかな環境変数しか渡らない。設定は `user_defines` で渡す（`hook/build.dart` の冒頭）
- 実測の来歴は labs の 3 つの lab（`AGENTS.md`）。qwentts.cpp の commit は `5916bf7c79dbb4e66fc059cdc507a79a23a28bb4`（2026-10-16）
- **hook が出す同梱物を減らすと、Flutter（3.47.2）は前回アプリに写したファイルでなく、写す元のファイルを消そうとする**（2026-10-23、cudart を外した後の例題の Windows の build。`Flutter failed to delete file at "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4\bin\x64\cudart64_13.dll"`）。
  権限が無くて消せず build が失敗した。`flutter clean` で直る。管理者の権限で build すると CUDA Toolkit の DLL が消えるおそれがある。上流への報告はオーナーと決める
- G-GEAR の checkout は、build で生まれた `example/pubspec.lock` の書き換えと生成物（`generated_plugin_registrant` など）で `git pull` が止まることがある。生成物なので戻して・消して pull する
