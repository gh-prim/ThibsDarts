import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:darts_engine/darts_engine.dart';

import '../game_config.dart';
import '../history/history_store.dart';
import '../players/player_store.dart';
import '../setup/owner_store.dart';
import '../spotify/spotify_link.dart';
import '../tournament/tournament.dart';

/// Un joueur du salon : le propriétaire (hôte), un pote venu avec son iPhone, ou un invité.
class LobbyPlayer {
  LobbyPlayer({required this.id, required this.name, this.host = false, this.guest = false, this.photoPath});

  final String id;
  String name;
  final bool host;
  final bool guest;
  String? photoPath;

  /// Un iPhone est relié à ce joueur (notifications, suivi).
  bool connected = false;

  /// Joue la partie. Le propriétaire peut rester hôte sans jouer et laisser jouer ses potes.
  bool playing = true;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'guest': guest,
    'photo': photoPath != null,
    'connected': connected,
    'playing': playing,
  };
}

enum LobbyState { closed, open, playing }

/// Salon de partie (planche Salon) et petit serveur HTTP pour les iPhone, port 8420.
class Lobby extends ChangeNotifier {
  Lobby._();

  static final Lobby instance = Lobby._();

  static const port = 8420;
  static const maxPlayers = 8;
  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final _rnd = Random.secure();

  LobbyState state = LobbyState.closed;
  GameConfig? config;
  String code = '';
  String? host;
  final List<LobbyPlayer> players = [];

  /// Nom de quelqu'un qui est en train de rejoindre (badge "Lou arrive").
  String? arriving;

  HttpServer? _server;

  /// Partie en direct, pour le suivi sur iPhone (null hors partie).
  Map<String, Object?>? live;

  void publishGame(Map<String, Object?> game) => live = game;

  /// Branché par l'écran de jeu : arrête la partie en cours et revient à l'accueil.
  VoidCallback? stopGame;

  /// Branché par l'accueil du Pi : affiche le salon créé depuis un iPhone.
  /// Renvoie false si l'écran n'est pas libre (menu ou partie en cours).
  bool Function(GameConfig cfg)? remoteOpen;

  /// Salon ouvert depuis un iPhone : il se ferme quand plus personne n'y joue.
  bool openedRemotely = false;

  String get qrPayload => Uri(
    scheme: 'thibsdarts',
    host: 'join',
    queryParameters: {'h': host ?? '127.0.0.1', 'p': '$port', 'c': code},
  ).toString();

  /// Démarre le serveur (une fois, après le setup).
  Future<void> serve({int port = port}) async {
    if (_server != null) return;
    host = await _localAddress();
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      _server!.listen(_handle);
    } catch (e) {
      debugPrint('Lobby: port $port indisponible ($e)');
    }
  }

  Future<void> shutdown() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Ouvre un salon avec les réglages choisis sur "Nouvelle partie".
  void open(GameConfig cfg) {
    config = cfg;
    code = List.generate(4, (_) => _codeAlphabet[_rnd.nextInt(_codeAlphabet.length)]).join();
    players.clear();
    final store = PlayerStore.instance;
    players.add(
      LobbyPlayer(id: 'owner', name: AppState.owner, host: true, photoPath: store.photoPath('owner'))
        ..playing = cfg.players.contains(AppState.owner),
    );
    for (final name in cfg.players.where((p) => p != AppState.owner)) {
      // Un profil de la cible garde son identifiant, un invité n'a qu'un nom pour cette partie.
      final prof = store.byName(name);
      players.add(
        prof == null
            ? LobbyPlayer(id: 'guest-${players.length}', name: name, guest: true)
            : LobbyPlayer(id: prof.id, name: prof.nickname, photoPath: store.photoPath(prof.id)),
      );
    }
    state = LobbyState.open;
    openedRemotely = false;
    live = null;
    notifyListeners();
  }

  /// Match de tournoi lancé sur la cible : pas de salon, mais la partie est suivie en direct
  /// (Apple TV, iPhone) comme une partie de salon.
  void playTournament(GameConfig cfg) {
    config = cfg;
    code = '';
    players.clear();
    final store = PlayerStore.instance;
    for (final name in cfg.players) {
      final prof = store.byName(name);
      players.add(
        prof == null
            ? LobbyPlayer(id: 'guest-${players.length}', name: name, guest: true)
            : LobbyPlayer(id: prof.id, name: name, host: prof.owner, photoPath: store.photoPath(prof.id)),
      );
    }
    state = LobbyState.playing;
    openedRemotely = false;
    live = null;
    arriving = null;
    notifyListeners();
  }

  void close() {
    state = LobbyState.closed;
    live = null;
    arriving = null;
    notifyListeners();
  }

  void addGuest() {
    if (players.length >= maxPlayers) return;
    final n = players.where((p) => p.guest).length + 1;
    players.add(LobbyPlayer(id: 'guest-${DateTime.now().microsecondsSinceEpoch}', name: 'Invité $n', guest: true));
    notifyListeners();
  }

  void remove(LobbyPlayer p) {
    if (p.host) return;
    players.remove(p);
    notifyListeners();
  }

  /// Le propriétaire joue ou regarde.
  void toggleHostPlaying() {
    final h = players.where((p) => p.host).firstOrNull;
    if (h == null) return;
    h.playing = !h.playing;
    notifyListeners();
  }

  /// Joueurs qui jouent vraiment, dans l'ordre de passage.
  List<LobbyPlayer> get inGame => [
    for (final p in players)
      if (p.playing) p,
  ];

  void reorder(int from, int to) {
    final p = players.removeAt(from);
    players.insert(to.clamp(0, players.length), p);
    notifyListeners();
  }

  /// Lance la partie : la config prend l'ordre et les noms du salon.
  GameConfig start() {
    final cfg = config!;
    for (final p in players) {
      if (p.photoPath != null) AppState.photos[p.name] = p.photoPath!;
    }
    final started = cfg.withPlayers([for (final p in inGame) p.name]);
    config = started;
    state = LobbyState.playing;
    notifyListeners();
    return started;
  }

  String get label {
    final c = config;
    if (c == null) return '';
    if (c.mode != null) {
      return switch (c.mode!) {
        GameMode.cricket => 'Cricket · 20 à 15 et bull',
        GameMode.clock => 'Around the clock · De 1 à 20',
        GameMode.shanghai => 'Shanghai · 7 manches',
        GameMode.killer => 'Killer · 3 vies',
        GameMode.halveIt => 'Halve-it · 9 manches',
        GameMode.bobs27 => "Bob's 27 · D1 à D20 puis bull",
      };
    }
    final out = c.doubleOut ? 'Double sortie' : 'Sortie simple';
    final legs = c.legsToWin == 1 ? '1 manche' : '${c.legsToWin} manches gagnantes';
    return '${c.startScore} · $out · $legs';
  }

  Map<String, Object?> _json() => {
    'state': state.name,
    'code': state == LobbyState.closed ? null : code,
    'hostName': AppState.owner,
    'label': label,
    'players': players.map((p) => p.toJson()).toList(),
    'game': state == LobbyState.playing ? live : null,
  };

  // MARK: HTTP

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;
    try {
      final seg = req.uri.pathSegments;
      final path = req.uri.path;
      if (req.method == 'GET' && (path == '/api/hello' || path == '/api/setup/hello')) {
        return await _send(res, {
          'device': 'ThibsDarts',
          'version': 1,
          'setupDone': true,
          'owner': AppState.owner,
          'pin': PlayerStore.instance.owner?.hasPin ?? false,
        });
      }
      if (path == '/api/players' || path.startsWith('/api/players/')) return await _playersRoute(req, res, seg);
      if (req.method == 'GET' && path == '/api/lobby') return await _send(res, _json());
      if (req.method == 'GET' && path == '/api/history') {
        final id = req.uri.queryParameters['player'];
        final all = id == null ? HistoryStore.instance.all() : HistoryStore.instance.forPlayer(id);
        return await _send(res, {'matches': all});
      }
      if (req.method == 'GET' && seg.length == 3 && seg[0] == 'api' && seg[1] == 'history') {
        final m = HistoryStore.instance.byId(seg[2]);
        if (m == null) return await _send(res, {'error': 'partie'}, status: 404);
        return await _send(res, m);
      }
      if (req.method == 'POST' && path == '/api/lobby/join') return await _join(req, res);
      if (req.method == 'POST' && path == '/api/lobby/create') return await _create(req, res);
      if (path == '/api/spotify' || path.startsWith('/api/spotify/')) return await _spotifyRoute(req, res, seg);
      if (path == '/api/tournament' || path.startsWith('/api/tournament/')) return await _tournamentRoute(req, res, seg);
      if (req.method == 'POST' && path == '/api/lobby/stop') {
        // Un joueur du salon arrête la partie depuis son iPhone (confirmé dans l'app).
        final b = await _body(req);
        if (!players.any((p) => p.id == b['id'])) return await _send(res, {'error': 'joueur'}, status: 403);
        if (state != LobbyState.playing || stopGame == null) return await _send(res, {'error': 'partie'}, status: 409);
        stopGame!();
        return await _send(res, _json());
      }
      if (req.method == 'POST' && path == '/api/lobby/leave') {
        final b = await _body(req);
        final p = players.where((p) => p.id == b['id']).firstOrNull;
        if (p != null && !p.host) {
          players.remove(p);
        } else if (p != null) {
          p.connected = false;
        }
        if (state == LobbyState.open && openedRemotely && inGame.isEmpty && !players.any((p) => p.connected)) {
          close();
        }
        notifyListeners();
        return await _send(res, _json());
      }
      return await _send(res, {'error': 'introuvable'}, status: 404);
    } catch (e) {
      try {
        await _send(res, {'error': '$e'}, status: 500);
      } catch (_) {}
    }
  }

  /// Mini player Spotify : lecture et commandes ouvertes au Wi-Fi de la maison (Apple TV),
  /// liaison du compte réservée au propriétaire.
  Future<void> _spotifyRoute(HttpRequest req, HttpResponse res, List<String> seg) async {
    final spotify = SpotifyLink.instance;
    final action = seg.length > 2 ? seg[2] : null;
    if (req.method == 'GET' && action == null) return _send(res, await spotify.nowPlaying());
    if (action == 'link') {
      if (!_authorized(req, PlayerStore.instance.owner)) return _send(res, {'error': 'cle'}, status: 401);
      if (req.method == 'DELETE') {
        await spotify.unlink();
        return _send(res, {'linked': false});
      }
      final b = await _body(req);
      final client = b['clientId'] as String?;
      final refresh = b['refreshToken'] as String?;
      if (client == null || refresh == null) return _send(res, {'error': 'spotify'}, status: 400);
      await spotify.link(client, refresh);
      return _send(res, await spotify.nowPlaying());
    }
    if (req.method == 'POST' && action != null) {
      if (!await spotify.control(action)) return _send(res, {'error': 'spotify'}, status: 409);
      return _send(res, {'ok': true});
    }
    return _send(res, {'error': 'introuvable'}, status: 404);
  }

  /// Tournoi : création et inscriptions depuis les iPhone, tirage et lancement par l'organisateur.
  Future<void> _tournamentRoute(HttpRequest req, HttpResponse res, List<String> seg) async {
    final tournaments = TournamentStore.instance;
    final action = seg.length > 2 ? seg[2] : null;
    Future<void> reply() => _send(res, {'tournament': tournaments.public()});
    if (req.method == 'GET' && action == null) return reply();
    if (req.method != 'POST') return _send(res, {'error': 'introuvable'}, status: 404);
    final b = await _body(req);
    final store = PlayerStore.instance;
    final me = store.byId(b['player'] as String?);
    if (!_authorized(req, me)) return _send(res, {'error': 'cle'}, status: 401);
    var t = tournaments.current;
    if (action == null) {
      if (t != null && !t.finished) return _send(res, {'error': 'en_cours'}, status: 409);
      final mode = b['mode'] as String? ?? '501';
      if (!Tournament.modes.contains(mode)) return _send(res, {'error': 'mode'}, status: 400);
      t = Tournament(
        id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
        organizer: me!.id,
        mode: mode,
        // Le Cricket se joue en une manche.
        legsToWin: mode == 'cricket' ? 1 : ((b['legsToWin'] as num?)?.toInt() ?? 3).clamp(1, 5),
        createdAt: DateTime.now(),
      )..entrants.add(me.id);
      await tournaments.set(t);
      return reply();
    }
    if (t == null) return _send(res, {'error': 'aucun'}, status: 404);
    final boss = me!.id == t.organizer || me.owner;
    switch (action) {
      case 'settings':
        if (!boss) return _send(res, {'error': 'organisateur'}, status: 403);
        if (t.state != 'inscriptions') return _send(res, {'error': 'tire'}, status: 409);
        final mode = b['mode'] as String? ?? t.mode;
        if (!Tournament.modes.contains(mode)) return _send(res, {'error': 'mode'}, status: 400);
        t
          ..mode = mode
          ..legsToWin = mode == 'cricket' ? 1 : ((b['legsToWin'] as num?)?.toInt() ?? t.legsToWin).clamp(1, 5);
      case 'join' || 'add':
        final who = action == 'join' ? me : store.byId(b['id'] as String?);
        if (who == null) return _send(res, {'error': 'joueur'}, status: 404);
        if (action == 'add' && !boss) return _send(res, {'error': 'organisateur'}, status: 403);
        if (t.state != 'inscriptions') return _send(res, {'error': 'tire'}, status: 409);
        if (!t.entrants.contains(who.id)) {
          if (t.entrants.length >= Tournament.maxPlayers) return _send(res, {'error': 'complet'}, status: 410);
          t.entrants.add(who.id);
        }
      case 'guest':
        // Un pote sans profil : juste un nom, pour ce tournoi.
        if (!boss) return _send(res, {'error': 'organisateur'}, status: 403);
        if (t.state != 'inscriptions') return _send(res, {'error': 'tire'}, status: 409);
        final name = (b['name'] as String? ?? '').trim();
        if (name.isEmpty || name.length > 20) return _send(res, {'error': 'nom'}, status: 400);
        final taken = [
          ...t.guests.values,
          for (final e in t.entrants) store.byId(e)?.nickname ?? '',
        ].any((n) => n.toLowerCase() == name.toLowerCase());
        if (taken) return _send(res, {'error': 'pris'}, status: 409);
        if (t.entrants.length >= Tournament.maxPlayers) return _send(res, {'error': 'complet'}, status: 410);
        final id = 'invite-${DateTime.now().microsecondsSinceEpoch}';
        t.guests[id] = name;
        t.entrants.add(id);
      case 'remove':
        final id = b['id'] as String? ?? me.id;
        if (id != me.id && !boss) return _send(res, {'error': 'organisateur'}, status: 403);
        if (t.state != 'inscriptions') return _send(res, {'error': 'tire'}, status: 409);
        t.entrants.remove(id);
        t.guests.remove(id);
      case 'draw':
        if (!boss) return _send(res, {'error': 'organisateur'}, status: 403);
        if (t.state != 'inscriptions' && t.state != 'tirage') return _send(res, {'error': 'lance'}, status: 409);
        if (t.entrants.length < 3) return _send(res, {'error': 'pas_assez'}, status: 409);
        t.draw();
      case 'redo':
        // Retour aux inscriptions après un tirage (quelqu'un arrive en retard).
        if (!boss) return _send(res, {'error': 'organisateur'}, status: 403);
        if (t.state != 'tirage') return _send(res, {'error': 'lance'}, status: 409);
        t
          ..rounds = []
          ..state = 'inscriptions';
      case 'start':
        if (!boss) return _send(res, {'error': 'organisateur'}, status: 403);
        if (t.state != 'tirage') return _send(res, {'error': 'pas_tire'}, status: 409);
        t.state = 'en_cours';
      case 'cancel':
        if (!boss) return _send(res, {'error': 'organisateur'}, status: 403);
        await tournaments.set(null);
        return reply();
      default:
        return _send(res, {'error': 'introuvable'}, status: 404);
    }
    await tournaments.save();
    return reply();
  }

  final Map<String, (int, DateTime?)> _fails = {};

  /// Profils de la cible : liste, création, connexion avec le code, surnom et photo.
  Future<void> _playersRoute(HttpRequest req, HttpResponse res, List<String> seg) async {
    final store = PlayerStore.instance;
    if (AppState.ownerProfile == null) return _send(res, {'error': 'setup'}, status: 409);
    if (seg.length == 2) {
      if (req.method == 'GET') return _send(res, {'players': store.all.map(store.public).toList()});
      if (req.method == 'POST') return _createProfile(req, res);
      return _send(res, {'error': 'introuvable'}, status: 404);
    }
    final p = store.byId(seg[2]);
    if (p == null) return _send(res, {'error': 'joueur'}, status: 404);
    final action = seg.length > 3 ? seg[3] : null;
    if (action == 'photo') {
      if (req.method == 'GET') {
        final f = store.photoFile(p.id);
        if (!f.existsSync()) return _send(res, {'error': 'photo'}, status: 404);
        res.headers.contentType = ContentType('image', 'jpeg');
        await res.addStream(f.openRead());
        await res.close();
        return;
      }
      if (req.method == 'PUT') {
        if (!_authorized(req, p)) return _send(res, {'error': 'cle'}, status: 401);
        final bytes = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        if (bytes.length < 1000 || bytes.length > 8 * 1024 * 1024) {
          return _send(res, {'error': 'photo'}, status: 400);
        }
        final f = store.photoFile(p.id);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(bytes, flush: true);
        // Une photo remplacée doit se redessiner : on vide le cache d'images.
        PaintingBinding.instance.imageCache.clear();
        for (final lp in players.where((lp) => lp.id == p.id)) {
          lp.photoPath = f.path;
        }
        notifyListeners();
        return _send(res, {'ok': true});
      }
    }
    if (req.method == 'GET' && action == null) return _send(res, store.public(p));
    if (req.method == 'PATCH' && action == null) {
      if (!_authorized(req, p)) return _send(res, {'error': 'cle'}, status: 401);
      final b = await _body(req);
      final name = (b['nickname'] as String? ?? '').trim();
      if (name.isEmpty || name.length > 20) return _send(res, {'error': 'surnom'}, status: 400);
      final other = store.byName(name);
      if (other != null && other.id != p.id) return _send(res, {'error': 'pris'}, status: 409);
      p.nickname = name;
      await store.save();
      if (p.owner) await _renameOwner(name);
      return _send(res, store.public(p));
    }
    if (req.method != 'POST') return _send(res, {'error': 'introuvable'}, status: 404);
    final b = await _body(req);
    final pin = b['pin'] as String?;
    if (!Profile.validPin(pin)) return _send(res, {'error': 'pin'}, status: 400);
    switch (action) {
      case 'claim':
        // Profil sans code (pote sans appli, vieille cible) : le premier code choisi devient le sien.
        if (p.hasPin) return _send(res, {'error': 'deja'}, status: 409);
        p.setPin(pin!);
        final token = p.issueToken();
        await store.save();
        return _send(res, {'token': token, 'player': store.public(p)});
      case 'login':
        if (!p.hasPin) return _send(res, {'error': 'pas_de_pin'}, status: 409);
        final now = DateTime.now();
        final (fails, until) = _fails[p.id] ?? (0, null);
        if (until != null && now.isBefore(until)) {
          return _send(res, {'error': 'bloque', 'wait': until.difference(now).inSeconds + 1}, status: 429);
        }
        if (!p.checkPin(pin!)) {
          if (fails + 1 >= 5) {
            _fails[p.id] = (0, now.add(const Duration(minutes: 1)));
            return _send(res, {'error': 'bloque', 'wait': 60}, status: 429);
          }
          _fails[p.id] = (fails + 1, null);
          return _send(res, {'error': 'pin', 'left': 4 - fails}, status: 403);
        }
        _fails.remove(p.id);
        final token = p.issueToken();
        await store.save();
        return _send(res, {'token': token, 'player': store.public(p)});
    }
    return _send(res, {'error': 'introuvable'}, status: 404);
  }

  /// Nouveau profil depuis un iPhone : surnom et code. Le propriétaire peut aussi créer
  /// le profil d'un pote sans appli, sans code.
  Future<void> _createProfile(HttpRequest req, HttpResponse res) async {
    final store = PlayerStore.instance;
    final b = await _body(req);
    final name = (b['nickname'] as String? ?? '').trim();
    final pin = b['pin'] as String?;
    if (name.isEmpty || name.length > 20) return _send(res, {'error': 'surnom'}, status: 400);
    if (store.byName(name) != null) return _send(res, {'error': 'pris'}, status: 409);
    if (pin == null) {
      if (!_authorized(req, store.owner)) return _send(res, {'error': 'cle'}, status: 401);
      final p = await store.create(name);
      return _send(res, {'player': store.public(p)});
    }
    if (!Profile.validPin(pin)) return _send(res, {'error': 'pin'}, status: 400);
    final p = await store.create(name, pin: pin, id: b['id'] as String?);
    final token = p.issueToken();
    await store.save();
    return _send(res, {'token': token, 'player': store.public(p)});
  }

  /// La clé de l'iPhone, dans l'en-tête Authorization: Bearer suivi de la clé.
  static String? _token(HttpRequest req) {
    final h = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    return h.startsWith('Bearer ') ? h.substring(7).trim() : null;
  }

  static bool _authorized(HttpRequest req, Profile? p) => p != null && p.checkToken(_token(req));

  Future<void> _renameOwner(String name) async {
    final o = AppState.ownerProfile;
    if (o == null) return;
    final renamed = Owner(
      firstName: o.firstName,
      lastName: o.lastName,
      nickname: name,
      photoPath: o.photoPath,
      pinSalt: o.pinSalt,
      pinHash: o.pinHash,
    );
    final old = AppState.owner;
    AppState.setOwner(await OwnerStore.instance.write(renamed));
    AppState.photos.remove(old);
    for (final lp in players.where((lp) => lp.host)) {
      lp.name = AppState.owner;
    }
    notifyListeners();
  }

  /// Un iPhone sur le même Wi-Fi crée la partie : le salon s'ouvre sur le Pi et il est dedans.
  Future<void> _create(HttpRequest req, HttpResponse res) async {
    final b = await _body(req);
    final me = PlayerStore.instance.byId(b['player'] as String?);
    if (!_authorized(req, me)) return _send(res, {'error': 'cle'}, status: 401);
    if (state == LobbyState.playing) return _send(res, {'error': 'en_cours'}, status: 409);
    if (state != LobbyState.closed) return _send(res, {'error': 'ouvert'}, status: 409);
    final m = b['mode'] as String? ?? '501';
    final x01 = int.tryParse(m);
    final mode = x01 == null ? GameMode.values.where((g) => g.name == m).firstOrNull : null;
    if (x01 == null && mode == null) return _send(res, {'error': 'mode'}, status: 400);
    final cfg = GameConfig(
      players: me!.owner ? [AppState.owner] : const [],
      startScore: x01 ?? 501,
      doubleOut: b['doubleOut'] as bool? ?? true,
      legsToWin: x01 == null ? 1 : ((b['legsToWin'] as num?)?.toInt() ?? 1).clamp(1, 5),
      mode: mode,
    );
    if (remoteOpen?.call(cfg) != true) return _send(res, {'error': 'occupe'}, status: 409);
    open(cfg);
    openedRemotely = true;
    return _enter(me, res);
  }

  Future<void> _join(HttpRequest req, HttpResponse res) async {
    final b = await _body(req);
    if (state != LobbyState.open) return _send(res, {'error': 'ferme'}, status: 409);
    if ((b['code'] as String? ?? '').toUpperCase() != code) return _send(res, {'error': 'code'}, status: 403);
    final me = PlayerStore.instance.byId(b['player'] as String?);
    if (!_authorized(req, me)) return _send(res, {'error': 'cle'}, status: 401);
    return _enter(me!, res);
  }

  /// Place le joueur de cet iPhone dans le salon ouvert.
  Future<void> _enter(Profile me, HttpResponse res) async {
    LobbyPlayer? p;
    if (me.owner) {
      // L'iPhone du propriétaire rejoint sa propre place d'hôte.
      p = players.firstWhere((p) => p.host);
    } else {
      p = players.where((p) => p.id == me.id).firstOrNull;
      if (p == null) {
        if (players.length >= maxPlayers) return _send(res, {'error': 'complet'}, status: 410);
        p = LobbyPlayer(id: me.id, name: _unique(me.nickname), photoPath: PlayerStore.instance.photoPath(me.id));
        players.add(p);
        arriving = p.name;
        // Le badge "arrive" reste le temps que la photo monte.
        Timer(const Duration(seconds: 3), () {
          if (arriving == p!.name) {
            arriving = null;
            notifyListeners();
          }
        });
      }
    }
    p.connected = true;
    notifyListeners();
    return _send(res, {'you': p.id, ..._json()});
  }

  String _unique(String name) {
    var n = name;
    var i = 2;
    while (players.any((p) => p.name == n)) {
      n = '$name $i';
      i++;
    }
    return n;
  }

  static Future<Map<String, Object?>> _body(HttpRequest req) async {
    final text = await utf8.decoder.bind(req).join();
    if (text.isEmpty) return {};
    return jsonDecode(text) as Map<String, Object?>;
  }

  static Future<void> _send(HttpResponse res, Object body, {int status = 200}) async {
    res.statusCode = status;
    res.write(jsonEncode(body));
    await res.close();
  }

  static Future<String?> _localAddress() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final all = [for (final i in ifs) ...i.addresses.map((a) => a.address)];
      return all.firstWhere(
        (a) => a.startsWith('192.168.') || a.startsWith('10.') || a.startsWith('172.'),
        orElse: () => all.isEmpty ? '127.0.0.1' : all.first,
      );
    } catch (_) {
      return null;
    }
  }
}
