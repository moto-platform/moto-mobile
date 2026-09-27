import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/session_meta.dart';
import '../services/ble_service.dart';
import '../services/session_recorder.dart';
import '../services/session_store.dart';

const String _lastUsedMetaPrefsKey = 'session_recorder.last_used_meta';

const List<String> _weatherOptions = ['dry', 'wet', 'unknown'];
const List<String> _routeTypeOptions = ['urban', 'rural', 'highway', 'closed_course', 'stationary'];

/// Ride-recording screen: metadata form + start/stop + live counters on one
/// tab, recorded-sessions list (share/delete) on the other.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.bleService});

  final BleService bleService;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final SessionRecorder _recorder;
  late final SessionStore _store;

  StreamSubscription<Uint8List>? _packetSub;
  StreamSubscription<bool>? _connSub;
  Timer? _tickTimer;

  bool _isConnected = false;
  List<SessionInfo> _sessions = [];

  final _riderNameCtrl = TextEditingController();
  final _riderWeightCtrl = TextEditingController();
  final _extraLoadCtrl = TextEditingController();
  final _ambientTempCtrl = TextEditingController();
  String _weather = 'unknown';
  final _tireFrontCtrl = TextEditingController();
  final _tireRearCtrl = TextEditingController();
  final _fuelLevelCtrl = TextEditingController();
  final _vehicleConfigCtrl = TextEditingController();
  final _conditionLabelCtrl = TextEditingController(text: 'healthy');
  String? _routeType = 'urban';
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _recorder = SessionRecorder();
    _store = SessionStore();
    _recorder.addListener(_onRecorderChanged);

    _packetSub = widget.bleService.rawPacketStream.listen(_recorder.handleRawPacket);
    _connSub = widget.bleService.connectionStream.listen((connected) {
      _recorder.handleConnectionChange(connected);
      if (mounted) setState(() => _isConnected = connected);
    });

    // Refreshes "last packet age" even when no new packet/event arrives.
    _tickTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });

    _loadLastUsedMeta();
    _refreshSessions();
  }

  @override
  void dispose() {
    _packetSub?.cancel();
    _connSub?.cancel();
    _tickTimer?.cancel();
    _recorder.removeListener(_onRecorderChanged);
    if (_recorder.isRecording) {
      // Best-effort: don't leave a dangling recording if the user backs out.
      unawaited(_recorder.stop());
      unawaited(WakelockPlus.disable());
    }
    _riderNameCtrl.dispose();
    _riderWeightCtrl.dispose();
    _extraLoadCtrl.dispose();
    _ambientTempCtrl.dispose();
    _tireFrontCtrl.dispose();
    _tireRearCtrl.dispose();
    _fuelLevelCtrl.dispose();
    _vehicleConfigCtrl.dispose();
    _conditionLabelCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _onRecorderChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadLastUsedMeta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastUsedMetaPrefsKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _riderNameCtrl.text = json['rider_name'] as String? ?? '';
        _riderWeightCtrl.text = (json['rider_weight_kg'] as num?)?.toString() ?? '';
        _extraLoadCtrl.text = (json['extra_load_kg'] as num?)?.toString() ?? '';
        _ambientTempCtrl.text = (json['ambient_temp_c'] as num?)?.toString() ?? '';
        _weather = json['weather'] as String? ?? 'unknown';
        _tireFrontCtrl.text = (json['tire_pressure_front_bar'] as num?)?.toString() ?? '';
        _tireRearCtrl.text = (json['tire_pressure_rear_bar'] as num?)?.toString() ?? '';
        _fuelLevelCtrl.text = json['fuel_level'] as String? ?? '';
        _vehicleConfigCtrl.text = json['vehicle_config'] as String? ?? '';
        _conditionLabelCtrl.text = json['condition_label'] as String? ?? 'healthy';
        _routeType = json['route_type'] as String? ?? 'urban';
      });
    } catch (_) {
      // No previous values (or corrupt prefs): keep the form defaults.
    }
  }

  Future<void> _saveLastUsedMeta(SessionMeta meta) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastUsedMetaPrefsKey,
      jsonEncode({
        'rider_name': meta.riderName,
        'rider_weight_kg': meta.riderWeightKg,
        'extra_load_kg': meta.extraLoadKg,
        'ambient_temp_c': meta.ambientTempC,
        'weather': meta.weather,
        'tire_pressure_front_bar': meta.tirePressureFrontBar,
        'tire_pressure_rear_bar': meta.tirePressureRearBar,
        'fuel_level': meta.fuelLevel,
        'vehicle_config': meta.vehicleConfig,
        'condition_label': meta.conditionLabel,
        'route_type': meta.routeType,
      }),
    );
  }

  double? _parseDouble(String text) => text.trim().isEmpty ? null : double.tryParse(text.trim());

  SessionMeta _buildMetaFromForm() {
    return SessionMeta(
      sessionId: '', // stamped by SessionRecorder.start()
      createdUtc: '',
      riderName: _riderNameCtrl.text.trim().isEmpty ? null : _riderNameCtrl.text.trim(),
      riderWeightKg: _parseDouble(_riderWeightCtrl.text),
      extraLoadKg: _parseDouble(_extraLoadCtrl.text),
      ambientTempC: _parseDouble(_ambientTempCtrl.text),
      weather: _weather,
      tirePressureFrontBar: _parseDouble(_tireFrontCtrl.text),
      tirePressureRearBar: _parseDouble(_tireRearCtrl.text),
      fuelLevel: _fuelLevelCtrl.text.trim().isEmpty ? null : _fuelLevelCtrl.text.trim(),
      vehicleConfig: _vehicleConfigCtrl.text.trim().isEmpty ? null : _vehicleConfigCtrl.text.trim(),
      conditionLabel: _conditionLabelCtrl.text.trim().isEmpty ? 'healthy' : _conditionLabelCtrl.text.trim(),
      routeType: _routeType,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      deviceName: widget.bleService.connectedDeviceName,
    );
  }

  Future<void> _startRecording() async {
    final meta = _buildMetaFromForm();
    final finalMeta = await _recorder.start(meta);
    await _saveLastUsedMeta(finalMeta);
    await WakelockPlus.enable();
    if (mounted) setState(() {});
  }

  Future<void> _stopRecording() async {
    final summary = await _recorder.stop();
    await WakelockPlus.disable();
    await _refreshSessions();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Session saved: ${summary.packetCount} packets, '
        '${summary.lossPercent.toStringAsFixed(1)}% loss',
      ),
    ));
  }

  Future<void> _refreshSessions() async {
    final sessions = await _store.listSessions();
    if (mounted) setState(() => _sessions = sessions);
  }

  Future<void> _shareSession(String sessionId) async {
    final files = await _store.shareableFiles(sessionId);
    if (files.isEmpty) return;
    await Share.shareXFiles(
      files.map((f) => XFile(f.path)).toList(),
      subject: 'moto-mobile ride session $sessionId',
    );
  }

  Future<void> _confirmDeleteSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text('This permanently deletes "$sessionId" and its recorded files.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _store.deleteSession(sessionId);
      await _refreshSessions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ride Recorder'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Record'),
            Tab(text: 'Sessions'),
          ]),
        ),
        body: TabBarView(
          children: [
            _buildRecordTab(),
            _buildSessionsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordTab() {
    final recording = _recorder.isRecording;
    final lastPacketUtc = _recorder.lastPacketUtc;
    final lastAgeMs = lastPacketUtc == null ? null : DateTime.now().toUtc().difference(lastPacketUtc).inMilliseconds;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: const Text(
              'Keep this screen on and the app in the foreground while recording. '
              'Android may kill the BLE connection if the app is backgrounded or '
              'killed -- there is no foreground service yet.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          if (!recording) _buildMetaForm() else _buildLiveCounters(lastAgeMs),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
              label: Text(recording ? 'STOP RECORDING' : 'START RECORDING'),
              style: ElevatedButton.styleFrom(
                backgroundColor: recording ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: recording ? _stopRecording : _startRecording,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SESSION METADATA', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        TextField(
          controller: _riderNameCtrl,
          decoration: const InputDecoration(labelText: 'Rider name'),
        ),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _riderWeightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Rider weight (kg)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _extraLoadCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Extra load (kg)'),
            ),
          ),
        ]),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ambientTempCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Ambient temp (°C)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _weather,
              decoration: const InputDecoration(labelText: 'Weather'),
              items: _weatherOptions.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
              onChanged: (v) => setState(() => _weather = v ?? 'unknown'),
            ),
          ),
        ]),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _tireFrontCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Tire pressure front (bar)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _tireRearCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Tire pressure rear (bar)'),
            ),
          ),
        ]),
        TextField(
          controller: _fuelLevelCtrl,
          decoration: const InputDecoration(labelText: 'Fuel level (e.g. full, 1/2, reserve)'),
        ),
        TextField(
          controller: _vehicleConfigCtrl,
          decoration: const InputDecoration(labelText: 'Vehicle config (gearing/exhaust/filter)'),
        ),
        TextField(
          controller: _conditionLabelCtrl,
          decoration: const InputDecoration(labelText: 'Condition label (healthy or fault type)'),
        ),
        DropdownButtonFormField<String>(
          initialValue: _routeType,
          decoration: const InputDecoration(labelText: 'Route type'),
          items: _routeTypeOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
          onChanged: (v) => setState(() => _routeType = v),
        ),
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(labelText: 'Note'),
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildLiveCounters(int? lastAgeMs) {
    final ageColor = (lastAgeMs != null && lastAgeMs > 1000) ? Colors.red : Colors.greenAccent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session: ${_recorder.currentSessionId ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Elapsed: ${_formatDuration(_recorder.elapsed)}'),
            Text('Packets: ${_recorder.packetCount}   Lost: ${_recorder.lostCount}   '
                'Loss: ${_recorder.lossPercent.toStringAsFixed(1)}%'),
            Text('Decode errors: ${_recorder.decodeErrorCount}   Disconnects: ${_recorder.disconnectCount}'),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: _isConnected ? Colors.greenAccent : Colors.grey,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(_isConnected ? 'Connected' : 'Disconnected'),
                const SizedBox(width: 16),
                Text(
                  lastAgeMs == null ? 'No packets yet' : 'Last packet: $lastAgeMs ms ago',
                  style: TextStyle(color: ageColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsTab() {
    if (_sessions.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshSessions,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No recorded sessions yet.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshSessions,
      child: ListView.builder(
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          final s = _sessions[index];
          final duration = s.duration;
          final loss = s.lossPercent;
          return ListTile(
            title: Text(s.sessionId),
            isThreeLine: true,
            subtitle: Text(
              '${s.createdUtc?.toLocal().toString() ?? 'unknown time'}\n'
              'duration: ${duration == null ? '-' : _formatDuration(duration)}  '
              'packets: ${s.packetCount ?? '-'}  '
              'loss: ${loss == null ? '-' : '${loss.toStringAsFixed(1)}%'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'Share',
                  onPressed: () => _shareSession(s.sessionId),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDeleteSession(s.sessionId),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = two(d.inHours);
  final m = two(d.inMinutes.remainder(60));
  final s = two(d.inSeconds.remainder(60));
  return '$h:$m:$s';
}
