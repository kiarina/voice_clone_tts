import 'dart:math' as math;
import 'dart:typed_data';

/// Windowed-sinc resampling of 16-bit PCM to 24 kHz float in -1..1. Used once per reference voice, so it favors
/// quality over speed.
Float32List resampleTo24k(Int16List pcm, int rate) {
  const target = 24000;
  final input = Float64List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    input[i] = pcm[i] / 32768.0;
  }
  if (rate == target) return Float32List.fromList(input);
  final ratio = target / rate;
  final cutoff = math.min(1.0, ratio) * 0.95;
  const half = 32; // taps on each side
  final out = Float32List((pcm.length * ratio).floor());
  for (var j = 0; j < out.length; j++) {
    final center = j / ratio;
    final first = center.floor() - half + 1;
    var acc = 0.0;
    for (var k = first; k <= center.floor() + half; k++) {
      if (k < 0 || k >= input.length) continue;
      final x = center - k;
      final sinc = x == 0
          ? 1.0
          : math.sin(math.pi * cutoff * x) / (math.pi * cutoff * x);
      final window = 0.5 + 0.5 * math.cos(math.pi * x / half);
      acc += input[k] * cutoff * sinc * window;
    }
    out[j] = acc;
  }
  return out;
}
