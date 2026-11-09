import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// Flux vidéo MJPEG (aperçu d'une caméra du Pi 5). Se reconnecte tout seul.
class MjpegView extends StatefulWidget {
  const MjpegView({super.key, required this.url, this.fit = BoxFit.cover});

  final Uri url;
  final BoxFit fit;

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  StreamSubscription<List<int>>? _sub;
  Timer? _retry;
  Uint8List? _frame;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(MjpegView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _connect();
  }

  Future<void> _connect() async {
    _retry?.cancel();
    await _sub?.cancel();
    final buf = BytesBuilder(copy: false);
    try {
      final req = await _client.getUrl(widget.url);
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('${res.statusCode}');
      _sub = res.listen(
        (chunk) {
          buf.add(chunk);
          final frame = takeJpeg(buf);
          if (frame != null && mounted) {
            setState(() {
              _frame = frame;
              _failed = false;
            });
          }
        },
        onError: (_) => _scheduleRetry(),
        onDone: _scheduleRetry,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (!mounted) return;
    setState(() => _failed = true);
    _retry = Timer(const Duration(seconds: 2), _connect);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _sub?.cancel();
    _client.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame == null) {
      return ColoredBox(
        color: Td.betonNuit,
        child: Center(
          child: Icon(_failed ? LucideIcons.cameraOff : LucideIcons.loaderCircle, size: 32, color: Td.ink3),
        ),
      );
    }
    return Image.memory(frame, fit: widget.fit, gaplessPlayback: true);
  }
}

/// Sort la dernière image JPEG complète (FFD8 ... FFD9) du tampon et garde le reste.
@visibleForTesting
Uint8List? takeJpeg(BytesBuilder buf) {
  final data = buf.toBytes();
  int? start, end;
  for (var i = data.length - 2; i >= 0; i--) {
    if (end == null) {
      if (data[i] == 0xFF && data[i + 1] == 0xD9) end = i + 2;
    } else if (data[i] == 0xFF && data[i + 1] == 0xD8) {
      start = i;
      break;
    }
  }
  if (start == null || end == null) {
    // Pas d'image complète : on garde tout, sans laisser le tampon grossir sans fin.
    buf.clear();
    if (data.length < 4 << 20) buf.add(data);
    return null;
  }
  buf
    ..clear()
    ..add(data.sublist(end));
  return Uint8List.sublistView(data, start, end);
}
