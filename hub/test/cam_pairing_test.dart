import 'package:dartos_hub/cam/cam_pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splitTerse garde les : échappés', () {
    expect(CamPairing.splitTerse(r'Box\:5G:802-11-wireless:wlan0'), ['Box:5G', '802-11-wireless', 'wlan0']);
    expect(CamPairing.splitTerse('ThibsDarts-cam-A1B2'), ['ThibsDarts-cam-A1B2']);
  });
}
