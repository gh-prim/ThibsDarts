import 'dart:convert';
import 'dart:io';

import 'package:dartos_hub/game_config.dart';
import 'package:dartos_hub/history/history_store.dart';
import 'package:dartos_hub/lobby/lobby.dart';
import 'package:dartos_hub/setup/owner_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const port = 8431;
  late HttpClient http;
  final lobby = Lobby.instance;

  Future<(int, Map<String, dynamic>)> call(String method, String path, {Object? body, List<int>? raw}) async {
    final req = await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (raw != null) {
      req.add(raw);
    } else if (body != null) {
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
  }

  setUpAll(() async {
    // Le binding de test bloque le réseau ; ici on parle à un vrai serveur local.
    HttpOverrides.global = null;
    http = HttpClient();
    OwnerStore.useDirectory(Directory.systemTemp.createTempSync('dartos-lobby').path);
    AppState.setOwner(const Owner(firstName: 'Thibault', lastName: '', nickname: 'Thibs'));
    await lobby.serve(port: port);
  });

  tearDownAll(() => lobby.shutdown());

  test('un pote rejoint le salon depuis son iPhone', () async {
    var (s, j) = await call('GET', '/api/lobby');
    expect(j['state'], 'closed');

    lobby.open(const GameConfig(players: ['Thibs'], startScore: 501, legsToWin: 2));
    expect(lobby.qrPayload, contains('c=${lobby.code}'));
    (s, j) = await call('GET', '/api/lobby');
    expect(j['label'], '501 · Double sortie · 2 manches gagnantes');

    (s, j) = await call('POST', '/api/lobby/join', body: {'code': 'XXXX', 'id': 'a', 'name': 'Max'});
    expect(s, 403);
    (s, j) = await call('POST', '/api/lobby/join', body: {'code': lobby.code.toLowerCase(), 'id': 'a', 'name': 'Max'});
    expect(s, 200);
    expect(j['you'], 'a');
    expect(lobby.players.map((p) => p.name), ['Thibs', 'Max']);

    // Même nom : suffixe pour les distinguer. Même id : pas de doublon.
    await call('POST', '/api/lobby/join', body: {'code': lobby.code, 'id': 'b', 'name': 'Max'});
    await call('POST', '/api/lobby/join', body: {'code': lobby.code, 'id': 'b', 'name': 'Max'});
    expect(lobby.players.map((p) => p.name), ['Thibs', 'Max', 'Max 2']);

    // Le propriétaire reprend sa place d'hôte.
    await call('POST', '/api/lobby/join', body: {'code': lobby.code, 'id': 'z', 'name': 'Thibs', 'owner': true});
    expect(lobby.players.length, 3);
    expect(lobby.players.first.connected, isTrue);

    (s, j) = await call('PUT', '/api/players/a/photo', raw: List.filled(4000, 1));
    expect(s, 200);
    expect(lobby.players[1].photoPath, isNotNull);

    (s, j) = await call('POST', '/api/lobby/leave', body: {'id': 'b'});
    expect(lobby.players.length, 2);

    lobby.addGuest();
    lobby.reorder(2, 0);
    final cfg = lobby.start();
    expect(cfg.players, ['Invité 1', 'Thibs', 'Max']);
    expect(AppState.photos['Max'], isNotNull);
    (s, j) = await call('POST', '/api/lobby/join', body: {'code': lobby.code, 'id': 'c', 'name': 'Lou'});
    expect(s, 409, reason: 'partie lancée');
  });

  test("l'historique d'un joueur, sans le détail des tours", () async {
    final store = HistoryStore.instance;
    await store.add({
      'id': '1',
      'at': '2026-11-06T20:00:00',
      'mode': '501',
      'kind': 'x01',
      'winner': 'Thibs',
      'players': [
        {
          'id': 'owner',
          'name': 'Thibs',
          'won': true,
          'darts': 21,
          'turns': [
            {
              'darts': ['T20'],
            },
          ],
        },
        {'id': 'phone-1', 'name': 'Lou', 'won': false, 'darts': 21},
      ],
    });
    await store.add({
      'id': '2',
      'at': '2026-11-06T21:00:00',
      'mode': 'Cricket',
      'kind': 'cricket',
      'winner': 'Max',
      'players': [
        {'id': 'guest:Max', 'name': 'Max', 'won': true},
        {'id': 'phone-1', 'name': 'Lou', 'won': false},
      ],
    });
    var (s, j) = await call('GET', '/api/history?player=phone-1');
    expect(s, 200);
    expect([for (final m in j['matches'] as List) m['id']], ['2', '1'], reason: 'la plus récente d\'abord');
    (s, j) = await call('GET', '/api/history?player=owner');
    final players = (j['matches'] as List).single['players'] as List;
    expect(players.first.containsKey('turns'), isFalse);
    (s, j) = await call('GET', '/api/history/1');
    expect((j['players'] as List).first['turns'], isNotEmpty);
    (s, _) = await call('GET', '/api/history/404');
    expect(s, 404);
    expect(HistoryStore.playerId('Thibs'), 'owner');
    expect(HistoryStore.playerId('Zoé'), 'guest:Zoé');
  });
}
