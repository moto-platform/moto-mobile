import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/session_meta.dart';
import 'package:moto_mobile/models/vehicle_signal_block.dart';
import 'package:moto_mobile/services/session_recorder.dart';

import 'vehicle_signal_block_test.dart' show Rec, buildVehicleSignalBlockBytes, byName, unknownDid;

const _meta = SessionMeta(sessionId: 'placeholder', createdUtc: 'placeholder');

void main() {
  late Directory tempDir;
  late SessionRecorder recorder;
  final speed = byName(VehicleSignalNames.vehicleSpeed);
  final rpm = byName(VehicleSignalNames.engineSpeed);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('session_recorder_vsig_test_');
    recorder = SessionRecorder(documentsDirProvider: () async => tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  List<List<String>> readCsv(String name) =>
      File('${recorder.sessionDir!.path}/$name').readAsLinesSync().map((l) => l.split(',')).toList();

  List<List<String>> events() => readCsv('events.csv').skip(1).toList();

  Uint8List block(int seq, [List<Rec>? records]) => buildVehicleSignalBlockBytes(
        records ?? [Rec(speed.did, BleVehicleSignalState.valid, 10, 50)],
        seq: seq,
      );

  test('signals.csv header: the moto-server contract', () {
    expect(SessionRecorder.signalsCsvHeader, [
      'rx_utc_iso', 'rx_mono_ms', 'block_seq', 'lost_since_prev', //
      'device_time_ms', 'total_records', 'first_record',
      'did', 'state', 'age_ms', 'raw', 'signal', 'value',
    ]);
  });

  test('meta.json carries vehicle_signal_block_version', () async {
    await recorder.start(_meta);
    final meta = jsonDecode(File('${recorder.sessionDir!.path}/meta.json').readAsStringSync());
    expect(meta['vehicle_signal_block_version'], BleVehicleSignalBlock.version);
  });

  test('signals.csv is created lazily; no block means no file and zero summary counts', () async {
    await recorder.start(_meta);
    expect(File('${recorder.sessionDir!.path}/signals.csv').existsSync(), isFalse);
    final summary = await recorder.stop();
    expect(File('${recorder.sessionDir!.path}/signals.csv').existsSync(), isFalse);
    expect(summary.vehicleSignalBlockCount, 0);
    final json = jsonDecode(File('${recorder.sessionDir!.path}/summary.json').readAsStringSync());
    expect(json['vehicle_signal_block_count'], 0);
    expect(json['vehicle_signal_record_count'], 0);
    expect(json['vehicle_signal_lost_blocks'], 0);
    expect(json['vehicle_signal_lost_percent'], 0.0);
  });

  test('one row per record: wire values, block header repeated, catalog decode', () async {
    await recorder.start(_meta);
    final unknown = unknownDid();
    recorder.handleRawVehicleSignalBlock(buildVehicleSignalBlockBytes(
      [
        Rec(rpm.did, BleVehicleSignalState.valid, 120, 14000),
        Rec(speed.did, BleVehicleSignalState.stale, BleTelemetry.ageMax, 62),
        Rec(speed.did, BleVehicleSignalState.negativeResponse, BleTelemetry.ageNeverReceived, 0x31),
        Rec(speed.did, BleVehicleSignalState.skipped, 500, 0),
        Rec(speed.did, BleVehicleSignalState.neverReceived, BleTelemetry.ageNeverReceived, 0),
        Rec(unknown, BleVehicleSignalState.valid, 5, 77),
        Rec(rpm.did, BleVehicleSignalState.valid, 1, maxRawForLength(rpm.length)),
        Rec(speed.did, BleVehicleSignalState.valid, 1, maxRawForLength(speed.length) + 1),
      ],
      seq: 252,
      deviceTimeMs: 9200,
      totalRecords: 19,
      firstRecord: 4,
    ));
    await recorder.stop();

    final rows = readCsv('signals.csv');
    expect(rows.first, SessionRecorder.signalsCsvHeader);
    expect(rows.length, 9);
    final data = rows.skip(1).map((r) => Map.fromIterables(SessionRecorder.signalsCsvHeader, r)).toList();

    // Block fields repeat on every row; the receive time is the block's.
    for (final row in data) {
      expect(row['block_seq'], '252');
      expect(row['lost_since_prev'], '0');
      expect(row['device_time_ms'], '9200');
      expect(row['total_records'], '19');
      expect(row['first_record'], '4');
      expect(row['rx_utc_iso'], data.first['rx_utc_iso']);
      expect(row['rx_mono_ms'], data.first['rx_mono_ms']);
    }

    // Wire values are written unchanged; DID as a decimal integer.
    expect(data[0]['did'], '${rpm.did}');
    expect(data[0]['state'], '${BleVehicleSignalState.valid}');
    expect(data[0]['age_ms'], '120');
    expect(data[0]['raw'], '14000');
    expect(data[0]['signal'], VehicleSignalNames.engineSpeed);
    expect(data[0]['value'], rpm.physical(14000).toString());

    // Stale: value kept; the age sentinel stays the raw wire value.
    expect(data[1]['state'], '${BleVehicleSignalState.stale}');
    expect(data[1]['age_ms'], '${BleTelemetry.ageMax}');
    expect(data[1]['value'], speed.physical(62).toString());

    // negativeResponse: raw = NRC, no value, but the signal name.
    expect(data[2]['state'], '${BleVehicleSignalState.negativeResponse}');
    expect(data[2]['age_ms'], '${BleTelemetry.ageNeverReceived}');
    expect(data[2]['raw'], '${0x31}');
    expect(data[2]['signal'], VehicleSignalNames.vehicleSpeed);
    expect(data[2]['value'], '');

    // skipped and neverReceived: no value.
    expect(data[3]['state'], '${BleVehicleSignalState.skipped}');
    expect(data[3]['value'], '');
    expect(data[4]['state'], '${BleVehicleSignalState.neverReceived}');
    expect(data[4]['value'], '');

    // Unknown DID: kept, empty signal and value.
    expect(data[5]['did'], '$unknown');
    expect(data[5]['raw'], '77');
    expect(data[5]['signal'], '');
    expect(data[5]['value'], '');

    // Largest raw that fits has a value; one more does not (row still written).
    expect(data[6]['value'], rpm.physical(maxRawForLength(rpm.length)).toString());
    expect(data[7]['raw'], '${maxRawForLength(speed.length) + 1}');
    expect(data[7]['signal'], VehicleSignalNames.vehicleSpeed);
    expect(data[7]['value'], '');
  });

  test('seq gaps: lost_since_prev on the first row of a block only, vsig_gap event and summary', () async {
    await recorder.start(_meta);
    two(int seq) => block(seq, [
          Rec(speed.did, BleVehicleSignalState.valid, 0, 1),
          Rec(rpm.did, BleVehicleSignalState.valid, 0, 2),
        ]);
    for (final seq in [250, 251, 254, 255, 0, 2]) {
      recorder.handleRawVehicleSignalBlock(two(seq));
    }
    final summary = await recorder.stop();

    final lost = readCsv('signals.csv').skip(1).map((r) => r[3]).toList();
    // Two rows per block; the gap shows on the first row only.
    expect(lost, ['0', '0', '0', '0', '2', '0', '0', '0', '0', '0', '1', '0']);
    final gaps = events().where((e) => e[2] == 'vsig_gap').map((e) => e[3]).toList();
    expect(gaps, ['missing=2;seq=254', 'missing=1;seq=2']);

    expect(summary.vehicleSignalBlockCount, 6);
    expect(summary.vehicleSignalRecordCount, 12);
    expect(summary.vehicleSignalLostBlocks, 3);
    expect(summary.vehicleSignalLostPercent, closeTo(3 / 9 * 100, 1e-9));
    final json = jsonDecode(File('${recorder.sessionDir!.path}/summary.json').readAsStringSync());
    expect(json['vehicle_signal_block_count'], 6);
    expect(json['vehicle_signal_record_count'], 12);
    expect(json['vehicle_signal_lost_blocks'], 3);
  });

  test('a bad block is a vsig:-prefixed decode_error and gets no row', () async {
    await recorder.start(_meta);
    recorder.handleRawVehicleSignalBlock(Uint8List.fromList([BleVehicleSignalBlock.version, 1, 2]));
    recorder.handleRawVehicleSignalBlock(buildVehicleSignalBlockBytes(
      [Rec(speed.did, BleVehicleSignalState.valid, 0, 1)],
      version: 9,
    ));
    recorder.handleRawVehicleSignalBlock(buildVehicleSignalBlockBytes(
      [Rec(speed.did, BleVehicleSignalState.valid, 0, 1)],
      recordCount: 3,
    ));
    await recorder.stop();

    expect(File('${recorder.sessionDir!.path}/signals.csv').existsSync(), isFalse);
    final errors = events().where((e) => e[2] == 'decode_error').map((e) => e[3]).toList();
    expect(errors.length, 3);
    expect(errors.every((d) => d.startsWith('vsig: ')), isTrue);
    expect(recorder.decodeErrorCount, 3);
    expect(recorder.vehicleSignalBlockCount, 0);
  });

  test('vehicle-signal input is ignored while not recording', () {
    recorder.handleRawVehicleSignalBlock(block(1));
    expect(recorder.vehicleSignalBlockCount, 0);
  });

  test('a new recording resets the vehicle-signal state', () async {
    await recorder.start(_meta);
    recorder.handleRawVehicleSignalBlock(block(10));
    await recorder.stop();

    await recorder.start(_meta);
    recorder.handleRawVehicleSignalBlock(block(20)); // no gap across sessions
    final summary = await recorder.stop();
    expect(summary.vehicleSignalBlockCount, 1);
    expect(summary.vehicleSignalLostBlocks, 0);
    expect(readCsv('signals.csv').length, 2);
  });

  test('SessionSummary and SessionMeta round-trip the vehicle-signal keys', () {
    const summary = SessionSummary(
      duration: Duration(seconds: 1),
      packetCount: 0,
      lostCount: 0,
      lossPercent: 0,
      decodeErrorCount: 0,
      disconnectCount: 0,
      firstPacketUtc: null,
      lastPacketUtc: null,
      vehicleSignalBlockCount: 7,
      vehicleSignalRecordCount: 70,
      vehicleSignalLostBlocks: 2,
      vehicleSignalLostPercent: 22.5,
    );
    final back = SessionSummary.fromJson(summary.toJson());
    expect(back.vehicleSignalBlockCount, 7);
    expect(back.vehicleSignalRecordCount, 70);
    expect(back.vehicleSignalLostBlocks, 2);
    expect(back.vehicleSignalLostPercent, 22.5);

    expect(SessionMeta.fromJson(_meta.toJson()).vehicleSignalBlockVersion, BleVehicleSignalBlock.version);
    final old = Map<String, dynamic>.from(_meta.toJson())..remove('vehicle_signal_block_version');
    expect(SessionMeta.fromJson(old).vehicleSignalBlockVersion, isNull);
  });
}
