import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/ble_service.dart';
import 'ui/app_shell.dart';
import 'ui/theme/app_theme.dart';

void main() {
  runApp(Cl250TelemetryApp());
}

class Cl250TelemetryApp extends StatelessWidget {
  Cl250TelemetryApp({super.key, BleService? bleService}) : bleService = bleService ?? BleService();

  /// Single BLE connection shared by every screen, so recording captures the
  /// same live connection the Live and Signals screens show.
  final BleService bleService;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: MaterialApp(
        title: 'CL250 Telemetry',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        darkTheme: buildAppTheme(),
        home: AppShell(bleService: bleService),
      ),
    );
  }
}
