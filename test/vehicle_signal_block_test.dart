import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/vehicle_signal_block.dart';

/// A record to put into a synthetic block (wire values).
class Rec {
  const Rec(this.did, this.state, this.ageMs, this.raw);
  final int did;
  final int state;
  final int ageMs;
  final int raw;
}

/// Builds one raw vehicle-signal block from the generated offsets (never
/// hand-written). [recordCount] defaults to `records.length`; overriding it
/// builds a block whose header lies about its length.
Uint8List buildVehicleSignalBlockBytes(
  List<Rec> records, {
  int version = BleVehicleSignalBlock.version,
  int seq = 0,
  int deviceTimeMs = 0,
  int totalRecords = 0,
  int firstRecord = 0,
  int? recordCount,
}) {
  final bytes = ByteData(BleVehicleSignalBlock.headerBytes + records.length * BleVehicleSignalBlock.recordBytes);
  bytes.setUint8(BleVehicleSignalHeaderOffsets.version, version);
  bytes.setUint8(BleVehicleSignalHeaderOffsets.seq, seq);
  bytes.setUint32(BleVehicleSignalHeaderOffsets.deviceTimeMs, deviceTimeMs, Endian.little);
  bytes.setUint8(BleVehicleSignalHeaderOffsets.totalRecords, totalRecords);
  bytes.setUint8(BleVehicleSignalHeaderOffsets.firstRecord, firstRecord);
  bytes.setUint8(BleVehicleSignalHeaderOffsets.recordCount, recordCount ?? records.length);
  bytes.setUint8(BleVehicleSignalHeaderOffsets.reserved, 0);
  for (var i = 0; i < records.length; i++) {
    final base = BleVehicleSignalBlock.headerBytes + i * BleVehicleSignalBlock.recordBytes;
    final r = records[i];
    bytes.setUint16(base + BleVehicleSignalRecordOffsets.did, r.did, Endian.little);
    bytes.setUint8(base + BleVehicleSignalRecordOffsets.state, r.state);
    bytes.setUint16(base + BleVehicleSignalRecordOffsets.ageMs, r.ageMs, Endian.little);
    bytes.setUint32(base + BleVehicleSignalRecordOffsets.raw, r.raw, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

VehicleSignal byName(String name) => vehicleSignalCatalog.firstWhere((s) => s.name == name);

/// A DID that is not in the generated catalog.
int unknownDid() {
  var did = 0xFFFF;
  while (vehicleSignalByDid(did) != null) {
    did--;
  }
  return did;
}

void main() {
  final speed = byName(VehicleSignalNames.vehicleSpeed); // 1 data byte
  final rpm = byName(VehicleSignalNames.engineSpeed); // 2 data bytes

  test('generated layout: header and record fields exactly cover their sizes', () {
    final header = <(int, int)>[
      (BleVehicleSignalHeaderOffsets.version, BleVehicleSignalHeaderSizes.version),
      (BleVehicleSignalHeaderOffsets.seq, BleVehicleSignalHeaderSizes.seq),
      (BleVehicleSignalHeaderOffsets.deviceTimeMs, BleVehicleSignalHeaderSizes.deviceTimeMs),
      (BleVehicleSignalHeaderOffsets.totalRecords, BleVehicleSignalHeaderSizes.totalRecords),
      (BleVehicleSignalHeaderOffsets.firstRecord, BleVehicleSignalHeaderSizes.firstRecord),
      (BleVehicleSignalHeaderOffsets.recordCount, BleVehicleSignalHeaderSizes.recordCount),
      (BleVehicleSignalHeaderOffsets.reserved, BleVehicleSignalHeaderSizes.reserved),
    ];
    var next = 0;
    for (final (offset, size) in header) {
      expect(offset, next);
      next += size;
    }
    expect(next, BleVehicleSignalBlock.headerBytes);

    final record = <(int, int)>[
      (BleVehicleSignalRecordOffsets.did, BleVehicleSignalRecordSizes.did),
      (BleVehicleSignalRecordOffsets.state, BleVehicleSignalRecordSizes.state),
      (BleVehicleSignalRecordOffsets.ageMs, BleVehicleSignalRecordSizes.ageMs),
      (BleVehicleSignalRecordOffsets.raw, BleVehicleSignalRecordSizes.raw),
    ];
    next = 0;
    for (final (offset, size) in record) {
      expect(offset, next);
      next += size;
    }
    expect(next, BleVehicleSignalBlock.recordBytes);
  });

  group('decode', () {
    test('a good block: header and records keyed by DID', () {
      final bytes = buildVehicleSignalBlockBytes(
        [
          Rec(speed.did, BleVehicleSignalState.valid, 120, 62),
          Rec(rpm.did, BleVehicleSignalState.stale, 900, 14000),
        ],
        seq: 7,
        deviceTimeMs: 0x01020304,
        totalRecords: 19,
        firstRecord: 5,
      );
      final block = VehicleSignalBlock.decode(bytes);
      expect(block.version, BleVehicleSignalBlock.version);
      expect(block.seq, 7);
      expect(block.deviceTimeMs, 0x01020304);
      expect(block.totalRecords, 19);
      expect(block.firstRecord, 5);
      expect(block.recordCount, 2);
      expect(block.records.map((r) => r.did).toList(), [speed.did, rpm.did]);

      final s = block.records[0];
      expect(s.state, BleVehicleSignalState.valid);
      expect(s.ageMs, 120);
      expect(s.raw, 62);
      expect(s.signal!.name, VehicleSignalNames.vehicleSpeed);
      expect(s.value, 62.0);

      final r = block.records[1];
      expect(r.state, BleVehicleSignalState.stale);
      expect(r.value, rpm.physical(14000)); // stale keeps its value
    });

    test('values are little-endian on the wire', () {
      final bytes = buildVehicleSignalBlockBytes([Rec(rpm.did, BleVehicleSignalState.valid, 0x0102, 0x00030201)]);
      const base = BleVehicleSignalBlock.headerBytes;
      expect(bytes[base + BleVehicleSignalRecordOffsets.did], rpm.did & 0xFF);
      expect(bytes[base + BleVehicleSignalRecordOffsets.ageMs], 0x02);
      expect(bytes[base + BleVehicleSignalRecordOffsets.raw], 0x01);
      final r = VehicleSignalBlock.decode(bytes).records.single;
      expect(r.ageMs, 0x0102);
      expect(r.raw, 0x00030201);
    });

    test('wrong version is a decode error', () {
      final bytes = buildVehicleSignalBlockBytes(
        [Rec(speed.did, BleVehicleSignalState.valid, 0, 1)],
        version: BleVehicleSignalBlock.version + 1,
      );
      expect(
        () => VehicleSignalBlock.decode(bytes),
        throwsA(isA<VehicleSignalBlockDecodeException>().having((e) => e.message, 'message', contains('version mismatch'))),
      );
    });

    test('a length that does not match recordCount is a decode error', () {
      final one = <Rec>[Rec(speed.did, BleVehicleSignalState.valid, 0, 1)];
      for (final lie in [0, 2, 3]) {
        expect(
          () => VehicleSignalBlock.decode(buildVehicleSignalBlockBytes(one, recordCount: lie)),
          throwsA(isA<VehicleSignalBlockDecodeException>().having((e) => e.message, 'message', contains('size mismatch'))),
          reason: 'recordCount=$lie',
        );
      }
      // A trailing byte is also a mismatch.
      final padded = Uint8List.fromList([...buildVehicleSignalBlockBytes(one), 0]);
      expect(() => VehicleSignalBlock.decode(padded), throwsA(isA<VehicleSignalBlockDecodeException>()));
      // Shorter than a header.
      expect(() => VehicleSignalBlock.decode(Uint8List(BleVehicleSignalBlock.headerBytes - 1)),
          throwsA(isA<VehicleSignalBlockDecodeException>()));
      expect(() => VehicleSignalBlock.decode(Uint8List(0)), throwsA(isA<VehicleSignalBlockDecodeException>()));
    });

    test('a header-only block with recordCount 0 decodes to no records', () {
      final block = VehicleSignalBlock.decode(buildVehicleSignalBlockBytes(const []));
      expect(block.records, isEmpty);
    });

    test('a full-size block of maxRecordsPerBlock records decodes', () {
      final records = List.generate(
          BleVehicleSignalBlock.maxRecordsPerBlock, (i) => Rec(speed.did, BleVehicleSignalState.valid, i, i));
      final bytes = buildVehicleSignalBlockBytes(records);
      expect(bytes.length, BleVehicleSignalBlock.totalBytesMax);
      expect(VehicleSignalBlock.decode(bytes).recordCount, BleVehicleSignalBlock.maxRecordsPerBlock);
    });

    test('an unknown DID is kept with its raw value and a null value', () {
      final did = unknownDid();
      final r = VehicleSignalBlock.decode(
        buildVehicleSignalBlockBytes([Rec(did, BleVehicleSignalState.valid, 10, 1234)]),
      ).records.single;
      expect(r.did, did);
      expect(r.raw, 1234);
      expect(r.signal, isNull);
      expect(r.value, isNull);
    });

    test('a raw too large for the DID length keeps the record with a null value', () {
      final fits = maxRawForLength(speed.length);
      final tooBig = fits + 1;
      final block = VehicleSignalBlock.decode(buildVehicleSignalBlockBytes([
        Rec(speed.did, BleVehicleSignalState.valid, 0, fits),
        Rec(speed.did, BleVehicleSignalState.valid, 0, tooBig),
        Rec(rpm.did, BleVehicleSignalState.valid, 0, maxRawForLength(rpm.length)),
        Rec(rpm.did, BleVehicleSignalState.valid, 0, maxRawForLength(rpm.length) + 1),
      ]));
      expect(block.records[0].value, speed.physical(fits));
      expect(block.records[1].raw, tooBig);
      expect(block.records[1].value, isNull);
      expect(block.records[2].value, rpm.physical(maxRawForLength(rpm.length)));
      expect(block.records[3].value, isNull);
    });

    test('each state: value only for valid and stale, NRC only for negativeResponse', () {
      final cases = <int, ({double? value, int? nrc})>{
        BleVehicleSignalState.neverReceived: (value: null, nrc: null),
        BleVehicleSignalState.valid: (value: speed.physical(42), nrc: null),
        BleVehicleSignalState.stale: (value: speed.physical(42), nrc: null),
        BleVehicleSignalState.skipped: (value: null, nrc: null),
        BleVehicleSignalState.negativeResponse: (value: null, nrc: 42),
      };
      for (final entry in cases.entries) {
        final r = VehicleSignalBlock.decode(
          buildVehicleSignalBlockBytes([Rec(speed.did, entry.key, 5, 42)]),
        ).records.single;
        expect(r.state, entry.key);
        expect(r.value, entry.value.value, reason: 'state ${entry.key}');
        expect(r.nrc, entry.value.nrc, reason: 'state ${entry.key}');
      }
    });

    test('NRC is the low byte of raw', () {
      final r = VehicleSignalBlock.decode(
        buildVehicleSignalBlockBytes([Rec(speed.did, BleVehicleSignalState.negativeResponse, 0, 0x31)]),
      ).records.single;
      expect(r.isNegativeResponse, isTrue);
      expect(r.nrc, 0x31);
    });

    test('age sentinels are not a usable age', () {
      Rec withAge(int age) => Rec(speed.did, BleVehicleSignalState.valid, age, 1);
      final block = VehicleSignalBlock.decode(buildVehicleSignalBlockBytes([
        withAge(100),
        withAge(BleTelemetry.ageMax),
        withAge(BleTelemetry.ageNeverReceived),
      ]));
      expect(block.records[0].knownAgeMs, 100);
      expect(block.records[1].ageMs, BleTelemetry.ageMax);
      expect(block.records[1].knownAgeMs, isNull);
      expect(block.records[2].ageMs, BleTelemetry.ageNeverReceived);
      expect(block.records[2].knownAgeMs, isNull);
    });

    test('the catalog lookup is by DID and covers every catalog entry', () {
      for (final s in vehicleSignalCatalog) {
        expect(vehicleSignalByDid(s.did), same(s), reason: s.name);
      }
      expect(vehicleSignalByDid(unknownDid()), isNull);
    });
  });

  group('VehicleSignalSeqTracker', () {
    VehicleSignalBlock blockWithSeq(int seq) =>
        VehicleSignalBlock.decode(buildVehicleSignalBlockBytes([Rec(speed.did, BleVehicleSignalState.valid, 0, 1)], seq: seq));

    test('the first block reports no gap', () {
      expect(VehicleSignalSeqTracker().missingBlocksFor(blockWithSeq(200)), 0);
    });

    test('consecutive blocks report no gap', () {
      final t = VehicleSignalSeqTracker();
      expect(t.missingBlocksFor(blockWithSeq(10)), 0);
      expect(t.missingBlocksFor(blockWithSeq(11)), 0);
      expect(t.missingBlocksFor(blockWithSeq(12)), 0);
    });

    test('a gap counts the blocks in between', () {
      final t = VehicleSignalSeqTracker();
      t.missingBlocksFor(blockWithSeq(10));
      expect(t.missingBlocksFor(blockWithSeq(14)), 3);
      expect(t.missingBlocksFor(blockWithSeq(15)), 0);
    });

    test('wrap-around 255 -> 0 is no gap, and gaps across the wrap are counted', () {
      final t = VehicleSignalSeqTracker();
      t.missingBlocksFor(blockWithSeq(254));
      expect(t.missingBlocksFor(blockWithSeq(255)), 0);
      expect(t.missingBlocksFor(blockWithSeq(0)), 0);
      expect(t.missingBlocksFor(blockWithSeq(3)), 2);

      final u = VehicleSignalSeqTracker();
      u.missingBlocksFor(blockWithSeq(253));
      expect(u.missingBlocksFor(blockWithSeq(2)), 4); // 254, 255, 0, 1 lost
    });

    test('reset forgets the previous seq', () {
      final t = VehicleSignalSeqTracker();
      t.missingBlocksFor(blockWithSeq(10));
      t.reset();
      expect(t.missingBlocksFor(blockWithSeq(50)), 0);
    });
  });
}
