import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../cam/cam_link.dart';
import '../theme/tokens.dart';
import '../widgets/mjpeg_view.dart';
import '../widgets/stage.dart';
import '../widgets/td_button.dart';

/// En-tête des écrans de réglages : bouton retour et titre.
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Row(
    spacing: Td.s4,
    children: [
      SizedBox(
        width: 180,
        child: TdButton(
          label: 'Retour',
          icon: LucideIcons.arrowLeft,
          variant: TdButtonVariant.secondary,
          height: Td.ciblePi,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      Text(title, style: TdText.title),
    ],
  );
}

/// Menu Réglages de la cible.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Td.beton,
    body: Stage(
      child: Padding(
        padding: const EdgeInsets.all(Td.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Td.s5,
          children: [
            const _Header(title: 'Réglages'),
            _Item(
              icon: LucideIcons.camera,
              title: 'Caméras',
              detail: 'Voir les 3 caméras en direct',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CamerasScreen())),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.title, required this.detail, required this.onTap});

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: Td.ciblePiFort,
      padding: const EdgeInsets.symmetric(horizontal: Td.s5),
      decoration: BoxDecoration(
        color: Td.verreLeger,
        borderRadius: BorderRadius.circular(Td.rLg),
        border: Border.all(color: Td.verreBord),
      ),
      child: Row(
        spacing: Td.s4,
        children: [
          Icon(icon, size: 28, color: Td.sunset),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TdText.headline),
                Text(detail, style: TdText.caption),
              ],
            ),
          ),
          const Icon(LucideIcons.chevronRight, size: 28, color: Td.ink3),
        ],
      ),
    ),
  );
}

/// État d'une caméra lu sur /status du Pi 5.
/// Les caméras sont toutes identiques : le Pi 5 les reconnaît à leur vue, quel que soit le port USB.
class CamInfo {
  const CamInfo({
    required this.id,
    required this.number,
    this.online = false,
    this.fps = 0,
    this.width,
    this.height,
    this.label,
    this.moving = false,
  });

  factory CamInfo.fromJson(Map<String, dynamic> j, int number) => CamInfo(
    id: j['id'] as String,
    number: number,
    online: j['online'] == true,
    fps: (j['fps'] as num?)?.toDouble() ?? 0,
    width: j['width'] as int?,
    height: j['height'] as int?,
    label: j['label'] as String?,
    moving: j['moving'] == true,
  );

  /// Identifiant du flux sur le Pi 5 (change si on change la caméra de port).
  final String id;

  /// Rang à l'écran, pour "Caméra 2" tant qu'elle n'a pas de nom.
  final int number;
  final bool online;
  final double fps;
  final int? width;
  final int? height;

  /// Nom choisi par le propriétaire ("Haut", "Gauche"), retrouvé d'après la vue de la caméra.
  final String? label;

  String get title => label ?? 'Caméra $number';

  /// La caméra voit bouger quelque chose (main passée devant pour la repérer).
  final bool moving;

  String get detail {
    if (!online) return 'débranchée';
    if (width == null) return 'en veille';
    return '${width}x$height · ${fps.round()} i/s';
  }
}

/// Lit l'état des caméras deux fois par seconde tant que l'écran est ouvert.
mixin _CamPolling<T extends StatefulWidget> on State<T> {
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  Timer? _timer;
  List<CamInfo> cams = [];
  List<String> presets = const [];

  /// Noms déjà donnés : une caméra sans nom est alors "non reconnue".
  List<String> known = const [];

  CamInfo? camById(String id) => cams.where((c) => c.id == id).firstOrNull;

  @override
  void initState() {
    super.initState();
    CamLink.instance.camStatus.addListener(_poll);
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
  }

  Future<void> _poll() async {
    final base = CamLink.instance.previewBase;
    if (base == null) {
      if (mounted) setState(() => cams = []);
      return;
    }
    try {
      final req = await _http.getUrl(base.resolve('/status'));
      final res = await req.close();
      final json = jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, dynamic>;
      final list = (json['cams'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        cams = [for (var i = 0; i < list.length; i++) CamInfo.fromJson(list[i], i + 1)];
        presets = (json['presets'] as List?)?.cast<String>() ?? const [];
        known = (json['known'] as List?)?.cast<String>() ?? const [];
      });
    } catch (_) {}
  }

  /// Donne un nom à une caméra (vide pour l'enlever), enregistré sur le Pi 5.
  Future<void> rename(String cam, String name) async {
    final base = CamLink.instance.previewBase;
    if (base == null) return;
    try {
      final req = await _http.postUrl(base.resolve('/cam/$cam/name'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'name': name}));
      await (await req.close()).drain<void>();
    } catch (_) {}
    await _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    CamLink.instance.camStatus.removeListener(_poll);
    _http.close(force: true);
    super.dispose();
  }
}

/// Les 3 caméras en direct (aperçu 640x360). Toucher une caméra l'ouvre en grand.
class CamerasScreen extends StatefulWidget {
  const CamerasScreen({super.key});

  @override
  State<CamerasScreen> createState() => _CamerasScreenState();
}

class _CamerasScreenState extends State<CamerasScreen> with _CamPolling {
  /// Pas de clavier sur la cible : noms proposés en pastilles.
  Future<void> _pickName(CamInfo cam) async {
    final current = cam.label;
    final choice = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) => Dialog(
        backgroundColor: Td.plateauNoir,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Td.rXl)),
        child: Padding(
          padding: const EdgeInsets.all(Td.s8),
          child: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Td.s4,
              children: [
                Text(cam.label == null ? 'Nommer cette caméra' : 'Renommer « ${cam.label} »', style: TdText.headline),
                Text(
                  'D’après sa place autour de la cible. Elle garde ce nom même branchée sur un autre port : '
                  'le Pi 5 la reconnaît à ce qu’elle voit. Fixe-la d’abord.',
                  style: TdText.body,
                ),
                Wrap(
                  spacing: Td.s2,
                  runSpacing: Td.s2,
                  children: [
                    for (final p in presets)
                      _Chip(label: p, selected: p == current, onTap: () => Navigator.of(ctx).pop(p)),
                    _Chip(label: 'Sans nom', selected: current == null, onTap: () => Navigator.of(ctx).pop('')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice != null) await rename(cam.id, choice);
  }

  @override
  Widget build(BuildContext context) {
    final base = CamLink.instance.previewBase;
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s5,
            children: [
              const _Header(title: 'Caméras'),
              Row(
                spacing: Td.s2,
                children: [
                  const Icon(LucideIcons.hand, size: 18, color: Td.fluo),
                  Text('Passe la main devant une caméra pour la repérer : sa vignette s’allume.', style: TdText.body),
                ],
              ),
              Expanded(
                child: base == null
                    ? Center(child: Text('Le Pi 5 des caméras ne répond pas.', style: TdText.body))
                    : cams.isEmpty
                    ? Center(child: Text('Aucune caméra branchée sur le Pi 5.', style: TdText.body))
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Td.s4,
                        children: [
                          for (final cam in cams)
                            Expanded(
                              child: _CamTile(
                                info: cam,
                                unknown: cam.label == null && known.isNotEmpty,
                                url: base.resolve('/cam/${cam.id}.mjpg'),
                                onRename: () => _pickName(cam),
                                onTap: () =>
                                    Navigator.of(context)
                                        .push(MaterialPageRoute<void>(builder: (_) => CameraFullScreen(id: cam.id))),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CamTile extends StatelessWidget {
  const _CamTile({
    required this.info,
    required this.unknown,
    required this.url,
    required this.onTap,
    required this.onRename,
  });

  final CamInfo info;
  final bool unknown;
  final Uri url;
  final VoidCallback onTap;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Td.s2,
    children: [
      GestureDetector(
        onTap: onTap,
        // La vignette s'allume quand la caméra voit bouger quelque chose.
        child: AnimatedContainer(
          duration: Td.rapide,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Td.rMd + 3),
            border: Border.all(color: info.moving ? Td.fluo : Td.verreBord, width: 2),
            boxShadow: info.moving ? [BoxShadow(color: Td.sunset.withValues(alpha: 0.55), blurRadius: 24)] : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Td.rMd),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: MjpegView(url: url),
            ),
          ),
        ),
      ),
      _CamLabel(info: info),
      Row(
        children: [
          Expanded(
            child: Text(
              unknown ? 'Non reconnue' : (info.label == null ? 'Sans nom' : 'Reconnue'),
              style: TdText.caption.copyWith(color: unknown ? Td.sunset : Td.ink3),
            ),
          ),
          GestureDetector(
            onTap: onRename,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: Td.s3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Td.verreLeger,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Td.verreBord),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Td.s1,
                children: [
                  const Icon(LucideIcons.pencil, size: 16, color: Td.ink2),
                  Text('Nommer', style: TdText.label),
                ],
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _CamLabel extends StatelessWidget {
  const _CamLabel({required this.info});

  final CamInfo info;

  @override
  Widget build(BuildContext context) => Row(
    spacing: Td.s2,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, color: info.online ? Td.succes : Td.erreur),
      ),
      Text(info.title, style: TdText.label.copyWith(color: info.moving ? Td.fluo : Td.ink)),
      Expanded(
        child: Text(info.detail, style: TdText.caption, textAlign: TextAlign.right),
      ),
    ],
  );
}

/// Une caméra en grand, pour régler son cadrage.
class CameraFullScreen extends StatefulWidget {
  const CameraFullScreen({super.key, required this.id});

  final String id;

  @override
  State<CameraFullScreen> createState() => _CameraFullScreenState();
}

class _CameraFullScreenState extends State<CameraFullScreen> with _CamPolling {
  @override
  Widget build(BuildContext context) {
    final base = CamLink.instance.previewBase;
    return Scaffold(
      backgroundColor: Td.betonNuit,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (base != null) MjpegView(url: base.resolve('/cam/${widget.id}.mjpg'), fit: BoxFit.contain),
            Positioned(
              left: Td.s4,
              bottom: Td.s4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Td.s3, vertical: Td.s2),
                decoration: BoxDecoration(color: Td.verreFort, borderRadius: BorderRadius.circular(999)),
                child: SizedBox(
                  width: 300,
                  child: _CamLabel(info: camById(widget.id) ?? CamInfo(id: widget.id, number: 0)),
                ),
              ),
            ),
            Positioned(
              right: Td.s4,
              bottom: Td.s4,
              child: Text('Touche pour revenir', style: TdText.caption),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: Td.s5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? Td.sunsetFond : Td.verreLeger,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? Td.sunset : Td.verreBord),
      ),
      child: Text(label, style: TdText.inter(17, 22, 600, selected ? Td.sunset : Td.ink)),
    ),
  );
}
