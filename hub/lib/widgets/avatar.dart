import 'dart:io';

import 'package:flutter/material.dart';

import '../game_config.dart';

import '../theme/tokens.dart';

/// Avatar rond avec initiales (composant Avatar).
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 44, this.active = false});

  final String name;
  final double size;
  final bool active;

  String get _initials => name
      .trim()
      .split(RegExp(r'\s+'))
      .map((s) => s.characters.first)
      .join()
      .characters
      .take(2)
      .toString()
      .toUpperCase();

  @override
  Widget build(BuildContext context) {
    // Le propriétaire a une vraie photo, prise à l'installation.
    final photo = AppState.photos[name];
    if (photo != null && File(photo).existsSync()) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: active ? Td.fluo : Td.verreBord, width: active ? 2 : 1),
          image: DecorationImage(image: FileImage(File(photo)), fit: BoxFit.cover),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Td.fluo : Td.asphalteHaut,
        border: active ? null : Border.all(color: Td.verreBord),
      ),
      child: Text(_initials, style: TdText.rounded(size * 0.38, 800, active ? Td.onAccent : Td.ink)),
    );
  }
}
