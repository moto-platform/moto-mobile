import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:path_provider/path_provider.dart';

import '../models/imu_block.dart';
import '../models/session_meta.dart';
import '../models/telemetry_data.dart';

/// Provides the platform's app-documents directory. Overridden in tests so
/// [SessionRecorder] never touches a real device path_provider channel.
typedef DocumentsDirProvider = Future<Directory> Function();

/// Resolves (and creates if needed) the `sessions/` directory under the
/// app's documents directory. Shared by [SessionRecorder] and any
/// session-listing/sharing code so they always agree on where sessions live.
Future<Directory> resolveSessionsRootDir(DocumentsDirProvider documentsDirProvider) async {
  final docs = await documentsDirProvider();
  final dir = Directory('${docs.path}/sessions');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Summary written to `summary.json` when a recording stops. Field names and
/// keys follow the session file contract shared with moto-server.
class SessionSummary {
  final Duration duration;
  final int packetCount;
  final int lostCount;
  final double lossPercent;
  final int decodeErrorCount;
  final int disconnectCount;
  final String? firstPacketUtc;
  final String? lastPacketUtc;

  /// Telemetry packets seen, keyed by their `version` byte (2 or 3).
  final Map<int, int> packetVersions;

  final int imuBlockCount;
  final int imuSampleCount;
  final int imuMissingSamples;
  final double imuLossPercent;

  /// Last negotiated ATT MTU, or `null` if never reported this session.
  final int? mtu;

  const SessionSummary({
    required this.duration,
    required this.packetCount,
    required this.lostCount,
    required this.lossPercent,
    required this.decodeErrorCount,
    required this.disconnectCount,
    required this.firstPacketUtc,
    required this.lastPacketUtc,
    this.packetVersions = const {},
    this.imuBlockCount = 0,
    this.imuSampleCount = 0,
    this.imuMissingSamples = 0,
    this.imuLossPercent = 0.0,
    this.mtu,
  });

  Map<String, dynamic> toJson() => {
        'duration_ms': duration.inMilliseconds,
        'packet_count': packetCount,
        'lost_count': lostCount,
        'loss_percent': lossPercent,
        'decode_error_count': decodeErrorCount,
        'disconnect_count': disconnectCount,
        'first_packet_utc': firstPacketUtc,
        'last_packet_utc': lastPacketUtc,
        'packet_versions': packetVersions.map((k, v) => MapEntry(k.toString(), v)),
        'imu_block_count': imuBlockCount,
        'imu_sample_count': imuSampleCount,
        'imu_missing_samples': imuMissingSamples,
        'imu_loss_percent': imuLossPercent,
        'mtu': mtu,
      };

  factory SessionSummary.fromJson(Map<String, dynamic> json) => SessionSummary(
        duration: Duration(milliseconds: json['duration_ms'] as int? ?? 0),
        packetCount: json['packet_count'] as int? ?? 0,
        lostCount: json['lost_count'] as int? ?? 0,
        lossPercent: (json['loss_percent'] as num?)?.toDouble() ?? 0.0,
        decodeErrorCount: json['decode_error_count'] as int? ?? 0,
        disconnectCount: json['disconnect_count'] as int? ?? 0,
        firstPacketUtc: json['first_packet_utc'] as String?,
        lastPacketUtc: json['last_packet_utc'] as String?,
        packetVersions: (json['packet_versions'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(int.parse(k), v as int)) ??
            const {},
        imuBlockCount: json['imu_block_count'] as int? ?? 0,
        imuSampleCount: json['imu_sample_count'] as int? ?? 0,
        imuMissingSamples: json['imu_missing_samples'] as int? ?? 0,
        imuLossPercent: (json['imu_loss_percent'] as num?)?.toDouble() ?? 0.0,
        mtu: json['mtu'] as int?,
      );
}

enum SessionRecorderState { idle, recording }

/// Records raw BLE telemetry and IMU notifications to a per-session
/// directory as `meta.json`, `telemetry.csv`, `events.csv` and (when any IMU
/// block arrives) `imu.csv`, and writes a `summary.json` on stop.
///
/// Field decoding is delegated entirely to [TelemetryData.fromBinaryBuffer]
/// and [ImuBlock.decode] -- the single sources of truth for the BLE packet
/// schema. This class only adds timing, sequence/gap bookkeeping and
/// CSV/JSON formatting around them; it never re-implements offset/scale
/// logic.
///
/// This class has no dependency on `BleService`: the caller (a UI widget)
/// feeds it raw packets, IMU blocks, MTU changes and connection-state
/// changes. That keeps it trivially unit-testable with synthetic packets and
/// a temp directory, with no BLE stack involved.
class SessionRecorder extends ChangeNotifier {
  SessionRecorder({DocumentsDirProvider? documentsDirProvider})
      : _documentsDirProvider = documentsDirProvider ?? getApplicationDocumentsDirectory;

  final DocumentsDirProvider _documentsDirProvider;

  static const List<String> telemetryCsvHeader = [
    'rx_utc_iso',
    'rx_mono_ms',
    'seq',
    'lost_since_prev',
    'raw_hex',
    'rpm',
    'speed_kmh',
    'coolant_c',
    'tps_pct',
    'battery_v',
    'lean_deg',
    'max_lean_right_deg',
    'max_lean_left_deg',
    'rpm_valid',
    'speed_valid',
    'coolant_valid',
    'tps_valid',
    'battery_valid',
    'lean_valid',
    'ecu_present',
    'decode_error',
    // Version-3-and-later columns appended at the end (contract §telemetry.csv):
    // blank whenever the decoded packet is version 2 or failed to decode.
    'packet_version',
    'device_time_ms',
    'rpm_age_ms',
    'speed_age_ms',
    'coolant_age_ms',
    'tps_age_ms',
    'battery_age_ms',
    'imu_active',
    'can_bus_state',
    'can_tec',
    'can_rec',
    'can_bus_off_count',
    'unanswered_did_count',
    'can_flags',
    // Version-4-only columns (D-058 tester stats, schema `testerStats`):
    // blank for version 2 and 3 rows and for rows that failed to decode.
    'step_gap_max_ms',
    'step_gap_over_count',
    'rtt_did',
    'rtt_min_ms',
    'rtt_max_ms',
    'rtt_sum_ms',
    'rtt_count',
    'rtt_nrc78_count',
  ];

  static const List<String> eventsCsvHeader = [
    'rx_utc_iso',
    'rx_mono_ms',
    'event',
    'detail',
  ];

  static const List<String> imuCsvHeader = [
    'rx_utc_iso',
    'rx_mono_ms',
    'block_seq',
    'block_flags',
    'block_missing_samples',
    'sample_index',
    'device_time_ms',
    'ax_raw',
    'ay_raw',
    'az_raw',
    'gx_raw',
    'gy_raw',
    'gz_raw',
    'ax_g',
    'ay_g',
    'az_g',
    'gx_dps',
    'gy_dps',
    'gz_dps',
  ];

  /// The first N telemetry packets considered for the
  /// `firmware_update_recommended` heuristic (contract §events.csv).
  static const int _firmwareCheckPacketWindow = 20;

  /// ATT notification header (opcode + handle): a notification carries at most
  /// MTU - 3 bytes of payload (schema `gatt.mtu.rule`).
  static const int _attNotificationOverheadBytes = 3;

  /// Below this negotiated MTU, version 2 packets are expected (the firmware
  /// falls back to it on its own: even the smallest full layout, version 3,
  /// does not fit) and not a sign of old firmware.
  static const int _mtuTooSmallForV3 = BleTelemetry.totalBytesV3 + _attNotificationOverheadBytes;

  /// True for the packet versions that carry the version-3 field set (ages,
  /// CAN health, `imuActive`): version 3 and its superset, version 4.
  static bool _hasV3Layout(int packetVersion) =>
      packetVersion == TelemetryVersion.v3 || packetVersion == TelemetryVersion.v4;

  SessionRecorderState _state = SessionRecorderState.idle;
  SessionRecorderState get state => _state;
  bool get isRecording => _state == SessionRecorderState.recording;

  SessionMeta? _meta;
  SessionMeta? get meta => _meta;
  String? get currentSessionId => _meta?.sessionId;

  /// Directory of the current (or, after [stop], most recently finished)
  /// session.
  Directory? _sessionDir;
  Directory? get sessionDir => _sessionDir;

  IOSink? _telemetrySink;
  IOSink? _eventsSink;
  IOSink? _imuSink;
  bool _imuFileCreated = false;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _flushTimer;

  int _packetCount = 0;
  int _lostCount = 0;
  int _decodeErrorCount = 0;
  int _disconnectCount = 0;
  int? _lastSeq;
  bool? _lastConnState;
  DateTime? _firstPacketUtc;
  DateTime? _lastPacketUtc;

  final Map<int, int> _packetVersionCounts = {};
  int? _lastLoggedPacketVersion;
  int _firmwareCheckPacketsSeen = 0;
  int _firmwareCheckV2PacketsSeen = 0;
  bool _firmwareRecommendationLogged = false;
  int? _currentMtu;

  CanBusState? _lastCanBusState;
  int? _lastCanFlags;
  int? _lastCanBusOffCount;
  int? _lastUnansweredDidCount;

  final ImuGapTracker _imuGapTracker = ImuGapTracker();
  int _imuBlockCount = 0;
  int _imuSampleCount = 0;
  int _imuMissingSamples = 0;

  int get packetCount => _packetCount;
  int get lostCount => _lostCount;
  int get decodeErrorCount => _decodeErrorCount;
  int get disconnectCount => _disconnectCount;
  DateTime? get lastPacketUtc => _lastPacketUtc;
  bool? get isBleConnected => _lastConnState;
  Duration get elapsed => _stopwatch.elapsed;
  int? get currentMtu => _currentMtu;
  int get imuBlockCount => _imuBlockCount;
  int get imuSampleCount => _imuSampleCount;
  int get imuMissingSamples => _imuMissingSamples;

  /// True once [_firmwareCheckPacketWindow] telemetry packets have all been
  /// version 2 while the MTU did not by itself explain it -- surfaced so the
  /// UI can show a persistent warning without re-deriving the heuristic.
  bool get firmwareUpdateRecommended => _firmwareRecommendationLogged;

  double get lossPercent {
    final total = _packetCount + _lostCount;
    if (total <= 0) return 0.0;
    return (_lostCount / total) * 100.0;
  }

  double get imuLossPercent {
    final total = _imuSampleCount + _imuMissingSamples;
    if (total <= 0) return 0.0;
    return (_imuMissingSamples / total) * 100.0;
  }

  /// Starts a new recording session: creates
  /// `<documents>/sessions/<session_id>/` and writes `meta.json`
  /// immediately. Returns the final [SessionMeta] with `sessionId` and
  /// `createdUtc` stamped at the actual start time (any values passed in
  /// [meta] for those two fields are overwritten).
  Future<SessionMeta> start(SessionMeta meta) async {
    if (isRecording) {
      throw StateError('A recording is already in progress.');
    }

    final nowUtc = DateTime.now().toUtc();
    final sessionId = _generateSessionId(nowUtc);
    final finalMeta = meta.copyWith(
      sessionId: sessionId,
      createdUtc: nowUtc.toIso8601String(),
    );

    final root = await resolveSessionsRootDir(_documentsDirProvider);
    final dir = Directory('${root.path}/$sessionId');
    await dir.create(recursive: true);

    _sessionDir = dir;
    _meta = finalMeta;
    _packetCount = 0;
    _lostCount = 0;
    _decodeErrorCount = 0;
    _disconnectCount = 0;
    _lastSeq = null;
    _lastConnState = null;
    _firstPacketUtc = null;
    _lastPacketUtc = null;
    _packetVersionCounts.clear();
    _lastLoggedPacketVersion = null;
    _firmwareCheckPacketsSeen = 0;
    _firmwareCheckV2PacketsSeen = 0;
    _firmwareRecommendationLogged = false;
    _currentMtu = null;
    _lastCanBusState = null;
    _lastCanFlags = null;
    _lastCanBusOffCount = null;
    _lastUnansweredDidCount = null;
    _imuGapTracker.reset();
    _imuBlockCount = 0;
    _imuSampleCount = 0;
    _imuMissingSamples = 0;
    _imuFileCreated = false;
    _imuSink = null;

    await File('${dir.path}/meta.json').writeAsString(_prettyJson(finalMeta.toJson()));

    _telemetrySink = File('${dir.path}/telemetry.csv').openWrite();
    _telemetrySink!.writeln(_csvRow(telemetryCsvHeader));

    _eventsSink = File('${dir.path}/events.csv').openWrite();
    _eventsSink!.writeln(_csvRow(eventsCsvHeader));

    _stopwatch
      ..reset()
      ..start();
    _state = SessionRecorderState.recording;

    _logEvent('recording_started', 'session_id=$sessionId');

    // Make sure the CSV headers (and the recording_started event) are
    // actually on disk before start() returns, not just buffered -- callers
    // may want to inspect the session directory right away.
    await _flush();

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 1), (_) => _flush());

    notifyListeners();
    return finalMeta;
  }

  /// Feeds one raw BLE telemetry notification payload into the recorder.
  /// No-op if not currently recording. Packets that fail to decode (bad
  /// version or wrong size for their version) are still written, with
  /// `decode_error` set and the decoded fields left blank -- nothing is ever
  /// silently dropped.
  void handleRawPacket(Uint8List bytes) {
    if (!isRecording) return;

    final rxUtc = DateTime.now().toUtc();
    final rxMonoMs = _stopwatch.elapsedMilliseconds;
    final rawHex = _bytesToHex(bytes);

    // `seq` sits at the same offset (1) in the version 2, 3 and 4 layouts, so
    // this peek is version-independent.
    final seq = bytes.length > BleTelemetryV2Offsets.seq ? bytes[BleTelemetryV2Offsets.seq] : null;
    int? lostSincePrev;
    if (seq != null) {
      if (_lastSeq != null) {
        // Same rolling 0-255 counter rule as TelemetryData.fromBinaryBuffer.
        lostSincePrev = (seq - _lastSeq! - 1 + 256) % 256;
      } else {
        lostSincePrev = 0;
      }
      _lastSeq = seq;
    }

    _packetCount++;
    _firstPacketUtc ??= rxUtc;
    _lastPacketUtc = rxUtc;

    String? decodeError;
    int? rawVersion;
    if (bytes.isEmpty) {
      decodeError = 'empty packet';
    } else {
      rawVersion = bytes[0];
      final expectedLength = TelemetryData.expectedLength(rawVersion);
      if (expectedLength == null || !BleTelemetry.acceptedVersions.contains(rawVersion)) {
        decodeError = 'version mismatch: got $rawVersion (expected one of ${BleTelemetry.acceptedVersions.join('/')})';
      } else if (bytes.length != expectedLength) {
        decodeError = 'size mismatch: got ${bytes.length} bytes (expected $expectedLength for version $rawVersion)';
      }
    }

    TelemetryData? data;
    if (decodeError == null) {
      data = TelemetryData.fromBinaryBuffer(bytes);
    } else {
      _decodeErrorCount++;
    }

    _writeTelemetryRow(
      rxUtc: rxUtc,
      rxMonoMs: rxMonoMs,
      seq: seq,
      lostSincePrev: lostSincePrev,
      rawHex: rawHex,
      data: data,
      decodeError: decodeError,
    );

    if (decodeError != null) {
      _logEvent('decode_error', decodeError, rxUtc: rxUtc, rxMonoMs: rxMonoMs);
    }

    if ((lostSincePrev ?? 0) > 0) {
      _lostCount += lostSincePrev!;
      _logEvent('packet_gap', 'lost=$lostSincePrev seq=$seq', rxUtc: rxUtc, rxMonoMs: rxMonoMs);
    }

    if (rawVersion != null && BleTelemetry.acceptedVersions.contains(rawVersion)) {
      _packetVersionCounts[rawVersion] = (_packetVersionCounts[rawVersion] ?? 0) + 1;

      if (_lastLoggedPacketVersion != rawVersion) {
        _logEvent('packet_version', 'version=$rawVersion', rxUtc: rxUtc, rxMonoMs: rxMonoMs);
        _lastLoggedPacketVersion = rawVersion;
      }

      _trackFirmwareUpdateRecommendation(rawVersion, rxUtc, rxMonoMs);
    }

    if (data != null && _hasV3Layout(data.packetVersion)) {
      _trackCanHealthEvent(data, rxUtc, rxMonoMs);
      _trackDidUnansweredEvent(data, rxUtc, rxMonoMs);
    }

    notifyListeners();
  }

  void _trackFirmwareUpdateRecommendation(int rawVersion, DateTime rxUtc, int rxMonoMs) {
    if (_firmwareRecommendationLogged || _firmwareCheckPacketsSeen >= _firmwareCheckPacketWindow) return;

    _firmwareCheckPacketsSeen++;
    if (rawVersion == TelemetryVersion.v2) _firmwareCheckV2PacketsSeen++;

    if (_firmwareCheckPacketsSeen == _firmwareCheckPacketWindow) {
      final mtu = _currentMtu;
      final mtuKnownTooSmall = mtu != null && mtu < _mtuTooSmallForV3;
      if (_firmwareCheckV2PacketsSeen == _firmwareCheckPacketWindow && !mtuKnownTooSmall) {
        _logEvent('firmware_update_recommended', 'only v2 packets received', rxUtc: rxUtc, rxMonoMs: rxMonoMs);
        _firmwareRecommendationLogged = true;
      }
    }
  }

  void _trackCanHealthEvent(TelemetryData data, DateTime rxUtc, int rxMonoMs) {
    final changed = _lastCanBusState != data.canBusState ||
        _lastCanFlags != data.canFlags ||
        _lastCanBusOffCount != data.canBusOffCount;
    if (changed) {
      _logEvent(
        'can_health',
        'state=${data.canBusState?.name};tec=${data.canTxErrorCount};rec=${data.canRxErrorCount};'
            'bus_off=${data.canBusOffCount};flags=${data.canFlags}',
        rxUtc: rxUtc,
        rxMonoMs: rxMonoMs,
      );
      _lastCanBusState = data.canBusState;
      _lastCanFlags = data.canFlags;
      _lastCanBusOffCount = data.canBusOffCount;
    }
  }

  void _trackDidUnansweredEvent(TelemetryData data, DateTime rxUtc, int rxMonoMs) {
    final current = data.unansweredDidCount;
    final prev = _lastUnansweredDidCount;
    if (current != null && prev != null && current > prev) {
      _logEvent('did_unanswered', 'count=$current;delta=${current - prev}', rxUtc: rxUtc, rxMonoMs: rxMonoMs);
    }
    if (current != null) _lastUnansweredDidCount = current;
  }

  /// Feeds one raw IMU block notification payload into the recorder. No-op
  /// if not currently recording. A block that fails to decode is counted as
  /// a decode error (`decode_error` with an `imu:`-prefixed detail) and
  /// otherwise dropped, since there is no well-formed row to write for it.
  ///
  /// `imu.csv` is created lazily, on the first block that decodes
  /// successfully -- sessions with no IMU (old firmware, or the
  /// characteristic never notified) simply never get one.
  void handleRawImuBlock(Uint8List bytes) {
    if (!isRecording) return;

    final rxUtc = DateTime.now().toUtc();
    final rxMonoMs = _stopwatch.elapsedMilliseconds;

    ImuBlock block;
    try {
      block = ImuBlock.decode(bytes);
    } catch (e) {
      _decodeErrorCount++;
      _logEvent('decode_error', 'imu: $e', rxUtc: rxUtc, rxMonoMs: rxMonoMs);
      notifyListeners();
      return;
    }

    final missing = _imuGapTracker.missingSamplesFor(block);
    _imuBlockCount++;
    _imuSampleCount += block.sampleCount;
    _imuMissingSamples += missing;

    _ensureImuSinkOpen();
    for (var i = 0; i < block.samples.length; i++) {
      final sample = block.samples[i];
      _imuSink?.writeln(_csvRow([
        rxUtc.toIso8601String(),
        rxMonoMs.toString(),
        block.seq.toString(),
        block.flags.toString(),
        (i == 0 ? missing : 0).toString(),
        sample.sampleIndex.toString(),
        sample.deviceTimeMs.toString(),
        sample.axRaw.toString(),
        sample.ayRaw.toString(),
        sample.azRaw.toString(),
        sample.gxRaw.toString(),
        sample.gyRaw.toString(),
        sample.gzRaw.toString(),
        sample.axG.toString(),
        sample.ayG.toString(),
        sample.azG.toString(),
        sample.gxDps.toString(),
        sample.gyDps.toString(),
        sample.gzDps.toString(),
      ]));
    }

    if (missing > 0) {
      _logEvent('imu_gap', 'missing=$missing;sample_index=${block.firstSampleIndex}', rxUtc: rxUtc, rxMonoMs: rxMonoMs);
    }

    notifyListeners();
  }

  void _ensureImuSinkOpen() {
    if (_imuFileCreated) return;
    final dir = _sessionDir;
    if (dir == null) return;
    _imuSink = File('${dir.path}/imu.csv').openWrite();
    _imuSink!.writeln(_csvRow(imuCsvHeader));
    _imuFileCreated = true;
  }

  /// Feeds a negotiated-MTU change into the recorder. No-op if not currently
  /// recording. Also used by the `firmware_update_recommended` heuristic.
  void handleMtuNegotiated(int mtu) {
    if (!isRecording) return;
    _currentMtu = mtu;
    _logEvent('mtu_negotiated', 'mtu=$mtu');
    notifyListeners();
  }

  /// Feeds a BLE connection-state change into the recorder. No-op if not
  /// currently recording.
  void handleConnectionChange(bool connected) {
    if (!isRecording) return;

    if (connected) {
      if (_lastConnState == null) {
        _logEvent('ble_connected', '');
      } else if (_lastConnState == false) {
        _logEvent('ble_reconnected', '');
      }
    } else {
      if (_lastConnState != false) {
        _disconnectCount++;
        _logEvent('ble_disconnected', '');
      }
    }
    _lastConnState = connected;
    notifyListeners();
  }

  /// Stops the recording, flushes and closes the CSV files, and writes
  /// `summary.json`.
  Future<SessionSummary> stop() async {
    if (!isRecording) {
      throw StateError('No recording in progress.');
    }

    _logEvent('recording_stopped', 'packet_count=$_packetCount lost_count=$_lostCount');

    _flushTimer?.cancel();
    _flushTimer = null;
    _stopwatch.stop();

    await _flush();
    await _telemetrySink?.close();
    await _eventsSink?.close();
    await _imuSink?.close();
    _telemetrySink = null;
    _eventsSink = null;
    _imuSink = null;

    final summary = SessionSummary(
      duration: _stopwatch.elapsed,
      packetCount: _packetCount,
      lostCount: _lostCount,
      lossPercent: lossPercent,
      decodeErrorCount: _decodeErrorCount,
      disconnectCount: _disconnectCount,
      firstPacketUtc: _firstPacketUtc?.toIso8601String(),
      lastPacketUtc: _lastPacketUtc?.toIso8601String(),
      packetVersions: Map.unmodifiable(_packetVersionCounts),
      imuBlockCount: _imuBlockCount,
      imuSampleCount: _imuSampleCount,
      imuMissingSamples: _imuMissingSamples,
      imuLossPercent: imuLossPercent,
      mtu: _currentMtu,
    );

    final dir = _sessionDir;
    if (dir != null) {
      await File('${dir.path}/summary.json').writeAsString(_prettyJson(summary.toJson()));
    }

    _state = SessionRecorderState.idle;
    notifyListeners();
    return summary;
  }

  Future<void> _flush() async {
    try {
      await _telemetrySink?.flush();
      await _eventsSink?.flush();
      await _imuSink?.flush();
    } catch (e) {
      debugPrint('SessionRecorder flush error: $e');
    }
  }

  void _logEvent(String event, String detail, {DateTime? rxUtc, int? rxMonoMs}) {
    final utc = rxUtc ?? DateTime.now().toUtc();
    final mono = rxMonoMs ?? _stopwatch.elapsedMilliseconds;
    _eventsSink?.writeln(_csvRow([
      utc.toIso8601String(),
      mono.toString(),
      event,
      detail,
    ]));
  }

  void _writeTelemetryRow({
    required DateTime rxUtc,
    required int rxMonoMs,
    required int? seq,
    required int? lostSincePrev,
    required String rawHex,
    required TelemetryData? data,
    required String? decodeError,
  }) {
    final hasV3Columns = data != null && _hasV3Layout(data.packetVersion);

    _telemetrySink?.writeln(_csvRow([
      rxUtc.toIso8601String(),
      rxMonoMs.toString(),
      seq?.toString() ?? '',
      lostSincePrev?.toString() ?? '',
      rawHex,
      data?.rpm.toString() ?? '',
      data?.speed.toString() ?? '',
      data?.coolantTemp.toString() ?? '',
      data?.throttlePos.toString() ?? '',
      data?.batteryVolt.toString() ?? '',
      data?.leanAngle?.toString() ?? '',
      data?.maxLeanRight?.toString() ?? '',
      data?.maxLeanLeft?.toString() ?? '',
      data == null ? '' : (data.rpmValid ? '1' : '0'),
      data == null ? '' : (data.speedValid ? '1' : '0'),
      data == null ? '' : (data.coolantTempValid ? '1' : '0'),
      data == null ? '' : (data.throttlePosValid ? '1' : '0'),
      data == null ? '' : (data.batteryVoltValid ? '1' : '0'),
      data == null ? '' : (data.leanValid ? '1' : '0'),
      data == null ? '' : (data.ecuPresent ? '1' : '0'),
      decodeError ?? '',
      // Version-3-and-later columns (contract §telemetry.csv): blank unless
      // this row decoded as a version 3 or version 4 packet.
      data?.packetVersion.toString() ?? '',
      hasV3Columns ? (data.deviceTimeMs?.toString() ?? '') : '',
      hasV3Columns ? (data.rpmAgeMs?.toString() ?? '') : '',
      hasV3Columns ? (data.speedAgeMs?.toString() ?? '') : '',
      hasV3Columns ? (data.coolantTempAgeMs?.toString() ?? '') : '',
      hasV3Columns ? (data.throttlePosAgeMs?.toString() ?? '') : '',
      hasV3Columns ? (data.batteryVoltAgeMs?.toString() ?? '') : '',
      hasV3Columns ? (data.imuActive ? '1' : '0') : '',
      hasV3Columns ? (data.canBusState?.value.toString() ?? '') : '',
      hasV3Columns ? (data.canTxErrorCount?.toString() ?? '') : '',
      hasV3Columns ? (data.canRxErrorCount?.toString() ?? '') : '',
      hasV3Columns ? (data.canBusOffCount?.toString() ?? '') : '',
      hasV3Columns ? (data.unansweredDidCount?.toString() ?? '') : '',
      hasV3Columns ? (data.canFlags?.toString() ?? '') : '',
      // Version-4-only columns (D-058 tester stats): the fields are null on
      // version 2/3 and when decoding failed, so no guard is needed.
      data?.stepGapMaxMs?.toString() ?? '',
      data?.stepGapOverCount?.toString() ?? '',
      data?.rttDid?.toString() ?? '',
      data?.rttMinMs?.toString() ?? '',
      data?.rttMaxMs?.toString() ?? '',
      data?.rttSumMs?.toString() ?? '',
      data?.rttCount?.toString() ?? '',
      data?.rttNrc78Count?.toString() ?? '',
    ]));
  }
}

String _generateSessionId(DateTime utc) {
  final datePart = '${utc.year.toString().padLeft(4, '0')}'
      '${utc.month.toString().padLeft(2, '0')}'
      '${utc.day.toString().padLeft(2, '0')}';
  final timePart = '${utc.hour.toString().padLeft(2, '0')}'
      '${utc.minute.toString().padLeft(2, '0')}'
      '${utc.second.toString().padLeft(2, '0')}';
  final rand = Random.secure();
  final hex = List.generate(2, (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  return '$datePart-$timePart-$hex';
}

String _bytesToHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

String _csvField(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String _csvRow(List<String> fields) => fields.map(_csvField).join(',');

String _prettyJson(Map<String, dynamic> json) => const JsonEncoder.withIndent('  ').convert(json);
