import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:darts_engine/darts_engine.dart';

import '../game_config.dart';
import '../players/player_store.dart';
import '../setup/owner_store.dart';

/// Un match du tableau. [a] et [b] sont des identifiants de profil ; null : place pas encore connue,
/// ou place vide au premier tour (le joueur en face passe sans jouer).
class TournamentMatch {
  TournamentMatch({required this.round, required this.index, this.a, this.b});

  final int round;
  final int index;
  String? a;
  String? b;
  int scoreA = 0;
  int scoreB = 0;
  String? winner;

  /// Joué sans adversaire (place vide au tirage).
  bool bye = false;

  /// En cours sur la cible.
  bool live = false;

  String get id => '$round-$index';
  bool get done => winner != null;
  bool get ready => !done && a != null && b != null;

  /// attente, pret, direct, fini ou gratuit.
  String get state => bye
      ? 'gratuit'
      : done
      ? 'fini'
      : live
      ? 'direct'
      : ready
      ? 'pret'
      : 'attente';

  Map<String, Object?> toJson() => {
    'round': round,
    'index': index,
    'a': a,
    'b': b,
    'scoreA': scoreA,
    'scoreB': scoreB,
    'winner': winner,
    'bye': bye,
    'live': live,
  };

  static TournamentMatch fromJson(Map<String, Object?> j) =>
      TournamentMatch(round: j['round'] as int, index: j['index'] as int, a: j['a'] as String?, b: j['b'] as String?)
        ..scoreA = j['scoreA'] as int? ?? 0
        ..scoreB = j['scoreB'] as int? ?? 0
        ..winner = j['winner'] as String?
        ..bye = j['bye'] == true
        ..live = j['live'] == true;
}

/// Tournoi à élimination directe, des 8es à la finale (16 joueurs au plus).
///
/// inscriptions : on ajoute les joueurs. tirage : le tableau est tiré, on peut retirer.
/// en_cours : les matchs se jouent sur la cible. fini : il y a un vainqueur.
class Tournament {
  Tournament({
    required this.id,
    required this.organizer,
    required this.mode,
    required this.legsToWin,
    required this.createdAt,
    this.state = 'inscriptions',
  });

  static const maxPlayers = 16;
  static const modes = ['501', '301', 'cricket'];

  final String id;

  /// Profil qui a créé le tournoi : lui seul tire au sort, lance et annule (avec le propriétaire).
  final String organizer;
  String mode;
  int legsToWin;
  String state;
  final DateTime createdAt;
  final List<String> entrants = [];

  /// Invités sans profil, ajoutés à la main par l'organisateur : identifiant vers nom.
  final Map<String, String> guests = {};
  List<List<TournamentMatch>> rounds = [];

  bool get finished => state == 'fini';

  /// Taille du tableau : 2, 4, 8 ou 16 places.
  int get size {
    var s = 2;
    while (s < entrants.length) {
      s *= 2;
    }
    return s;
  }

  static String roundName(int matches) => switch (matches) {
    1 => 'Finale',
    2 => 'Demies',
    4 => 'Quarts',
    _ => '8es',
  };

  /// Nom long pour les annonces : "Demi-finale", "8e de finale".
  static String roundTitle(int matches) => switch (matches) {
    1 => 'Finale',
    2 => 'Demi-finale',
    4 => 'Quart de finale',
    _ => '8e de finale',
  };

  String? get champion => rounds.isEmpty ? null : rounds.last.first.winner;

  /// Prochain match à jouer : le premier prêt, tour par tour.
  TournamentMatch? get next {
    for (final r in rounds) {
      for (final m in r) {
        if (m.ready) return m;
      }
    }
    return null;
  }

  TournamentMatch? match(String id) {
    for (final r in rounds) {
      for (final m in r) {
        if (m.id == id) return m;
      }
    }
    return null;
  }

  /// Tire le tableau au hasard. Les places vides tombent chacune sur un match différent.
  void draw([Random? rnd]) {
    rnd ??= Random.secure();
    final players = [...entrants]..shuffle(rnd);
    final half = size ~/ 2;
    final byes = size - players.length;
    final pairs = <(String?, String?)>[
      for (var k = 0; k < half; k++) k < byes ? (players.removeLast(), null) : (players.removeLast(), players.removeLast()),
    ]..shuffle(rnd);
    rounds = [];
    for (var n = half, r = 0; n >= 1; n ~/= 2, r++) {
      rounds.add([for (var i = 0; i < n; i++) TournamentMatch(round: r, index: i)]);
    }
    for (var i = 0; i < half; i++) {
      rounds.first[i]
        ..a = pairs[i].$1
        ..b = pairs[i].$2;
    }
    for (final m in rounds.first) {
      if (m.b == null) {
        m.bye = true;
        _win(m, m.a!);
      }
    }
    state = 'tirage';
  }

  /// Résultat d'un match en manches gagnées.
  bool record(String matchId, int scoreA, int scoreB) {
    final m = match(matchId);
    if (m == null || !m.ready || scoreA == scoreB) return false;
    m
      ..scoreA = scoreA
      ..scoreB = scoreB
      ..live = false;
    _win(m, scoreA > scoreB ? m.a! : m.b!);
    if (champion != null) state = 'fini';
    return true;
  }

  void _win(TournamentMatch m, String winner) {
    m.winner = winner;
    if (m.round + 1 >= rounds.length) return;
    final up = rounds[m.round + 1][m.index ~/ 2];
    if (m.index.isEven) {
      up.a = winner;
    } else {
      up.b = winner;
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'organizer': organizer,
    'mode': mode,
    'legsToWin': legsToWin,
    'state': state,
    'createdAt': createdAt.toIso8601String(),
    'entrants': entrants,
    'guests': guests,
    'rounds': [
      for (final r in rounds) [for (final m in r) m.toJson()],
    ],
  };

  static Tournament fromJson(Map<String, Object?> j) {
    final t = Tournament(
      id: j['id'] as String,
      organizer: j['organizer'] as String,
      mode: j['mode'] as String? ?? '501',
      legsToWin: j['legsToWin'] as int? ?? 3,
      state: j['state'] as String? ?? 'inscriptions',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
    t.entrants.addAll([for (final e in j['entrants'] as List? ?? const []) e as String]);
    t.guests.addAll({for (final g in (j['guests'] as Map? ?? const {}).entries) g.key as String: g.value as String});
    t.rounds = [
      for (final r in j['rounds'] as List? ?? const [])
        [for (final m in r as List) TournamentMatch.fromJson(m as Map<String, Object?>)],
    ];
    return t;
  }
}

/// Le tournoi en cours sur la cible, gardé dans tournament.json (partition /data sur le Pi).
class TournamentStore extends ChangeNotifier {
  TournamentStore._();

  static final TournamentStore instance = TournamentStore._();

  File get _file => File('${OwnerStore.instance.dir.path}/tournament.json');

  String? _loadedFrom;
  Tournament? _current;

  Tournament? get current {
    final dir = OwnerStore.instance.dir.path;
    if (_loadedFrom != dir) {
      _loadedFrom = dir;
      _current = null;
      try {
        if (_file.existsSync()) {
          _current = Tournament.fromJson(jsonDecode(_file.readAsStringSync()) as Map<String, Object?>);
        }
      } catch (_) {}
    }
    return _current;
  }

  Future<void> set(Tournament? t) async {
    current;
    _current = t;
    await save();
  }

  Future<void> save() async {
    final t = _current;
    if (t == null) {
      if (_file.existsSync()) await _file.delete();
    } else {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode(t.toJson()), flush: true);
    }
    notifyListeners();
  }

  /// Nom affiché d'un joueur du tournoi (profil ou invité).
  String nameOf(String id) => current?.guests[id] ?? PlayerStore.instance.byId(id)?.nickname ?? '?';

  /// Lance un match sur la cible : la partie démarre avec le joueur du haut du tableau.
  GameConfig? startMatch(String matchId) {
    final t = current;
    final m = t?.match(matchId);
    if (t == null || m == null || !m.ready) return null;
    for (final id in [m.a!, m.b!]) {
      final photo = PlayerStore.instance.photoPath(id);
      if (photo != null && !t.guests.containsKey(id)) AppState.photos[nameOf(id)] = photo;
    }
    m.live = true;
    save();
    final x01 = int.tryParse(t.mode);
    return GameConfig(
      players: [nameOf(m.a!), nameOf(m.b!)],
      startScore: x01 ?? 501,
      legsToWin: x01 == null ? 1 : t.legsToWin,
      mode: x01 == null ? GameMode.cricket : null,
      tournamentMatch: matchId,
    );
  }

  /// Fin de la partie d'un match : [legsA] et [legsB] dans l'ordre du tableau. Sans vainqueur
  /// (partie arrêtée, égalité), le match redevient à jouer.
  void endMatch(String matchId, {int? legsA, int? legsB}) {
    final t = current;
    final m = t?.match(matchId);
    if (t == null || m == null) return;
    m.live = false;
    if (legsA != null && legsB != null) t.record(matchId, legsA, legsB);
    save();
  }

  /// Le joueur a gagné son match du tour précédent : "A battu Hugo 3 à 1".
  String? lastWin(String id) {
    final t = current;
    if (t == null) return null;
    TournamentMatch? last;
    for (final r in t.rounds) {
      for (final m in r) {
        if (m.winner == id) last = m;
      }
    }
    if (last == null) return null;
    if (last.bye) return "Qualifié d'office";
    final other = last.a == id ? last.b! : last.a!;
    final (w, l) = last.a == id ? (last.scoreA, last.scoreB) : (last.scoreB, last.scoreA);
    return 'A battu ${nameOf(other)} $w à $l';
  }

  /// Tournoi pour les iPhone et l'Apple TV : noms et photos des joueurs, tours nommés.
  Map<String, Object?>? public() {
    final t = current;
    if (t == null) return null;
    final store = PlayerStore.instance;
    Map<String, Object?>? player(String? id) {
      if (id == null) return null;
      final guest = t.guests[id];
      if (guest != null) return {'id': id, 'name': guest, 'photo': false, 'guest': true};
      final p = store.byId(id);
      return {'id': id, 'name': p?.nickname ?? '?', 'photo': store.photoPath(id) != null};
    }

    final organizer = store.byId(t.organizer);
    return {
      'id': t.id,
      'name': 'Tournoi de ${organizer?.nickname ?? 'la cible'}',
      'organizer': t.organizer,
      'mode': t.mode,
      'legsToWin': t.legsToWin,
      'state': t.state,
      'size': t.size,
      'max': Tournament.maxPlayers,
      'entrants': [for (final e in t.entrants) player(e)],
      'rounds': [
        for (final r in t.rounds)
          {
            'name': Tournament.roundName(r.length),
            'title': Tournament.roundTitle(r.length),
            'matches': [
              for (final m in r)
                {
                  'id': m.id,
                  'a': player(m.a),
                  'b': player(m.b),
                  'scoreA': m.scoreA,
                  'scoreB': m.scoreB,
                  'winner': m.winner,
                  'state': m.state,
                },
            ],
          },
      ],
      'next': t.state == 'en_cours' ? t.next?.id : null,
      'champion': player(t.champion),
    };
  }
}
