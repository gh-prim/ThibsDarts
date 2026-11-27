import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../cam/cam_link.dart';
import 'release.dart';

/// Mise à jour du système du Pi 4 (OS, config.txt, paquets, services), en plus de l'app.
/// Le travail est fait par system/apply (dans le paquet de la release) et thibsdarts-update.
/// Ici : l'état affiché à l'écran, et le premier passage sur un Pi dont thibsdarts-update est
/// trop ancien pour connaître system/apply.
class SystemUpdate {
  SystemUpdate._();

  static const _status = '/data/system/status';
  static const _installedId = '/etc/thibsdarts/system-id';
  static const _installedVersion = '/etc/thibsdarts/system-version';
  static const _packageDir = '/opt/thibsdarts/system';

  /// Étape en cours : null (rien), 'system', 'packages' ou 'reboot'.
  static final step = ValueNotifier<String?>(null);

  static Timer? _poll;
  static Timer? _bootstrap;

  /// Version de la release dont le système est installé ("v0.2.37"), null si inconnue.
  static String? get installedVersion => _read(_installedVersion);

  /// Vrai si le système de la version qui tourne n'est pas encore installé.
  static bool get behind {
    final want = _read('$_packageDir/ID');
    return want != null && want != _read(_installedId);
  }

  static String? _read(String path) {
    try {
      final v = File(path).readAsStringSync().trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  static void start() {
    if (!Release.managed) return;
    _poll ??= Timer.periodic(const Duration(seconds: 2), (_) => _readStatus());
    _readStatus();
    // Laisse l'ancien thibsdarts-update finir son contrôle de santé (30 s) avant de lancer.
    _bootstrap ??= Timer(const Duration(seconds: 60), _bootstrapIfNeeded);
  }

  static void _readStatus() {
    final f = File(_status);
    String? s;
    try {
      // Écrit avant le dernier démarrage (ex. "reboot") ou vieux de plus de 20 min : c'est fini.
      final at = f.lastModifiedSync();
      if (at.isAfter(_bootTime()) && DateTime.now().difference(at) < const Duration(minutes: 20)) {
        s = f.readAsStringSync().trim();
      }
    } catch (_) {}
    step.value = const {'system', 'packages', 'reboot'}.contains(s) ? s : null;
  }

  static DateTime? _boot;
  static DateTime _bootTime() {
    if (_boot != null) return _boot!;
    try {
      final up = double.parse(File('/proc/uptime').readAsStringSync().split(' ').first);
      return _boot = DateTime.now().subtract(Duration(milliseconds: (up * 1000).round()));
    } catch (_) {
      return _boot = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  static Future<void> _bootstrapIfNeeded() async {
    _bootstrap = null;
    if (!behind || File('/data/system/pending').existsSync()) return;
    // Un thibsdarts-update récent s'en charge tout seul.
    try {
      if (File('/usr/local/sbin/thibsdarts-update').readAsStringSync().contains('system/apply')) return;
    } catch (_) {}
    if (CamLink.instance.playing) {
      _bootstrap = Timer(const Duration(minutes: 10), _bootstrapIfNeeded);
      return;
    }
    await Process.run('sudo', [
      '-n',
      'systemd-run',
      '--collect',
      '--unit=thibsdarts-system-now',
      '$_packageDir/apply',
      '--reboot',
    ]);
  }
}
