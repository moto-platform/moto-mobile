import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/imu_block.dart';

/// Builds one raw IMU block: a 12-byte header followed by [sampleCount]
/// 12-byte samples, all sharing the same raw axis values unless overridden
/// per-sample by the caller.
Uint8List buildImuBlockBytes({
  int version = BleImuBlock.version,
  int seq = 0,
  int deviceTimeMs = 0,
  int firstSampleIndex = 0,
  required int sampleCount,
  int samplePeriodMs = BleImuBlock.samplePeriodMs,
  int flags = 0,
  int ax = 0,
  int ay = 0,
  int az = 0,
  int gx = 0,
  int gy = 0,
  int gz = 0,
}) {
  final totalBytes = BleImuBlock.headerBytes + BleImuBlock.sampleBytes * sampleCount;
  final bytes = ByteData(totalBytes);
  bytes.setUint8(BleImuHeaderOffsets.version, version);
  bytes.setUint8(BleImuHeaderOffsets.seq, seq);
  bytes.setUint32(BleImuHeaderOffsets.deviceTimeMs, deviceTimeMs, Endian.little);
  bytes.setUint16(BleImuHeaderOffsets.firstSampleIndex, firstSampleIndex, Endian.little);
  bytes.setUint8(BleImuHeaderOffsets.sampleCount, sampleCount);
  bytes.setUint8(BleImuHeaderOffsets.samplePeriodMs, samplePeriodMs);
  bytes.setUint8(BleImuHeaderOffsets.flags, flags);
  bytes.setUint8(BleImuHeaderOffsets.reserved, 0);

  for (var i = 0; i < sampleCount; i++) {
    final base = BleImuBlock.headerBytes + i * BleImuBlock.sampleBytes;
    bytes.setInt16(base + BleImuSampleOffsets.ax, ax, Endian.little);
    bytes.setInt16(base + BleImuSampleOffsets.ay, ay, Endian.little);
    bytes.setInt16(base + BleImuSampleOffsets.az, az, Endian.little);
    bytes.setInt16(base + BleImuSampleOffsets.gx, gx, Endian.little);
    bytes.setInt16(base + BleImuSampleOffsets.gy, gy, Endian.little);
    bytes.setInt16(base + BleImuSampleOffsets.gz, gz, Endian.little);
  }

  return bytes.buffer.asUint8List();
}

void main() {
  group('generated layout is self-consistent', () {
    // The layout itself lives in the generated moto_defs package (D-061); a
    // drift between it and the firmware is caught by moto-vehicle-defs, not
    // here. These checks only guard the assumptions the decoder makes.
    test('header fields exactly cover headerBytes', () {
      final fields = <(int, int)>[
        (BleImuHeaderOffsets.version, BleImuHeaderSizes.version),
        (BleImuHeaderOffsets.seq, BleImuHeaderSizes.seq),
        (BleImuHeaderOffsets.deviceTimeMs, BleImuHeaderSizes.deviceTimeMs),
        (BleImuHeaderOffsets.firstSampleIndex, BleImuHeaderSizes.firstSampleIndex),
        (BleImuHeaderOffsets.sampleCount, BleImuHeaderSizes.sampleCount),
        (BleImuHeaderOffsets.samplePeriodMs, BleImuHeaderSizes.samplePeriodMs),
        (BleImuHeaderOffsets.flags, BleImuHeaderSizes.flags),
        (BleImuHeaderOffsets.reserved, BleImuHeaderSizes.reserved),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      var next = 0;
      for (final (offset, size) in fields) {
        expect(offset, next, reason: 'header fields must be contiguous');
        next = offset + size;
      }
      expect(next, BleImuBlock.headerBytes);
    });

    test('sample fields exactly cover sampleBytes', () {
      final fields = <(int, int)>[
        (BleImuSampleOffsets.ax, BleImuSampleSizes.ax),
        (BleImuSampleOffsets.ay, BleImuSampleSizes.ay),
        (BleImuSampleOffsets.az, BleImuSampleSizes.az),
        (BleImuSampleOffsets.gx, BleImuSampleSizes.gx),
        (BleImuSampleOffsets.gy, BleImuSampleSizes.gy),
        (BleImuSampleOffsets.gz, BleImuSampleSizes.gz),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      var next = 0;
      for (final (offset, size) in fields) {
        expect(offset, next, reason: 'sample fields must be contiguous');
        next = offset + size;
      }
      expect(next, BleImuBlock.sampleBytes);
    });

    test('the largest block fits the declared maximum', () {
      expect(
        BleImuBlock.headerBytes + BleImuBlock.sampleBytes * BleImuBlock.maxSamples,
        BleImuBlock.totalBytesMax,
      );
    });

    test('flag masks are distinct single bits', () {
      final masks = [
        BleImuFlagBits.deviceOverflow,
        BleImuFlagBits.readError,
        BleImuFlagBits.sensorReconfigured,
      ];
      for (final mask in masks) {
        expect(mask & (mask - 1), 0, reason: 'mask $mask must be a single bit');
      }
      expect(masks.toSet(), hasLength(masks.length));
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

      expect(block.version, BleImuBlock.version);
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
      final overflowOnly = ImuBlock.decode(buildImuBlockBytes(sampleCount: 1, flags: BleImuFlagBits.deviceOverflow));
      expect(overflowOnly.deviceOverflow, isTrue);
      expect(overflowOnly.readError, isFalse);
      expect(overflowOnly.sensorReconfigured, isFalse);

      final reconfiguredOnly =
          ImuBlock.decode(buildImuBlockBytes(sampleCount: 1, flags: BleImuFlagBits.sensorReconfigured));
      expect(reconfiguredOnly.deviceOverflow, isFalse);
      expect(reconfiguredOnly.readError, isFalse);
      expect(reconfiguredOnly.sensorReconfigured, isTrue);
    });

    test('accepts the maximum sample count', () {
      final bytes = buildImuBlockBytes(sampleCount: BleImuBlock.maxSamples);
      final block = ImuBlock.decode(bytes);
      expect(block.samples, hasLength(BleImuBlock.maxSamples));
    });
  });

  group('rejecting malformed blocks', () {
    test('too short for even the header throws', () {
      expect(
        () => ImuBlock.decode(Uint8List(BleImuBlock.headerBytes - 1)),
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
      final bytes = ByteData(BleImuBlock.headerBytes);
      bytes.setUint8(BleImuHeaderOffsets.version, BleImuBlock.version);
      bytes.setUint8(BleImuHeaderOffsets.sampleCount, 0);
      expect(
        () => ImuBlock.decode(bytes.buffer.asUint8List()),
        throwsA(isA<ImuBlockDecodeException>()),
      );
    });

    test('sampleCount above maxSamples throws', () {
      final bytes = buildImuBlockBytes(sampleCount: BleImuBlock.maxSamples + 1);
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
