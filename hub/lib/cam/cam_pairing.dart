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

  /// Étape en cours ou résultat de la dernière recherche lancée à la main (Réglages > Système).
  final ValueNotifier<String?> message = ValueNotifier(null);

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
    await _attempt(manual: false);
  }

  /// Recherche lancée par le bouton : tout de suite, sans attendre, avec chaque étape affichée.
  Future<void> pairNow() async {
    if (_busy) return;
    if (!Platform.isLinux) {
      message.value = 'Pas de Wi-Fi à piloter sur le Mac.';
      return;
    }
    await _attempt(manual: true);
  }

  Future<void> _attempt({required bool manual}) async {
    _busy = true;
    void say(String m) {
      debugPrint('CamPairing: $m');
      if (manual) message.value = m;
    }

    try {
      say('Lecture du Wi-Fi du Pi 4…');
      // Hub en setup (son propre hotspot) ou sur câble : pas de Wi-Fi maison à transmettre.
      final home = await _homeWifi();
      if (home == null) {
        say('Le Pi 4 n’est pas sur un Wi-Fi maison : rien à transmettre au Pi 5.');
        return;
      }
      say('Recherche du réseau ThibsDarts-cam…');
      final ap = await _findCamAp(rescan: manual);
      if (ap == null) {
        say('Pi 5 introuvable. Il ouvre son réseau ThibsDarts-cam 45 s après le démarrage s’il n’a pas de Wi-Fi. '
            'Attends une minute et réessaie.');
        return;
      }
      _nextTry = DateTime.now().add(const Duration(minutes: 3));
      final error = await _push(ap, home, say);
      if (error != null) {
        say(error);
        return;
      }
      say('Wi-Fi ${home.$2} envoyé au Pi 5. Il se connecte, ça prend jusqu’à une minute…');
      if (!manual) return;
      final end = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(end)) {
        if (CamLink.instance.camStatus.value?['state'] == 'online') {
          say('Pi 5 connecté.');
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      say('Le Pi 5 a reçu le Wi-Fi mais ne s’est pas encore annoncé. Vérifie qu’il est à portée de la box.');
    } catch (e) {
      say('Erreur : $e');
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
      final keyMgmt = await _get(name, '802-11-wireless-security.key-mgmt');
      if (psk.isEmpty && keyMgmt.isNotEmpty) {
        throw 'mot de passe du Wi-Fi $ssid illisible sur le Pi 4 ($keyMgmt)';
      }
      return (name, ssid, psk);
    }
    return null;
  }

  Future<String> _get(String con, String field, {bool secrets = false}) async {
    final r = await _nmcli([if (secrets) '-s', '-g', field, 'con', 'show', con]);
    return (r.stdout as String).trim();
  }

  Future<String?> _findCamAp({bool rescan = false}) async {
    final r = await _nmcli(['-t', '-f', 'SSID', 'dev', 'wifi', 'list', '--rescan', rescan ? 'yes' : 'auto']);
    for (final line in (r.stdout as String).split('\n')) {
      final ssid = splitTerse(line).first.trim();
      if (ssid.startsWith(apPrefix)) return ssid;
    }
    return null;
  }

  /// Null si le Pi 5 a accepté le Wi-Fi, sinon le problème en clair.
  Future<String?> _push(String ap, (String, String, String) home, void Function(String) say) async {
    final (homeCon, ssid, psk) = home;
    say('Pi 5 trouvé ($ap). Le Pi 4 s’y connecte quelques secondes…');
    pairing.value = true;
    try {
      await _nmcli(['con', 'delete', _pairCon]);
      await _nmcli([
        'con', 'add', 'type', 'wifi', 'ifname', _iface, 'con-name', _pairCon, 'autoconnect', 'no', //
        'ssid', ap, 'wifi-sec.key-mgmt', 'wpa-psk', 'wifi-sec.psk', pairKey, 'ipv6.method', 'ignore',
      ]);
      final up = await _nmcli(['con', 'up', _pairCon]);
      if (up.exitCode != 0) {
        return 'Connexion au réseau $ap impossible : ${(up.stderr as String).trim()}';
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
        if (res.statusCode != 200) return 'Le Pi 5 a refusé le Wi-Fi (code ${res.statusCode}).';
        return null;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      return 'Le Pi 5 ne répond pas sur son réseau : $e';
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
