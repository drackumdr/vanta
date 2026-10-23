import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanta/ui/tv/tv_text_field.dart';

void main() {
  testWidgets('TvTextField moves focus to next widget on arrowDown', (tester) async {
    final controller1 = TextEditingController();
    final controller2 = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TvTextField(controller: controller1, labelText: 'Campo 1', autofocus: true),
              TvTextField(controller: controller2, labelText: 'Campo 2'),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Comprobar que Campo 1 tiene el foco inicial
    final textField1 = tester.widget<TextField>(find.byType(TextField).first);
    expect(textField1.focusNode?.hasFocus, isTrue);

    // Enviar evento de teclado arrowDown (simula cruceta abajo de control remoto)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // Comprobar que el foco se movió a Campo 2
    final textField2 = tester.widget<TextField>(find.byType(TextField).last);
    expect(textField2.focusNode?.hasFocus, isTrue);

    // Enviar evento de teclado arrowUp (simula cruceta arriba de control remoto)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    // Comprobar que el foco regresó a Campo 1
    expect(textField1.focusNode?.hasFocus, isTrue);
  });
}
