import 'dart:io';

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/foundation.dart';

/// Sons du hub, joués par les haut-parleurs de l'écran 7" (son HDMI, carte vc4hdmi0).
/// Sur le Pi, la sortie HDMI ne rend le son qu'en stéréo via le périphérique "hdmi:" : la sortie par
/// défaut est muette. DARTOS_AUDIO change de périphérique. Hors du Pi (Mac), rien n'est joué.
class Sounds {
  Sounds._();

  static final _device = Platform.environment['DARTOS_AUDIO'] ?? 'hdmi:CARD=vc4hdmi0,DEV=0';

  /// Dossier des sons dans le bundle flutter-pi (assets à côté de l'exécutable).
  static String get _dir => '${File(Platform.resolvedExecutable).parent.path}/assets/sounds';

  static Process? _playing;

  /// Joue assets/sounds/[name].wav (WAV stéréo 48 kHz) sans attendre. Un son coupe le précédent.
  static Future<void> play(String name) async {
    if (!Platform.isLinux) return;
    final path = '$_dir/$name.wav';
    if (!File(path).existsSync()) {
      debugPrint('Sounds: $path introuvable');
      return;
    }
    try {
      _playing?.kill();
      _playing = await Process.start('aplay', ['-q', '-D', _device, path]);
    } catch (e) {
      debugPrint('Sounds: $e');
    }
  }

  /// Coupe le son en cours (vidéo 180 passée d'un toucher).
  static void stop() {
    _playing?.kill();
    _playing = null;
  }

  /// Fléchette lancée par le joueur (caméras ou posée à la main) : son qui va avec.
  static void dart(DartThrow d) {
    if (d.isMiss) {
      play('miss');
    } else if (d.sector == 20 && d.multiplier == 3) {
      play('t20');
    }
  }
}
