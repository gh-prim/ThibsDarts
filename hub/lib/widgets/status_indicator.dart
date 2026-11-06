import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum StatusKind { camera, wifi, pi }

enum Status { ok, warning, error }

/// Pastille d'état : caméra, Wi-Fi, Pi 5.
class StatusIndicator extends StatelessWidget {
  const StatusIndicator({super.key, required this.kind, this.status = Status.ok, this.label, this.compact = false});

  final StatusKind kind;
  final Status status;
  final String? label;
  final bool compact;

  IconData get _icon => switch (kind) {
        StatusKind.camera => Icons.videocam_outlined,
        StatusKind.wifi => Icons.wifi,
        StatusKind.pi => Icons.memory,
      };

  Color get _color => switch (status) {
        Status.ok => Td.succes,
        Status.warning => Td.fluo,
        Status.error => Td.erreur,
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${label ?? kind.name} ${status.name}',
      child: Container(
        height: 36,
        padding: EdgeInsets.symmetric(horizontal: compact ? Td.s2 : Td.s3),
        decoration: BoxDecoration(
          color: Td.verreLeger,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Td.bord),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 18, color: Td.ink2),
            const SizedBox(width: Td.s2),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
            if (!compact && label != null) ...[
              const SizedBox(width: Td.s2),
              Text(label!, style: TdText.label),
            ],
          ],
        ),
      ),
    );
  }
}
