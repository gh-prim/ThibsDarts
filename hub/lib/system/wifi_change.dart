import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../cam/cam_link.dart';
import '../cam/cam_pairing.dart';

/// Changer le Wi-Fi des deux Pi depuis Réglages > Wi-Fi.
///
/// Le Pi 5 reçoit le nouveau réseau d'abord (il est encore joignable sur l'ancien), puis le Pi 4 bascule.
/// Si le Pi 4 n'arrive pas à se connecter (mauvais mot de passe), il revient sur l'ancien réseau ; le Pi 5,
/// qui a échoué aussi, rouvre son point d'accès et l'appairage automatique lui renvoie l'ancien Wi-Fi.
class WifiChange {
  WifiChange._();

  static const steps = ['Envoi au Pi 5', 'Connexion du Pi 4', 'Pi 5 en ligne'];

  static Future<ProcessResult> _nmcli(List<String> args) =>
      Process.run('nmcli', args, environment: const {'LC_ALL': 'C'});

  /// Profil Wi-Fi actif du Pi 4 (nom NetworkManager), null si aucun.
  static Future<String?> activeConnection() async {
    final r = await _nmcli(['-t', '-f', 'NAME,TYPE,DEVICE', 'con', 'show', '--active']);
    for (final line in (r.stdout as String).split('\n')) {
      final f = CamPairing.splitTerse(line);
      if (f.length >= 3 && f[1].contains('wireless') && f[2] == 'wlan0') return f[0];
    }
    return null;
  }

  /// Change de réseau. [say] reçoit l'étape (index dans [steps]) et la phrase à afficher.
  /// Renvoie null si tout a marché, sinon le problème en clair.
  static Future<String?> run(String ssid, String password, void Function(int step, String message) say) async {
    if (!Platform.isLinux) {
      await Future<void>.delayed(const Duration(seconds: 2));
      return password == 'faux' ? 'Mot de passe refusé (simulation sur le Mac).' : null;
    }
    final old = await activeConnection();

    // 1. Pi 5, s'il est en ligne : même API que l'appairage, sur son adresse du réseau actuel.
    final cam = CamLink.instance.previewBase;
    var camSent = false;
    if (cam != null) {
      say(0, 'Envoi du nouveau Wi-Fi au Pi 5…');
      camSent = await _sendToCam(cam.host, ssid, password);
      if (!camSent) say(0, 'Le Pi 5 n’a pas répondu, il suivra par l’appairage automatique.');
    } else {
      say(0, 'Pi 5 hors ligne : il suivra par l’appairage automatique.');
    }

    // 2. Pi 4.
    say(1, 'Le Pi 4 se connecte à $ssid…');
    var ok = false;
    for (var i = 1; i <= 3 && !ok; i++) {
      if (i > 1) say(1, 'Nouvel essai de connexion à $ssid ($i sur 3)…');
      await _nmcli(['dev', 'wifi', 'rescan', 'ifname', 'wlan0']);
      await Future<void>.delayed(const Duration(seconds: 3));
      final args = ['dev', 'wifi', 'connect', ssid, 'ifname', 'wlan0'];
      if (password.isNotEmpty) args.addAll(['password', password]);
      final r = await _nmcli(args);
      ok = r.exitCode == 0;
      if (!ok) debugPrint('WifiChange: ${(r.stderr as String).trim()}');
    }
    if (!ok) {
      if (old != null) {
        say(1, 'Échec, retour sur le réseau d’avant…');
        await _nmcli(['con', 'up', old]);
      }
      return 'Connexion à $ssid impossible. Vérifie le mot de passe. Le Pi 4 est resté sur l’ancien réseau.';
    }

    // 3. Le Pi 5 réapparaît sur le nouveau réseau (ou sera appairé tout seul).
    say(2, 'Pi 4 connecté. On attend le Pi 5…');
    final end = DateTime.now().add(const Duration(seconds: 90));
    // Le statut "online" de l'ancien réseau peut rester affiché un moment : on attend une nouvelle adresse
    // ou un passage hors ligne avant de croire au retour du Pi 5.
    var sawOffline = cam == null;
    while (DateTime.now().isBefore(end)) {
      final online = CamLink.instance.camStatus.value?['state'] == 'online';
      if (!online) sawOffline = true;
      if (online && (sawOffline || CamLink.instance.previewBase?.host != cam?.host)) return null;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return camSent
        ? 'Pi 4 sur $ssid. Le Pi 5 ne s’est pas encore annoncé : utilise « Appairer le Pi 5 » dans Système.'
        : 'Pi 4 sur $ssid. Le Pi 5 sera appairé tout seul dans quelques minutes, ou via « Appairer le Pi 5 ».';
  }

  static Future<bool> _sendToCam(String host, String ssid, String password) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.post(host, 8090, '/pair');
      final body = utf8.encode(jsonEncode({'ssid': ssid, 'password': password}));
      req.headers
        ..contentType = ContentType.json
        ..contentLength = body.length
        ..set('X-Pair-Key', CamPairing.pairKey);
      req.add(body);
      final res = await req.close().timeout(const Duration(seconds: 8));
      await res.drain<void>();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('WifiChange: Pi 5 injoignable : $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
