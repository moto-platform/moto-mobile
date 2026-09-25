import 'package:flutter/material.dart';
import 'ui/dashboard_screen.dart';

void main() {
  runApp(const HondaTelemetryApp());
}

class HondaTelemetryApp extends StatelessWidget {
  const HondaTelemetryApp({super.key});

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
      home: const DashboardScreen(),
    );
  }
}
