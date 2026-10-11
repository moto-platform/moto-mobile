import 'dart:typed_data';

import 'package:moto_defs/moto_defs.dart';

// Vehicle-signal block decoder (D-066 item 4). The block layout (header and
// record offsets/sizes, version, record limits, state values) is NOT defined
// here: the single source of truth is moto-vehicle-defs `ble/ble_schema.json`
// (`vehicleSignalBlock`, D-061), taken through the generated `moto_defs` Dart
// package (`BleVehicleSignalBlock`, `BleVehicleSignalHeaderOffsets`,
// `BleVehicleSignalRecordOffsets`, `BleVehicleSignalState`). The physical
// value of a record comes from the generated catalog (`vehicleSignalCatalog`,
// `VehicleSignal.physical`), looked up by DID.
//
// Records are keyed by DID, never by position: the catalog order changes when
// a candidate is promoted, the DID does not (schema `recordKey`).
//
// Notified on the `vehicleSignals` characteristic
// (`BleGatt.vehicleSignalsCharacteristicUuid`). It needs no bonding; firmware
// without it simply lacks the characteristic.

/// Thrown by [VehicleSignalBlock.decode] when a raw payload does not match the
/// schema (too short, bad version, or a length that does not match
/// `recordCount`). The message is suitable for the `decode_error` events
/// column (contract: `vsig:` prefix added by the caller).
class VehicleSignalBlockDecodeException implements Exception {
  VehicleSignalBlockDecodeException(this.message);
  final String message;

  @override
  String toString() => message;
}

final Map<int, VehicleSignal> _catalogByDid = Map<int, VehicleSignal>.unmodifiable({
  for (final signal in vehicleSignalCatalog) signal.did: signal,
});

/// The generated catalog entry of [did], or `null` for a DID this app's
/// catalog does not know (a sender built from a newer defs).
VehicleSignal? vehicleSignalByDid(int did) => _catalogByDid[did];

/// Largest raw value that fits a DID of [length] data bytes.
int maxRawForLength(int length) => (1 << (8 * length)) - 1;

/// One record of a vehicle-signal block: the wire values, authoritative.
class VehicleSignalRecord {
  const VehicleSignalRecord({
    required this.did,
    required this.state,
    required this.ageMs,
    required this.raw,
  });

  /// UDS DID of the record (the record key).
  final int did;

  /// A [BleVehicleSignalState] value (an unknown value is kept as is).
  final int state;

  /// Wire age in ms, sentinels included: [BleTelemetry.ageNeverReceived]
  /// (no positive answer since boot) and [BleTelemetry.ageMax] (saturated).
  final int ageMs;

  /// The 32-bit raw field: the data bytes (unsigned big-endian number) for
  /// valid and stale, the NRC for negativeResponse, 0 otherwise.
  final int raw;

  /// The catalog entry of [did], or `null` when the DID is unknown here.
  VehicleSignal? get signal => vehicleSignalByDid(did);

  bool get isValid => state == BleVehicleSignalState.valid;
  bool get isStale => state == BleVehicleSignalState.stale;
  bool get isSkipped => state == BleVehicleSignalState.skipped;
  bool get isNegativeResponse => state == BleVehicleSignalState.negativeResponse;
  bool get isNeverReceived => state == BleVehicleSignalState.neverReceived;

  /// The NRC of a negativeResponse record (raw holds it in the low byte), else
  /// `null`.
  int? get nrc => isNegativeResponse ? raw & 0xFF : null;

  /// Wire age as a duration-in-ms, or `null` for the "never" and "saturated"
  /// sentinels (no usable age).
  int? get knownAgeMs => ageMs >= BleTelemetry.ageMax ? null : ageMs;

  /// Physical value `raw * factor_num / factor_den + offset` in the catalog
  /// unit. Only for state valid or stale, a DID known to the catalog and a raw
  /// that fits the DID's `length` (raw <= 2^(8*length) - 1); otherwise `null`.
  double? get value {
    if (!isValid && !isStale) return null;
    final s = signal;
    if (s == null) return null;
    if (raw > maxRawForLength(s.length)) return null;
    return s.physical(raw);
  }
}

/// One decoded vehicle-signal block notification.
class VehicleSignalBlock {
  const VehicleSignalBlock({
    required this.version,
    required this.seq,
    required this.deviceTimeMs,
    required this.totalRecords,
    required this.firstRecord,
    required this.records,
  });

  final int version;

  /// Rolling 0-255 counter, incremented once per block the sender hands to the
  /// BLE stack (schema `sequenceRule`).
  final int seq;

  /// Node clock when the block was built.
  final int deviceTimeMs;

  /// Size of the sender's DID table.
  final int totalRecords;

  /// Table index of the first record of this block.
  final int firstRecord;

  /// The records, in wire order.
  final List<VehicleSignalRecord> records;

  int get recordCount => records.length;

  /// Decodes one raw vehicle-signal block notification. The version must equal
  /// [BleVehicleSignalBlock.version] and the length must equal
  /// `headerBytes + recordCount * recordBytes` exactly (the sender never
  /// truncates a block, schema `mtuRule`). Throws
  /// [VehicleSignalBlockDecodeException] otherwise.
  factory VehicleSignalBlock.decode(Uint8List bytes) {
    if (bytes.length < BleVehicleSignalBlock.headerBytes) {
      throw VehicleSignalBlockDecodeException(
          'size mismatch: got ${bytes.length} bytes (header needs ${BleVehicleSignalBlock.headerBytes})');
    }
    final buffer = ByteData.sublistView(bytes);
    final version = buffer.getUint8(BleVehicleSignalHeaderOffsets.version);
    if (version != BleVehicleSignalBlock.version) {
      throw VehicleSignalBlockDecodeException(
          'version mismatch: got $version (expected ${BleVehicleSignalBlock.version})');
    }
    final recordCount = buffer.getUint8(BleVehicleSignalHeaderOffsets.recordCount);
    final expectedLength = BleVehicleSignalBlock.headerBytes + recordCount * BleVehicleSignalBlock.recordBytes;
    if (bytes.length != expectedLength) {
      throw VehicleSignalBlockDecodeException(
          'size mismatch: got ${bytes.length} bytes (expected $expectedLength for $recordCount records)');
    }
    final records = <VehicleSignalRecord>[];
    for (var i = 0; i < recordCount; i++) {
      final base = BleVehicleSignalBlock.headerBytes + i * BleVehicleSignalBlock.recordBytes;
      records.add(VehicleSignalRecord(
        did: buffer.getUint16(base + BleVehicleSignalRecordOffsets.did, Endian.little),
        state: buffer.getUint8(base + BleVehicleSignalRecordOffsets.state),
        ageMs: buffer.getUint16(base + BleVehicleSignalRecordOffsets.ageMs, Endian.little),
        raw: buffer.getUint32(base + BleVehicleSignalRecordOffsets.raw, Endian.little),
      ));
    }
    return VehicleSignalBlock(
      version: version,
      seq: buffer.getUint8(BleVehicleSignalHeaderOffsets.seq),
      deviceTimeMs: buffer.getUint32(BleVehicleSignalHeaderOffsets.deviceTimeMs, Endian.little),
      totalRecords: buffer.getUint8(BleVehicleSignalHeaderOffsets.totalRecords),
      firstRecord: buffer.getUint8(BleVehicleSignalHeaderOffsets.firstRecord),
      records: List<VehicleSignalRecord>.unmodifiable(records),
    );
  }
}

/// Tracks `seq` across vehicle-signal blocks within one session, per the
/// schema's `sequenceRule`: missing = (seq - prev.seq - 1) mod 256.
class VehicleSignalSeqTracker {
  int? _prevSeq;

  /// Returns the blocks lost between the previous block seen by this tracker
  /// and [block]; 0 for the first block.
  int missingBlocksFor(VehicleSignalBlock block) {
    final prev = _prevSeq;
    _prevSeq = block.seq;
    if (prev == null) return 0;
    return (block.seq - prev - 1) % 256;
  }

  void reset() => _prevSeq = null;
}

/// The latest record of one DID together with the phone time it arrived at.
class ReceivedVehicleSignal {
  const ReceivedVehicleSignal(this.record, this.receivedAt);

  final VehicleSignalRecord record;
  final DateTime receivedAt;
}
