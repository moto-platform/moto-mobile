import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/telemetry_data.dart';
import 'package:moto_mobile/models/vehicle_signal_block.dart';
import 'package:moto_mobile/ui/signals_screen.dart';
import 'package:moto_mobile/ui/telemetry/signal_view.dart';
import 'package:moto_mobile/ui/telemetry/telemetry_store.dart';
import 'package:moto_mobile/ui/theme/app_theme.dart';
import 'package:moto_mobile/ui/widgets/common.dart';

Widget host(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

TelemetryData livePacket() => TelemetryData(
      packetVersion: TelemetryVersion.v4,
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
      batteryVoltValid: false,
      leanValid: false,
      ecuPresent: true,
      rpmAgeMs: 40,
      speedAgeMs: 30,
      coolantTempAgeMs: 300,
      throttlePosAgeMs: 80,
      batteryVoltAgeMs: 4000,
    );

/// A block with one record, as the BLE service would hand it to the store.
VehicleSignalBlock blockOf(List<VehicleSignalRecord> records) => VehicleSignalBlock(
      version: BleVehicleSignalBlock.version,
      seq: 0,
      deviceTimeMs: 0,
      totalRecords: records.length,
      firstRecord: 0,
      records: records,
    );

VehicleSignalRecord record(VehicleSignal s, int state, {int raw = 0, int ageMs = 0}) =>
    VehicleSignalRecord(did: s.did, state: state, ageMs: ageMs, raw: raw);

void main() {
  final candidates = vehicleSignalCatalog.where((s) => !s.isPolled).toList();

  Finder chipsOf(SignalState state) => find.byWidgetPredicate((w) => w is StateChip && w.state == state);

  /// Pumps the Signals screen on a tall viewport against [store].
  Future<void> pumpScreen(WidgetTester tester, TelemetryStore store) async {
    tester.view.physicalSize = const Size(800, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(SignalsScreen(store: store)));
  }

  testWidgets('without vehicle-signal records every candidate shows NOT POLLED', (tester) async {
    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    await pumpScreen(tester, store);

    expect(chipsOf(SignalState.notPolled), findsNWidgets(candidates.length));
    expect(find.descendant(of: find.byType(StateChip), matching: find.text('NOT POLLED')), findsNWidgets(candidates.length));
    expect(find.text('Not polled'), findsNWidgets(candidates.length));
    expect(chipsOf(SignalState.live), findsNothing);
  });

  testWidgets('a candidate that arrives with state valid shows LIVE with its value and catalog unit',
      (tester) async {
    final candidate = candidates.first;
    final raw = candidate.length == 1 ? 100 : 1000;
    final expected = candidate.physical(raw).toStringAsFixed(vehicleSignalDecimals(candidate));

    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateVehicleSignalBlock(blockOf([record(candidate, BleVehicleSignalState.valid, raw: raw, ageMs: 80)]));
    await pumpScreen(tester, store);

    expect(chipsOf(SignalState.live), findsOneWidget);
    expect(find.descendant(of: find.byType(StateChip), matching: find.text('LIVE')), findsOneWidget);
    expect(find.text(expected), findsOneWidget);
    expect(find.text(displayUnit(candidate.unit)), findsWidgets);
    expect(chipsOf(SignalState.notPolled), findsNWidgets(candidates.length - 1));
    expect(find.textContaining('Reported by the node'), findsOneWidget);
  });

  testWidgets('a valid record older than 2000 ms, and a stale record, show STALE', (tester) async {
    var now = DateTime.utc(2026, 10, 11, 12);
    final store = TelemetryStore(clock: () => now);
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateVehicleSignalBlock(blockOf([
      record(candidates[0], BleVehicleSignalState.valid, raw: 1),
      record(candidates[1], BleVehicleSignalState.stale, raw: 1, ageMs: 7000),
    ]));
    now = now.add(vehicleSignalLiveWithin + const Duration(milliseconds: 1));
    store.updateVehicleSignalBlock(blockOf([record(candidates[2], BleVehicleSignalState.valid, raw: 1)]));
    await pumpScreen(tester, store);

    // candidates[0]: valid but received 2001 ms ago; candidates[1]: state stale;
    // candidates[2]: valid and just received.
    expect(chipsOf(SignalState.stale), findsNWidgets(2));
    expect(find.descendant(of: find.byType(StateChip), matching: find.text('STALE')), findsNWidgets(2));
    expect(chipsOf(SignalState.live), findsOneWidget);
  });

  testWidgets('a negative response shows NRC 0x31 and a skipped DID shows SKIPPED', (tester) async {
    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateVehicleSignalBlock(blockOf([
      record(candidates[0], BleVehicleSignalState.negativeResponse,
          raw: 0x31, ageMs: BleTelemetry.ageNeverReceived),
      record(candidates[1], BleVehicleSignalState.skipped),
    ]));
    await pumpScreen(tester, store);

    expect(find.text('NRC 0x31'), findsOneWidget);
    expect(chipsOf(SignalState.negativeResponse), findsOneWidget);
    expect(find.text('SKIPPED'), findsOneWidget);
    expect(chipsOf(SignalState.live), findsNothing);
    expect(chipsOf(SignalState.notPolled), findsNWidgets(candidates.length - 2));
  });

  testWidgets('a v4 telemetry packet keeps the five polled signals LIVE alongside vehicle-signal records',
      (tester) async {
    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateTelemetry(livePacket());
    store.updateVehicleSignalBlock(blockOf([record(candidates.first, BleVehicleSignalState.valid, raw: 1)]));
    await pumpScreen(tester, store);

    expect(chipsOf(SignalState.live), findsNWidgets(5)); // four live v4 signals + the candidate
    expect(find.text('62'), findsOneWidget);
  });

  testWidgets('records are dropped on disconnect', (tester) async {
    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateVehicleSignalBlock(blockOf([record(candidates.first, BleVehicleSignalState.valid, raw: 1)]));
    expect(store.vehicleSignals, isNotEmpty);
    store.updateConnection(false);
    expect(store.vehicleSignals, isEmpty);
    await pumpScreen(tester, store);
    expect(chipsOf(SignalState.live), findsNothing);
  });

  testWidgets('Signals screen renders every catalog signal label', (tester) async {
    // Tall viewport so the lazy list builds every row.
    tester.view.physicalSize = const Size(800, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = TelemetryStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(host(SignalsScreen(store: store)));

    for (final signal in vehicleSignalCatalog) {
      expect(find.text(signal.label), findsOneWidget, reason: signal.name);
    }
    // Group headers in catalog group order.
    for (final group in vehicleSignalGroups) {
      if (vehicleSignalCatalog.any((s) => s.group == group)) {
        expect(find.text(groupTitle(group).toUpperCase()), findsOneWidget, reason: group);
      }
    }
  });

  testWidgets('summary header and chips follow the live state', (tester) async {
    tester.view.physicalSize = const Size(800, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateTelemetry(livePacket());

    await tester.pumpWidget(host(SignalsScreen(store: store)));

    final polled = vehicleSignalCatalog.where((s) => s.isPolled).length;
    final candidates = vehicleSignalCatalog.length - polled;
    expect(find.text('4'), findsWidgets); // four live (battery is stale)
    expect(find.text('$polled'), findsWidgets);
    expect(find.text('$candidates'), findsWidgets);
    Finder chips(SignalState state) =>
        find.byWidgetPredicate((w) => w is StateChip && w.state == state);
    expect(chips(SignalState.live), findsNWidgets(4));
    expect(chips(SignalState.stale), findsOneWidget);
    expect(chips(SignalState.notPolled), findsNWidgets(candidates));
    expect(find.text('62'), findsOneWidget);
  });

  testWidgets('filter shows only candidates', (tester) async {
    tester.view.physicalSize = const Size(800, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = TelemetryStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(host(SignalsScreen(store: store)));
    await tester.tap(find.text('Candidates'));
    await tester.pump();

    for (final signal in vehicleSignalCatalog) {
      expect(find.text(signal.label), signal.isPolled ? findsNothing : findsOneWidget, reason: signal.name);
    }
  });

  testWidgets('renders without overflow at large text scale on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateTelemetry(livePacket());

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
        child: child!,
      ),
      home: SignalsScreen(store: store),
    ));
    expect(tester.takeException(), isNull);
  });
}
