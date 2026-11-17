import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/foundation.dart';

import 'cam_link.dart';

/// Traces des fléchettes détectées, gardées par le Pi 5 (cam/vision/traces.py) :
/// ce que chaque caméra a capté, et l'envoi des corrections pour l'apprentissage (cam/vision/learning.py).
class CamTraces {
  CamTraces._();

  static Uri? get _base => CamLink.instance.previewBase;

  static bool get available => _base != null;

  static String slug(String cam) =>
      cam.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

  /// Image d'une caméra pour cette fléchette, overlay dessiné par le Pi 5 à la demande.
  static String? imageUrl(String id, String cam, {bool after = true, bool overlay = true, bool zoom = false}) {
    final base = _base;
    if (base == null) return null;
    return base
        .replace(
          path: '/trace/$id/${slug(cam)}.jpg',
          queryParameters: {
            'view': after ? 'apres' : 'avant',
            'overlay': overlay ? '1' : '0',
            if (zoom) 'zoom': '1',
          },
        )
        .toString();
  }

  static Future<Map<String, dynamic>?> _get(String path) async {
    final base = _base;
    if (base == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.getUrl(base.replace(path: path));
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Mesures de chaque caméra pour cette fléchette, null si le Pi 5 ne l'a plus (30 dernières).
  static Future<Map<String, dynamic>?> trace(String id) => _get('/trace/$id');

  /// Faits sur l'apprentissage : corrections, écart médian, poids de chaque caméra.
  static Future<Map<String, dynamic>?> learning() => _get('/learning');

  /// Envoie la vraie fléchette au Pi 5 (position si touchée sur la cible). Sans attendre la réponse.
  static void correct(String id, DartThrow dart, Offset? position) {
    final base = _base;
    if (base == null) return;
    unawaited(() async {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      try {
        final req = await client.postUrl(base.replace(path: '/trace/$id/correct'));
        final body = utf8.encode(
          jsonEncode({
            'number': dart.isMiss ? 0 : dart.sector,
            'multiplier': dart.isMiss ? 0 : dart.multiplier,
            if (position != null) 'x': position.dx,
            if (position != null) 'y': position.dy,
          }),
        );
        req.headers.contentType = ContentType.json;
        req.contentLength = body.length;
        req.add(body);
        await (await req.close().timeout(const Duration(seconds: 6))).drain<void>();
      } catch (e) {
        debugPrint('CamTraces: correction non envoyée ($e)');
      } finally {
        client.close(force: true);
      }
    }());
  }
}
