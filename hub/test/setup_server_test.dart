import 'dart:convert';
import 'dart:io';

import 'package:dartos_hub/setup/owner_store.dart';
import 'package:dartos_hub/setup/setup_server.dart';
import 'package:dartos_hub/setup/wifi_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late SetupController c;
  final http = HttpClient();
  const base = 'http://127.0.0.1:${SetupController.port}';

  Future<(int, Map<String, dynamic>)> call(String method, String path, {Object? body, String? token, List<int>? raw}) async {
    final req = await http.openUrl(method, Uri.parse('$base$path'));
    if (token != null) req.headers.set('authorization', 'Bearer $token');
    if (raw != null) {
      req.add(raw);
    } else if (body != null) {
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('dartos-setup');
    OwnerStore.useDirectory(dir.path);
    c = SetupController(wifi: SimulatedWifi(), store: OwnerStore.instance);
    await c.start();
  });

  tearDown(() async {
    await c.stop();
  });

  test('parcours complet depuis l’iPhone', () async {
    expect(c.qrPayload, startsWith('thibsdarts://setup?'));
    expect(c.qrPayload, contains('c=${c.code}'));

    var (s, j) = await call('POST', '/api/setup/pair', body: {'code': '0000x', 'device': 'iPhone'});
    expect(s, 403);

    (s, j) = await call('POST', '/api/setup/pair', body: {'code': c.code, 'device': 'iPhone de Thibault'});
    expect(s, 200);
    final token = j['token'] as String;
    expect(c.phase, SetupPhase.paired);
    expect(c.phoneName, 'iPhone de Thibault');

    (s, j) = await call('GET', '/api/setup/networks');
    expect(s, 401);
    (s, j) = await call('GET', '/api/setup/networks', token: token);
    expect((j['networks'] as List), isNotEmpty);

    (s, j) = await call('POST', '/api/setup/wifi', token: token, body: {'ssid': 'Maison', 'password': 'faux'});
    expect(s, 202);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(c.wifiState, WifiState.error);

    (s, j) = await call('POST', '/api/setup/wifi', token: token, body: {'ssid': 'Maison', 'password': 'golden-hour'});
    await Future<void>.delayed(const Duration(seconds: 3));
    (s, j) = await call('GET', '/api/setup/status', token: token);
    expect(j['wifi'], 'ok');
    expect(j['phase'], 'profile');

    (s, j) = await call('POST', '/api/setup/profile', token: token, body: {'firstName': 'Thibault'});
    expect(s, 400, reason: 'photo obligatoire');

    (s, j) = await call('PUT', '/api/setup/photo', token: token, raw: List.filled(5000, 7));
    expect(s, 200);
    (s, j) = await call('POST', '/api/setup/profile',
        token: token, body: {'firstName': 'Thibault', 'lastName': 'Hubert', 'nickname': 'Thibs'});
    expect(s, 200);
    expect(c.phase, SetupPhase.done);

    final saved = OwnerStore.instance.load()!;
    expect(saved.nickname, 'Thibs');
    expect(saved.photoPath, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
