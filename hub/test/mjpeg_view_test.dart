import 'dart:typed_data';

import 'package:dartos_hub/widgets/mjpeg_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('découpe les images JPEG du flux MJPEG', () {
    final buf = BytesBuilder(copy: false);
    buf.add([0x2D, 0x2D, 0xFF, 0xD8, 1, 2]);
    expect(takeJpeg(buf), isNull);
    buf.add([3, 0xFF, 0xD9, 0x0D, 0x0A, 0xFF, 0xD8, 9]);
    expect(takeJpeg(buf), [0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);
    buf.add([0xFF, 0xD9]);
    expect(takeJpeg(buf), [0xFF, 0xD8, 9, 0xFF, 0xD9]);
  });
}
