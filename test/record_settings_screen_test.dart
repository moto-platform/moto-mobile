import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_mobile/services/ble_service.dart';
import 'package:moto_mobile/ui/record_screen.dart';
import 'package:moto_mobile/ui/settings_screen.dart';
import 'package:moto_mobile/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget host(Widget child, {double textScale = 1.0}) => MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: child,
    );

void main() {
  late Directory tmp;

  setUp(() {
    // The keystore plugin has no host in unit tests: answer every call with null
    // (no stored secret).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('moto_ui_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Record screen lays out on a 360 px phone at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await tester.pumpWidget(host(RecordScreen(bleService: BleService()), textScale: scale));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('START RECORDING'), findsOneWidget);
      expect(find.text('SESSION METADATA'), findsOneWidget);

      await tester.tap(find.text('Sessions'));
      await tester.pumpAndSettle();
      expect(find.text('No recorded sessions yet.'), findsOneWidget);

      // Dispose the screen (cancels its tick timer).
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Settings screen lays out on a 360 px phone at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(const SettingsScreen(), textScale: scale));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Save'), findsOneWidget);
    });
  }
}
