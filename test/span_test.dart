import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_clone_tts/voice_clone_tts.dart';

void main() {
  const rule = SpanRule();

  test('Japanese: punctuation from 8 characters, else 24', () {
    expect(spanEnd('うん、今日は', 'ja', false, rule), 0);
    expect(spanEnd('うん、今日はいい天気ですね。少し', 'ja', false, rule), 14);
    expect(spanEnd('あいうえおかきくけこさしすせそたちつてとなにぬねの', 'ja', false, rule), 24);
    expect(spanEnd('はい', 'ja', true, rule), 2);
  });

  test('English: punctuation from 14 characters, else 6 words', () {
    expect(spanEnd('Tokyo is a busy city with quiet', 'en', false, rule), 'Tokyo is a busy city with '.length);
    expect(spanEnd('Hi, I am here. And', 'en', false, rule), 'Hi, I am here. '.length);
  });

  test('language names', () {
    expect(qwenLanguage('ja-JP'), 'japanese');
    expect(qwenLanguage('en'), 'english');
    expect(qwenLanguage(null), isNull);
    expect(qwenLanguage('auto'), isNull);
  });

  test('voice bytes round trip', () {
    final v = Voice(
      transcript: 'こんにちは',
      speakerEmbedding: Float32List.fromList([0.5, -1.25]),
      codes: Int32List.fromList([1, 2, 3, 4]),
      codebooks: 2,
    );
    final back = Voice.fromBytes(v.toBytes());
    expect(back.transcript, v.transcript);
    expect(back.speakerEmbedding, v.speakerEmbedding);
    expect(back.codes, v.codes);
    expect(back.frames, 2);
  });
}
