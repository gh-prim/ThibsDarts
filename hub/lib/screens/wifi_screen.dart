import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../cam/cam_pairing.dart';
import '../setup/wifi_manager.dart';
import '../system/wifi_change.dart';
import '../theme/tokens.dart';
import '../widgets/live_status.dart';
import '../widgets/stage.dart';
import '../widgets/steps_progress.dart';
import '../widgets/td_button.dart';

class _Header extends StatelessWidget {
  const _Header({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

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
      Expanded(
        child: Text(title, style: TdText.title, overflow: TextOverflow.ellipsis),
      ),
      ?trailing,
    ],
  );
}

/// Réglages > Wi-Fi : réseau actuel et réseaux visibles. Toucher un réseau pour le rejoindre.
class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key, this.wifi});

  /// Pour les tests : sinon nmcli (Pi) ou simulateur (Mac).
  final WifiManager? wifi;

  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  late final WifiManager _wifi = widget.wifi ?? WifiManager.create();
  List<WifiNetwork>? _networks;

  @override
  void initState() {
    super.initState();
    WifiStatus.instance.attach();
    _scan();
  }

  @override
  void dispose() {
    WifiStatus.instance.detach();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _networks = null);
    final list = await _wifi.scan();
    if (mounted) setState(() => _networks = list);
  }

  Future<void> _open(WifiNetwork n) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WifiJoinScreen(network: n)));
    if (mounted) _scan();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Td.beton,
    body: Stage(
      child: Padding(
        padding: const EdgeInsets.all(Td.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Td.s4,
          children: [
            _Header(
              title: 'Wi-Fi',
              trailing: SizedBox(
                width: 200,
                child: TdButton(
                  label: 'Actualiser',
                  icon: LucideIcons.refreshCw,
                  variant: TdButtonVariant.secondary,
                  height: Td.ciblePi,
                  onPressed: _networks == null ? null : _scan,
                ),
              ),
            ),
            ListenableBuilder(
              listenable: WifiStatus.instance,
              builder: (context, _) {
                final w = WifiStatus.instance;
                return Text(
                  w.ssid == null ? 'Pi 4 sans Wi-Fi' : 'Connecté à ${w.ssid}. Le Pi 5 suit le même réseau.',
                  style: TdText.body,
                );
              },
            ),
            Expanded(
              child: _networks == null
                  ? const Center(child: CircularProgressIndicator(color: Td.sunset))
                  : _networks!.isEmpty
                  ? Center(child: Text('Aucun réseau trouvé.', style: TdText.body))
                  : ListenableBuilder(
                      listenable: WifiStatus.instance,
                      builder: (context, _) => ListView.separated(
                        itemCount: _networks!.length,
                        separatorBuilder: (_, _) => const SizedBox(height: Td.s2),
                        itemBuilder: (context, i) {
                          final n = _networks![i];
                          return _NetworkTile(
                            network: n,
                            current: n.name == WifiStatus.instance.ssid,
                            onTap: () => _open(n),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({required this.network, required this.current, required this.onTap});

  final WifiNetwork network;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: current ? null : onTap,
    child: Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: Td.s5),
      decoration: BoxDecoration(
        color: current ? Td.succesFond : Td.verreLeger,
        borderRadius: BorderRadius.circular(Td.rLg),
        border: Border.all(color: current ? Td.succes : Td.verreBord),
      ),
      child: Row(
        spacing: Td.s4,
        children: [
          Icon(
            network.signal >= 3
                ? LucideIcons.wifi
                : network.signal == 2
                ? LucideIcons.wifiHigh
                : LucideIcons.wifiLow,
            size: 24,
            color: current ? Td.succes : Td.sunset,
          ),
          Expanded(
            child: Text(network.name, style: TdText.headline, overflow: TextOverflow.ellipsis),
          ),
          if (current) Text('Connecté', style: TdText.label.copyWith(color: Td.succes)),
          if (network.locked) const Icon(LucideIcons.lock, size: 20, color: Td.ink3),
          if (!current) const Icon(LucideIcons.chevronRight, size: 24, color: Td.ink3),
        ],
      ),
    ),
  );
}

/// Mot de passe au clavier de l'écran, puis bascule des deux Pi avec les étapes affichées.
class WifiJoinScreen extends StatefulWidget {
  const WifiJoinScreen({super.key, required this.network});

  final WifiNetwork network;

  @override
  State<WifiJoinScreen> createState() => _WifiJoinScreenState();
}

class _WifiJoinScreenState extends State<WifiJoinScreen> {
  String _password = '';
  bool _show = false;
  PairProgress? _progress;

  bool get _running => _progress?.state == PairState.running;

  Future<void> _connect() async {
    var step = 0;
    setState(() => _progress = const PairProgress(0, PairState.running, 'Préparation…'));
    final error = await WifiChange.run(widget.network.name, _password, (s, m) {
      step = s;
      if (mounted) setState(() => _progress = PairProgress(s, PairState.running, m));
    });
    if (!mounted) return;
    setState(
      () => _progress = error == null
          ? PairProgress(WifiChange.steps.length - 1, PairState.done, 'Les deux Pi sont sur ${widget.network.name}.')
          : PairProgress(step, PairState.failed, error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final needsPassword = widget.network.locked;
    final p = _progress;
    return Scaffold(
      backgroundColor: Td.beton,
      body: Stage(
        child: Padding(
          padding: const EdgeInsets.all(Td.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Td.s4,
            children: [
              _Header(title: widget.network.name),
              if (p == null) ...[
                if (needsPassword)
                  Row(
                    spacing: Td.s3,
                    children: [
                      Expanded(
                        child: Container(
                          height: 64,
                          padding: const EdgeInsets.symmetric(horizontal: Td.s5),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: Td.verreLeger,
                            borderRadius: BorderRadius.circular(Td.rLg),
                            border: Border.all(color: Td.sunset),
                          ),
                          child: Text(
                            _password.isEmpty ? 'Mot de passe' : (_show ? _password : '•' * _password.length),
                            style: TdText.headline.copyWith(color: _password.isEmpty ? Td.ink3 : Td.ink),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        child: TdButton(
                          label: '',
                          icon: _show ? LucideIcons.eyeOff : LucideIcons.eye,
                          variant: TdButtonVariant.secondary,
                          height: 64,
                          onPressed: () => setState(() => _show = !_show),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TdButton(
                          label: 'Rejoindre',
                          icon: LucideIcons.wifi,
                          height: 64,
                          onPressed: _password.length >= 8 ? _connect : null,
                        ),
                      ),
                    ],
                  )
                else
                  TdButton(label: 'Rejoindre ce réseau ouvert', icon: LucideIcons.wifi, onPressed: _connect),
                if (needsPassword)
                  Expanded(
                    child: TdKeyboard(
                      onKey: (k) => setState(() => _password += k),
                      onBackspace: () => setState(
                        () => _password = _password.isEmpty ? '' : _password.substring(0, _password.length - 1),
                      ),
                    ),
                  ),
              ] else ...[
                StepsProgress(steps: WifiChange.steps, progress: p),
                const Spacer(),
                if (!_running)
                  TdButton(
                    label: p.state == PairState.done ? 'Terminé' : 'Réessayer',
                    icon: p.state == PairState.done ? LucideIcons.check : LucideIcons.rotateCcw,
                    variant: p.state == PairState.done ? TdButtonVariant.primary : TdButtonVariant.secondary,
                    onPressed: () =>
                        p.state == PairState.done ? Navigator.of(context).pop() : setState(() => _progress = null),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Clavier AZERTY de l'écran tactile (pas de clavier physique sur la cible).
class TdKeyboard extends StatefulWidget {
  const TdKeyboard({super.key, required this.onKey, required this.onBackspace});

  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;

  @override
  State<TdKeyboard> createState() => _TdKeyboardState();
}

class _TdKeyboardState extends State<TdKeyboard> {
  bool _shift = false;
  bool _symbols = false;

  static const _letters = ['azertyuiop', 'qsdfghjklm', 'wxcvbn'];
  static const _signs = ['1234567890', '@#&*-_+=()', '!?.,;:\'"/\$'];

  Widget _key(String label, VoidCallback onTap, {int flex = 1, IconData? icon, bool active = false}) => Expanded(
    flex: flex,
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: _Key(label: label, icon: icon, active: active, onTap: onTap),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final rows = _symbols ? _signs : _letters;
    String shown(String c) => _shift && !_symbols ? c.toUpperCase() : c;
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++)
          Expanded(
            child: Row(
              children: [
                if (r == 2)
                  _key(
                    '',
                    () => setState(() => _shift = !_shift),
                    flex: 2,
                    icon: LucideIcons.arrowBigUp,
                    active: _shift,
                  ),
                for (final c in rows[r].split('')) _key(shown(c), () => widget.onKey(shown(c))),
                if (r == 2) _key('', widget.onBackspace, flex: 2, icon: LucideIcons.delete),
              ],
            ),
          ),
        Expanded(
          child: Row(
            children: [
              _key(_symbols ? 'ABC' : '123', () => setState(() => _symbols = !_symbols), flex: 2),
              _key('-', () => widget.onKey('-')),
              _key('espace', () => widget.onKey(' '), flex: 5),
              _key('.', () => widget.onKey('.')),
              _key('@', () => widget.onKey('@'), flex: 2),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({required this.label, required this.onTap, this.icon, this.active = false});

  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _down = true),
    onTapUp: (_) => setState(() => _down = false),
    onTapCancel: () => setState(() => _down = false),
    onTap: widget.onTap,
    child: AnimatedContainer(
      duration: Td.rapide,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _down || widget.active ? Td.sunset.withValues(alpha: 0.35) : Td.verreLeger,
        borderRadius: BorderRadius.circular(Td.rSm),
        border: Border.all(color: Td.verreBord),
      ),
      child: widget.icon != null
          ? Icon(widget.icon, size: 26, color: Td.ink)
          : Text(widget.label, style: TdText.headline),
    ),
  );
}
