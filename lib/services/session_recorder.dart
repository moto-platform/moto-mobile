import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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

/// Summary written to `summary.json` when a recording stops.
class SessionSummary {
  final Duration duration;
  final int packetCount;
  final int lostCount;
  final double lossPercent;
  final int decodeErrorCount;
  final int disconnectCount;
  final String? firstPacketUtc;
  final String? lastPacketUtc;

  const SessionSummary({
    required this.duration,
    required this.packetCount,
    required this.lostCount,
    required this.lossPercent,
    required this.decodeErrorCount,
    required this.disconnectCount,
    required this.firstPacketUtc,
    required this.lastPacketUtc,
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
      );
}

enum SessionRecorderState { idle, recording }

/// Records raw BLE telemetry notifications to a per-session directory as
/// `meta.json`, `telemetry.csv` and `events.csv`, and writes a `summary.json`
/// on stop.
///
/// Field decoding is delegated entirely to [TelemetryData.fromBinaryBuffer]
/// -- the single source of truth for the v2 BLE packet schema. This class
/// only adds timing, sequence-loss bookkeeping and CSV/JSON formatting
/// around it; it never re-implements offset/scale logic.
///
/// This class has no dependency on `BleService`: the caller (a UI widget)
/// feeds it raw packets and connection-state changes via [handleRawPacket]
/// and [handleConnectionChange]. That keeps it trivially unit-testable with
/// synthetic packets and a temp directory, with no BLE stack involved.
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
  ];

  static const List<String> eventsCsvHeader = [
    'rx_utc_iso',
    'rx_mono_ms',
    'event',
    'detail',
  ];

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

  int get packetCount => _packetCount;
  int get lostCount => _lostCount;
  int get decodeErrorCount => _decodeErrorCount;
  int get disconnectCount => _disconnectCount;
  DateTime? get lastPacketUtc => _lastPacketUtc;
  bool? get isBleConnected => _lastConnState;
  Duration get elapsed => _stopwatch.elapsed;

  double get lossPercent {
    final total = _packetCount + _lostCount;
    if (total <= 0) return 0.0;
    return (_lostCount / total) * 100.0;
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

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 1), (_) => _flush());

    notifyListeners();
    return finalMeta;
  }

  /// Feeds one raw BLE notification payload into the recorder. No-op if not
  /// currently recording. Packets that fail to decode (bad version or too
  /// short) are still written, with `decode_error` set and the decoded
  /// fields left blank -- nothing is ever silently dropped.
  void handleRawPacket(Uint8List bytes) {
    if (!isRecording) return;

    final rxUtc = DateTime.now().toUtc();
    final rxMonoMs = _stopwatch.elapsedMilliseconds;
    final rawHex = _bytesToHex(bytes);

    final seq = bytes.length > BlePacketFieldOffsets.seq ? bytes[BlePacketFieldOffsets.seq] : null;
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
    if (bytes.length < blePacketSizeBytes) {
      decodeError = 'short packet: ${bytes.length} bytes (expected $blePacketSizeBytes)';
    } else {
      final version = bytes[BlePacketFieldOffsets.version];
      if (version != blePacketExpectedVersion) {
        decodeError = 'version mismatch: got $version (expected $blePacketExpectedVersion)';
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
    _telemetrySink = null;
    _eventsSink = null;

    final summary = SessionSummary(
      duration: _stopwatch.elapsed,
      packetCount: _packetCount,
      lostCount: _lostCount,
      lossPercent: lossPercent,
      decodeErrorCount: _decodeErrorCount,
      disconnectCount: _disconnectCount,
      firstPacketUtc: _firstPacketUtc?.toIso8601String(),
      lastPacketUtc: _lastPacketUtc?.toIso8601String(),
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
