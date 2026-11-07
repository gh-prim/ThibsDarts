import 'dart:convert';
import 'dart:io';

import '../game_config.dart';
import '../lobby/lobby.dart';
import '../setup/owner_store.dart';

/// Parties terminées, une ligne JSON par partie dans history.jsonl (partition /data sur le Pi).
///
/// Une partie : id, at (ISO 8601), mode ("501", "Cricket"), kind ("x01" ou le mode),
/// winner, et players : id, name, won, darts, plus les stats du mode
/// (X01 : scored, best, tries, hits, turns ; autres : score, value, valueLabel).
class HistoryStore {
  HistoryStore._();

  static final HistoryStore instance = HistoryStore._();

  File get _file => File('${OwnerStore.instance.dir.path}/history.jsonl');

  /// Identifiant stable d'un joueur : son iPhone, "owner" pour le propriétaire, sinon son nom.
  static String playerId(String name) {
    final lobby = Lobby.instance;
    if (lobby.state != LobbyState.closed) {
      final p = lobby.players.where((p) => p.name == name).firstOrNull;
      if (p != null && !p.guest) return p.host ? 'owner' : p.id;
    }
    if (name == AppState.owner) return 'owner';
    return 'guest:$name';
  }

  Future<void> add(Map<String, Object?> match) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString('${jsonEncode(match)}\n', mode: FileMode.append, flush: true);
  }

  /// Toutes les parties, la plus récente d'abord.
  List<Map<String, Object?>> all() {
    try {
      if (!_file.existsSync()) return [];
      final out = <Map<String, Object?>>[];
      for (final line in _file.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        try {
          out.add(jsonDecode(line) as Map<String, Object?>);
        } catch (_) {}
      }
      return out.reversed.toList();
    } catch (_) {
      return [];
    }
  }

  /// Parties d'un joueur, sans le détail des tours.
  List<Map<String, Object?>> forPlayer(String id) => [
    for (final m in all())
      if ((m['players'] as List).any((p) => (p as Map)['id'] == id))
        {
          ...m,
          'players': [
            for (final p in m['players'] as List) {...(p as Map<String, Object?>)}..remove('turns'),
          ],
        },
  ];

  Map<String, Object?>? byId(String id) => all().where((m) => m['id'] == id).firstOrNull;
}
