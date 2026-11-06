import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:darts_engine/darts_engine.dart';

import '../game_config.dart';
import '../history/history_store.dart';
import '../setup/owner_store.dart';

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

  String get qrPayload => Uri(
    scheme: 'thibsdarts',
    host: 'join',
    queryParameters: {'h': host ?? '127.0.0.1', 'p': '$port', 'c': code},
  ).toString();

  Directory get _photos => Directory('${OwnerStore.instance.dir.path}/players');

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
    final owner = AppState.ownerProfile;
    players.add(
      LobbyPlayer(id: 'owner', name: AppState.owner, host: true, photoPath: owner?.photoPath)
        ..playing = cfg.players.contains(AppState.owner),
    );
    for (final g in cfg.players.where((p) => p != AppState.owner)) {
      players.add(LobbyPlayer(id: 'guest-${players.length}', name: g, guest: true));
    }
    state = LobbyState.open;
    live = null;
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
        return await _send(res, {'device': 'ThibsDarts', 'version': 1, 'setupDone': true, 'owner': AppState.owner});
      }
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
      if (req.method == 'POST' && path == '/api/lobby/leave') {
        final b = await _body(req);
        final p = players.where((p) => p.id == b['id']).firstOrNull;
        if (p != null && !p.host) {
          players.remove(p);
        } else if (p != null) {
          p.connected = false;
        }
        notifyListeners();
        return await _send(res, _json());
      }
      if (seg.length == 4 && seg[0] == 'api' && seg[1] == 'players' && seg[3] == 'photo') {
        final p = players.where((p) => p.id == seg[2]).firstOrNull;
        if (p == null) return await _send(res, {'error': 'joueur'}, status: 404);
        if (req.method == 'PUT') {
          final bytes = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
          if (bytes.length < 1000 || bytes.length > 8 * 1024 * 1024) {
            return await _send(res, {'error': 'photo'}, status: 400);
          }
          await _photos.create(recursive: true);
          final f = File('${_photos.path}/${p.id.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '')}.jpg');
          await f.writeAsBytes(bytes, flush: true);
          // Une photo remplacée doit se redessiner : on vide le cache d'images.
          PaintingBinding.instance.imageCache.clear();
          p.photoPath = f.path;
          notifyListeners();
          return await _send(res, {'ok': true});
        }
        if (req.method == 'GET' && p.photoPath != null) {
          res.headers.contentType = ContentType('image', 'jpeg');
          await res.addStream(File(p.photoPath!).openRead());
          await res.close();
          return;
        }
      }
      return await _send(res, {'error': 'introuvable'}, status: 404);
    } catch (e) {
      try {
        await _send(res, {'error': '$e'}, status: 500);
      } catch (_) {}
    }
  }

  Future<void> _join(HttpRequest req, HttpResponse res) async {
    final b = await _body(req);
    if (state != LobbyState.open) return _send(res, {'error': 'ferme'}, status: 409);
    if ((b['code'] as String? ?? '').toUpperCase() != code) return _send(res, {'error': 'code'}, status: 403);
    final id = (b['id'] as String? ?? '').trim();
    final name = (b['name'] as String? ?? '').trim();
    if (id.isEmpty || name.isEmpty) return _send(res, {'error': 'profil'}, status: 400);

    LobbyPlayer? p;
    if (b['owner'] == true) {
      // L'iPhone du propriétaire rejoint sa propre place d'hôte.
      p = players.firstWhere((p) => p.host);
    } else {
      p = players.where((p) => p.id == id).firstOrNull;
      if (p == null) {
        if (players.length >= maxPlayers) return _send(res, {'error': 'complet'}, status: 410);
        p = LobbyPlayer(id: id, name: _unique(name));
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
