import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_mobile/models/imu_block.dart';

/// Builds one raw IMU block: a 12-byte header followed by [sampleCount]
/// 12-byte samples, all sharing the same raw axis values unless overridden
/// per-sample by the caller.
Uint8List buildImuBlockBytes({
  int version = imuBlockVersion,
  int seq = 0,
  int deviceTimeMs = 0,
  int firstSampleIndex = 0,
  required int sampleCount,
  int samplePeriodMs = imuBlockSamplePeriodMsDefault,
  int flags = 0,
  int ax = 0,
  int ay = 0,
  int az = 0,
  int gx = 0,
  int gy = 0,
  int gz = 0,
}) {
  final totalBytes = imuBlockHeaderBytes + imuBlockSampleBytes * sampleCount;
  final bytes = ByteData(totalBytes);
  bytes.setUint8(ImuBlockHeaderOffsets.version, version);
  bytes.setUint8(ImuBlockHeaderOffsets.seq, seq);
  bytes.setUint32(ImuBlockHeaderOffsets.deviceTimeMs, deviceTimeMs, Endian.little);
  bytes.setUint16(ImuBlockHeaderOffsets.firstSampleIndex, firstSampleIndex, Endian.little);
  bytes.setUint8(ImuBlockHeaderOffsets.sampleCount, sampleCount);
  bytes.setUint8(ImuBlockHeaderOffsets.samplePeriodMs, samplePeriodMs);
  bytes.setUint8(ImuBlockHeaderOffsets.flags, flags);
  bytes.setUint8(ImuBlockHeaderOffsets.reserved, 0);

  for (var i = 0; i < sampleCount; i++) {
    final base = imuBlockHeaderBytes + i * imuBlockSampleBytes;
    bytes.setInt16(base + ImuSampleOffsets.ax, ax, Endian.little);
    bytes.setInt16(base + ImuSampleOffsets.ay, ay, Endian.little);
    bytes.setInt16(base + ImuSampleOffsets.az, az, Endian.little);
    bytes.setInt16(base + ImuSampleOffsets.gx, gx, Endian.little);
    bytes.setInt16(base + ImuSampleOffsets.gy, gy, Endian.little);
    bytes.setInt16(base + ImuSampleOffsets.gz, gz, Endian.little);
  }

  return bytes.buffer.asUint8List();
}

void main() {
  group('schema fixture matches the decoder', () {
    late Map<String, dynamic> imuSchema;

    setUpAll(() {
      final raw = File('test/fixtures/ble_telemetry_packet_schema.json').readAsStringSync();
      final schema = jsonDecode(raw) as Map<String, dynamic>;
      imuSchema = schema['imuBlock'] as Map<String, dynamic>;
    });

    test('top-level IMU block metadata', () {
      expect(imuSchema['version'], imuBlockVersion);
      expect(imuSchema['headerBytes'], imuBlockHeaderBytes);
      expect(imuSchema['sampleBytes'], imuBlockSampleBytes);
      expect(imuSchema['maxSamples'], imuBlockMaxSamples);
      expect(imuSchema['samplePeriodMs'], imuBlockSamplePeriodMsDefault);
    });

    test('scale factors match ImuScale', () {
      expect((imuSchema['scale']['accel']['lsbPerUnit'] as num).toDouble(), ImuScale.accelLsbPerG);
      expect((imuSchema['scale']['gyro']['lsbPerUnit'] as num).toDouble(), ImuScale.gyroLsbPerDps);
    });

    test('header field offsets/sizes match ImuBlockHeaderOffsets', () {
      final fields = (imuSchema['headerFields'] as List).cast<Map<String, dynamic>>();
      final expectedOffsets = <String, int>{
        'version': ImuBlockHeaderOffsets.version,
        'seq': ImuBlockHeaderOffsets.seq,
        'deviceTimeMs': ImuBlockHeaderOffsets.deviceTimeMs,
        'firstSampleIndex': ImuBlockHeaderOffsets.firstSampleIndex,
        'sampleCount': ImuBlockHeaderOffsets.sampleCount,
        'samplePeriodMs': ImuBlockHeaderOffsets.samplePeriodMs,
        'flags': ImuBlockHeaderOffsets.flags,
        'reserved': ImuBlockHeaderOffsets.reserved,
      };
      expect(fields.length, expectedOffsets.length);
      for (final field in fields) {
        final name = field['name'] as String;
        expect(expectedOffsets.containsKey(name), isTrue, reason: 'unexpected header field $name');
        expect(field['offset'], expectedOffsets[name], reason: 'offset mismatch for $name');
      }
      // headerBytes must exactly cover the header fields.
      final last = fields.reduce((a, b) => (a['offset'] as int) > (b['offset'] as int) ? a : b);
      expect((last['offset'] as int) + (last['size'] as int), imuBlockHeaderBytes);
    });

    test('sample field offsets match ImuSampleOffsets', () {
      final fields = (imuSchema['sampleFields'] as List).cast<Map<String, dynamic>>();
      final expectedOffsets = <String, int>{
        'ax': ImuSampleOffsets.ax,
        'ay': ImuSampleOffsets.ay,
        'az': ImuSampleOffsets.az,
        'gx': ImuSampleOffsets.gx,
        'gy': ImuSampleOffsets.gy,
        'gz': ImuSampleOffsets.gz,
      };
      expect(fields.length, expectedOffsets.length);
      for (final field in fields) {
        final name = field['name'] as String;
        expect(expectedOffsets.containsKey(name), isTrue, reason: 'unexpected sample field $name');
        expect(field['offset'], expectedOffsets[name], reason: 'offset mismatch for $name');
      }
      final last = fields.reduce((a, b) => (a['offset'] as int) > (b['offset'] as int) ? a : b);
      expect((last['offset'] as int) + (last['size'] as int), imuBlockSampleBytes);
    });

    test('flag bit positions match ImuBlockFlagBits', () {
      final bits = (imuSchema['flags']['bits'] as List).cast<Map<String, dynamic>>();
      final expected = <String, int>{
        'deviceOverflow': ImuBlockFlagBits.deviceOverflow,
        'readError': ImuBlockFlagBits.readError,
        'sensorReconfigured': ImuBlockFlagBits.sensorReconfigured,
      };
      for (final bit in bits) {
        final name = bit['name'] as String;
        if (name == 'reserved') continue;
        expect(expected.containsKey(name), isTrue, reason: 'unexpected IMU flag $name in schema');
        expect(bit['bit'], expected[name], reason: 'bit position mismatch for $name');
      }
    });
  });

  group('decoding a valid block', () {
    test('decodes header and sample fields, and scales correctly', () {
      final bytes = buildImuBlockBytes(
        seq: 7,
        deviceTimeMs: 1000,
        firstSampleIndex: 42,
        sampleCount: 1,
        samplePeriodMs: 10,
        flags: 0,
        ax: 4096, // 1.0 g
        ay: -4096, // -1.0 g
        az: 2048, // 0.5 g
        gx: 655, // ~10 dps
        gy: -655,
        gz: 0,
      );

      final block = ImuBlock.decode(bytes);

      expect(block.version, imuBlockVersion);
      expect(block.seq, 7);
      expect(block.deviceTimeMs, 1000);
      expect(block.firstSampleIndex, 42);
      expect(block.sampleCount, 1);
      expect(block.samplePeriodMs, 10);
      expect(block.samples, hasLength(1));

      final sample = block.samples.single;
      expect(sample.sampleIndex, 42);
      expect(sample.deviceTimeMs, 1000);
      expect(sample.axRaw, 4096);
      expect(sample.axG, closeTo(1.0, 1e-9));
      expect(sample.ayG, closeTo(-1.0, 1e-9));
      expect(sample.azG, closeTo(0.5, 1e-9));
      expect(sample.gxDps, closeTo(10.0, 0.01));
      expect(sample.gyDps, closeTo(-10.0, 0.01));
      expect(sample.gzDps, closeTo(0.0, 1e-9));
    });

    test('per-sample device time and sample index advance across a multi-sample block', () {
      final bytes = buildImuBlockBytes(
        deviceTimeMs: 5000,
        firstSampleIndex: 65534, // wraps within this block
        sampleCount: 4,
        samplePeriodMs: 10,
      );

      final block = ImuBlock.decode(bytes);
      expect(block.samples, hasLength(4));

      expect(block.samples[0].sampleIndex, 65534);
      expect(block.samples[1].sampleIndex, 65535);
      expect(block.samples[2].sampleIndex, 0); // wrapped
      expect(block.samples[3].sampleIndex, 1);

      expect(block.samples[0].deviceTimeMs, 5000);
      expect(block.samples[1].deviceTimeMs, 5010);
      expect(block.samples[2].deviceTimeMs, 5020);
      expect(block.samples[3].deviceTimeMs, 5030);
    });

    test('flag bits decode correctly, including sensorReconfigured', () {
      final overflowOnly = ImuBlock.decode(buildImuBlockBytes(sampleCount: 1, flags: 1 << ImuBlockFlagBits.deviceOverflow));
      expect(overflowOnly.deviceOverflow, isTrue);
      expect(overflowOnly.readError, isFalse);
      expect(overflowOnly.sensorReconfigured, isFalse);

      final reconfiguredOnly =
          ImuBlock.decode(buildImuBlockBytes(sampleCount: 1, flags: 1 << ImuBlockFlagBits.sensorReconfigured));
      expect(reconfiguredOnly.deviceOverflow, isFalse);
      expect(reconfiguredOnly.readError, isFalse);
      expect(reconfiguredOnly.sensorReconfigured, isTrue);
    });

    test('accepts the maximum sample count', () {
      final bytes = buildImuBlockBytes(sampleCount: imuBlockMaxSamples);
      final block = ImuBlock.decode(bytes);
      expect(block.samples, hasLength(imuBlockMaxSamples));
    });
  });

  group('rejecting malformed blocks', () {
    test('too short for even the header throws', () {
      expect(
        () => ImuBlock.decode(Uint8List(imuBlockHeaderBytes - 1)),
        throwsA(isA<ImuBlockDecodeException>()),
      );
    });

    test('wrong version throws', () {
      final bytes = buildImuBlockBytes(version: 2, sampleCount: 1);
      expect(() => ImuBlock.decode(bytes), throwsA(isA<ImuBlockDecodeException>()));
    });

    test('sampleCount of 0 throws', () {
      // Build manually: buildImuBlockBytes requires sampleCount >= 0 sample
      // bytes but a real firmware bug could still claim 0 in the header.
      final bytes = ByteData(imuBlockHeaderBytes);
      bytes.setUint8(ImuBlockHeaderOffsets.version, imuBlockVersion);
      bytes.setUint8(ImuBlockHeaderOffsets.sampleCount, 0);
      expect(
        () => ImuBlock.decode(bytes.buffer.asUint8List()),
        throwsA(isA<ImuBlockDecodeException>()),
      );
    });

    test('sampleCount above maxSamples throws', () {
      final bytes = buildImuBlockBytes(sampleCount: imuBlockMaxSamples + 1);
      expect(() => ImuBlock.decode(bytes), throwsA(isA<ImuBlockDecodeException>()));
    });

    test('a size that does not match headerBytes + sampleBytes*sampleCount throws', () {
      final bytes = buildImuBlockBytes(sampleCount: 2);
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 1);
      expect(() => ImuBlock.decode(truncated), throwsA(isA<ImuBlockDecodeException>()));
    });
  });

  group('ImuGapTracker', () {
    test('the first block seen has 0 missing samples', () {
      final tracker = ImuGapTracker();
      final block = ImuBlock.decode(buildImuBlockBytes(firstSampleIndex: 100, sampleCount: 5));
      expect(tracker.missingSamplesFor(block), 0);
    });

    test('consecutive blocks (no gap) report 0 missing', () {
      final tracker = ImuGapTracker();
      final first = ImuBlock.decode(buildImuBlockBytes(firstSampleIndex: 0, sampleCount: 5));
      tracker.missingSamplesFor(first);
      final second = ImuBlock.decode(buildImuBlockBytes(firstSampleIndex: 5, sampleCount: 5));
      expect(tracker.missingSamplesFor(second), 0);
    });

    test('a gap between blocks is reported', () {
      final tracker = ImuGapTracker();
      final first = ImuBlock.decode(buildImuBlockBytes(firstSampleIndex: 0, sampleCount: 5));
      tracker.missingSamplesFor(first);
      // Expected next firstSampleIndex is 5; got 8 -> 3 missing.
      final second = ImuBlock.decode(buildImuBlockBytes(firstSampleIndex: 8, sampleCount: 5));
      expect(tracker.missingSamplesFor(second), 3);
    });

    test('a gap across the uint16 wrap (65536 -> 0) is computed correctly', () {
      final tracker = ImuGapTracker();
      final first = ImuBlock.decode(buildImuBlockBytes(firstSampleIndex: 65530, sampleCount: 5));
      tracker.missingSamplesFor(first); // covers 65530..65534, next expected 65535
      // Next block starts at 2 instead of 65535 -> missing = 65535..65535 (1) + 0,1 (2) = 3
      final second = ImuBlock.decode(buildImuBlockBytes(firstSampleIndex: 2, sampleCount: 3));
      expect(tracker.missingSamplesFor(second), 3);
    });

    test('reset() forgets the previous block', () {
      final tracker = ImuGapTracker();
      final first = ImuBlock.decode(buildImuBlockBytes(firstSampleIndex: 0, sampleCount: 5));
      tracker.missingSamplesFor(first);
      tracker.reset();
      final second = ImuBlock.decode(buildImuBlockBytes(firstSampleIndex: 999, sampleCount: 5));
      expect(tracker.missingSamplesFor(second), 0);
    });
  });
}
