@Tags(['screenshot'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartos_hub/screens/setup_screen.dart';
import 'package:dartos_hub/setup/owner_store.dart';
import 'package:dartos_hub/setup/setup_server.dart';
import 'package:dartos_hub/setup/wifi_manager.dart';
import 'package:dartos_hub/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _font(String family, String path) async {
  final l = FontLoader(family)..addFont(rootBundle.load(path));
  await l.load();
}

void main() {
  testWidgets('captures setup', (tester) async {
    final out = Platform.environment['SHOTS'];
    if (out == null) return;
    await tester.runAsync(() async {
      await _font('Inter', 'assets/fonts/Inter.ttf');
      await _font('Nunito', 'assets/fonts/Nunito.ttf');
      await _font('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf');
    });
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = SetupController(wifi: SimulatedWifi(), store: OwnerStore.instance)..host = '192.168.1.20';
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Inter', scaffoldBackgroundColor: Td.beton),
      home: Scaffold(body: RepaintBoundary(child: SetupScreen(controller: c))),
    ));

    Future<void> shot(String name) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final ro = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final img = await ro.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await shot('setup-1-qr');
    c
      ..phase = SetupPhase.wifiConnecting
      ..phoneName = 'iPhone de Thibault'
      ..ssid = 'Freebox-Thibs'
      ..wifiState = WifiState.connecting;
    c.notifyListeners();
    await shot('setup-2-encours');
    c
      ..phase = SetupPhase.done
      ..owner = const Owner(firstName: 'Thibault', lastName: 'H', nickname: 'Thibs');
    c.notifyListeners();
    await shot('setup-3-bienvenue');
  });
}
