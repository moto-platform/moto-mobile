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
  // Since defs v0.12.0 (D-068) the catalog has no candidates: every signal is
  // polled. [recordOnly] are those the v4 packet does not carry, so they get a
  // value only from a vehicle-signal record.
  final recordOnly =
      vehicleSignalCatalog.where((s) => s.isPolled && !boundSignalNames.contains(s.name)).toList();
  final total = vehicleSignalCatalog.length;

  Finder chipsOf(SignalState state) => find.byWidgetPredicate((w) => w is StateChip && w.state == state);

  /// Pumps the Signals screen on a tall viewport against [store].
  Future<void> pumpScreen(WidgetTester tester, TelemetryStore store) async {
    tester.view.physicalSize = const Size(800, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(SignalsScreen(store: store)));
  }

  testWidgets('without vehicle-signal records every polled signal shows NO DATA', (tester) async {
    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    await pumpScreen(tester, store);

    expect(chipsOf(SignalState.noData), findsNWidgets(total));
    expect(chipsOf(SignalState.notPolled), findsNothing);
    expect(find.text('NOT POLLED'), findsNothing);
    expect(find.text('Not polled'), findsNothing);
    expect(chipsOf(SignalState.live), findsNothing);
  });

  testWidgets('a record-only signal that arrives with state valid shows LIVE with its value and catalog unit',
      (tester) async {
    final candidate = recordOnly.first;
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
    expect(chipsOf(SignalState.noData), findsNWidgets(total - 1));
    expect(find.textContaining('Poll every ${candidate.pollPeriodMs} ms'), findsWidgets);
  });

  testWidgets('a valid record older than 2000 ms, and a stale record, show STALE', (tester) async {
    var now = DateTime.utc(2026, 10, 11, 12);
    final store = TelemetryStore(clock: () => now);
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateVehicleSignalBlock(blockOf([
      record(recordOnly[0], BleVehicleSignalState.valid, raw: 1),
      record(recordOnly[1], BleVehicleSignalState.stale, raw: 1, ageMs: 7000),
    ]));
    now = now.add(vehicleSignalLiveWithin + const Duration(milliseconds: 1));
    store.updateVehicleSignalBlock(blockOf([record(recordOnly[2], BleVehicleSignalState.valid, raw: 1)]));
    await pumpScreen(tester, store);

    // recordOnly[0]: valid but received 2001 ms ago; recordOnly[1]: state stale;
    // recordOnly[2]: valid and just received.
    expect(chipsOf(SignalState.stale), findsNWidgets(2));
    expect(find.descendant(of: find.byType(StateChip), matching: find.text('STALE')), findsNWidgets(2));
    expect(chipsOf(SignalState.live), findsOneWidget);
  });

  testWidgets('a negative response shows NRC 0x31 and a skipped DID shows SKIPPED', (tester) async {
    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateVehicleSignalBlock(blockOf([
      record(recordOnly[0], BleVehicleSignalState.negativeResponse,
          raw: 0x31, ageMs: BleTelemetry.ageNeverReceived),
      record(recordOnly[1], BleVehicleSignalState.skipped),
    ]));
    await pumpScreen(tester, store);

    expect(find.text('NRC 0x31'), findsOneWidget);
    expect(chipsOf(SignalState.negativeResponse), findsOneWidget);
    expect(find.text('SKIPPED'), findsOneWidget);
    expect(chipsOf(SignalState.live), findsNothing);
    expect(chipsOf(SignalState.noData), findsNWidgets(total - 2));
  });

  testWidgets('a v4 telemetry packet keeps the packet-bound signals LIVE alongside vehicle-signal records',
      (tester) async {
    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateTelemetry(livePacket());
    store.updateVehicleSignalBlock(blockOf([record(recordOnly.first, BleVehicleSignalState.valid, raw: 1)]));
    await pumpScreen(tester, store);

    expect(chipsOf(SignalState.live), findsNWidgets(5)); // four live v4 signals + the record-only signal
    expect(find.text('62'), findsOneWidget);
  });

  testWidgets('records are dropped on disconnect', (tester) async {
    final store = TelemetryStore();
    addTearDown(store.dispose);
    store.updateConnection(true);
    store.updateVehicleSignalBlock(blockOf([record(recordOnly.first, BleVehicleSignalState.valid, raw: 1)]));
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
    final candidates = vehicleSignalCatalog.length - polled; // 0 since D-068
    expect(find.text('4'), findsWidgets); // four live (battery is stale)
    expect(find.text('$polled'), findsWidgets);
    expect(find.text('$candidates'), findsWidgets);
    Finder chips(SignalState state) =>
        find.byWidgetPredicate((w) => w is StateChip && w.state == state);
    expect(chips(SignalState.live), findsNWidgets(4));
    expect(chips(SignalState.stale), findsOneWidget);
    expect(chips(SignalState.notPolled), findsNWidgets(candidates));
    expect(chips(SignalState.noData), findsNWidgets(polled - 5));
    expect(find.text('62'), findsOneWidget);
  });

  testWidgets('filter shows only candidates (none in the current catalog)', (tester) async {
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
