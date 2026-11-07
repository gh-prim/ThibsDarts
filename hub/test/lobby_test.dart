import 'dart:convert';
import 'dart:io';

import 'package:darts_engine/darts_engine.dart';
import 'package:dartos_hub/game_config.dart';
import 'package:dartos_hub/history/history_store.dart';
import 'package:dartos_hub/lobby/lobby.dart';
import 'package:dartos_hub/players/player_store.dart';
import 'package:dartos_hub/setup/owner_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const port = 8431;
  late HttpClient http;
  final lobby = Lobby.instance;

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, {
    Object? body,
    List<int>? raw,
    String? token,
  }) async {
    final req = await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (token != null) req.headers.set('authorization', 'Bearer $token');
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

  // Profils créés par les tests : surnom vers clé.
  final keys = <String, String>{};
  final ids = <String, String>{};

  Future<void> profile(String name, {String? id}) async {
    final (s, j) = await call(
      'POST',
      '/api/players',
      body: {'nickname': name, 'pin': '4321', 'id': ?id},
    );
    expect(s, 200, reason: 'profil $name');
    keys[name] = j['token'] as String;
    ids[name] = (j['player'] as Map)['id'] as String;
  }

  test('le propriétaire choisit son code puis se reconnecte avec', () async {
    var (s, j) = await call('GET', '/api/hello');
    expect(j['pin'], isFalse, reason: 'cible installée avant le PIN');
    (s, j) = await call('GET', '/api/players');
    expect([for (final p in j['players'] as List) p['nickname']], ['Thibs']);
    (s, j) = await call('POST', '/api/players/owner/login', body: {'pin': '1234'});
    expect(s, 409);
    (s, j) = await call('POST', '/api/players/owner/claim', body: {'pin': '12a4'});
    expect(s, 400);
    (s, j) = await call('POST', '/api/players/owner/claim', body: {'pin': '1234'});
    expect(s, 200);
    keys['Thibs'] = j['token'] as String;
    (s, j) = await call('POST', '/api/players/owner/claim', body: {'pin': '9999'});
    expect(s, 409, reason: 'on ne remplace pas un code existant comme ça');
    (s, j) = await call('GET', '/api/hello');
    expect(j['pin'], isTrue);

    (s, j) = await call('POST', '/api/players/owner/login', body: {'pin': '1234'});
    expect(s, 200);
    expect((j['player'] as Map)['nickname'], 'Thibs');
    expect(j['token'], isNot(keys['Thibs']), reason: 'une clé par iPhone');
    for (var i = 0; i < 5; i++) {
      (s, j) = await call('POST', '/api/players/owner/login', body: {'pin': '0000'});
    }
    expect(s, 429, reason: 'le 5e essai annonce le blocage');
    (s, j) = await call('POST', '/api/players/owner/login', body: {'pin': '1234'});
    expect(s, 429, reason: 'bloqué une minute après 5 erreurs');
  });

  test('chaque joueur a son profil sur la cible', () async {
    var (s, j) = await call('POST', '/api/players', body: {'nickname': 'Max', 'pin': '12'});
    expect(s, 400);
    await profile('Max', id: 'iphone-de-max-1');
    expect(ids['Max'], 'iphone-de-max-1', reason: "l'ancien identifiant de l'iPhone garde ses parties");
    (s, j) = await call('POST', '/api/players', body: {'nickname': 'max', 'pin': '1111'});
    expect(s, 409, reason: 'surnom déjà pris');

    // Un pote sans appli : seul le propriétaire crée son profil, sans code.
    (s, j) = await call('POST', '/api/players', body: {'nickname': 'Lou'});
    expect(s, 401);
    (s, j) = await call('POST', '/api/players', body: {'nickname': 'Lou'}, token: keys['Thibs']);
    expect(s, 200);
    final lou = (j['player'] as Map)['id'] as String;
    expect((j['player'] as Map)['pin'], isFalse);
    (s, j) = await call('POST', '/api/players/$lou/claim', body: {'pin': '2222'});
    expect(s, 200, reason: 'Lou réclame son profil depuis son appli');

    (s, j) = await call('PATCH', '/api/players/${ids['Max']}', body: {'nickname': 'Maxou'});
    expect(s, 401);
    (s, j) = await call('PATCH', '/api/players/${ids['Max']}', body: {'nickname': 'Maxou'}, token: keys['Max']);
    expect(j['nickname'], 'Maxou');
    keys['Maxou'] = keys['Max']!;
    ids['Maxou'] = ids['Max']!;
    (s, j) = await call('PUT', '/api/players/${ids['Max']}/photo', raw: List.filled(4000, 1), token: keys['Max']);
    expect(s, 200);
    expect(PlayerStore.instance.photoPath(ids['Max']!), isNotNull);
    (s, j) = await call('GET', '/api/players');
    expect([for (final p in j['players'] as List) p['nickname']], ['Thibs', 'Maxou', 'Lou']);
  });

  test('un pote rejoint le salon depuis son iPhone', () async {
    lobby.close();
    var (s, j) = await call('GET', '/api/lobby');
    expect(j['state'], 'closed');

    lobby.open(const GameConfig(players: ['Thibs', 'Lou'], startScore: 501, legsToWin: 2));
    expect(lobby.qrPayload, contains('c=${lobby.code}'));
    expect(lobby.players[1].guest, isFalse, reason: 'Lou a un profil');
    (s, j) = await call('GET', '/api/lobby');
    expect(j['label'], '501 · Double sortie · 2 manches gagnantes');

    final max = {'player': ids['Maxou']};
    (s, j) = await call('POST', '/api/lobby/join', body: {'code': 'XXXX', ...max}, token: keys['Maxou']);
    expect(s, 403);
    (s, j) = await call('POST', '/api/lobby/join', body: {'code': lobby.code, ...max}, token: 'faux');
    expect(s, 401, reason: 'pas la bonne clé');
    (s, j) = await call(
      'POST',
      '/api/lobby/join',
      body: {'code': lobby.code.toLowerCase(), ...max},
      token: keys['Maxou'],
    );
    expect(s, 200);
    expect(j['you'], ids['Maxou']);
    await call('POST', '/api/lobby/join', body: {'code': lobby.code, ...max}, token: keys['Maxou']);
    expect(lobby.players.map((p) => p.name), ['Thibs', 'Lou', 'Maxou'], reason: 'pas de doublon');
    expect(lobby.players[2].photoPath, isNotNull);

    // Le propriétaire reprend sa place d'hôte.
    await call('POST', '/api/lobby/join', body: {'code': lobby.code, 'player': 'owner'}, token: keys['Thibs']);
    expect(lobby.players.length, 3);
    expect(lobby.players.first.connected, isTrue);

    lobby.addGuest();
    lobby.reorder(3, 0);
    final cfg = lobby.start();
    expect(cfg.players, ['Invité 1', 'Thibs', 'Lou', 'Maxou']);
    expect(AppState.photos['Maxou'], isNotNull);
    expect(HistoryStore.playerId('Maxou'), ids['Maxou']);
    expect(HistoryStore.playerId('Invité 1'), 'guest:Invité 1');
    (s, j) = await call('POST', '/api/lobby/join', body: {'code': lobby.code, ...max}, token: keys['Maxou']);
    expect(s, 409, reason: 'partie lancée');
  });

  test("un pote crée la partie depuis son iPhone", () async {
    lobby.close();
    lobby.remoteOpen = null;
    final lou = {'player': ids['Maxou'], 'mode': 'cricket'};
    final key = keys['Maxou'];
    var (s, j) = await call('POST', '/api/lobby/create', body: lou, token: key);
    expect(s, 409, reason: "l'accueil du Pi n'est pas à l'écran");
    expect(j['error'], 'occupe');

    GameConfig? shown;
    lobby.remoteOpen = (cfg) {
      shown = cfg;
      return true;
    };
    (s, j) = await call('POST', '/api/lobby/create', body: lou);
    expect(s, 401);
    (s, j) = await call('POST', '/api/lobby/create', body: lou, token: key);
    expect(s, 200);
    expect(shown?.mode, GameMode.cricket);
    expect(j['you'], ids['Maxou']);
    expect(j['state'], 'open');
    expect(lobby.players.firstWhere((p) => p.host).playing, isFalse, reason: 'Thibs ne joue pas par défaut');
    expect(lobby.inGame.map((p) => p.name), ['Maxou']);

    (s, j) = await call('POST', '/api/lobby/create', body: lou, token: key);
    expect(s, 409, reason: 'un salon est déjà ouvert');
    (s, j) = await call('POST', '/api/lobby/leave', body: {'id': ids['Maxou']});
    expect(lobby.state, LobbyState.closed, reason: 'le créateur parti, le salon vide se ferme');
    (s, j) = await call('POST', '/api/lobby/create', body: lou, token: key);
    expect(s, 200);
    lobby.start();
    (s, j) = await call('POST', '/api/lobby/create', body: lou, token: key);
    expect(s, 409, reason: 'une partie est en cours');
    expect(j['error'], 'en_cours');
    lobby.close();
    lobby.remoteOpen = null;
  });

  test('le propriétaire peut regarder sans jouer', () {
    lobby.open(const GameConfig(players: ['Invité 1', 'Invité 2'], startScore: 501));
    final host = lobby.players.firstWhere((p) => p.host);
    expect(host.playing, isFalse, reason: 'pas coché sur Nouvelle partie');
    expect(lobby.start().players, ['Invité 1', 'Invité 2']);
    lobby.close();

    lobby.open(const GameConfig(players: ['Thibs'], startScore: 501));
    expect(lobby.players.single.playing, isTrue);
    lobby.toggleHostPlaying();
    expect(lobby.inGame, isEmpty);
    lobby.toggleHostPlaying();
    expect(lobby.start().players, ['Thibs']);
    lobby.close();
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
