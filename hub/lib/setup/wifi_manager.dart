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

  Future<void> startHotspot(String ssid, String password);
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

  Future<ProcessResult> _nmcli(List<String> args) => Process.run('nmcli', args);

  @override
  Future<void> startHotspot(String ssid, String password) async {
    await _nmcli([
      'dev',
      'wifi',
      'hotspot',
      'ifname',
      iface,
      'con-name',
      _hotspotName,
      'ssid',
      ssid,
      'password',
      password,
    ]);
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
    final args = ['dev', 'wifi', 'connect', ssid, 'ifname', iface];
    if (password.isNotEmpty) args.addAll(['password', password]);
    final r = await _nmcli(args);
    return r.exitCode == 0;
  }
}

/// Mac de dev : aucun vrai Wi-Fi n'est touché. Un réseau simulé, le mot de passe "faux" échoue.
class SimulatedWifi implements WifiManager {
  @override
  bool get simulated => true;

  @override
  Future<void> startHotspot(String ssid, String password) async {}

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
