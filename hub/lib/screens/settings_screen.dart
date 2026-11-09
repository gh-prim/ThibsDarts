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

/// Les 3 caméras du Pi 5, repérées par leur prise USB.
const camNames = ['A', 'B', 'C'];

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
class CamInfo {
  const CamInfo({this.online = false, this.fps = 0, this.width, this.height});

  factory CamInfo.fromJson(Map<String, dynamic> j) => CamInfo(
    online: j['online'] == true,
    fps: (j['fps'] as num?)?.toDouble() ?? 0,
    width: j['width'] as int?,
    height: j['height'] as int?,
  );

  final bool online;
  final double fps;
  final int? width;
  final int? height;

  String get detail {
    if (!online) return 'débranchée';
    if (width == null) return 'en veille';
    return '${width}x$height · ${fps.round()} i/s';
  }
}

/// Lit l'état des caméras toutes les 2 secondes tant que l'écran est ouvert.
mixin _CamPolling<T extends StatefulWidget> on State<T> {
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  Timer? _timer;
  Map<String, CamInfo> cams = {};

  @override
  void initState() {
    super.initState();
    CamLink.instance.camStatus.addListener(_poll);
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    final base = CamLink.instance.previewBase;
    if (base == null) {
      if (mounted) setState(() => cams = {});
      return;
    }
    try {
      final req = await _http.getUrl(base.resolve('/status'));
      final res = await req.close();
      final json = jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, dynamic>;
      final list = (json['cams'] as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => cams = {for (final c in list) c['name'] as String: CamInfo.fromJson(c)});
    } catch (_) {}
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
              Expanded(
                child: base == null
                    ? Center(child: Text('Le Pi 5 des caméras ne répond pas.', style: TdText.body))
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Td.s4,
                        children: [
                          for (final name in camNames)
                            Expanded(
                              child: _CamTile(
                                name: name,
                                info: cams[name] ?? const CamInfo(),
                                url: base.resolve('/cam/$name.mjpg'),
                                onTap: () =>
                                    Navigator.of(context)
                                        .push(MaterialPageRoute<void>(builder: (_) => CameraFullScreen(name: name))),
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
  const _CamTile({required this.name, required this.info, required this.url, required this.onTap});

  final String name;
  final CamInfo info;
  final Uri url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Td.s2,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Td.rMd),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: MjpegView(url: url),
          ),
        ),
        _CamLabel(name: name, info: info),
      ],
    ),
  );
}

class _CamLabel extends StatelessWidget {
  const _CamLabel({required this.name, required this.info});

  final String name;
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
      Text('Caméra $name', style: TdText.label.copyWith(color: Td.ink)),
      Expanded(
        child: Text(info.detail, style: TdText.caption, textAlign: TextAlign.right),
      ),
    ],
  );
}

/// Une caméra en grand, pour régler son cadrage.
class CameraFullScreen extends StatefulWidget {
  const CameraFullScreen({super.key, required this.name});

  final String name;

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
            if (base != null) MjpegView(url: base.resolve('/cam/${widget.name}.mjpg'), fit: BoxFit.contain),
            Positioned(
              left: Td.s4,
              bottom: Td.s4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Td.s3, vertical: Td.s2),
                decoration: BoxDecoration(color: Td.verreFort, borderRadius: BorderRadius.circular(999)),
                child: SizedBox(
                  width: 300,
                  child: _CamLabel(name: widget.name, info: cams[widget.name] ?? const CamInfo()),
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
