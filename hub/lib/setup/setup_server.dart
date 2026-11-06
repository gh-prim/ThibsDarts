import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'owner_store.dart';
import 'wifi_manager.dart';

enum SetupPhase { waiting, paired, wifiConnecting, profile, done }

enum WifiState { idle, connecting, ok, error }

/// Setup du premier allumage, piloté par l'iPhone.
///
/// Le Pi ouvre un hotspot "ThibsDarts-<code>", affiche un QR code et écoute
/// sur le port 8420. L'iPhone s'appaire avec le code, donne le Wi-Fi, puis le profil.
class SetupController extends ChangeNotifier {
  SetupController({WifiManager? wifi, OwnerStore? store, Random? random})
      : wifi = wifi ?? WifiManager.create(),
        store = store ?? OwnerStore.instance,
        _rnd = random ?? Random.secure() {
    code = List.generate(4, (_) => _rnd.nextInt(10)).join();
    hotspotPassword = List.generate(10, (_) => _alphabet[_rnd.nextInt(_alphabet.length)]).join();
  }

  static const port = 8420;
  static const _alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';

  final WifiManager wifi;
  final OwnerStore store;
  final Random _rnd;

  late final String code;
  late final String hotspotPassword;
  String get hotspotSsid => 'ThibsDarts-$code';

  SetupPhase phase = SetupPhase.waiting;
  WifiState wifiState = WifiState.idle;
  String? ssid;
  String? phoneName;
  String? host;
  bool wifiFailed = false;
  Owner? owner;

  String? _token;
  HttpServer? _server;

  /// Lien encodé dans le QR code.
  String get qrPayload {
    final q = {
      'h': host ?? '10.42.0.1',
      'p': '$port',
      'c': code,
      if (!wifi.simulated) 's': hotspotSsid,
      if (!wifi.simulated) 'k': hotspotPassword,
    };
    return Uri(scheme: 'thibsdarts', host: 'setup', queryParameters: q).toString();
  }

  Future<void> start() async {
    await wifi.startHotspot(hotspotSsid, hotspotPassword);
    host = await _localAddress();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _server!.listen(_handle);
    notifyListeners();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  static Future<String?> _localAddress() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      // Le hotspot NetworkManager est en 10.42.0.1 ; sinon la première adresse privée.
      final all = [for (final i in ifs) ...i.addresses.map((a) => a.address)];
      return all.firstWhere((a) => a.startsWith('10.42.'),
          orElse: () => all.firstWhere((a) => a.startsWith('192.168.') || a.startsWith('10.') || a.startsWith('172.'),
              orElse: () => all.isEmpty ? '127.0.0.1' : all.first));
    } catch (_) {
      return null;
    }
  }

  void _set(void Function() f) {
    f();
    notifyListeners();
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;
    try {
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/api/setup/hello') {
        return await _json(res, {'device': 'ThibsDarts', 'version': 1, 'setupDone': phase == SetupPhase.done});
      }
      if (req.method == 'POST' && path == '/api/setup/pair') {
        final body = await _body(req);
        if (body['code'] != code) return await _json(res, {'error': 'code'}, status: 403);
        _token = List.generate(32, (_) => _alphabet[_rnd.nextInt(_alphabet.length)]).join();
        _set(() {
          phoneName = (body['device'] as String?)?.trim();
          if (phase == SetupPhase.waiting) phase = SetupPhase.paired;
          wifiFailed = false;
        });
        return await _json(res, {'token': _token, 'simulated': wifi.simulated});
      }

      if (_token == null || req.headers.value('authorization') != 'Bearer $_token') {
        return await _json(res, {'error': 'auth'}, status: 401);
      }

      switch ((req.method, path)) {
        case ('GET', '/api/setup/status'):
          return await _json(res, _status());
        case ('GET', '/api/setup/networks'):
          final nets = await wifi.scan();
          return await _json(res, {'networks': nets.map((n) => n.toJson()).toList()});
        case ('POST', '/api/setup/wifi'):
          final body = await _body(req);
          final name = (body['ssid'] as String? ?? '').trim();
          if (name.isEmpty) return await _json(res, {'error': 'ssid'}, status: 400);
          _set(() {
            ssid = name;
            phase = SetupPhase.wifiConnecting;
            wifiState = WifiState.connecting;
          });
          await _json(res, _status(), status: 202);
          // On répond d'abord : sur le Pi, couper le hotspot coupe aussi l'iPhone.
          unawaited(_connect(name, body['password'] as String? ?? ''));
          return;
        case ('POST', '/api/setup/profile'):
          final body = await _body(req);
          final first = (body['firstName'] as String? ?? '').trim();
          final last = (body['lastName'] as String? ?? '').trim();
          final nick = (body['nickname'] as String? ?? '').trim();
          if (first.isEmpty) return await _json(res, {'error': 'firstName'}, status: 400);
          if (!store.photoFile.existsSync()) return await _json(res, {'error': 'photo'}, status: 400);
          final saved = await store.save(firstName: first, lastName: last, nickname: nick.isEmpty ? first : nick);
          _set(() {
            owner = saved;
            phase = SetupPhase.done;
          });
          return await _json(res, _status());
        case ('PUT', '/api/setup/photo'):
          final bytes = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
          if (bytes.length < 1000 || bytes.length > 8 * 1024 * 1024) {
            return await _json(res, {'error': 'photo'}, status: 400);
          }
          await store.savePhoto(bytes);
          return await _json(res, {'ok': true});
      }
      return await _json(res, {'error': 'not found'}, status: 404);
    } catch (e) {
      return await _json(res, {'error': '$e'}, status: 500);
    }
  }

  Future<void> _connect(String name, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final ok = await wifi.connect(name, password);
    if (ok) {
      _set(() {
        wifiState = WifiState.ok;
        phase = SetupPhase.profile;
      });
    } else {
      // Retour au QR code avec le hotspot relancé.
      await wifi.startHotspot(hotspotSsid, hotspotPassword);
      _set(() {
        wifiState = WifiState.error;
        wifiFailed = true;
        phase = wifi.simulated ? SetupPhase.paired : SetupPhase.waiting;
      });
    }
  }

  Map<String, Object?> _status() => {
        'phase': phase.name,
        'wifi': wifiState.name,
        'ssid': ssid,
      };

  static Future<Map<String, Object?>> _body(HttpRequest req) async {
    final text = await utf8.decoder.bind(req).join();
    if (text.isEmpty) return {};
    return jsonDecode(text) as Map<String, Object?>;
  }

  static Future<void> _json(HttpResponse res, Object body, {int status = 200}) async {
    res.statusCode = status;
    res.write(jsonEncode(body));
    await res.close();
  }
}
