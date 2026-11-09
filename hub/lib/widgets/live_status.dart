import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../cam/cam_link.dart';
import '../theme/tokens.dart';
import 'status_indicator.dart';

/// Wi-Fi du Pi 4, lu avec nmcli toutes les 15 secondes tant qu'une pastille l'affiche.
class WifiStatus extends ChangeNotifier {
  WifiStatus._();

  static final WifiStatus instance = WifiStatus._();

  /// Nom du réseau connecté, null si aucun.
  String? ssid;

  /// Qualité du signal, 0 à 100.
  int? signal;
  bool checked = false;
  Timer? _timer;
  int _users = 0;

  void attach() {
    if (_users++ > 0) return;
    _check();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
  }

  void detach() {
    if (--_users > 0) return;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    if (!Platform.isLinux) {
      // Sur le Mac, le réseau de l'ordinateur.
      ssid = 'Mac';
    } else {
      try {
        final r = await Process.run('nmcli', ['-t', '-f', 'ACTIVE,SSID,SIGNAL', 'dev', 'wifi']);
        final active = (r.stdout as String).split('\n').where((l) => l.startsWith('yes:')).firstOrNull;
        final parts = active?.split(':');
        ssid = parts == null || parts.length < 3 ? null : parts.sublist(1, parts.length - 1).join(':');
        signal = parts == null ? null : int.tryParse(parts.last);
      } catch (_) {
        ssid = null;
      }
    }
    checked = true;
    notifyListeners();
  }
}

/// Pastilles d'état réelles : les caméras branchées sur le Pi 5, le Wi-Fi du Pi 4 et le Pi 5 lui-même.
class LiveStatusBar extends StatefulWidget {
  const LiveStatusBar({super.key, this.compact = true, this.wifi = true, this.wrap = false});

  final bool compact;
  final bool wifi;

  /// Sur plusieurs lignes si la place manque (colonne de l'écran de jeu).
  final bool wrap;

  @override
  State<LiveStatusBar> createState() => _LiveStatusBarState();
}

class _LiveStatusBarState extends State<LiveStatusBar> {
  late final _listen = Listenable.merge([CamLink.instance.camStatus, WifiStatus.instance]);

  @override
  void initState() {
    super.initState();
    WifiStatus.instance.attach();
  }

  @override
  void dispose() {
    WifiStatus.instance.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _listen,
    builder: (context, _) {
      final pills = [...cameraPills(), if (widget.wifi) _wifiPill(), piPill()];
      return widget.wrap
          ? Wrap(spacing: Td.s2, runSpacing: Td.s2, children: pills)
          : Row(mainAxisSize: MainAxisSize.min, spacing: Td.s2, children: pills);
    },
  );

  Map<String, dynamic>? get _cam => CamLink.instance.camStatus.value;
  bool get _piOnline => _cam?['state'] == 'online';

  /// Une pastille par caméra attendue : verte si branchée, rouge sinon, grise si le Pi 5 est éteint.
  List<Widget> cameraPills() {
    final cams = (_cam?['cams'] as Map?)?.cast<String, Object?>() ?? {};
    final names = cams.values.toList();
    return [
      for (var i = 0; i < 3; i++)
        StatusIndicator(
          kind: StatusKind.camera,
          compact: widget.compact,
          label: i < names.length ? (names[i] as String? ?? 'Caméra ${i + 1}') : 'Caméra ${i + 1}',
          status: !_piOnline ? Status.idle : (i < names.length ? Status.ok : Status.off),
          detail: _piOnline && i >= names.length ? 'débranchée' : null,
        ),
    ];
  }

  Widget _wifiPill() {
    final w = WifiStatus.instance;
    return StatusIndicator(
      kind: StatusKind.wifi,
      compact: widget.compact,
      status: !w.checked ? Status.busy : (w.ssid == null ? Status.off : Status.ok),
      detail: w.ssid == null ? null : (w.signal == null ? w.ssid : '${w.ssid} · ${w.signal} %'),
    );
  }

  /// Pi 5 des caméras : en ligne (MQTT), température, alerte d'alimentation.
  Widget piPill() {
    final health = (_cam?['health'] as Map?)?.cast<String, Object?>() ?? {};
    final temp = health['temp'] as num?;
    final alert = health['undervoltage'] == true || health['throttled'] == true || (temp ?? 0) >= 80;
    return StatusIndicator(
      kind: StatusKind.pi,
      compact: widget.compact,
      label: 'Pi 5',
      status: _cam == null ? Status.busy : (!_piOnline || alert ? Status.off : Status.ok),
      detail: _cam == null
          ? 'recherche'
          : !_piOnline
          ? 'éteint'
          : health['undervoltage'] == true
          ? 'sous-tension'
          : (temp == null ? 'OK' : '${temp.round()} °C'),
    );
  }
}
