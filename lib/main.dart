import 'package:flutter/material.dart';
import 'services/ble_service.dart';
import 'ui/dashboard_screen.dart';

void main() {
  runApp(HondaTelemetryApp());
}

class HondaTelemetryApp extends StatelessWidget {
  HondaTelemetryApp({super.key, BleService? bleService}) : bleService = bleService ?? BleService();

  /// Single BLE connection shared by the dashboard and the ride recorder, so
  /// recording captures the same live connection the dashboard shows.
  final BleService bleService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Honda CL250 Telemetry',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F0FF),
          secondary: Color(0xFFFF2E4C),
        ),
      ),
      home: DashboardScreen(bleService: bleService),
    );
  }
}
