import 'package:darts_engine/darts_engine.dart';
import 'package:dartos_hub/cam/cam_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lit les fléchettes du contrat MQTT', () {
    expect(CamLink.parseDart({'number': 20, 'multiplier': 3})?.$1, const DartThrow.triple(20));
    expect(CamLink.parseDart({'number': 25, 'multiplier': 2})?.$1, DartThrow.bull);
    expect(CamLink.parseDart({'number': 0, 'multiplier': 0})?.$1, const DartThrow.miss());
    expect(CamLink.parseDart({'number': 7, 'multiplier': 1, 'x': 1.5, 'y': -3})?.$2, const Offset(1.5, -3));
  });

  test('refuse les fléchettes impossibles', () {
    expect(CamLink.parseDart({'number': 25, 'multiplier': 3}), isNull);
    expect(CamLink.parseDart({'number': 21, 'multiplier': 1}), isNull);
    expect(CamLink.parseDart({'segment': 'T20'}), isNull);
  });
}
