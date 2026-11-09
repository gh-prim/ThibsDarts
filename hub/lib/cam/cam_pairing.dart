import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'cam_link.dart';

/// Donne au Pi 5 caméra le Wi-Fi de la maison, sans câble ni écran.
///
/// Un Pi 5 sans réseau ouvre son point d'accès "ThibsDarts-cam-XXXX" (cam/pairing/pair.py).
/// Quand le Pi 5 ne répond plus sur MQTT depuis une minute, hors partie, le hub cherche ce
/// point d'accès, s'y connecte quelques secondes, lui envoie le Wi-Fi sur lequel il est
/// lui-même, puis revient sur la maison. Le Pi 5 rejoint alors le hub par dartos-hub.local.
class CamPairing {
  CamPairing._();

  static final CamPairing instance = CamPairing._();

  static const apPrefix = 'ThibsDarts-cam-';

  /// Même valeur côté Pi 5 (cam/pairing/pair.py).
  static const pairKey = 'thibsdarts-pair';
  static const _pairCon = 'thibsdarts-pair';
  static const _iface = 'wlan0';

  /// Vrai pendant que le hub est parti sur le point d'accès du Pi 5.
  final ValueNotifier<bool> pairing = ValueNotifier(false);

  Timer? _timer;
  bool _busy = false;
  DateTime? _offlineSince;
  DateTime _nextTry = DateTime.fromMillisecondsSinceEpoch(0);

  void start() {
    if (!Platform.isLinux || _timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_busy) return;
    final now = DateTime.now();
    if (CamLink.instance.camStatus.value?['state'] == 'online') {
      _offlineSince = null;
      return;
    }
    _offlineSince ??= now;
    if (now.difference(_offlineSince!) < const Duration(minutes: 1)) return;
    if (now.isBefore(_nextTry) || CamLink.instance.playing) return;
    _busy = true;
    try {
      // Hub en setup (son propre hotspot) ou sur câble : pas de Wi-Fi maison à transmettre.
      final home = await _homeWifi();
      if (home == null) return;
      final ap = await _findCamAp();
      if (ap == null) return;
      _nextTry = now.add(const Duration(minutes: 3));
      await _push(ap, home);
    } catch (e) {
      debugPrint('CamPairing: $e');
    } finally {
      _busy = false;
    }
  }

  Future<ProcessResult> _nmcli(List<String> args) => Process.run('nmcli', args);

  /// Découpe une ligne `nmcli -t` (les ':' des valeurs sont échappés en '\:').
  @visibleForTesting
  static List<String> splitTerse(String line) {
    final out = <String>[];
    final cur = StringBuffer();
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == r'\' && i + 1 < line.length) {
        cur.write(line[++i]);
      } else if (c == ':') {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(c);
      }
    }
    out.add(cur.toString());
    return out;
  }

  /// Connexion Wi-Fi active du hub en mode client : (nom du profil, ssid, mot de passe).
  Future<(String, String, String)?> _homeWifi() async {
    final r = await _nmcli(['-t', '-f', 'NAME,TYPE,DEVICE', 'con', 'show', '--active']);
    for (final line in (r.stdout as String).split('\n')) {
      final f = splitTerse(line);
      if (f.length < 3 || f[2] != _iface || !f[1].contains('wireless') || f[0] == _pairCon) continue;
      final name = f[0];
      final mode = await _get(name, '802-11-wireless.mode');
      if (mode == 'ap') return null;
      final ssid = await _get(name, '802-11-wireless.ssid');
      if (ssid.isEmpty) return null;
      final psk = await _get(name, '802-11-wireless-security.psk', secrets: true);
      return (name, ssid, psk);
    }
    return null;
  }

  Future<String> _get(String con, String field, {bool secrets = false}) async {
    final r = await _nmcli([if (secrets) '-s', '-g', field, 'con', 'show', con]);
    return (r.stdout as String).trim();
  }

  Future<String?> _findCamAp() async {
    final r = await _nmcli(['-t', '-f', 'SSID', 'dev', 'wifi', 'list', '--rescan', 'auto']);
    for (final line in (r.stdout as String).split('\n')) {
      final ssid = splitTerse(line).first.trim();
      if (ssid.startsWith(apPrefix)) return ssid;
    }
    return null;
  }

  Future<void> _push(String ap, (String, String, String) home) async {
    final (homeCon, ssid, psk) = home;
    debugPrint('CamPairing: Pi 5 trouvé ($ap), envoi du Wi-Fi $ssid');
    pairing.value = true;
    try {
      await _nmcli(['con', 'delete', _pairCon]);
      await _nmcli([
        'con', 'add', 'type', 'wifi', 'ifname', _iface, 'con-name', _pairCon, 'autoconnect', 'no', //
        'ssid', ap, 'wifi-sec.key-mgmt', 'wpa-psk', 'wifi-sec.psk', pairKey, 'ipv6.method', 'ignore',
      ]);
      final up = await _nmcli(['con', 'up', _pairCon]);
      if (up.exitCode != 0) {
        debugPrint('CamPairing: point d\'accès injoignable : ${(up.stderr as String).trim()}');
        return;
      }
      final gw = (await _nmcli(['-g', 'IP4.GATEWAY', 'dev', 'show', _iface])).stdout as String;
      final host = gw.trim().isEmpty ? '10.42.0.1' : gw.trim();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final req = await client.post(host, 8090, '/pair');
        req.headers
          ..contentType = ContentType.json
          ..set('X-Pair-Key', pairKey);
        req.write(jsonEncode({'ssid': ssid, 'password': psk}));
        final res = await req.close().timeout(const Duration(seconds: 10));
        await res.drain<void>();
        debugPrint('CamPairing: réponse du Pi 5 ${res.statusCode}');
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('CamPairing: $e');
    } finally {
      await _nmcli(['con', 'down', _pairCon]);
      await _nmcli(['con', 'delete', _pairCon]);
      for (var i = 0; i < 3; i++) {
        if ((await _nmcli(['con', 'up', homeCon])).exitCode == 0) break;
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      pairing.value = false;
    }
  }
}
