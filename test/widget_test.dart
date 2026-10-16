import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_mobile/main.dart';

void main() {
  testWidgets('App shell shows the Live screen and the five destinations', (WidgetTester tester) async {
    await tester.pumpWidget(Cl250TelemetryApp());

    // App bar title of the Live destination.
    expect(find.text('CL250 Telemetry'), findsOneWidget);

    // Navigation bar destinations.
    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget);
    for (final label in ['Live', 'Signals', 'Record', 'Diagnostics', 'Settings']) {
      expect(find.descendant(of: bar, matching: find.text(label)), findsOneWidget);
    }

    // The removed brand badge and telematics form are gone.
    expect(find.text('HONDA'), findsNothing);
    expect(find.text('SYNC TO BIKE SCREEN'), findsNothing);

    // Tear the tree down so the store's tick timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Navigation switches between destinations', (WidgetTester tester) async {
    await tester.pumpWidget(Cl250TelemetryApp());

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Signals')));
    await tester.pump();
    expect(find.text('NO DATA'), findsWidgets);

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Diagnostics')));
    await tester.pump();
    expect(find.text('LINK'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
