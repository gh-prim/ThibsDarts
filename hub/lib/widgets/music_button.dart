import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../spotify/spotify_link.dart';
import '../theme/tokens.dart';

/// Petite note de musique dans le coin de l'écran, visible quand Spotify est relié.
/// Un appui ouvre le mini lecteur : morceau en cours, précédent, pause, suivant.
class MusicButton extends StatefulWidget {
  const MusicButton({super.key, required this.navigator});

  /// Le bouton vit au-dessus du Navigator de l'appli : il lui faut sa clé pour ouvrir la fenêtre.
  final GlobalKey<NavigatorState> navigator;

  @override
  State<MusicButton> createState() => _MusicButtonState();
}

class _MusicButtonState extends State<MusicButton> {
  Map<String, Object?>? _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final now = SpotifyLink.instance.linked ? await SpotifyLink.instance.nowPlaying() : null;
    if (mounted) setState(() => _now = now);
  }

  @override
  Widget build(BuildContext context) {
    if (_now?['linked'] != true) return const SizedBox.shrink();
    final playing = _now?['playing'] == true;
    return Semantics(
      button: true,
      label: 'Musique',
      child: GestureDetector(
        onTap: () {
          final ctx = widget.navigator.currentContext;
          if (ctx != null) showDialog<void>(context: ctx, barrierColor: const Color(0xCC000000), builder: (_) => const MusicSheet());
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Td.plateauNoir,
            shape: BoxShape.circle,
            border: Border.all(color: playing ? Td.sunset : Td.plateauFil),
          ),
          child: Icon(LucideIcons.music, size: 20, color: playing ? Td.sunset : Td.ink2),
        ),
      ),
    );
  }
}

/// Fenêtre du mini lecteur.
class MusicSheet extends StatefulWidget {
  const MusicSheet({super.key});

  @override
  State<MusicSheet> createState() => _MusicSheetState();
}

class _MusicSheetState extends State<MusicSheet> {
  Map<String, Object?>? _now;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final now = await SpotifyLink.instance.nowPlaying();
    if (mounted) setState(() => _now = now);
  }

  Future<void> _do(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await SpotifyLink.instance.control(action);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final active = now?['active'] == true;
    final playing = now?['playing'] == true;
    final art = now?['art'] as String?;
    final progress = (now?['progressMs'] as num?)?.toDouble();
    final duration = (now?['durationMs'] as num?)?.toDouble();
    return Dialog(
      backgroundColor: Td.plateauNoir,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Td.rXl)),
      child: Padding(
        padding: const EdgeInsets.all(Td.s6),
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Td.rMd),
                    child: SizedBox.square(
                      dimension: 96,
                      child: art == null
                          ? const ColoredBox(color: Td.plateauFil, child: Icon(LucideIcons.music, color: Td.ink3))
                          : Image.network(art, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: Td.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          now == null ? 'Spotify…' : (active ? '${now['title']}' : 'Rien en lecture'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TdText.headline,
                        ),
                        const SizedBox(height: Td.s1),
                        Text(
                          active ? '${now?['artist'] ?? ''}' : 'Lance un morceau sur ton téléphone ou ta télé.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TdText.body,
                        ),
                        if (active && now?['device'] != null) ...[
                          const SizedBox(height: Td.s1),
                          Text('Sur ${now!['device']}', style: TdText.caption),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (active && progress != null && duration != null && duration > 0) ...[
                const SizedBox(height: Td.s4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (progress / duration).clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: Td.plateauFil,
                    color: Td.sunset,
                  ),
                ),
              ],
              const SizedBox(height: Td.s6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: Td.s6,
                children: [
                  _control(LucideIcons.skipBack, 'Précédent', active ? () => _do('previous') : null),
                  _control(
                    playing ? LucideIcons.pause : LucideIcons.play,
                    playing ? 'Pause' : 'Lecture',
                    active ? () => _do(playing ? 'pause' : 'play') : null,
                    big: true,
                  ),
                  _control(LucideIcons.skipForward, 'Suivant', active ? () => _do('next') : null),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _control(IconData icon, String label, VoidCallback? onTap, {bool big = false}) {
    final size = big ? 72.0 : 60.0;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: big ? Td.sunset : null,
            border: big ? null : Border.all(color: Td.plateauFil),
          ),
          child: Icon(
            icon,
            size: size * 0.42,
            color: onTap == null ? Td.ink3 : (big ? Td.onAccent : Td.ink),
          ),
        ),
      ),
    );
  }
}
