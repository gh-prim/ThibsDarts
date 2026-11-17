import 'package:dartos_hub/widgets/td_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Future<void> _font(String family, String path) async {
  final l = FontLoader(family)..addFont(rootBundle.load(path));
  await l.load();
}

void main() {
  testWidgets('bouton Caméras de Corriger : le libellé tient', (tester) async {
    await tester.runAsync(() async {
      await _font('Inter', 'assets/fonts/Inter.ttf');
      await _font('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf');
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Inter'),
        home: Center(
          child: SizedBox(
            width: 190,
            child: TdButton(label: 'Caméras', icon: LucideIcons.camera, height: 44, onPressed: () {}),
          ),
        ),
      ),
    );
    final text = tester.getSize(find.text('Caméras')).width;
    expect(tester.takeException(), isNull);
    // Icône 26 + espace 8 + marges 2 x 16 + texte : doit rester sous 190.
    expect(text + 26 + 8 + 32, lessThan(190));
  });
}
