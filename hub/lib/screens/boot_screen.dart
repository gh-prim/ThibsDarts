import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/logo.dart';
import '../widgets/stage.dart';
import '../widgets/status_indicator.dart';
import 'home_screen.dart';

/// Démarrage : logo, chargement, état des caméras et du Pi 5.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
        ..forward().whenComplete(_ready);

  void _ready() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: Td.lente,
      pageBuilder: (_, _, _) => const HomeScreen(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stage(
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Logo(height: 72),
                const SizedBox(height: Td.s8),
                SizedBox(
                  width: 240,
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (_, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _progress.value,
                        minHeight: 6,
                        backgroundColor: Td.verreMoyen,
                        valueColor: const AlwaysStoppedAnimation(Td.sunset),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: Td.s2,
              children: [
                StatusIndicator(kind: StatusKind.camera, label: 'Caméra 1'),
                StatusIndicator(kind: StatusKind.camera, label: 'Caméra 2'),
                StatusIndicator(kind: StatusKind.camera, label: 'Caméra 3'),
                StatusIndicator(kind: StatusKind.pi, label: 'Pi 5'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
