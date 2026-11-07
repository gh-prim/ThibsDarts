import 'dart:convert';
import 'dart:io';

import '../setup/owner_store.dart';

/// Compte Spotify du propriétaire, relié depuis son iPhone (PKCE, sans secret).
/// Le Pi garde le jeton de rafraîchissement et sert le mini player à l'Apple TV.
class SpotifyLink {
  SpotifyLink._();

  static final SpotifyLink instance = SpotifyLink._();

  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  String? _clientId;
  String? _refresh;
  String? _access;
  DateTime _expires = DateTime(0);
  bool _loaded = false;

  File get _file => File('${OwnerStore.instance.dir.path}/spotify.json');

  bool get linked {
    _load();
    return _clientId != null && _refresh != null;
  }

  void _load() {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!_file.existsSync()) return;
      final j = jsonDecode(_file.readAsStringSync()) as Map<String, Object?>;
      _clientId = j['clientId'] as String?;
      _refresh = j['refreshToken'] as String?;
    } catch (_) {}
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode({'clientId': _clientId, 'refreshToken': _refresh}), flush: true);
  }

  Future<void> link(String clientId, String refreshToken) async {
    _loaded = true;
    _clientId = clientId;
    _refresh = refreshToken;
    _access = null;
    await _save();
  }

  Future<void> unlink() async {
    _loaded = true;
    _clientId = _refresh = _access = null;
    if (_file.existsSync()) await _file.delete();
  }

  Future<String?> _token() async {
    if (!linked) return null;
    if (_access != null && DateTime.now().isBefore(_expires)) return _access;
    final req = await _http.postUrl(Uri.parse('https://accounts.spotify.com/api/token'));
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    req.write(
      Uri(queryParameters: {'grant_type': 'refresh_token', 'refresh_token': _refresh!, 'client_id': _clientId!}).query,
    );
    final res = await req.close();
    final body = await utf8.decoder.bind(res).join();
    if (res.statusCode != 200) {
      // Accès retiré côté Spotify : il faudra relier le compte depuis l'iPhone.
      if (res.statusCode == 400) await unlink();
      return null;
    }
    final j = jsonDecode(body) as Map<String, Object?>;
    _access = j['access_token'] as String?;
    _expires = DateTime.now().add(Duration(seconds: ((j['expires_in'] as num?) ?? 3600).toInt() - 60));
    final rotated = j['refresh_token'] as String?;
    if (rotated != null && rotated != _refresh) {
      _refresh = rotated;
      await _save();
    }
    return _access;
  }

  Future<(int, String)> _api(String method, String path) async {
    final token = await _token();
    if (token == null) return (401, '');
    final req = await _http.openUrl(method, Uri.parse('https://api.spotify.com/v1$path'));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (method != 'GET') req.contentLength = 0;
    final res = await req.close();
    return (res.statusCode, await utf8.decoder.bind(res).join());
  }

  /// Ce qui joue sur le compte, quel que soit l'appareil.
  Future<Map<String, Object?>> nowPlaying() async {
    if (!linked) return {'linked': false};
    final (status, body) = await _api('GET', '/me/player?additional_types=episode');
    if (status != 200 || body.isEmpty) return {'linked': linked, 'active': false};
    final j = jsonDecode(body) as Map<String, Object?>;
    final item = j['item'] as Map<String, Object?>?;
    if (item == null) return {'linked': true, 'active': false};
    final album = item['album'] as Map<String, Object?>? ?? item['show'] as Map<String, Object?>?;
    final images = (album?['images'] as List?)?.cast<Map<String, Object?>>() ?? const [];
    final artists = (item['artists'] as List?)?.cast<Map<String, Object?>>() ?? const [];
    return {
      'linked': true,
      'active': true,
      'playing': j['is_playing'] == true,
      'title': item['name'],
      'artist': artists.isNotEmpty ? artists.map((a) => a['name']).join(', ') : album?['name'],
      'art': images.isNotEmpty ? images.first['url'] : null,
      'progressMs': j['progress_ms'],
      'durationMs': item['duration_ms'],
      'device': (j['device'] as Map<String, Object?>?)?['name'],
    };
  }

  /// play, pause, next, previous. Spotify Premium requis.
  Future<bool> control(String action) async {
    final (method, path) = switch (action) {
      'play' => ('PUT', '/me/player/play'),
      'pause' => ('PUT', '/me/player/pause'),
      'next' => ('POST', '/me/player/next'),
      'previous' => ('POST', '/me/player/previous'),
      _ => ('', ''),
    };
    if (method.isEmpty) return false;
    final (status, _) = await _api(method, path);
    return status >= 200 && status < 300;
  }
}
