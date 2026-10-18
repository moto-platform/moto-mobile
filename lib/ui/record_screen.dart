import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/gps_block.dart';
import '../models/session_meta.dart';
import '../models/vehicle_signal_block.dart';
import '../services/app_settings.dart';
import '../services/ble_service.dart';
import '../services/session_recorder.dart';
import '../services/session_store.dart';
import '../services/session_upload.dart';
import 'telemetry/link_status.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

const String _lastUsedMetaPrefsKey = 'session_recorder.last_used_meta';

const List<String> _weatherOptions = ['dry', 'wet', 'unknown'];
const List<String> _routeTypeOptions = ['urban', 'rural', 'highway', 'closed_course', 'stationary'];

/// Ride-recording screen: metadata form + start/stop + live counters on one
/// tab, recorded-sessions list (share/delete) on the other.
class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.bleService,
    this.initiallyConnected = false,
    this.settingsChanged,
  });

  final BleService bleService;

  /// BLE state when the screen is created (it is built lazily, possibly after
  /// the connection was made, so the connection stream alone is not enough).
  final bool initiallyConnected;

  /// Notifies when the settings were saved on the Settings destination, so
  /// the upload action picks up a new server configuration.
  final Listenable? settingsChanged;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final SessionRecorder _recorder;
  late final SessionStore _store;
  late final SessionUploader _uploader;
  final AppSettingsStore _settingsStore = const AppSettingsStore();

  StreamSubscription<Uint8List>? _packetSub;
  StreamSubscription<Uint8List>? _imuPacketSub;
  StreamSubscription<Uint8List>? _gpsPacketSub;
  StreamSubscription<Uint8List>? _vehicleSignalPacketSub;
  StreamSubscription<GpsLinkStatus>? _gpsLinkSub;
  StreamSubscription<int>? _mtuSub;
  StreamSubscription<bool>? _connSub;
  Timer? _tickTimer;

  bool _isConnected = false;
  List<SessionInfo> _sessions = [];
  AppSettings _settings = const AppSettings();

  /// Upload status per session id, refreshed on [_refreshSessions] and
  /// updated live while an upload is in flight.
  final Map<String, SessionUploadStatus> _uploadStatuses = {};

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
    _uploader = SessionUploader(documentsDirProvider: _store.documentsDirProvider);
    _recorder.addListener(_onRecorderChanged);
    _isConnected = widget.initiallyConnected;
    widget.settingsChanged?.addListener(_loadSettings);

    _packetSub = widget.bleService.rawPacketStream.listen(_recorder.handleRawPacket);
    _imuPacketSub = widget.bleService.rawImuBlockStream.listen(_recorder.handleRawImuBlock);
    _gpsPacketSub = widget.bleService.rawGpsBlockStream.listen(_recorder.handleRawGpsBlock);
    _vehicleSignalPacketSub =
        widget.bleService.rawVehicleSignalBlockStream.listen(_recorder.handleRawVehicleSignalBlock);
    _gpsLinkSub = widget.bleService.gpsLinkStream.listen((status) {
      _recorder.handleGpsLinkStatus(status);
      if (mounted) setState(() {});
    });
    _mtuSub = widget.bleService.mtuStream.listen(_recorder.handleMtuNegotiated);
    _connSub = widget.bleService.connectionStream.listen((connected) {
      _recorder.handleConnectionChange(connected);
      if (mounted) setState(() => _isConnected = connected);
    });

    // Refreshes "last packet age" even when no new packet/event arrives.
    _tickTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });

    _loadLastUsedMeta();
    _loadSettings();
    _refreshSessions();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsStore.load();
    if (mounted) setState(() => _settings = settings);
  }

  @override
  void dispose() {
    _packetSub?.cancel();
    _imuPacketSub?.cancel();
    _gpsPacketSub?.cancel();
    _vehicleSignalPacketSub?.cancel();
    _gpsLinkSub?.cancel();
    _mtuSub?.cancel();
    _connSub?.cancel();
    _tickTimer?.cancel();
    widget.settingsChanged?.removeListener(_loadSettings);
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
      requestedMtu: BleGatt.requestedMtu,
    );
  }

  Future<void> _startRecording() async {
    final meta = _buildMetaFromForm();
    final finalMeta = await _recorder.start(meta);
    // The GPS subscription may have settled before this recording started.
    _recorder.handleGpsLinkStatus(widget.bleService.gpsLinkStatus);
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
    final statuses = <String, SessionUploadStatus>{};
    for (final s in sessions) {
      statuses[s.sessionId] = await _uploader.readStatus(s.sessionId);
    }
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _uploadStatuses
          ..clear()
          ..addAll(statuses);
      });
    }
  }

  Future<void> _uploadSession(String sessionId) async {
    setState(() => _uploadStatuses[sessionId] = const SessionUploadStatus(state: SessionUploadState.uploading));
    final status = await _uploader.upload(sessionId, _settings);
    if (!mounted) return;
    setState(() => _uploadStatuses[sessionId] = status);
    if (status.state == SessionUploadState.failed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Upload failed: ${status.reason ?? 'unknown error'}'),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload complete.')));
    }
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
            child: Text('Delete', style: TextStyle(color: context.moto.error)),
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
          title: const Text('Record'),
          actions: [
            if (_recorder.isRecording)
              Padding(
                padding: const EdgeInsets.only(right: Spacing.lg),
                child: StatusPill(
                  icon: Icons.fiber_manual_record,
                  label: 'REC ${_formatDuration(_recorder.elapsed)}',
                  tone: Tone.error,
                ),
              ),
          ],
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
    final t = context.moto;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InfoBanner(
            icon: Icons.screen_lock_portrait,
            tone: Tone.warn,
            text: 'Keep this screen on and the app in the foreground while recording. '
                'Android may kill the BLE connection if the app is backgrounded or '
                'killed -- there is no foreground service yet.',
          ),
          const SizedBox(height: Spacing.lg),
          if (!recording) _buildMetaForm() else _buildLiveCounters(lastAgeMs),
          const SizedBox(height: Spacing.lg),
          FilledButton.icon(
            icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
            label: Text(recording ? 'STOP RECORDING' : 'START RECORDING'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              backgroundColor: recording ? t.textPrimary : t.record,
              foregroundColor: recording ? t.background : t.textPrimary,
            ),
            onPressed: recording ? _stopRecording : _startRecording,
          ),
        ],
      ),
    );
  }

  /// Two fields side by side, stacked when the width is small or the system
  /// text scale is large.
  Widget _pair(Widget a, Widget b) {
    return LayoutBuilder(builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final stack = constraints.maxWidth < 360 || scale > 1.3;
      if (stack) {
        return Column(children: [a, const SizedBox(height: Spacing.md), b]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: Spacing.md),
          Expanded(child: b),
        ],
      );
    });
  }

  Widget _buildMetaForm() {
    const gap = SizedBox(height: Spacing.md);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Session metadata'),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _riderNameCtrl,
                decoration: const InputDecoration(labelText: 'Rider name'),
              ),
              gap,
              _pair(
                TextField(
                  controller: _riderWeightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Rider weight (kg)'),
                ),
                TextField(
                  controller: _extraLoadCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Extra load (kg)'),
                ),
              ),
              gap,
              _pair(
                TextField(
                  controller: _ambientTempCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Ambient temp (°C)'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _weather,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Weather'),
                  items: _weatherOptions.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                  onChanged: (v) => setState(() => _weather = v ?? 'unknown'),
                ),
              ),
              gap,
              _pair(
                TextField(
                  controller: _tireFrontCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Tire pressure front (bar)'),
                ),
                TextField(
                  controller: _tireRearCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Tire pressure rear (bar)'),
                ),
              ),
              gap,
              TextField(
                controller: _fuelLevelCtrl,
                decoration: const InputDecoration(labelText: 'Fuel level (e.g. full, 1/2, reserve)'),
              ),
              gap,
              TextField(
                controller: _vehicleConfigCtrl,
                decoration: const InputDecoration(labelText: 'Vehicle config (gearing/exhaust/filter)'),
              ),
              gap,
              TextField(
                controller: _conditionLabelCtrl,
                decoration: const InputDecoration(labelText: 'Condition label (healthy or fault type)'),
              ),
              gap,
              DropdownButtonFormField<String>(
                initialValue: _routeType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Route type'),
                items: _routeTypeOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => setState(() => _routeType = v),
              ),
              gap,
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(labelText: 'Note'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Display only: the GPS fix of the last block and the subscription state
  /// (D-062: the `gps` characteristic needs a bonded link).
  Widget _buildGpsLine() {
    final block = _recorder.lastGpsBlock;
    final link = widget.bleService.gpsLinkStatus;
    final style = Theme.of(context).textTheme.bodyMedium;
    if (link.state == GpsLinkState.failed) {
      return Text(
        'GPS: not subscribed -- pair the phone with the bike (bonded link required); '
        'it is retried on the next connection',
        style: style!.copyWith(color: context.moto.warning),
      );
    }
    if (block == null) {
      final label = switch (link.state) {
        GpsLinkState.subscribing => 'GPS: pairing / subscribing...',
        GpsLinkState.subscribed => 'GPS: subscribed, waiting for data',
        GpsLinkState.notOffered => 'GPS: not offered by the firmware',
        GpsLinkState.disconnected || GpsLinkState.failed => 'GPS: -',
      };
      return Text(label, style: style);
    }
    final kmh = (block.groundSpeedMps * 3.6).toStringAsFixed(1);
    return Text('GPS: ${block.fixTypeLabel}${block.gnssFixOk ? '' : ' (not OK)'}   '
        'Sats: ${block.numSv}   $kmh km/h   '
        'Lost/skipped: ${_recorder.gpsLostOrSkippedBlocks}', style: style);
  }

  Widget _statCell(String label, String value, {Color? color}) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
          Text(value, style: theme.textTheme.headlineSmall!.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _buildLiveCounters(int? lastAgeMs) {
    final t = context.moto;
    final theme = Theme.of(context);
    final ageColor = (lastAgeMs != null && lastAgeMs > 1000) ? t.error : t.live;
    return SectionCard(
      borderColor: t.record,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fiber_manual_record, color: t.record, size: 18),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text('Session: ${_recorder.currentSessionId ?? '-'}', style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(_formatDuration(_recorder.elapsed), style: theme.textTheme.displayMedium),
          ),
          Text('ELAPSED', style: theme.textTheme.labelSmall),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.xl,
            runSpacing: Spacing.md,
            children: [
              _statCell('Packets', '${_recorder.packetCount}'),
              _statCell('Lost', '${_recorder.lostCount}'),
              _statCell('Loss', '${_recorder.lossPercent.toStringAsFixed(1)}%'),
              _statCell('Decode errors', '${_recorder.decodeErrorCount}',
                  color: _recorder.decodeErrorCount > 0 ? t.error : null),
              _statCell('Disconnects', '${_recorder.disconnectCount}',
                  color: _recorder.disconnectCount > 0 ? t.stale : null),
              if (_recorder.imuBlockCount > 0 || _recorder.imuMissingSamples > 0) ...[
                _statCell('IMU samples', '${_recorder.imuSampleCount}'),
                _statCell('IMU missing', '${_recorder.imuMissingSamples}'),
                _statCell('MTU', '${_recorder.currentMtu ?? '-'}'),
              ],
            ],
          ),
          const SizedBox(height: Spacing.md),
          _buildGpsLine(),
          const SizedBox(height: Spacing.xs),
          VehicleSignalStatusLine(
            latest: _recorder.latestVehicleSignals,
            blockCount: _recorder.vehicleSignalBlockCount,
            lostBlocks: _recorder.vehicleSignalLostBlocks,
          ),
          if (_recorder.firmwareUpdateRecommended)
            const Padding(
              padding: EdgeInsets.only(top: Spacing.md),
              child: InfoBanner(
                icon: Icons.system_update,
                tone: Tone.warn,
                text: 'Only version 2 telemetry packets received so far -- the connected '
                    'device firmware may be outdated. Update it to get CAN health, ages '
                    'and IMU data.',
              ),
            ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.lg,
            runSpacing: Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: _isConnected ? t.live : t.noData,
                    size: 20,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(_isConnected ? 'Connected' : 'Disconnected', style: theme.textTheme.bodyMedium),
                ],
              ),
              Text(
                lastAgeMs == null ? 'No packets yet' : 'Last packet: $lastAgeMs ms ago',
                style: theme.textTheme.titleSmall!.copyWith(color: ageColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _uploadStatusLabel(SessionUploadStatus status) {
    switch (status.state) {
      case SessionUploadState.notUploaded:
        return _settings.isServerConfigured ? 'not uploaded' : 'not uploaded (no server configured)';
      case SessionUploadState.uploading:
        return 'uploading...';
      case SessionUploadState.uploaded:
        return 'uploaded${status.uploadedAtUtc != null ? ' (${status.uploadedAtUtc})' : ''}';
      case SessionUploadState.failed:
        return 'failed: ${status.reason ?? 'unknown error'}';
    }
  }

  Color _uploadStatusColor(SessionUploadStatus status) {
    final t = context.moto;
    return switch (status.state) {
      SessionUploadState.notUploaded => t.textSecondary,
      SessionUploadState.uploading => t.accent,
      SessionUploadState.uploaded => t.live,
      SessionUploadState.failed => t.error,
    };
  }

  Widget _buildUploadButton(String sessionId, SessionUploadStatus status) {
    if (status.state == SessionUploadState.uploading) {
      return const SizedBox(
        width: Spacing.touchTarget,
        height: Spacing.touchTarget,
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    // Recording and sharing must keep working with no server configured;
    // the upload action itself is simply disabled with an explanatory hint.
    final canUpload = _settings.isServerConfigured;
    final isRetry = status.state == SessionUploadState.failed;
    return IconButton(
      icon: Icon(isRetry ? Icons.refresh : Icons.cloud_upload_outlined),
      tooltip: !canUpload
          ? 'Set a server URL in Settings to enable uploads'
          : (isRetry ? 'Retry upload' : 'Upload to moto-server'),
      onPressed: canUpload ? () => _uploadSession(sessionId) : null,
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
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _refreshSessions,
      child: ListView.builder(
        padding: const EdgeInsets.all(Spacing.lg),
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          final s = _sessions[index];
          final duration = s.duration;
          final loss = s.lossPercent;
          final uploadStatus = _uploadStatuses[s.sessionId] ?? const SessionUploadStatus();
          return Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: SectionCard(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.sm, Spacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.sessionId, style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.xs),
                  Text(s.createdUtc?.toLocal().toString() ?? 'unknown time', style: theme.textTheme.bodySmall),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'duration: ${duration == null ? '-' : _formatDuration(duration)}  '
                    'packets: ${s.packetCount ?? '-'}  '
                    'loss: ${loss == null ? '-' : '${loss.toStringAsFixed(1)}%'}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'upload: ${_uploadStatusLabel(uploadStatus)}',
                    style: theme.textTheme.bodyMedium!.copyWith(color: _uploadStatusColor(uploadStatus)),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildUploadButton(s.sessionId, uploadStatus),
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
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Display only: the state of the vehicle-signal block (D-066 item 4) while
/// recording -- how many of the DIDs seen are valid, stale, skipped, answered
/// with a negative response or never received, plus the lost blocks. The
/// states come from the generated [BleVehicleSignalState]; nothing is
/// interpreted here.
class VehicleSignalStatusLine extends StatelessWidget {
  const VehicleSignalStatusLine({
    super.key,
    required this.latest,
    required this.blockCount,
    required this.lostBlocks,
  });

  /// Latest record per DID.
  final Map<int, VehicleSignalRecord> latest;
  final int blockCount;
  final int lostBlocks;

  /// "Vehicle signals: ..." text of the current state.
  String get label {
    if (blockCount == 0) return 'Vehicle signals: waiting for data (or not offered by the firmware)';
    int count(int state) => latest.values.where((r) => r.state == state).length;
    final known = [
      (count(BleVehicleSignalState.valid), 'valid'),
      (count(BleVehicleSignalState.stale), 'stale'),
      (count(BleVehicleSignalState.skipped), 'skipped'),
      (count(BleVehicleSignalState.negativeResponse), 'NRC'),
      (count(BleVehicleSignalState.neverReceived), 'never'),
    ];
    final other = latest.values
        .where((r) => r.state < BleVehicleSignalState.neverReceived || r.state > BleVehicleSignalState.negativeResponse)
        .length;
    final parts = [
      for (final (n, name) in known)
        if (n > 0) '$n $name',
      if (other > 0) '$other unknown state',
    ];
    return 'Vehicle signals (${latest.length} DIDs): ${parts.join(', ')}   Lost blocks: $lostBlocks';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.moto;
    final style = Theme.of(context).textTheme.bodyMedium!;
    final problem = lostBlocks > 0 ||
        latest.values.any((r) => r.isNegativeResponse || r.isSkipped || r.isStale || r.isNeverReceived);
    return Text(label, style: blockCount > 0 && problem ? style.copyWith(color: t.warning) : style);
  }
}

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = two(d.inHours);
  final m = two(d.inMinutes.remainder(60));
  final s = two(d.inSeconds.remainder(60));
  return '$h:$m:$s';
}
