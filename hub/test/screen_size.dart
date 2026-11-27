import 'dart:io';
import 'dart:ui';

/// Écran simulé par les tests, en pixels réels : SCREEN=1280x800 flutter test (1024x600 par défaut).
/// Sert à vérifier que les écrans tiennent sur les dalles 10" (1280x800, 1920x1080, 1920x1200).
final Size testScreen = () {
  final m = RegExp(r'^(\d+)x(\d+)$').firstMatch(Platform.environment['SCREEN'] ?? '');
  return m == null ? const Size(1024, 600) : Size(double.parse(m[1]!), double.parse(m[2]!));
}();
