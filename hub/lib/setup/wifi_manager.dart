import 'dart:io';

/// Réseau vu par le Pi.
class WifiNetwork {
  const WifiNetwork(this.name, {this.signal = 3, this.locked = true});

  final String name;

  /// 0 à 4 barres.
  final int signal;
  final bool locked;

  Map<String, Object> toJson() => {'name': name, 'signal': signal, 'locked': locked};
}

/// Pilote le Wi-Fi : hotspot de setup, scan, connexion au réseau de la maison.
abstract class WifiManager {
  static WifiManager create() => Platform.isLinux ? NmcliWifi() : SimulatedWifi();

  /// Vrai si c'est le simulateur du Mac (pas de vrai Wi-Fi touché).
  bool get simulated;

  /// Wi-Fi ouvert (sans mot de passe) le temps du setup.
  Future<void> startHotspot(String ssid);
  Future<void> stopHotspot();
  Future<List<WifiNetwork>> scan();

  /// Renvoie true si la connexion a marché.
  Future<bool> connect(String ssid, String password);
}

/// Raspberry Pi : NetworkManager via nmcli.
class NmcliWifi implements WifiManager {
  static const _hotspotName = 'thibsdarts-setup';
  String iface = 'wlan0';

  @override
  bool get simulated => false;

  Future<ProcessResult> _nmcli(List<String> args) => Process.run('nmcli', args, environment: const {'LC_ALL': 'C'});

  @override
  Future<void> startHotspot(String ssid) async {
    // `nmcli dev wifi hotspot` impose toujours un mot de passe : on crée un point d'accès ouvert à la main.
    await _nmcli(['con', 'delete', _hotspotName]);
    await _nmcli([
      'con',
      'add',
      'type',
      'wifi',
      'ifname',
      iface,
      'con-name',
      _hotspotName,
      'autoconnect',
      'no',
      'ssid',
      ssid,
      '802-11-wireless.mode',
      'ap',
      '802-11-wireless.band',
      'bg',
      'ipv4.method',
      'shared',
    ]);
    await _nmcli(['con', 'up', _hotspotName]);
  }

  @override
  Future<void> stopHotspot() async {
    await _nmcli(['con', 'down', _hotspotName]);
  }

  @override
  Future<List<WifiNetwork>> scan() async {
    final r = await _nmcli(['-t', '-f', 'SSID,SIGNAL,SECURITY', 'dev', 'wifi', 'list', '--rescan', 'yes']);
    final seen = <String, WifiNetwork>{};
    for (final line in (r.stdout as String).split('\n')) {
      final parts = line.split(':');
      if (parts.length < 3 || parts[0].isEmpty || parts[0].startsWith('ThibsDarts-')) continue;
      final pct = int.tryParse(parts[1]) ?? 0;
      final net = WifiNetwork(
        parts[0],
        signal: (pct / 25).ceil().clamp(1, 4),
        locked: parts[2].isNotEmpty && parts[2] != '--',
      );
      final prev = seen[net.name];
      if (prev == null || prev.signal < net.signal) seen[net.name] = net;
    }
    final list = seen.values.toList()..sort((a, b) => b.signal.compareTo(a.signal));
    return list;
  }

  @override
  Future<bool> connect(String ssid, String password) async {
    await stopHotspot();
    // Profil déjà enregistré pour ce réseau (ex. Raspberry Pi Imager) : on met le mot de passe à jour et on l'active.
    final saved = await _savedConnection(ssid);
    if (saved != null) {
      if (password.isNotEmpty) {
        await _nmcli(['con', 'modify', saved, 'wifi-sec.key-mgmt', 'wpa-psk', 'wifi-sec.psk', password]);
      }
      if ((await _nmcli(['con', 'up', saved])).exitCode == 0) return true;
    }
    // En mode point d'accès, la puce ne scanne pas : la liste est vide juste après. On rescanne et on réessaie.
    for (var i = 0; i < 4; i++) {
      await _nmcli(['dev', 'wifi', 'rescan', 'ifname', iface]);
      await Future<void>.delayed(const Duration(seconds: 3));
      final args = ['dev', 'wifi', 'connect', ssid, 'ifname', iface];
      if (password.isNotEmpty) args.addAll(['password', password]);
      final r = await _nmcli(args);
      if (r.exitCode == 0) return true;
      stderr.writeln('nmcli connect "$ssid" : ${(r.stderr as String).trim()}');
    }
    return false;
  }

  Future<String?> _savedConnection(String ssid) async {
    final r = await _nmcli(['-t', '-f', 'NAME,TYPE', 'con', 'show']);
    for (final line in (r.stdout as String).split('\n')) {
      final i = line.lastIndexOf(':');
      if (i <= 0 || !line.substring(i + 1).contains('wireless')) continue;
      final name = line.substring(0, i).replaceAll(r'\:', ':');
      if (name == _hotspotName) continue;
      final s = await _nmcli(['-g', '802-11-wireless.ssid', 'con', 'show', name]);
      if ((s.stdout as String).trim() == ssid) return name;
    }
    return null;
  }
}

/// Mac de dev : aucun vrai Wi-Fi n'est touché. Un réseau simulé, le mot de passe "faux" échoue.
class SimulatedWifi implements WifiManager {
  @override
  bool get simulated => true;

  @override
  Future<void> startHotspot(String ssid) async {}

  @override
  Future<void> stopHotspot() async {}

  @override
  Future<List<WifiNetwork>> scan() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return const [WifiNetwork('Wi-Fi simulé (Mac)', signal: 4)];
  }

  @override
  Future<bool> connect(String ssid, String password) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    return password != 'faux';
  }
}
