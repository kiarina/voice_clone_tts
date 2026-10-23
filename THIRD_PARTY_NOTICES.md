# Third-party notices

## qwentts.cpp and ggml

The native backend compiles [qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp)
(pinned as the `third_party/qwentts.cpp` submodule) and the ggml it bundles.
Both are licensed under the MIT License. See `third_party/qwentts.cpp/LICENSE`
and `third_party/qwentts.cpp/ggml/LICENSE`.

## Qwen3-TTS (model weights, not bundled)

The weights are downloaded at run time, not shipped with the package:
Qwen3-TTS-12Hz-1.7B-Base and the Qwen3-TTS-Tokenizer-12Hz by the Qwen team
(Alibaba), licensed under the Apache License 2.0, in the GGUF conversion
published by the qwentts.cpp author.

## NVIDIA CUDA (Windows, not bundled with the package)

On Windows the build hook links the CUDA runtime statically and copies the cuBLAS DLLs (`cublas64_*.dll`,
`cublasLt64_*.dll`) from the CUDA Toolkit installed on the build machine into the app. They come from the developer's
own CUDA Toolkit and are distributed with the app under the
[NVIDIA CUDA Toolkit EULA](https://docs.nvidia.com/cuda/eula/), which lists them as redistributable. An app that ships
them is responsible for following its terms.
