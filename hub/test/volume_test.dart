import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dartos_hub/setup/owner_store.dart';
import 'package:dartos_hub/system/sounds.dart';
import 'package:dartos_hub/theme/tokens.dart';
import 'package:dartos_hub/widgets/volume_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_size.dart';

import 'package:dartos_hub/main.dart' show ScreenFit;

/// WAV PCM 16 bits minimal avec les échantillons donnés.
Uint8List _wav(List<int> samples) {
  final b = BytesBuilder();
  ByteData u32(int v) => ByteData(4)..setUint32(0, v, Endian.little);
  ByteData u16(int v) => ByteData(2)..setUint16(0, v, Endian.little);
  b.add('RIFF'.codeUnits);
  b.add(u32(36 + samples.length * 2).buffer.asUint8List());
  b.add('WAVEfmt '.codeUnits);
  b.add(u32(16).buffer.asUint8List());
  for (final v in [1, 2]) {
    b.add(u16(v).buffer.asUint8List());
  }
  b.add(u32(48000).buffer.asUint8List());
  b.add(u32(48000 * 4).buffer.asUint8List());
  b.add(u16(4).buffer.asUint8List());
  b.add(u16(16).buffer.asUint8List());
  b.add('data'.codeUnits);
  b.add(u32(samples.length * 2).buffer.asUint8List());
  for (final s in samples) {
    b.add((ByteData(2)..setInt16(0, s, Endian.little)).buffer.asUint8List());
  }
  return b.toBytes();
}

List<int> _samples(Uint8List wav) {
  final d = ByteData.sublistView(wav);
  return [for (var i = 44; i < wav.length; i += 2) d.getInt16(i, Endian.little)];
}

void main() {
  setUp(() => OwnerStore.useDirectory(Directory.systemTemp.createTempSync('vol').path));

  test('le volume multiplie les échantillons, en-tête intact', () {
    final wav = _wav([1000, -1000, 32767, -32768]);
    final half = Sounds.scaleWav(wav, 0.5);
    expect(half.sublist(0, 44), wav.sublist(0, 44));
    expect(_samples(half), [500, -500, 16384, -16384]);
    expect(_samples(Sounds.scaleWav(wav, 0)), [0, 0, 0, 0]);
  });

  test('volume et muet gardés dans volume.json', () async {
    await Sounds.setVolume(30);
    await Sounds.setMuted(true);
    expect(Sounds.gain, 0);
    final j = File('${OwnerStore.instance.dir.path}/volume.json').readAsStringSync();
    expect(j, contains('"volume":30'));
    expect(j, contains('"muted":true'));
    await Sounds.setVolume(60);
    expect(Sounds.muted.value, isFalse);
    expect(Sounds.gain, closeTo(0.36, 1e-9));
  });

  testWidgets('icône, appui ouvre le volume, muet', (tester) async {
    tester.view.physicalSize = testScreen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      for (final (f, p) in [
        ('Inter', 'assets/fonts/Inter.ttf'),
        ('Nunito', 'assets/fonts/Nunito.ttf'),
        ('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf'),
      ]) {
        await (FontLoader(f)..addFont(rootBundle.load(p))).load();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Inter', scaffoldBackgroundColor: Td.beton, brightness: Brightness.dark),
        builder: (context, child) => ScreenFit(
          child: RepaintBoundary(key: const Key('shot'), child: child),
        ),
        home: const Scaffold(body: Center(child: VolumeButton())),
      ),
    );
    await tester.runAsync(() => Sounds.setVolume(70));
    await tester.tap(find.byType(VolumeButton));
    await tester.pumpAndSettle();
    expect(find.text('70 %'), findsOneWidget);

    Future<void> shot(String name) async {
      final out = Platform.environment['SHOTS'];
      if (out == null) return;
      final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
      await tester.runAsync(() async {
        final img = await ro.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await shot('volume');
    await tester.tap(find.bySemanticsLabel('Muet'));
    await tester.pumpAndSettle();
    expect(find.text('Muet'), findsOneWidget);
    expect(Sounds.muted.value, isTrue);
    await shot('volume-muet');
  });
}
