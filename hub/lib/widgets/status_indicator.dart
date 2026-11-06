import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum StatusKind { camera, wifi, pi, bluetooth }

enum Status { ok, busy, off, idle }

/// Pastille d'état (composant StatusIndicator du design system).
class StatusIndicator extends StatelessWidget {
  const StatusIndicator({super.key, required this.kind, this.status = Status.ok, this.label, this.compact = false});

  final StatusKind kind;
  final Status status;
  final String? label;
  final bool compact;

  IconData get _icon => switch ((kind, status)) {
        (_, Status.busy) => Icons.autorenew,
        (StatusKind.camera, Status.ok) => Icons.photo_camera_outlined,
        (StatusKind.camera, _) => Icons.no_photography_outlined,
        (StatusKind.wifi, Status.ok) => Icons.wifi,
        (StatusKind.wifi, _) => Icons.wifi_off,
        (StatusKind.pi, _) => Icons.memory,
        (StatusKind.bluetooth, _) => Icons.bluetooth,
      };

  Color get _iconColor => switch (status) {
        Status.ok => Td.succes,
        Status.busy => Td.ciel,
        Status.off => Td.erreur,
        Status.idle => Td.ink3,
      };

  String get _defaultLabel => switch (kind) {
        StatusKind.camera => 'Caméra',
        StatusKind.pi => 'Pi',
        StatusKind.bluetooth => 'Bluetooth',
        StatusKind.wifi => 'Wi-Fi',
      };

  String get _statusText => switch (status) {
        Status.ok => 'OK',
        Status.busy => 'recherche',
        Status.off => 'perdu',
        Status.idle => 'éteint',
      };

  @override
  Widget build(BuildContext context) {
    final text = label ?? _defaultLabel;
    final off = status == Status.off;
    final ink = off ? Td.erreur : (status == Status.idle ? Td.ink3 : Td.ink);
    return Semantics(
      label: '$text: $_statusText',
      child: Container(
        height: 32,
        width: compact ? 32 : null,
        padding: compact ? EdgeInsets.zero : const EdgeInsets.only(left: Td.s2, right: Td.s3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Td.verreLeger,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: off ? Td.erreur : Td.verreBord),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 18, color: _iconColor),
            if (!compact) ...[
              const SizedBox(width: Td.s2),
              Text(text, style: TdText.label.copyWith(color: ink)),
              const SizedBox(width: Td.s2),
              Text(_statusText,
                  style: TdText.caption.copyWith(color: off ? Td.erreur : Td.ink2)),
            ],
          ],
        ),
      ),
    );
  }
}
