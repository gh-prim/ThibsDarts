import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import '../widgets/live_status.dart';
import '../widgets/logo.dart';
import '../widgets/stage.dart';
import '../game_config.dart';
import '../lobby/lobby.dart';
import '../setup/owner_store.dart';
import 'home_screen.dart';
import 'setup_screen.dart';

/// Démarrage (composant BootScreen du design system) :
/// logo 120 px, barre de chargement Golden Hour, puis "Prêt. Tranquille."
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _bar = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // En attendant le vrai check (caméras, Pi 5), on simule le démarrage.
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      setState(() => _ready = true);
      Future.delayed(const Duration(milliseconds: 1400), _goHome);
    });
  }

  void _goHome() {
    if (!mounted) return;
    // Pas encore de propriétaire : premier allumage, setup depuis l'iPhone.
    final owner = OwnerStore.instance.load();
    if (owner != null) {
      AppState.setOwner(owner);
      Lobby.instance.serve();
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Td.lente,
        pageBuilder: (_, _, _) => owner == null ? const SetupScreen() : const HomeScreen(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _bar.dispose();
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
                const Logo(height: 120),
                const SizedBox(height: Td.s6),
                SizedBox(
                  height: 22,
                  child: AnimatedSwitcher(
                    duration: Td.base,
                    child: _ready ? const _ReadyBadge() : _LoadingBar(animation: _bar),
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Center(child: LiveStatusBar(compact: false, wifi: false)),
          ),
        ],
      ),
    );
  }
}

/// Barre 200x4 avec un segment Golden Hour qui glisse (td-boot__p).
class _LoadingBar extends StatelessWidget {
  const _LoadingBar({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Container(
          width: 200,
          height: 4,
          color: Td.verreMoyen,
          child: AnimatedBuilder(
            animation: animation,
            builder: (_, _) {
              // translateX de -100% à 260% du segment (40% de la barre).
              final t = const Cubic(0.45, 0.05, 0.55, 0.95).transform(animation.value);
              final x = (-1 + 3.6 * t) * 80;
              return Stack(
                children: [
                  Positioned(
                    left: x,
                    top: 0,
                    width: 80,
                    height: 4,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: Td.goldenHour,
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ReadyBadge extends StatelessWidget {
  const _ReadyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: Td.s2),
      decoration: BoxDecoration(color: const Color(0x243DDC97), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.check, size: 14, color: Td.succes),
          const SizedBox(width: Td.s1),
          Text(
            'Prêt. Tranquille.',
            style: TdText.label.copyWith(fontSize: 12, height: 16 / 12, color: Td.succes),
          ),
        ],
      ),
    );
  }
}
