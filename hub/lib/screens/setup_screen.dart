import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr/qr.dart';

import '../game_config.dart';
import '../lobby/lobby.dart';
import '../setup/setup_server.dart';
import '../theme/tokens.dart';
import '../widgets/game_widgets.dart';
import '../widgets/logo.dart';
import '../widgets/stage.dart';
import '../widgets/status_indicator.dart';
import '../widgets/td_button.dart';
import 'home_screen.dart';

/// Premier allumage (planches "0. Setup") : QR code, suivi, bienvenue.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.controller});

  /// Injecté par les tests ; sinon créé et démarré ici.
  final SetupController? controller;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final SetupController _c = widget.controller ?? SetupController();

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _c.start();
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  void _finish() {
    final o = _c.owner;
    if (o != null) AppState.setOwner(o);
    // Le serveur de setup libère le port 8420 pour celui des salons.
    _c.stop().then((_) => Lobby.instance.serve());
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Td.lente,
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Material : sans lui, Flutter souligne les textes en jaune (style de debug).
    return Material(
      type: MaterialType.transparency,
      child: Stage(
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => AnimatedSwitcher(
            duration: Td.base,
            child: switch (_c.phase) {
              SetupPhase.waiting => _QrView(key: const ValueKey('qr'), c: _c),
              SetupPhase.done => _WelcomeView(key: const ValueKey('done'), c: _c, onGo: _finish),
              _ => _ProgressView(key: const ValueKey('progress'), c: _c),
            },
          ),
        ),
      ),
    );
  }
}

/// Grille commune : colonne de gauche (logo, titre, étapes) | panneau de 380.
class _SetupLayout extends StatelessWidget {
  const _SetupLayout({required this.title, required this.subtitle, required this.steps, required this.panel});

  final String title;
  final String subtitle;
  final List<Widget> steps;
  final Widget panel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Logo(height: 48),
                const SizedBox(height: 28),
                Text(title, style: TdText.title),
                const SizedBox(height: Td.s3),
                Text(subtitle, style: TdText.body),
                const SizedBox(height: 28),
                for (final (i, s) in steps.indexed) ...[if (i > 0) const SizedBox(height: Td.s4), s],
              ],
            ),
          ),
          const SizedBox(width: 40),
          SizedBox(
            width: 380,
            child: Container(
              padding: const EdgeInsets.all(Td.s6),
              decoration: BoxDecoration(
                color: Td.verreLeger,
                borderRadius: BorderRadius.circular(Td.rXl),
                border: Border.all(color: Td.verreBord),
              ),
              child: panel,
            ),
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, current, todo }

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.state, required this.title, required this.detail});

  final int n;
  final _StepState state;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final Widget dot = switch (state) {
      _StepState.done => Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Td.succes),
        child: const Icon(LucideIcons.check, size: 20, color: Td.onAccent),
      ),
      _StepState.current => Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Td.fluo, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x66FFE14D), blurRadius: 20, blurStyle: BlurStyle.outer)],
        ),
        child: Text('$n', style: TdText.rounded(18, 900, Td.fluo)),
      ),
      _StepState.todo => CustomPaint(
        painter: _DashedCircle(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(child: Text('$n', style: TdText.rounded(18, 900, Td.ink3))),
        ),
      ),
    };
    final titleColor = switch (state) {
      _StepState.done => Td.ink2,
      _StepState.current => Td.ink,
      _StepState.todo => Td.ink3,
    };
    return Row(
      children: [
        dot,
        const SizedBox(width: Td.s4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TdText.inter(20, 26, 700, titleColor)),
              Text(detail, style: TdText.inter(15, 20, 400, Td.ink3)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashedCircle extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Td.bordControle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final r = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    const n = 24;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(r, i * 2 * 3.14159 / n, 3.14159 / n, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// SetupQR : "Salut. On installe ton ThibsDarts."
class _QrView extends StatelessWidget {
  const _QrView({super.key, required this.c});

  final SetupController c;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _SetupLayout(
          title: 'Salut. On installe ton ThibsDarts.',
          subtitle: 'Tout se fait depuis ton iPhone. Deux minutes, pas plus.',
          steps: const [
            _Step(
              n: 1,
              state: _StepState.current,
              title: 'Scanne le QR code',
              detail: 'Avec l’appareil photo de ton iPhone.',
            ),
            _Step(
              n: 2,
              state: _StepState.todo,
              title: 'Donne le Wi-Fi de la maison',
              detail: 'Le Pi le passe ensuite au Pi 5.',
            ),
            _Step(n: 3, state: _StepState.todo, title: 'Crée ton profil', detail: 'Prénom, nom et une vraie photo.'),
          ],
          panel: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(Td.s4),
                decoration: BoxDecoration(
                  color: Td.plateauCreme,
                  borderRadius: BorderRadius.circular(Td.rLg),
                  boxShadow: const [BoxShadow(color: Color(0x59FF7A2F), blurRadius: 32, blurStyle: BlurStyle.outer)],
                ),
                child: SizedBox.square(dimension: 200, child: SetupQrCode(data: c.qrPayload)),
              ),
              const SizedBox(height: Td.s4),
              Text(
                'Pas d’app ? Le QR ouvre l’App Store.\nLe Pi crée son propre Wi-Fi le temps du setup.',
                textAlign: TextAlign.center,
                style: TdText.inter(15, 20, 400, Td.ink2),
              ),
              const SizedBox(height: Td.s4),
              Text('Code d’appairage', style: TdText.inter(13, 18, 600, Td.ink3)),
              const SizedBox(height: 2),
              Text(c.code, style: TdText.rounded(44, 900, Td.ink, height: 48).copyWith(letterSpacing: 8)),
              if (!c.wifi.simulated) ...[
                const SizedBox(height: Td.s4),
                Text('Wi-Fi ${c.hotspotSsid}', style: TdText.inter(13, 18, 600, Td.ink3)),
                const SizedBox(height: 2),
                Text(c.hotspotPassword, style: TdText.rounded(28, 800, Td.ink, height: 34).copyWith(letterSpacing: 2)),
              ],
            ],
          ),
        ),
        if (c.wifiFailed)
          const Positioned(
            left: 40,
            right: 460,
            bottom: 24,
            child: TdBanner(text: 'Le Wi-Fi n’a pas marché. Rescanne le QR code et réessaie.'),
          ),
      ],
    );
  }
}

/// SetupEnCours : "L’iPhone de Thibault est là."
class _ProgressView extends StatelessWidget {
  const _ProgressView({super.key, required this.c});

  final SetupController c;

  @override
  Widget build(BuildContext context) {
    final phone = c.phoneName;
    final wifiStep = switch (c.phase) {
      SetupPhase.paired => _StepState.current,
      SetupPhase.wifiConnecting => _StepState.current,
      _ => _StepState.done,
    };
    final ssid = c.ssid ?? 'Wi-Fi';
    final wifiDetail = switch (c.wifiState) {
      WifiState.connecting => '$ssid, ça tourne...',
      WifiState.ok => '$ssid, connecté.',
      WifiState.error => 'Mot de passe refusé. Réessaie depuis l’iPhone.',
      WifiState.idle => 'Choisis le réseau sur l’iPhone.',
    };
    final wifiStatus = switch (c.wifiState) {
      WifiState.ok => Status.ok,
      WifiState.connecting => Status.busy,
      WifiState.error => Status.off,
      WifiState.idle => Status.idle,
    };
    return _SetupLayout(
      title: phone == null || phone.isEmpty ? 'Ton iPhone est là.' : 'L’$phone est là.',
      subtitle: 'Continue sur ton téléphone, ici on suit.',
      steps: [
        _Step(n: 1, state: _StepState.done, title: 'iPhone connecté', detail: 'Code ${c.code} validé.'),
        _Step(n: 2, state: wifiStep, title: 'Connexion au Wi-Fi', detail: wifiDetail),
        _Step(
          n: 3,
          state: c.phase == SetupPhase.profile ? _StepState.current : _StepState.todo,
          title: 'Crée ton profil',
          detail: 'Prénom, nom et une vraie photo.',
        ),
      ],
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('État du système', style: TdText.inter(13, 18, 600, Td.ink2)),
          const SizedBox(height: Td.s3),
          StatusIndicator(kind: StatusKind.wifi, status: wifiStatus, label: 'Wi-Fi', detail: c.ssid),
          const SizedBox(height: Td.s3),
          StatusIndicator(
            kind: StatusKind.pi,
            status: Status.idle,
            label: 'Pi 5',
            detail: c.wifiState == WifiState.ok ? 'pas encore relié' : 'attend le Wi-Fi',
          ),
          const SizedBox(height: Td.s3),
          const StatusIndicator(
            kind: StatusKind.camera,
            status: Status.idle,
            label: 'Caméras',
            detail: 'après le Pi 5',
          ),
          const Spacer(),
          const TdBanner(error: false, text: 'Le Wi-Fi ne passe pas ? Le Pi revient tout seul au QR code.'),
        ],
      ),
    );
  }
}

/// SetupBienvenue : "Bienvenue, Thibault."
class _WelcomeView extends StatelessWidget {
  const _WelcomeView({super.key, required this.c, required this.onGo});

  final SetupController c;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final o = c.owner;
    final photo = o?.photoPath;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: Td.goldenHour,
                boxShadow: [BoxShadow(color: Color(0x80FF4D8D), blurRadius: 40)],
              ),
              child: Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Td.beton, width: 4),
                  color: Td.asphalteHaut,
                  image: photo == null ? null : DecorationImage(image: FileImage(File(photo)), fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: Td.s5),
            Text(
              'Bienvenue, ${o?.firstName ?? ''}.',
              style: TdText.inter(40, 46, 800, Td.ink).copyWith(letterSpacing: -0.5),
            ),
            const SizedBox(height: Td.s5),
            SizedBox(
              width: 520,
              child: Text(
                'Ton ThibsDarts est prêt. Tes potes rejoignent les parties avec le QR code du salon, rien à installer de ton côté.',
                textAlign: TextAlign.center,
                style: TdText.body,
              ),
            ),
            const SizedBox(height: Td.s5),
            const Wrap(
              spacing: Td.s2,
              runSpacing: Td.s2,
              alignment: WrapAlignment.center,
              children: [
                StatusIndicator(kind: StatusKind.wifi, label: 'Wi-Fi'),
                StatusIndicator(kind: StatusKind.pi, status: Status.idle, label: 'Pi 5'),
                StatusIndicator(kind: StatusKind.camera, status: Status.idle, label: 'Caméra 1'),
                StatusIndicator(kind: StatusKind.camera, status: Status.idle, label: 'Caméra 2'),
                StatusIndicator(kind: StatusKind.camera, status: Status.idle, label: 'Caméra 3'),
              ],
            ),
            const SizedBox(height: Td.s5 + Td.s2),
            SizedBox(
              width: 360,
              child: TdButton(label: 'C’est parti', icon: LucideIcons.arrowRight, onPressed: onGo),
            ),
          ],
        ),
      ),
    );
  }
}

/// QR code dessiné en béton sur fond crème.
class SetupQrCode extends StatelessWidget {
  const SetupQrCode({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final qr = QrImage(QrCode(payload: QrPayload.fromString(data)));
    return Semantics(
      label: 'QR code d’installation',
      child: CustomPaint(painter: _QrPainter(qr)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.qr);

  final QrImage qr;

  @override
  void paint(Canvas canvas, Size size) {
    final n = qr.moduleCount;
    final cell = size.width / n;
    final p = Paint()..color = Td.beton;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (qr.isDark(y, x)) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.4, cell + 0.4), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => old.qr != qr;
}
