import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/foundation.dart';

import '../game_config.dart';
import '../screens/correction_screen.dart';
import '../setup/owner_store.dart';

/// Partie mise en pause : la config, la graine du hasard et tout ce qui s'est passé (fléchettes,
/// corrections, fins de tour). Gardée dans paused.json du dossier de données : elle survit à un
/// redémarrage et à une mise à jour. On la reprend en rejouant le journal.
class PausedGame {
  PausedGame({required this.config, required this.seed, required this.log, DateTime? at})
    : at = at ?? DateTime.now();

  final GameConfig config;
  final int seed;
  final List<Map<String, Object?>> log;
  final DateTime at;

  static File get _file => File('${OwnerStore.instance.dir.path}/paused.json');

  /// Prévient l'accueil quand une partie est mise en pause ou reprise.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static PausedGame? load() {
    try {
      if (!_file.existsSync()) return null;
      final j = jsonDecode(_file.readAsStringSync()) as Map<String, Object?>;
      return PausedGame(
        config: GameConfig.fromJson(j['config'] as Map<String, Object?>),
        seed: j['seed'] as int,
        log: [for (final e in j['log'] as List) Map<String, Object?>.from(e as Map)],
        at: DateTime.tryParse(j['at'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  void save() {
    final f = _file;
    f.parent.createSync(recursive: true);
    final tmp = File('${f.path}.tmp');
    tmp.writeAsStringSync(
      jsonEncode({'config': config.toJson(), 'seed': seed, 'log': log, 'at': at.toIso8601String()}),
      flush: true,
    );
    tmp.renameSync(f.path);
    changed.value++;
  }

  static void clear() {
    try {
      if (_file.existsSync()) _file.deleteSync();
    } catch (_) {}
    changed.value++;
  }

  static int newSeed() => math.Random().nextInt(1 << 31);
}

/// Journal d'une partie, pour la mettre en pause puis la rejouer à l'identique.
class GameLog {
  GameLog({int? seed, this.replayLog}) : seed = seed ?? PausedGame.newSeed();

  final int seed;
  late final math.Random random = math.Random(seed);
  final List<Map<String, Object?>> entries = [];
  /// Journal de la partie reprise, rejoué par [replay].
  final List<Map<String, Object?>>? replayLog;

  /// Vrai pendant qu'on rejoue une partie reprise : pas d'animation, pas de message au Pi 5.
  bool replaying = false;

  static Map<String, Object?> dart(String t, DartThrow d, {double? x, double? y, Map<String, Object?>? more}) => {
    't': t,
    's': d.sector,
    'm': d.multiplier,
    'x': ?x,
    'y': ?y,
    ...?more,
  };

  static DartThrow dartOf(Map<String, Object?> e) => DartThrow(e['s'] as int, e['m'] as int);

  static Offset? offsetOf(Map<String, Object?> e) =>
      e['x'] == null ? null : Offset((e['x'] as num).toDouble(), (e['y'] as num).toDouble());

  static Map<String, Object?> correction(Correction c) =>
      dart('c', c.dart, x: c.position?.dx, y: c.position?.dy, more: {'i': c.index});

  /// Fléchette [index] du tour retirée (coup fantôme, annulation).
  static Map<String, Object?> removal(int index) => {'t': 'u', 'i': index};

  static Correction correctionOf(Map<String, Object?> e) =>
      Correction(e['i'] as int, dartOf(e), position: offsetOf(e));

  void add(Map<String, Object?> e) {
    if (!replaying) entries.add(e);
  }

  /// Rejoue le journal d'une partie reprise, une entrée à la fois.
  void replay(void Function(Map<String, Object?> e) apply) {
    final r = replayLog;
    if (r == null) return;
    replaying = true;
    try {
      for (final e in r) {
        entries.add(e);
        apply(e);
      }
    } finally {
      replaying = false;
    }
  }

  void pause(GameConfig config) => PausedGame(config: config, seed: seed, log: entries).save();
}
