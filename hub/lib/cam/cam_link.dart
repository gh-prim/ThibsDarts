import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:darts_engine/darts_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Lien MQTT avec le Pi 5 (dartos-cam) : reçoit les fléchettes détectées et
/// annonce si une partie est en cours. Contrat des topics : cam/README.md.
/// Sans broker (sur le Mac par exemple), il réessaie en silence et ne fait rien.
class CamLink {
  CamLink._();

  static final CamLink instance = CamLink._();

  static const dartTopic = 'thibsdarts/cam/dart';
  static const takeoutTopic = 'thibsdarts/cam/takeout';
  static const statusTopic = 'thibsdarts/cam/status';
  static const stateTopic = 'thibsdarts/hub/state';
  static const turnTopic = 'thibsdarts/hub/turn';
  static const cmdTopic = 'thibsdarts/cam/cmd';
  static const projectorTopic = 'thibsdarts/hub/projector';
  static const debugSetTopic = 'thibsdarts/debug/set';
  static const debugStateTopic = 'thibsdarts/debug/state';
  static const debugMarkTopic = 'thibsdarts/debug/mark';
  static const debugEventTopic = 'thibsdarts/debug/event';
  static const debugTruthTopic = 'thibsdarts/debug/truth';

  /// Vrai si le mode Debug est actif sur le Pi 5.
  bool get debugOn => debugState.value?['on'] == true;

  /// Partie ou entraînement en cours (ex. "série T20 de 15 fléchettes"), joint aux vérités du mode Debug.
  String? debugGame;

  /// Mode Debug : la vérité d'une fléchette, donnée par le joueur sur le hub.
  /// [kind] : correction (mauvais segment), fantome (pas une fléchette), manuelle (fléchette pas détectée,
  /// ajoutée à la main). Le Pi 5 la range avec les photos de la détection.
  void debugTruth(String kind, {DartThrow? detected, DartThrow? real, String? traceId, Offset? position}) {
    if (!debugOn) return;
    String? name(DartThrow? d) => d == null ? null : d.isMiss ? 'MISS' : d.label;
    _publish(debugTruthTopic, {
      'kind': kind,
      'detected': ?name(detected),
      'real': ?name(real),
      'trace': ?traceId,
      'x': ?position?.dx,
      'y': ?position?.dy,
      'game': ?debugGame,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Mode Debug du Pi 5 : {on, projector}, retenu sur le broker (gardé après un redémarrage).
  final ValueNotifier<Map<String, dynamic>?> debugState = ValueNotifier(null);

  /// Dernières décisions de la détection en mode Debug (la plus récente en premier).
  final ValueNotifier<List<Map<String, dynamic>>> debugEvents = ValueNotifier(const []);

  /// Écran de partie qui reçoit les fléchettes (position en unités plateau, en mm).
  void Function(DartThrow dart, Offset? position, String? traceId)? onDart;

  /// Fléchettes retirées de la cible : fin du tour.
  VoidCallback? onTakeout;

  /// Dernier statut publié par le Pi 5 (online, mode...), null si jamais reçu.
  final ValueNotifier<Map<String, dynamic>?> camStatus = ValueNotifier(null);

  /// Adresse du serveur d'aperçu des caméras (ex. http://192.168.1.160:8081), si le Pi 5 est en ligne.
  Uri? get previewBase {
    final s = camStatus.value;
    final url = s?['preview'];
    return s?['state'] == 'online' && url is String ? Uri.tryParse(url) : null;
  }

  MqttServerClient? _client;
  bool _playing = false;

  /// Vrai pendant une partie (annoncé au Pi 5 sur thibsdarts/hub/state).
  bool get playing => _playing;
  final _seen = <String>{};

  Future<void> start() async {
    if (_client != null) return;
    final host = Platform.environment['DARTOS_MQTT_HOST'] ?? 'localhost';
    final client = MqttServerClient(host, 'dartos-hub-$pid')
      ..port = 1883
      ..keepAlivePeriod = 20
      ..autoReconnect = true
      ..logging(on: false)
      ..onAutoReconnected = _publishState;
    _client = client;
    while (true) {
      try {
        await client.connect();
        if (client.connectionStatus?.state == MqttConnectionState.connected) break;
      } catch (_) {
        client.disconnect();
      }
      await Future<void>.delayed(const Duration(seconds: 10));
    }
    debugPrint('CamLink: connecté à $host');
    for (final t in [dartTopic, takeoutTopic, statusTopic, debugStateTopic, debugEventTopic]) {
      client.subscribe(t, MqttQos.atLeastOnce);
    }
    client.updates!.listen((events) {
      for (final e in events) {
        final msg = e.payload as MqttPublishMessage;
        _onMessage(e.topic, MqttPublishPayload.bytesToStringAsString(msg.payload.message));
      }
    });
    _publishState();
  }

  /// Appelé par les écrans de partie à l'ouverture et à la fermeture.
  void setPlaying(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    _publishState();
  }

  /// Fin de tour (bouton ou retrait) : le Pi 5 sait que les fléchettes en place sont de l'ancien tour.
  void turnEnded() {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) return;
    final payload = MqttClientPayloadBuilder()..addUTF8String(jsonEncode({'ts': DateTime.now().millisecondsSinceEpoch}));
    client.publishMessage(turnTopic, MqttQos.atLeastOnce, payload.payload!);
  }

  /// Demande au Pi 5 de s'éteindre ("poweroff") ou de redémarrer ("reboot"). Faux si le broker est injoignable.
  bool sendCommand(String action) {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) return false;
    final payload = MqttClientPayloadBuilder()..addUTF8String(jsonEncode({'action': action}));
    client.publishMessage(cmdTopic, MqttQos.atLeastOnce, payload.payload!);
    return true;
  }

  String _scene = jsonEncode({'scene': 'accueil'});

  /// Écran du hub hors partie, pour l'animation d'attente du vidéoprojecteur :
  /// accueil, partie (choix d'une partie) ou entrainement (choix d'un entraînement).
  void setScene(String scene) => _setProjector({'scene': scene});

  /// En partie : nom du jeu écrit sur le surround, et check-out proposé (cases allumées par le projecteur).
  void setGameInfo(String title, {List<String>? checkout}) => _setProjector({
    'scene': 'jeu',
    'title': title,
    if (checkout != null && checkout.isNotEmpty) 'checkout': checkout,
  });

  void _setProjector(Map<String, dynamic> body) {
    final text = jsonEncode(body);
    if (_scene == text) return;
    _scene = text;
    _publishScene();
  }

  void _publishScene() {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) return;
    final payload = MqttClientPayloadBuilder()..addUTF8String(_scene);
    client.publishMessage(projectorTopic, MqttQos.atLeastOnce, payload.payload!, retain: true);
  }

  /// Mode Debug : captures [on] et vidéoprojecteur [projector] (null : inchangé).
  bool setDebug({bool? on, bool? projector}) => _publish(debugSetTopic, {
    'on': ?on,
    'projector': ?projector,
  });

  /// Bouton Signaler : le Pi 5 garde les images du moment.
  bool debugMark() => _publish(debugMarkTopic, {'ts': DateTime.now().millisecondsSinceEpoch, 'game': ?debugGame});

  bool _publish(String topic, Map<String, dynamic> body) {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) return false;
    final payload = MqttClientPayloadBuilder()..addUTF8String(jsonEncode(body));
    client.publishMessage(topic, MqttQos.atLeastOnce, payload.payload!);
    return true;
  }

  void _publishState() {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) return;
    final payload = MqttClientPayloadBuilder()
      ..addUTF8String(jsonEncode({'playing': _playing, 'ts': DateTime.now().millisecondsSinceEpoch}));
    client.publishMessage(stateTopic, MqttQos.atLeastOnce, payload.payload!, retain: true);
    _publishScene();
  }

  void _onMessage(String topic, String text) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      json = {};
    }
    switch (topic) {
      case statusTopic:
        camStatus.value = json;
      case debugStateTopic:
        debugState.value = json;
      case debugEventTopic:
        debugEvents.value = [json, ...debugEvents.value.take(59)];
      case takeoutTopic:
        onTakeout?.call();
      case dartTopic:
        final parsed = parseDart(json);
        if (parsed == null) {
          debugPrint('CamLink: fléchette illisible $text');
          return;
        }
        final id = json['id']?.toString();
        if (id != null) {
          if (!_seen.add(id)) return;
          if (_seen.length > 100) _seen.remove(_seen.first);
        }
        onDart?.call(parsed.$1, parsed.$2, json['source'] == 'vision' ? id : null);
    }
  }

  /// Fléchette du contrat MQTT : number 0-20 ou 25, multiplier 0-3, x/y optionnels en mm.
  @visibleForTesting
  static (DartThrow, Offset?)? parseDart(Map<String, dynamic> json) {
    final n = json['number'], m = json['multiplier'];
    if (n is! int || m is! int) return null;
    DartThrow dart;
    if (n == 0 || m == 0) {
      dart = const DartThrow.miss();
    } else if (!((n >= 1 && n <= 20 && m <= 3) || (n == 25 && m <= 2)) || m < 0) {
      return null;
    } else {
      dart = DartThrow(n, m);
    }
    final x = json['x'], y = json['y'];
    final pos = x is num && y is num ? Offset(x.toDouble(), y.toDouble()) : null;
    return (dart, pos);
  }
}
