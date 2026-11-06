import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

enum StatusKind { camera, wifi, pi, bluetooth }

enum Status { ok, busy, off, idle }

/// Pastille d'état (composant StatusIndicator du design system).
class StatusIndicator extends StatelessWidget {
  const StatusIndicator({super.key, required this.kind, this.status = Status.ok, this.label, this.detail, this.compact = false});

  final StatusKind kind;
  final Status status;
  final String? label;

  /// Remplace le texte d'état ("Freebox-Thibs", "attend le Wi-Fi").
  final String? detail;
  final bool compact;

  IconData get _icon => switch ((kind, status)) {
        (_, Status.busy) => LucideIcons.loaderCircle,
        (StatusKind.camera, Status.ok) => LucideIcons.camera,
        (StatusKind.camera, _) => LucideIcons.cameraOff,
        (StatusKind.wifi, Status.ok) => LucideIcons.wifi,
        (StatusKind.wifi, _) => LucideIcons.wifiOff,
        (StatusKind.pi, _) => LucideIcons.cpu,
        (StatusKind.bluetooth, _) => LucideIcons.bluetooth,
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
      label: '$text: ${detail ?? _statusText}',
      child: Container(
        height: 32,
        width: compact ? 32 : null,
        padding: compact ? EdgeInsets.zero : const EdgeInsets.only(left: Td.s2, right: Td.s3),
        alignment: compact ? Alignment.center : null,
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
              Text(detail ?? _statusText,
                  style: TdText.caption.copyWith(color: off ? Td.erreur : Td.ink2)),
            ],
          ],
        ),
      ),
    );
  }
}
