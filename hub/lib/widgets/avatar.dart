import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Avatar rond avec initiales (composant Avatar).
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 44, this.active = false});

  final String name;
  final double size;
  final bool active;

  String get _initials =>
      name.trim().split(RegExp(r'\s+')).map((s) => s.characters.first).join().characters.take(2).toString().toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Td.fluo : Td.asphalteHaut,
        border: active ? null : Border.all(color: Td.verreBord),
      ),
      child: Text(
        _initials,
        style: TdText.rounded(size * 0.38, 800, active ? Td.onAccent : Td.ink),
      ),
    );
  }
}
