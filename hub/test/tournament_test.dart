import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartos_hub/game_config.dart';
import 'package:dartos_hub/lobby/lobby.dart';
import 'package:dartos_hub/setup/owner_store.dart';
import 'package:dartos_hub/tournament/tournament.dart';
import 'package:flutter_test/flutter_test.dart';

Tournament _with(int n) => Tournament(
  id: 't',
  organizer: 'p0',
  mode: '501',
  legsToWin: 3,
  createdAt: DateTime(2026),
)..entrants.addAll([for (var i = 0; i < n; i++) 'p$i']);

void main() {
  group('tableau', () {
    test('taille et noms des tours', () {
      expect(_with(3).size, 4);
      expect(_with(8).size, 8);
      expect(_with(9).size, 16);
      expect(_with(16).size, 16);
      final t = _with(16)..draw(Random(1));
      expect([for (final r in t.rounds) Tournament.roundName(r.length)], ['8es', 'Quarts', 'Demies', 'Finale']);
    });

    test('chaque joueur est placé une fois, places vides sur des matchs différents', () {
      for (final n in [3, 5, 9, 12, 15]) {
        final t = _with(n)..draw(Random(n));
        final first = t.rounds.first;
        final placed = [for (final m in first) ...[m.a, m.b]].whereType<String>().toList();
        expect(placed.toSet(), t.entrants.toSet(), reason: '$n joueurs');
        expect(placed.length, n);
        expect(first.where((m) => m.a == null).isEmpty, true);
        expect(first.where((m) => m.bye).length, t.size - n);
        // Les qualifiés d'office sont déjà au tour suivant.
        for (final m in first.where((m) => m.bye)) {
          expect(m.winner, m.a);
          final up = t.rounds[1][m.index ~/ 2];
          expect(m.index.isEven ? up.a : up.b, m.a);
        }
      }
    });

    test('un tournoi complet jusqu\'au vainqueur', () {
      final t = _with(11)..draw(Random(7));
      t.state = 'en_cours';
      var guard = 0;
      while (t.next != null && guard++ < 20) {
        expect(t.record(t.next!.id, 3, 1), true);
      }
      expect(t.state, 'fini');
      expect(t.champion, isNotNull);
      expect(t.record(t.rounds.last.first.id, 3, 0), false);
      final copy = Tournament.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, Object?>);
      expect(copy.champion, t.champion);
    });

    test('pas d\'égalité, pas de match incomplet', () {
      final t = _with(4)..draw(Random(2));
      expect(t.record(t.rounds.first.first.id, 2, 2), false);
      expect(t.record(t.rounds.last.first.id, 3, 0), false);
    });
  });

  group('API', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const port = 8433;
    late HttpClient http;

    Future<(int, Map<String, dynamic>)> call(String method, String path, {Object? body, String? token}) async {
      final req = await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
      if (token != null) req.headers.set('authorization', 'Bearer $token');
      if (body != null) req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
    }

    setUpAll(() async {
      HttpOverrides.global = null;
      http = HttpClient();
      OwnerStore.useDirectory(Directory.systemTemp.createTempSync('dartos-tournoi').path);
      AppState.setOwner(const Owner(firstName: 'Thibault', lastName: '', nickname: 'Thibs'));
      await Lobby.instance.serve(port: port);
    });

    tearDownAll(() => Lobby.instance.shutdown());

    test('créer, inscrire, tirer, lancer', () async {
      final keys = <String, String>{};
      final ids = <String, String>{};
      for (final n in ['Max', 'Inès', 'Léo', 'Hugo']) {
        final (s, j) = await call('POST', '/api/players', body: {'nickname': n, 'pin': '1234'});
        expect(s, 200, reason: '$j');
        keys[n] = j['token'] as String;
        ids[n] = (j['player'] as Map)['id'] as String;
      }
      var (s, j) = await call('GET', '/api/tournament');
      expect(j['tournament'], isNull);

      (s, j) = await call('POST', '/api/tournament', body: {'player': ids['Max'], 'mode': '501', 'legsToWin': 3});
      expect(s, 401);
      (s, j) = await call(
        'POST',
        '/api/tournament',
        body: {'player': ids['Max'], 'mode': '501', 'legsToWin': 3},
        token: keys['Max'],
      );
      expect(s, 200);
      expect(j['tournament']['name'], 'Tournoi de Max');
      expect(j['tournament']['entrants'], hasLength(1));

      // Un deuxième tournoi attend la fin du premier.
      (s, _) = await call('POST', '/api/tournament', body: {'player': ids['Inès']}, token: keys['Inès']);
      expect(s, 409);

      (s, _) = await call('POST', '/api/tournament/join', body: {'player': ids['Inès']}, token: keys['Inès']);
      expect(s, 200);
      // Seul l'organisateur ajoute les autres et tire au sort.
      (s, _) = await call(
        'POST',
        '/api/tournament/add',
        body: {'player': ids['Inès'], 'id': ids['Léo']},
        token: keys['Inès'],
      );
      expect(s, 403);
      (s, j) = await call('POST', '/api/tournament/draw', body: {'player': ids['Max']}, token: keys['Max']);
      expect(s, 409);
      expect(j['error'], 'pas_assez');
      for (final n in ['Léo', 'Hugo']) {
        (s, _) = await call(
          'POST',
          '/api/tournament/add',
          body: {'player': ids['Max'], 'id': ids[n]},
          token: keys['Max'],
        );
        expect(s, 200);
      }
      (s, j) = await call(
        'POST',
        '/api/tournament/settings',
        body: {'player': ids['Max'], 'mode': 'cricket', 'legsToWin': 2},
        token: keys['Max'],
      );
      expect(j['tournament']['mode'], 'cricket');
      (s, j) = await call('POST', '/api/tournament/draw', body: {'player': ids['Max']}, token: keys['Max']);
      expect(s, 200);
      final t = j['tournament'] as Map;
      expect(t['state'], 'tirage');
      expect(t['size'], 4);
      expect((t['rounds'] as List).map((r) => r['name']), ['Demies', 'Finale']);

      (s, j) = await call('POST', '/api/tournament/start', body: {'player': ids['Max']}, token: keys['Max']);
      expect(j['tournament']['state'], 'en_cours');
      expect(j['tournament']['next'], '0-0');
      expect(TournamentStore.instance.current?.state, 'en_cours');

      (s, j) = await call('POST', '/api/tournament/cancel', body: {'player': ids['Max']}, token: keys['Max']);
      expect(j['tournament'], isNull);
    });
  });
}
