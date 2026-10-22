// Bindings to src/vct.h, the C layer built by hook/build.dart (the code asset named after this file).
import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class VctRequest extends Struct {
  external Pointer<Utf8> text;
  external Pointer<Utf8> lang;
  external Pointer<Utf8> refText;
  external Pointer<Float> spkEmb;
  @Int32()
  external int spkDim;
  external Pointer<Int32> codes;
  @Int32()
  external int frames;
  @Int64()
  external int seed;
  @Int32()
  external int maxFrames;
  @Float()
  external double temperature;
  @Int32()
  external int topK;
  @Float()
  external double topP;
  @Float()
  external double repetitionPenalty;
  @Float()
  external double subtalkerTemperature;
  @Int32()
  external int subtalkerTopK;
  @Float()
  external double subtalkerTopP;
}

const vctEventPcm = 0;
const vctEventDone = 1;
const vctEventCancelled = 2;
const vctEventError = 3;

typedef VctEventCallback = Void Function(
  Int64 request,
  Int32 kind,
  Pointer<Int16> pcm,
  Int32 n,
  Int32 status,
  Pointer<Utf8> message,
);

@Native<Pointer<Utf8> Function()>(symbol: 'vct_engine_version')
external Pointer<Utf8> vctEngineVersion();

@Native<Int32 Function(Pointer<Utf8>, Int32)>(symbol: 'vct_best_gpu')
external int vctBestGpu(Pointer<Utf8> buf, int size);

@Native<
  Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32)
>(symbol: 'vct_open')
external Pointer<Void> vctOpen(
  Pointer<Utf8> talker,
  Pointer<Utf8> codec,
  Pointer<Utf8> device,
  int maxBatch,
);

@Native<Void Function(Pointer<Void>)>(symbol: 'vct_close')
external void vctClose(Pointer<Void> engine);

@Native<Pointer<Utf8> Function()>(symbol: 'vct_last_error')
external Pointer<Utf8> vctLastError();

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Float>,
    Int32,
    Pointer<Pointer<Float>>,
    Pointer<Int32>,
    Pointer<Pointer<Int32>>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
>(symbol: 'vct_extract_voice')
external int vctExtractVoice(
  Pointer<Void> engine,
  Pointer<Float> pcm,
  int n,
  Pointer<Pointer<Float>> spk,
  Pointer<Int32> spkDim,
  Pointer<Pointer<Int32>> codes,
  Pointer<Int32> frames,
  Pointer<Int32> codebooks,
);

@Native<
  Int64 Function(
    Pointer<Void>,
    Pointer<VctRequest>,
    Pointer<NativeFunction<VctEventCallback>>,
  )
>(symbol: 'vct_start')
external int vctStart(
  Pointer<Void> engine,
  Pointer<VctRequest> request,
  Pointer<NativeFunction<VctEventCallback>> cb,
);

@Native<Void Function(Int64)>(symbol: 'vct_cancel')
external void vctCancel(int request);

@Native<Void Function(Pointer<Void>)>(symbol: 'vct_free')
external void vctFree(Pointer<Void> p);
