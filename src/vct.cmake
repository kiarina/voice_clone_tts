# Injected into qwentts.cpp's own CMake project (CMAKE_PROJECT_qwentts-ggml_INCLUDE, set by hook/build.dart) so that
# its macros and CMAKE_SOURCE_DIR-relative paths keep working. At the end of its top-level CMakeLists.txt, adds the
# `voice_clone_tts` shared library: our vct.cpp, the static qwen-core, and ggml linked statically, exporting only vct_*.
cmake_language(DEFER DIRECTORY ${CMAKE_SOURCE_DIR} CALL _vct_add_library)

function(_vct_add_library)
    add_library(voice_clone_tts SHARED ${VCT_SOURCE_DIR}/vct.cpp)
    target_include_directories(voice_clone_tts PRIVATE ${VCT_SOURCE_DIR})
    target_link_libraries(voice_clone_tts PRIVATE qwen-core)
    link_ggml_backends(voice_clone_tts)
    set_target_properties(voice_clone_tts PROPERTIES
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON
    )
endfunction()
