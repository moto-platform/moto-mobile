import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/gps_block.dart';

/// Builds one raw GPS block from the generated offsets (never hand-written).
Uint8List buildGpsBlockBytes({
  int version = BleGpsBlock.version,
  int seq = 0,
  int deviceTimeMs = 0,
  int groundSpeed = 0,
  int headingOfMotion = 0,
  int speedAccuracy = 0,
  int headingAccuracy = 0,
  int fixType = BleGpsFixType.fix3d,
  int numSv = 0,
  int flags = 0,
}) {
  final bytes = ByteData(BleGpsBlock.totalBytes);
  bytes.setUint8(BleGpsOffsets.version, version);
  bytes.setUint8(BleGpsOffsets.seq, seq);
  bytes.setUint32(BleGpsOffsets.deviceTimeMs, deviceTimeMs, Endian.little);
  bytes.setInt32(BleGpsOffsets.groundSpeed, groundSpeed, Endian.little);
  bytes.setInt32(BleGpsOffsets.headingOfMotion, headingOfMotion, Endian.little);
  bytes.setUint32(BleGpsOffsets.speedAccuracy, speedAccuracy, Endian.little);
  bytes.setUint32(BleGpsOffsets.headingAccuracy, headingAccuracy, Endian.little);
  bytes.setUint8(BleGpsOffsets.fixType, fixType);
  bytes.setUint8(BleGpsOffsets.numSv, numSv);
  bytes.setUint8(BleGpsOffsets.flags, flags);
  bytes.setUint8(BleGpsOffsets.reserved, 0);
  return bytes.buffer.asUint8List();
}

Uint8List _hex(String hex) => Uint8List.fromList(
    List.generate(hex.length ~/ 2, (i) => int.parse(hex.substring(2 * i, 2 * i + 2), radix: 16)));

void main() {
  test('generated layout: fields exactly cover totalBytes', () {
    final fields = <(int, int)>[
      (BleGpsOffsets.version, BleGpsSizes.version),
      (BleGpsOffsets.seq, BleGpsSizes.seq),
      (BleGpsOffsets.deviceTimeMs, BleGpsSizes.deviceTimeMs),
      (BleGpsOffsets.groundSpeed, BleGpsSizes.groundSpeed),
      (BleGpsOffsets.headingOfMotion, BleGpsSizes.headingOfMotion),
      (BleGpsOffsets.speedAccuracy, BleGpsSizes.speedAccuracy),
      (BleGpsOffsets.headingAccuracy, BleGpsSizes.headingAccuracy),
      (BleGpsOffsets.fixType, BleGpsSizes.fixType),
      (BleGpsOffsets.numSv, BleGpsSizes.numSv),
      (BleGpsOffsets.flags, BleGpsSizes.flags),
      (BleGpsOffsets.reserved, BleGpsSizes.reserved),
    ];
    var next = 0;
    for (final (offset, size) in fields) {
      expect(offset, next);
      next += size;
    }
    expect(next, BleGpsBlock.totalBytes);
  });

  test('decodes every field and scales speed and heading', () {
    final block = GpsBlock.decode(buildGpsBlockBytes(
      seq: 7,
      deviceTimeMs: 0xFFFFFFF0,
      groundSpeed: 27778,
      headingOfMotion: 35999999,
      speedAccuracy: 250,
      headingAccuracy: 100000,
      fixType: BleGpsFixType.fix3d,
      numSv: 12,
      flags: BleGpsFlagBits.gnssFixOk | BleGpsFlagBits.uartOverflow,
    ));
    expect(block.version, BleGpsBlock.version);
    expect(block.seq, 7);
    expect(block.deviceTimeMs, 0xFFFFFFF0);
    expect(block.groundSpeedMps, closeTo(27.778, 1e-9));
    expect(block.headingOfMotionDeg, closeTo(359.99999, 1e-9));
    expect(block.speedAccuracyMps, closeTo(0.25, 1e-9));
    expect(block.headingAccuracyDeg, closeTo(1.0, 1e-9));
    expect(block.numSv, 12);
    expect(block.gnssFixOk, isTrue);
    expect(block.parseError, isFalse);
    expect(block.uartOverflow, isTrue);
    expect(block.fixTypeLabel, '3D');
  });

  test('ground speed and heading are signed int32', () {
    final block = GpsBlock.decode(buildGpsBlockBytes(groundSpeed: -5, headingOfMotion: -100000));
    expect(block.groundSpeed, -5);
    expect(block.headingOfMotionDeg, closeTo(-1.0, 1e-9));
  });

  test('agrees with moto-server on a block of its v4_gps fixture', () {
    // tests/fixtures/v4_gps_session/gps.csv row 2 in moto-server, packed there
    // from the same defs schema by its own encoder.
    final block = GpsBlock.decode(_hex('01fcf0230000672b0000798489002c01000050c3000003090100'));
    expect(block.seq, 252);
    expect(block.deviceTimeMs, 9200);
    expect(block.groundSpeed, 11111);
    expect(block.headingOfMotion, 9012345);
    expect(block.speedAccuracy, 300);
    expect(block.headingAccuracy, 50000);
    expect(block.fixType, BleGpsFixType.fix3d);
    expect(block.numSv, 9);
    expect(block.flags, BleGpsFlagBits.gnssFixOk);
    expect(block.groundSpeedMps.toString(), '11.111');
    expect(block.headingOfMotionDeg.toString(), '90.12345');
  });

  test('rejects a wrong size (never truncated) and a wrong version', () {
    final good = buildGpsBlockBytes();
    expect(() => GpsBlock.decode(Uint8List.sublistView(good, 0, good.length - 1)),
        throwsA(isA<GpsBlockDecodeException>()));
    expect(() => GpsBlock.decode(Uint8List.fromList([...good, 0])), throwsA(isA<GpsBlockDecodeException>()));
    expect(() => GpsBlock.decode(buildGpsBlockBytes(version: BleGpsBlock.version + 1)),
        throwsA(isA<GpsBlockDecodeException>().having((e) => e.message, 'message', contains('version'))));
  });

  test('usableForSpeedCheck follows the schema fixType rule', () {
    bool usable(int fixType, int flags) =>
        GpsBlock.decode(buildGpsBlockBytes(fixType: fixType, flags: flags)).usableForSpeedCheck;
    const ok = BleGpsFlagBits.gnssFixOk;
    expect(usable(BleGpsFixType.fix3d, ok), isTrue);
    expect(usable(BleGpsFixType.gnssDeadReckoning, ok), isTrue);
    expect(usable(BleGpsFixType.fix3d, 0), isFalse);
    expect(usable(BleGpsFixType.fix2d, ok), isFalse);
    expect(usable(BleGpsFixType.noFix, ok), isFalse);
    expect(usable(BleGpsFixType.deadReckoningOnly, ok), isFalse);
  });

  test('GpsSeqTracker counts lost or MTU-skipped blocks mod 256', () {
    final tracker = GpsSeqTracker();
    GpsBlock b(int seq) => GpsBlock.decode(buildGpsBlockBytes(seq: seq));
    expect(tracker.missingBlocksFor(b(250)), 0); // first block
    expect(tracker.missingBlocksFor(b(251)), 0);
    expect(tracker.missingBlocksFor(b(254)), 2);
    expect(tracker.missingBlocksFor(b(0)), 1); // 255 missing across the wrap
    expect(tracker.missingBlocksFor(b(1)), 0);
    tracker.reset();
    expect(tracker.missingBlocksFor(b(100)), 0);
  });

  test('redactDeviceIds removes MAC addresses and UUID-shaped device ids', () {
    expect(
      redactDeviceIds('bond failed for AA:bb:0C:11:22:33 (code 5)'),
      'bond failed for <device> (code 5)',
    );
    expect(
      redactDeviceIds('remoteId: 3C8F9255-BA3F-4BDA-90B3-8C30BCBCACE1 insufficient authentication'),
      'remoteId: <id> insufficient authentication',
    );
    expect(redactDeviceIds('FlutterBluePlusException | setNotifyValue | android-code: 5 | GATT_INSUF'),
        'FlutterBluePlusException | setNotifyValue | android-code: 5 | GATT_INSUF');
  });
}
