import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../system/sounds.dart';
import '../theme/tokens.dart';

/// Vidéo 180 (clip Blender, 6 s) plein écran sur le petit écran, avec son.
/// flutter-pi n'a pas de lecteur vidéo : les images JPEG 1024 x 576 sont mises bout à bout dans
/// assets/fete180/fete180.frames (index dans fete180.json) et décodées quelques images en avance.
/// Le son (assets/sounds/fete180.wav) part avec la première image. Toucher l'écran coupe la vidéo.
class Fete180Video extends StatefulWidget {
  const Fete180Video({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<Fete180Video> createState() => _Fete180VideoState();
}

class _Clip {
  _Clip(this.data, this.frames, this.fps);
  final ByteData data;
  final List<List<int>> frames;
  final int fps;

  static Future<_Clip>? _loading;

  /// Chargé une fois, gardé en mémoire (6 Mo) pour les 180 suivants.
  static Future<_Clip> load() => _loading ??= () async {
    final index = jsonDecode(await rootBundle.loadString('assets/fete180/fete180.json')) as Map<String, dynamic>;
    final data = await rootBundle.load('assets/fete180/fete180.frames');
    final frames = [for (final f in index['frames'] as List) (f as List).cast<int>()];
    return _Clip(data, frames, index['fps'] as int? ?? 30);
  }();

  Uint8List bytes(int i) => data.buffer.asUint8List(data.offsetInBytes + frames[i][0], frames[i][1]);
}

class _Fete180VideoState extends State<Fete180Video> with SingleTickerProviderStateMixin {
  static const _ahead = 6;

  _Clip? _clip;
  late final Ticker _ticker = createTicker(_tick);
  final Map<int, ui.Image> _decoded = {};
  final Set<int> _pending = {};
  ui.Image? _shown;
  int _index = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _Clip.load().then((c) {
      if (!mounted) return;
      _clip = c;
      _fill(0);
      Sounds.play('fete180');
      _ticker.start();
    }).catchError((Object e) {
      debugPrint('Fete180Video: $e');
      _finish();
    });
  }

  void _fill(int from) {
    final c = _clip!;
    for (var i = from; i < from + _ahead && i < c.frames.length; i++) {
      if (_decoded.containsKey(i) || _pending.contains(i)) continue;
      _pending.add(i);
      ui.instantiateImageCodec(c.bytes(i)).then((codec) => codec.getNextFrame()).then((f) {
        _pending.remove(i);
        if (!mounted || i < _index) {
          f.image.dispose();
          return;
        }
        _decoded[i] = f.image;
      });
    }
  }

  void _tick(Duration elapsed) {
    final c = _clip!;
    final i = (elapsed.inMicroseconds * c.fps / 1e6).floor();
    if (i >= c.frames.length) return _finish();
    // Image pas encore décodée : on garde la précédente (pas d'écran noir).
    final img = _decoded.remove(i);
    for (final k in _decoded.keys.where((k) => k < i).toList()) {
      _decoded.remove(k)!.dispose();
    }
    _index = i;
    _fill(i + 1);
    if (img != null) {
      final old = _shown;
      setState(() => _shown = img);
      old?.dispose();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    if (_ticker.isActive) _ticker.stop();
    widget.onDone();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shown?.dispose();
    for (final img in _decoded.values) {
      img.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Sounds.stop();
        _finish();
      },
      child: ColoredBox(
        color: Td.betonNuit,
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _shown == null ? const SizedBox.expand() : RawImage(image: _shown, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}
