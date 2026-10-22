import 'dart:io';
import 'dart:typed_data';

import 'package:dartotsu_image_rust/dartotsu_image_rust.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bmp(int w, int h) {
  final row = (w * 3 + 3) & ~3;
  final size = 54 + row * h;
  final data = ByteData(size)
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4D)
    ..setUint32(2, size, Endian.little)
    ..setUint32(10, 54, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, w, Endian.little)
    ..setInt32(22, h, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(34, row * h, Endian.little);
  for (var i = 54; i < size; i++) {
    data.setUint8(i, (i * 7) & 0xFF);
  }
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Directory.systemTemp.createTempSync('dartotsu_scaler');
  final file = File('${dir.path}/page.bmp')..writeAsBytesSync(_bmp(400, 600));

  tearDownAll(() => dir.deleteSync(recursive: true));

  test('scales to the requested width', () async {
    if (!DartotsuImageRust.isSupported) return;
    final out = await DartotsuImageRust.scale(file.path, maxWidth: 200).result;
    expect(out, isNotNull);
    expect((out!.width, out.height), (200, 300));
    expect(out.rgba.length, 200 * 300 * 4);
  });

  test('returns null when the image already fits', () async {
    if (!DartotsuImageRust.isSupported) return;
    final out = await DartotsuImageRust.scale(file.path, maxWidth: 1000).result;
    expect(out, isNull);
  });

  test('returns null for a missing or corrupt file', () async {
    if (!DartotsuImageRust.isSupported) return;
    expect(
      await DartotsuImageRust.scale('${dir.path}/nope.jpg', maxWidth: 100).result,
      isNull,
    );
    final bad = File('${dir.path}/bad.jpg')..writeAsBytesSync([1, 2, 3, 4]);
    expect(await DartotsuImageRust.scale(bad.path, maxWidth: 100).result, isNull);
  });

  test('queued jobs can be cancelled', () async {
    if (!DartotsuImageRust.isSupported) return;
    final tickets = [
      for (var i = 0; i < 12; i++)
        DartotsuImageRust.scale(file.path, maxWidth: 100),
    ];
    tickets.last.cancel();
    final results = await Future.wait(tickets.map((t) => t.result));
    expect(results.last, isNull);
    expect(results.first, isNotNull);
  });
}
