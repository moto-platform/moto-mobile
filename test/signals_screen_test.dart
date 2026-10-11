import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/telemetry_data.dart';
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

void main() {
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
