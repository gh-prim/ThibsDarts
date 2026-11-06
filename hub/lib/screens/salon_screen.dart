import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../game_config.dart';
import '../lobby/lobby.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/player_card.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';
import 'mode_game_screen.dart';
import 'setup_screen.dart' show SetupQrCode;

/// Salon (planche Salon) : QR code pour rejoindre depuis l'iPhone, joueurs, Invité, Lancer.
class SalonScreen extends StatefulWidget {
  const SalonScreen({super.key, required this.config, this.lobby});

  final GameConfig config;

  /// Injecté par les tests ; sinon le salon de l'appareil.
  final Lobby? lobby;

  @override
  State<SalonScreen> createState() => _SalonScreenState();
}

class _SalonScreenState extends State<SalonScreen> {
  late final Lobby _lobby = widget.lobby ?? Lobby.instance;

  @override
  void initState() {
    super.initState();
    _lobby.open(widget.config);
  }

  void _back() {
    _lobby.close();
    Navigator.of(context).pop();
  }

  void _launch() {
    final cfg = _lobby.start();
    Navigator.of(context)
        .pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => gameScreenFor(cfg)), (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: ListenableBuilder(
          listenable: _lobby,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.all(Td.s5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 380, child: _JoinPanel(lobby: _lobby)),
                const SizedBox(width: Td.s5),
                Expanded(child: _players(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _players(BuildContext context) {
    final players = _lobby.players;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TdIconButton(icon: LucideIcons.chevronLeft, label: 'Retour aux options', onPressed: _back),
            const SizedBox(width: Td.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Salon de ${AppState.owner}', style: TdText.headline),
                  Text(_lobby.label, style: TdText.inter(13, 18, 400, Td.ink2)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Td.s3),
        Row(
          children: [
            Expanded(
              child: Text(
                'Joueurs, ${players.length} sur ${Lobby.maxPlayers}. Glisse pour changer l’ordre.',
                style: TdText.inter(13, 18, 600, Td.ink2),
              ),
            ),
            if (_lobby.arriving != null) _LoadingBadge(text: '${_lobby.arriving} arrive'),
          ],
        ),
        const SizedBox(height: Td.s3),
        Expanded(
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - Td.s2) / 2;
                return Wrap(
                  spacing: Td.s2,
                  runSpacing: Td.s2,
                  children: [
                    for (final (i, p) in players.indexed)
                      SizedBox(
                        width: w,
                        child: _DraggableCard(lobby: _lobby, index: i, player: p),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: Td.s3),
        Row(
          children: [
            const Icon(LucideIcons.bell, size: 16, color: Td.ink3),
            const SizedBox(width: Td.s2),
            Expanded(
              child: Text(
                'Chacun reçoit une notification sur son iPhone quand c’est son tour.',
                style: TdText.inter(13, 18, 400, Td.ink3),
              ),
            ),
          ],
        ),
        const SizedBox(height: Td.s3),
        Row(
          children: [
            Expanded(
              child: TdButton(
                label: 'Invité',
                icon: LucideIcons.plus,
                variant: TdButtonVariant.secondary,
                onPressed: players.length < Lobby.maxPlayers ? _lobby.addGuest : null,
              ),
            ),
            const SizedBox(width: Td.s2),
            Expanded(
              child: TdButton(label: 'Lancer', icon: LucideIcons.play, onPressed: _launch),
            ),
          ],
        ),
      ],
    );
  }
}

/// Carte joueur qu'on glisse sur une autre pour changer l'ordre de passage.
class _DraggableCard extends StatelessWidget {
  const _DraggableCard({required this.lobby, required this.index, required this.player});

  final Lobby lobby;
  final int index;
  final LobbyPlayer player;

  PlayerSummary get _summary => PlayerSummary(
    player.name,
    message: player.host ? 'Hôte' : (player.guest ? 'Invité' : 'Prêt'),
    ready: !player.host && !player.guest,
  );

  @override
  Widget build(BuildContext context) {
    final card = PlayerCard(player: _summary);
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => lobby.reorder(d.data, index),
      builder: (context, hover, _) => LongPressDraggable<int>(
        data: index,
        delay: const Duration(milliseconds: 250),
        feedback: Material(
          type: MaterialType.transparency,
          child: SizedBox(width: 300, child: Opacity(opacity: 0.9, child: card)),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: card),
        child: AnimatedScale(
          scale: hover.isNotEmpty ? 1.03 : 1,
          duration: Td.rapide,
          child: player.guest
              ? GestureDetector(
                  // Un invité se retire d'un double appui.
                  onDoubleTap: () => lobby.remove(player),
                  child: card,
                )
              : card,
        ),
      ),
    );
  }
}

class _JoinPanel extends StatelessWidget {
  const _JoinPanel({required this.lobby});

  final Lobby lobby;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Td.s5),
      decoration: BoxDecoration(
        color: Td.verreLeger,
        borderRadius: BorderRadius.circular(Td.rXl),
        border: Border.all(color: Td.verreBord),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Rejoins la partie.', style: TdText.inter(28, 34, 800, Td.ink).copyWith(letterSpacing: -0.3)),
          const SizedBox(height: Td.s4),
          Container(
            padding: const EdgeInsets.all(Td.s4),
            decoration: BoxDecoration(
              color: Td.plateauCreme,
              borderRadius: BorderRadius.circular(Td.rLg),
              boxShadow: const [BoxShadow(color: Color(0x59FF7A2F), blurRadius: 32, blurStyle: BlurStyle.outer)],
            ),
            child: SizedBox.square(dimension: 200, child: SetupQrCode(data: lobby.qrPayload)),
          ),
          const SizedBox(height: Td.s4),
          Text(
            'Scanne avec l’app ThibsDarts.\nOu tape le code du salon.',
            textAlign: TextAlign.center,
            style: TdText.inter(15, 20, 400, Td.ink2),
          ),
          const SizedBox(height: Td.s4),
          Text(lobby.code, style: TdText.rounded(44, 900, Td.ink, height: 48).copyWith(letterSpacing: 8)),
        ],
      ),
    );
  }
}

class _LoadingBadge extends StatelessWidget {
  const _LoadingBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: Td.s2),
      decoration: BoxDecoration(color: Td.verreMoyen, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.loaderCircle, size: 12, color: Td.ink2),
          const SizedBox(width: Td.s1),
          Text(text, style: TdText.inter(12, 16, 600, Td.ink2)),
        ],
      ),
    );
  }
}
