import 'package:dartos_hub/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('démarre puis affiche l\'accueil', (tester) async {
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const DartOsApp());
    expect(find.text('ThibsDarts'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Rejouer'), findsOneWidget);
    expect(find.text('Nouvelle partie'), findsOneWidget);
  });
}
