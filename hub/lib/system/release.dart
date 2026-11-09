import 'dart:io';

/// Version installée, dernière release GitHub, et actions système (mise à jour, reset usine).
/// Sur le Mac ou sur un Pi installé à la main (os/quick), les scripts n'existent pas : version "dev".
class Release {
  Release._();

  static const _conf = '/etc/thibsdarts/thibsdarts.conf';

  /// Tag de la release qui tourne (fichier VERSION à la racine du paquet), "dev" sinon.
  static String get current {
    final exeRoot = File(Platform.resolvedExecutable).parent.parent.path;
    for (final path in ['$exeRoot/VERSION', '/opt/thibsdarts/VERSION']) {
      try {
        final v = File(path).readAsStringSync().trim();
        if (v.isNotEmpty) return v;
      } catch (_) {}
    }
    return 'dev';
  }

  static String get repo {
    try {
      for (final line in File(_conf).readAsLinesSync()) {
        if (line.startsWith('REPO=')) return line.substring(5).trim();
      }
    } catch (_) {}
    return 'gh-prim/ThibsDarts';
  }

  /// Vrai sur une image Dart OS (scripts de mise à jour présents).
  static bool get managed => File('/usr/local/sbin/thibsdarts-update').existsSync();

  /// Dernière release publiée (hors pre-release), null si GitHub est injoignable.
  static Future<String?> latest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse('https://github.com/$repo/releases/latest'))
        ..followRedirects = false;
      final res = await req.close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      final loc = res.headers.value(HttpHeaders.locationHeader) ?? '';
      final i = loc.indexOf('/releases/tag/');
      return i < 0 ? null : Uri.decodeComponent(loc.substring(i + '/releases/tag/'.length));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Lance la mise à jour du Pi 4 dans sa propre unité systemd : elle redémarre l'app à la fin.
  static Future<bool> updateNow() => _run('update', ['/usr/local/sbin/thibsdarts-update', '--force']);

  /// Efface profils, historique, Wi-Fi et caméras nommées, puis redémarre le Pi 4.
  static Future<bool> factoryReset() => _run('factory-reset', ['/usr/local/sbin/thibsdarts-factory-reset']);

  static Future<bool> _run(String name, List<String> cmd) async {
    if (!managed) return false;
    final r = await Process.run('sudo', ['-n', 'systemd-run', '--collect', '--unit=thibsdarts-$name-now', ...cmd]);
    return r.exitCode == 0;
  }
}
