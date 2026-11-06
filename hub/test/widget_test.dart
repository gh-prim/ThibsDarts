import 'package:dartos_hub/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("démarre puis affiche l'accueil", (tester) async {
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const DartOsApp());
    await tester.pump();
    expect(find.bySemanticsLabel('ThibsDarts'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Prêt. Tranquille.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Rejouer'), findsNothing);
    expect(find.text('Nouvelle partie'), findsOneWidget);
  });
}
