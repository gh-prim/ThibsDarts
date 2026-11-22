import 'dart:convert';
import 'dart:io';

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/foundation.dart';

import '../setup/owner_store.dart';

/// Sons du hub, joués par les haut-parleurs de l'écran 7" (son HDMI, carte vc4hdmi0).
/// Sur le Pi, la sortie HDMI ne rend le son qu'en stéréo via le périphérique "hdmi:" : la sortie par
/// défaut est muette. DARTOS_AUDIO change de périphérique. Hors du Pi (Mac), rien n'est joué.
class Sounds {
  Sounds._();

  static final _device = Platform.environment['DARTOS_AUDIO'] ?? 'hdmi:CARD=vc4hdmi0,DEV=0';

  /// Dossier des sons dans le bundle flutter-pi (assets à côté de l'exécutable).
  static String get _dir => '${File(Platform.resolvedExecutable).parent.path}/assets/sounds';

  static Process? _playing;

  /// Volume 0 à 100, gardé dans volume.json (dossier de données). La sortie HDMI du Pi n'a pas de
  /// mixeur matériel : le volume est appliqué aux échantillons avant de les envoyer à aplay.
  static final volume = ValueNotifier<int>(80);

  /// Muet : plus aucun son, le volume est gardé pour la remise en route.
  static final muted = ValueNotifier<bool>(false);

  static bool _loaded = false;

  static File get _volumeFile => File('${OwnerStore.instance.dir.path}/volume.json');

  /// Lit volume.json une fois (au premier son ou à la première ouverture du réglage).
  static void load() {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!_volumeFile.existsSync()) return;
      final j = jsonDecode(_volumeFile.readAsStringSync()) as Map<String, Object?>;
      volume.value = ((j['volume'] as num?)?.round() ?? volume.value).clamp(0, 100);
      muted.value = j['muted'] == true;
    } catch (e) {
      debugPrint('Sounds: volume.json $e');
    }
  }

  static Future<void> _save() async {
    try {
      await _volumeFile.parent.create(recursive: true);
      await _volumeFile.writeAsString(jsonEncode({'volume': volume.value, 'muted': muted.value}), flush: true);
    } catch (e) {
      debugPrint('Sounds: volume.json $e');
    }
  }

  static Future<void> setVolume(int v) async {
    load();
    volume.value = v.clamp(0, 100);
    if (volume.value > 0) muted.value = false;
    await _save();
  }

  static Future<void> setMuted(bool m) async {
    load();
    muted.value = m;
    if (m) stop();
    if (!m && volume.value == 0) volume.value = 50;
    await _save();
  }

  /// Gain appliqué aux échantillons : courbe au carré, plus proche de ce que l'oreille entend.
  static double get gain {
    load();
    if (muted.value) return 0;
    final v = volume.value / 100;
    return v * v;
  }

  static final _cache = <String, Uint8List>{};

  /// Copie du WAV (PCM 16 bits) avec les échantillons multipliés par [gain].
  @visibleForTesting
  static Uint8List scaleWav(Uint8List wav, double gain) {
    final out = Uint8List.fromList(wav);
    final data = ByteData.sublistView(out);
    // Cherche le bloc "data" après l'en-tête RIFF.
    var pos = 12;
    while (pos + 8 <= out.length) {
      final id = String.fromCharCodes(out.sublist(pos, pos + 4));
      final size = data.getUint32(pos + 4, Endian.little);
      if (id == 'data') {
        final end = (pos + 8 + size).clamp(0, out.length);
        for (var i = pos + 8; i + 1 < end; i += 2) {
          final s = (data.getInt16(i, Endian.little) * gain).round().clamp(-32768, 32767);
          data.setInt16(i, s, Endian.little);
        }
        return out;
      }
      pos += 8 + size + (size.isOdd ? 1 : 0);
    }
    return out;
  }

  /// Joue assets/sounds/[name].wav (WAV stéréo 48 kHz) sans attendre. Un son coupe le précédent.
  static Future<void> play(String name) async {
    if (!Platform.isLinux) return;
    final g = gain;
    if (g <= 0) return;
    final path = '$_dir/$name.wav';
    if (!File(path).existsSync()) {
      debugPrint('Sounds: $path introuvable');
      return;
    }
    try {
      _playing?.kill();
      if (g >= 1) {
        _playing = await Process.start('aplay', ['-q', '-D', _device, path]);
        return;
      }
      final raw = _cache[name] ??= await File(path).readAsBytes();
      final p = await Process.start('aplay', ['-q', '-D', _device, '-']);
      _playing = p;
      p.stdin.add(scaleWav(raw, g));
      await p.stdin.close();
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
