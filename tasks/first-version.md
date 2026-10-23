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
- [ ] Windows の配布の大きさ: `cublasLt64_13.dll` だけで 490 MB。cudart を外す、重みと同じく後から取るなどを考える
- [ ] 重みの実際の download（Hugging Face から 4.5 GB、`.part` からの再開、SHA-256 の不一致で消す）。Mac・Windows とも Hugging Face のキャッシュから置いて済ませた
- [ ] 例題アプリ（`example/`）を Mac と Windows で動かす。参照の WAV と文字起こしを選んで話す。今は `--dart-define` で渡す仮の画面
- [ ] 配る GPU の世代（`cuda_architectures`）を決める。既定は qwentts.cpp の広い一覧で、build が長い（この repo の `flutter test` を既定の一覧で build すると、Core i9-12900K で約 40 分。`86-real` だけなら数分）
- [ ] macOS の共有ライブラリが ggml の記号を外に出している（`nm -gU` で約 1,500）。macOS は 2 段の名前空間で他の ggml とはぶつからないが、出すのを `vct_*` だけに絞る（`-exported_symbols_list`）か決める
- [ ] `flutter analyze` の残りの info（if の波括弧など）

## 申し送り

- 本物のエンジンの通し: `VCT_REAL=1 VCT_CACHE=<重みの置き場所> VCT_REFERENCE=<24 kHz 16 bit mono の WAV> flutter test test/real_test.dart`。重みの置き場所は `<cache>/<revision>/` に 2 つのファイルと、SHA-256 を書いた `.ok`
- Windows で通すときは、アプリ（またはこの repo）の pubspec に `hooks: user_defines: voice_clone_tts: cuda_architectures: "86-real"` を置くと build が短い（RTX 30 系）。この repo には commit していない
- build hook には PATH・PROGRAMDATA などわずかな環境変数しか渡らない。設定は `user_defines` で渡す（`hook/build.dart` の冒頭）
- 実測の来歴は labs の 3 つの lab（`AGENTS.md`）。qwentts.cpp の commit は `5916bf7c79dbb4e66fc059cdc507a79a23a28bb4`（2026-10-16）
