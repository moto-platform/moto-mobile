import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/telemetry_data.dart';
import 'package:moto_mobile/models/vehicle_signal_block.dart' show vehicleSignalByDid;
import 'package:moto_mobile/services/ble_service.dart';
import 'package:moto_mobile/ui/diagnostics_screen.dart';
import 'package:moto_mobile/ui/live_screen.dart';
import 'package:moto_mobile/ui/telemetry/link_status.dart' show didHex;
import 'package:moto_mobile/ui/telemetry/telemetry_store.dart';
import 'package:moto_mobile/ui/theme/app_theme.dart';

/// The rotating RTT DID of the fixtures, taken from the generated catalog.
final int _rttDid = vehicleSignalCatalog.firstWhere((s) => s.name == VehicleSignalNames.engineSpeed).did;

TelemetryData packet({int canFlags = 0x01}) => TelemetryData(
      packetVersion: TelemetryVersion.v4,
      deviceTimeMs: 123456,
      rpm: 3500,
      speed: 62,
      coolantTemp: 88,
      throttlePos: 17,
      batteryVolt: 13.8,
      leanAngle: null,
      maxLeanRight: null,
      maxLeanLeft: null,
      rpmValid: true,
      speedValid: true,
      coolantTempValid: true,
      throttlePosValid: true,
      batteryVoltValid: true,
      leanValid: false,
      ecuPresent: true,
      imuActive: true,
      rpmAgeMs: 40,
      speedAgeMs: 30,
      coolantTempAgeMs: 300,
      throttlePosAgeMs: 80,
      batteryVoltAgeMs: 500,
      canBusState: CanBusState.running,
      canTxErrorCount: 0,
      canRxErrorCount: 1,
      canBusOffCount: 0,
      unansweredDidCount: 2,
      canFlags: canFlags,
      stepGapMaxMs: 48,
      stepGapOverCount: 3,
      rttDid: _rttDid,
      rttMinMs: 6,
      rttMaxMs: 21,
      rttSumMs: 400,
      rttCount: 40,
      rttNrc78Count: 0,
    );

Widget host(Widget child, {double textScale = 1.0}) => MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: child,
    );

void main() {
  for (final scale in [1.0, 2.0]) {
    for (final size in const [Size(360, 740), Size(412, 915), Size(900, 600)]) {
      testWidgets('Live screen lays out at $size, text scale $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final store = TelemetryStore();
        addTearDown(store.dispose);
        store.updateConnection(true, deviceName: 'Test-Bike');
        // 0x08 = synthetic data, 0x06 = both latches.
        store.updateTelemetry(packet(canFlags: 0x0E));

        await tester.pumpWidget(host(
          LiveScreen(store: store, bleService: BleService(), onOpenRecord: () {}),
          textScale: scale,
        ));

        expect(tester.takeException(), isNull);
        expect(find.text('SYNTHETIC DATA'), findsOneWidget);
        expect(find.text('62'), findsOneWidget);
        expect(find.text('ECU present'), findsOneWidget);
        expect(find.text('Foreign tester latched'), findsOneWidget);
        expect(find.text('Bus-off latched'), findsOneWidget);
        expect(find.text('IMU active'), findsOneWidget);
      });
    }
  }

  testWidgets('Live screen with no connection shows placeholders and a Connect action', (tester) async {
    final store = TelemetryStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(host(
      LiveScreen(store: store, bleService: BleService(), onOpenRecord: () {}),
    ));
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('--'), findsWidgets);
    expect(find.text('SYNTHETIC DATA'), findsNothing);
    // Lean angle is not shown anywhere.
    expect(find.textContaining('LEAN'), findsNothing);
  });

  testWidgets('Record button calls onOpenRecord', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var opened = 0;
    final store = TelemetryStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(host(
      LiveScreen(store: store, bleService: BleService(), onOpenRecord: () => opened++),
    ));
    // The app bar action is always visible, even on a short screen.
    await tester.tap(find.byTooltip('Open the Record screen'));
    expect(opened, 1);
    await tester.ensureVisible(find.text('RECORD A SESSION'));
    await tester.tap(find.text('RECORD A SESSION'));
    expect(opened, 2);
  });

  testWidgets('Diagnostics screen shows tester stats and CAN counters', (tester) async {
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateTelemetry(packet());
    store.updateMtu(247);

    await tester.pumpWidget(host(DiagnosticsScreen(store: store)));
    expect(tester.takeException(), isNull);
    expect(find.text('247'), findsOneWidget);
    expect(find.text('48 ms'), findsOneWidget); // step gap max
    expect(find.text('${vehicleSignalByDid(_rttDid)!.label} (${didHex(_rttDid)})'), findsOneWidget); // rotating RTT DID from the catalog
    expect(find.text('10.0 ms'), findsOneWidget); // 400 / 40
  });

  testWidgets('Diagnostics screen at large text scale does not overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateTelemetry(packet());

    await tester.pumpWidget(host(DiagnosticsScreen(store: store), textScale: 2.0));
    expect(tester.takeException(), isNull);
  });
}
