import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vanta/app.dart';
import 'package:vanta/state/app_state.dart';

void main() {
  testWidgets('VANTA renders dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const VantaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VANTA'), findsOneWidget);
  });

  testWidgets('dashboard shows empty state without devices', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const VantaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dispositivos'), findsNothing);
    expect(find.text('Registrar dispositivo'), findsOneWidget);
  });
}