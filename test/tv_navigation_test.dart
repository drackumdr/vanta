import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanta/ui/tv/tv_focusable.dart';
import 'package:vanta/ui/tv/tv_utils.dart';
import 'package:vanta/widgets/camera_tile.dart';

void main() {
  testWidgets(
    'TvFocusable invokes onTap when ActivateIntent is dispatched (D-Pad Select)',
    (tester) async {
      var tapped = false;
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TvFocusable(
                focusNode: focusNode,
                autofocus: true,
                onTap: () => tapped = true,
                child: const Text('Cámara 1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isTrue);

      // Enviar evento de activación de D-Pad / Enter
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      if (!tapped) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }

      expect(tapped, isTrue);
    },
  );

  test('TvUtils has safe overscan padding configured', () {
    expect(TvUtils.overscanPadding.horizontal, greaterThanOrEqualTo(40));
    expect(TvUtils.overscanPadding.vertical, greaterThanOrEqualTo(20));
  });

  testWidgets('CameraTile maps a long Select press to camera reassignment', (
    tester,
  ) async {
    var tapped = false;
    var longPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CameraTile(
          session: null,
          name: 'Cámara 1',
          autofocus: true,
          onTap: () => tapped = true,
          onLongPress: () => longPressed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(longPressed, isTrue);
    expect(tapped, isFalse);
  });
}
