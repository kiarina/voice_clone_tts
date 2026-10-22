#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint voice_clone_tts.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'voice_clone_tts'
  s.version          = '0.0.1'
  s.summary          = 'Voice cloning text-to-speech for Flutter: Qwen3-TTS through qwentts.cpp (ggml), Metal on macOS and CUDA on Windows.'
  s.description      = <<-DESC
Voice cloning text-to-speech for Flutter: Qwen3-TTS through qwentts.cpp (ggml), Metal on macOS and CUDA on Windows.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'voice_clone_tts/Sources/voice_clone_tts/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'voice_clone_tts_privacy' => ['voice_clone_tts/Sources/voice_clone_tts/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
