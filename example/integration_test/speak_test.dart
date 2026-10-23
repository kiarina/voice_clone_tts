// Fills in the example's fields and speaks, on the real engine and GPU. Skipped unless VCT_REFERENCE and
// VCT_TRANSCRIPT are set (a 16-bit WAV and what it says):
//   VCT_REFERENCE=<wav> VCT_TRANSCRIPT=<text> flutter test integration_test -d macos   # or -d windows
// It plays the result on the speakers.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_clone_tts_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final reference = env['VCT_REFERENCE'];

  testWidgets(
    'speaks in the reference voice',
    (tester) async {
      final out = File('${Directory.systemTemp.path}/voice_clone_tts_example.wav');
      if (out.existsSync()) out.deleteSync();
      app.main();
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), reference!);
      await tester.enterText(fields.at(1), env['VCT_TRANSCRIPT']!);
      await tester.pump();
      for (var i = 0; i < 100 && !_enabled(tester, 'Speak'); i++) {
        await tester.pump(const Duration(milliseconds: 100)); // support() still checking
      }
      await tester.tap(find.text('Speak'));
      for (var i = 0; i < 1800 && !find.textContaining('wrote ').evaluate().isNotEmpty; i++) {
        if (find.textContaining('error:').evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.textContaining('error:'), findsNothing);
      expect(out.existsSync(), isTrue);
      expect(out.lengthSync(), greaterThan(44 + 24000 * 2)); // more than a second of 24 kHz audio
    },
    skip: reference == null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

bool _enabled(WidgetTester tester, String label) {
  final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));
  return button.onPressed != null;
}
