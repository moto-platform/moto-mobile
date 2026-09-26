// The BLE packet schema has ONE source: moto-connectivity-node's
// docs/ble_telemetry_packet_schema.json. test/fixtures/ keeps a byte-identical copy
// that the decoder tests use; this test fails when the copy drifts from the source.
//
// Source location, in order:
//   1. MOTO_CONN_SCHEMA (path to the file; CI downloads it there)
//   2. ../moto-connectivity-node/docs/ble_telemetry_packet_schema.json (workspace layout)
// If neither exists the test is skipped, unless MOTO_SCHEMA_DRIFT_REQUIRED=1.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fixturePath = 'test/fixtures/ble_telemetry_packet_schema.json';
const _workspacePath = '../moto-connectivity-node/docs/ble_telemetry_packet_schema.json';

File? _sourceSchema() {
  final fromEnv = Platform.environment['MOTO_CONN_SCHEMA'];
  for (final path in [if (fromEnv != null && fromEnv.isNotEmpty) fromEnv, _workspacePath]) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  return null;
}

void main() {
  final source = _sourceSchema();
  final required = Platform.environment['MOTO_SCHEMA_DRIFT_REQUIRED'] == '1';

  test(
    'fixture is a byte-identical copy of the connectivity-node schema',
    () {
      if (source == null) {
        fail('MOTO_SCHEMA_DRIFT_REQUIRED=1 but no source schema was found');
      }
      final fixture = File(_fixturePath).readAsBytesSync();
      expect(source.readAsBytesSync(), orderedEquals(fixture),
          reason: 'copy ${source.path} to $_fixturePath and update the decoder tests');
    },
    skip: source == null && !required
        ? 'source schema not available (set MOTO_CONN_SCHEMA or use the workspace layout)'
        : false,
  );
}
