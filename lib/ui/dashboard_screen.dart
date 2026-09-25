import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../models/telemetry_data.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final BleService _bleService = BleService();
  bool _isConnected = false;
  TelemetryData _data = TelemetryData.initial();

  final TextEditingController _songCtrl = TextEditingController(text: "Highway Star");
  final TextEditingController _artistCtrl = TextEditingController(text: "Deep Purple");
  final TextEditingController _distCtrl = TextEditingController(text: "450");

  StreamSubscription<bool>? _connSub;
  StreamSubscription<TelemetryData>? _telemSub;

  @override
  void initState() {
    super.initState();
    _connSub = _bleService.connectionStream.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    _telemSub = _bleService.telemetryStream.listen((data) {
      if (mounted) setState(() => _data = data);
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _telemSub?.cancel();
    _songCtrl.dispose();
    _artistCtrl.dispose();
    _distCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B26),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF2E4C),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('HONDA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
            ),
            const SizedBox(width: 10),
            const Text('CL250 Telemetry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: _isConnected ? const Color(0xFF00E676) : Colors.grey),
            onPressed: () {
              if (_isConnected) {
                _bleService.disconnect();
              } else {
                _bleService.connectToBike();
              }
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Hero Speedometer Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF161B26),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TACHOMETER & SPEED', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('${_data.rpm.toInt()} RPM', style: const TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('${_data.speed}', style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Text('KM/H', style: TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, letterSpacing: 2)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Motorcycle Lean Dynamics Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF161B26),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('LEAN DYNAMICS', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('${_data.leanAngle.toStringAsFixed(1)}°', style: const TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Transform.rotate(
                    angle: _data.leanAngle * 3.14159 / 180,
                    child: const Icon(Icons.two_wheeler, size: 90, color: Color(0xFF00F0FF)),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text('${_data.maxLeanLeft.toStringAsFixed(1)}°', style: const TextStyle(color: Color(0xFFFFB800), fontWeight: FontWeight.bold, fontSize: 18)),
                          const Text('MAX LEFT', style: TextStyle(color: Colors.grey, fontSize: 10)),
                        ],
                      ),
                      Column(
                        children: [
                          Text('${_data.maxLeanRight.toStringAsFixed(1)}°', style: const TextStyle(color: Color(0xFFFFB800), fontWeight: FontWeight.bold, fontSize: 18)),
                          const Text('MAX RIGHT', style: TextStyle(color: Colors.grey, fontSize: 10)),
                        ],
                      ),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Engine Health Metrics Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B26),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricTile("Coolant", "${_data.coolantTemp} °C"),
                  _buildMetricTile("Throttle", "${_data.throttlePos.toInt()} %"),
                  _buildMetricTile("Battery", "${_data.batteryVolt.toStringAsFixed(1)} V"),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Telematics Sync Form Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B26),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TELEMATICS SYNC TO HANDLEBAR', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _songCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Song Title', labelStyle: TextStyle(color: Colors.grey)),
                  ),
                  TextField(
                    controller: _artistCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Artist Name', labelStyle: TextStyle(color: Colors.grey)),
                  ),
                  TextField(
                    controller: _distCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Nav Distance (m)', labelStyle: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F0FF)),
                      onPressed: () {
                        final dist = int.tryParse(_distCtrl.text) ?? 0;
                        _bleService.syncTelematics(_songCtrl.text, _artistCtrl.text, dist);
                      },
                      child: const Text('SYNC TO BIKE SCREEN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}
