import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/vehicle_signal_block.dart';
import 'package:moto_mobile/services/ble_service.dart';
import 'package:moto_mobile/ui/record_screen.dart';
import 'package:moto_mobile/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vehicle_signal_block_test.dart' show Rec, buildVehicleSignalBlockBytes, byName;

/// A BLE service whose vehicle-signal stream the test drives.
class _FakeBle extends BleService {
  final StreamController<Uint8List> vsig = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get rawVehicleSignalBlockStream => vsig.stream;
}

Widget _host(Widget child) => MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

VehicleSignalRecord _rec(int did, int state) => VehicleSignalRecord(did: did, state: state, ageMs: 0, raw: 0);

void main() {
  final speed = byName(VehicleSignalNames.vehicleSpeed);
  final rpm = byName(VehicleSignalNames.engineSpeed);

  group('VehicleSignalStatusLine', () {
    testWidgets('before any block it says it waits for data', (tester) async {
      await tester.pumpWidget(_host(const VehicleSignalStatusLine(latest: {}, blockCount: 0, lostBlocks: 0)));
      expect(find.textContaining('Vehicle signals: waiting for data'), findsOneWidget);
    });

    testWidgets('counts the block states per DID and the lost blocks', (tester) async {
      await tester.pumpWidget(_host(VehicleSignalStatusLine(
        latest: {
          speed.did: _rec(speed.did, BleVehicleSignalState.valid),
          rpm.did: _rec(rpm.did, BleVehicleSignalState.negativeResponse),
          0xFFFF: _rec(0xFFFF, BleVehicleSignalState.skipped),
        },
        blockCount: 5,
        lostBlocks: 2,
      )));
      expect(
        find.text('Vehicle signals (3 DIDs): 1 valid, 1 skipped, 1 NRC   Lost blocks: 2'),
        findsOneWidget,
      );
    });
  });

  group('Record screen', () {
    late Directory tmp;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );
      // wakelock_plus has no host in unit tests.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (message) async => const StandardMessageCodec().encodeMessage(<Object?>[]),
      );
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('moto_vsig_ui_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    testWidgets('shows the vehicle-signal status line while recording and updates it per block', (tester) async {
      tester.view.physicalSize = const Size(400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ble = _FakeBle();
      addTearDown(ble.vsig.close);

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: RecordScreen(bleService: ble)));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      // Not recording: the metadata form, no counters.
      expect(find.textContaining('Vehicle signals'), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.text('START RECORDING'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(find.textContaining('Vehicle signals: waiting for data'), findsOneWidget);

      await tester.runAsync(() async {
        ble.vsig.add(buildVehicleSignalBlockBytes([
          Rec(speed.did, BleVehicleSignalState.valid, 10, 50),
          Rec(rpm.did, BleVehicleSignalState.stale, 900, 14000),
        ], seq: 0));
        ble.vsig.add(buildVehicleSignalBlockBytes([
          Rec(speed.did, BleVehicleSignalState.valid, 10, 50),
        ], seq: 2)); // seq 1 lost
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(
        find.text('Vehicle signals (2 DIDs): 1 valid, 1 stale   Lost blocks: 1'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await tester.tap(find.text('STOP RECORDING'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpWidget(const SizedBox());
    });
  });
}
