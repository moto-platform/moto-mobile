import 'package:moto_defs/moto_defs.dart';

import '../../models/telemetry_data.dart';
import '../../models/vehicle_signal_block.dart';
import 'link_status.dart';

// Signal view-model layer. Pure Dart (no Flutter imports) so it is unit
// tested without a widget tree.
//
// The signal list, labels, units, groups, poll periods and statuses all come
// from the generated catalog (`vehicleSignalCatalog`, D-066). The only
// hand-maintained piece is the binding of the five *polled* catalog signals
// to the fields of the BLE telemetry packet ([TelemetryData]), keyed by the
// generated [VehicleSignalNames] constants. Every other catalog entry is a
// candidate: not polled, so without a record it never carries a value.
//
// The vehicle-signal block (D-066 item 4) adds a second, generic source: the
// latest record per DID, with the phone time it arrived at. A catalog signal
// with a record is LIVE / STALE / SKIPPED / NRC from that record, whether it
// is polled or a candidate (so a candidate promoted in the firmware turns LIVE
// with no code change). For the five telemetry-v4 signals the v4 packet
// (100 ms) stays the primary source and wins while it says LIVE.

/// Display state of one catalog signal.
enum SignalState {
  /// Polled and the packet says the value is valid and fresh.
  live,

  /// Polled and received before, but not valid now (or the link went quiet).
  stale,

  /// Polled, but nothing usable was received (not connected, nothing yet, or
  /// a version 2 packet that carries no per-signal ages).
  noData,

  /// Catalog candidate: not in the tester's poll table and no vehicle-signal
  /// record for it, so it has no value.
  notPolled,

  /// The sender skips this DID after repeated timeouts (vehicle-signal record
  /// state skipped).
  skipped,

  /// The DID's last answer was a negative response (vehicle-signal record
  /// state negativeResponse); [SignalView.nrc] holds the code.
  negativeResponse,
}

/// A polled signal reads its value, validity bit and age from the packet.
class _Binding {
  const _Binding({
    required this.value,
    required this.valid,
    required this.ageMs,
    required this.decimals,
  });

  final double Function(TelemetryData) value;
  final bool Function(TelemetryData) valid;
  final int? Function(TelemetryData) ageMs;

  /// Fraction digits shown. This is the display precision of the value as the
  /// node transmits it (e.g. rpm and throttle arrive as whole numbers), not a
  /// signal fact.
  final int decimals;
}

final Map<String, _Binding> _bindings = <String, _Binding>{
  VehicleSignalNames.engineSpeed: _Binding(
    value: (d) => d.rpm,
    valid: (d) => d.rpmValid,
    ageMs: (d) => d.rpmAgeMs,
    decimals: 0,
  ),
  VehicleSignalNames.vehicleSpeed: _Binding(
    value: (d) => d.speed.toDouble(),
    valid: (d) => d.speedValid,
    ageMs: (d) => d.speedAgeMs,
    decimals: 0,
  ),
  VehicleSignalNames.throttlePos: _Binding(
    value: (d) => d.throttlePos,
    valid: (d) => d.throttlePosValid,
    ageMs: (d) => d.throttlePosAgeMs,
    decimals: 0,
  ),
  VehicleSignalNames.coolantTemp: _Binding(
    value: (d) => d.coolantTemp.toDouble(),
    valid: (d) => d.coolantTempValid,
    ageMs: (d) => d.coolantTempAgeMs,
    decimals: 0,
  ),
  VehicleSignalNames.batteryVoltage: _Binding(
    value: (d) => d.batteryVolt,
    valid: (d) => d.batteryVoltValid,
    ageMs: (d) => d.batteryVoltAgeMs,
    decimals: 1,
  ),
};

/// Catalog names that have a packet binding (the polled signals).
Set<String> get boundSignalNames => Set<String>.unmodifiable(_bindings.keys);

/// Placeholder shown where a value is not available.
const String noValueText = '--';

/// If the newest packet is older than this while connected, live values are
/// shown as stale (the link went quiet without a disconnect event).
const Duration linkStaleAfter = Duration(milliseconds: 2000);

/// A vehicle-signal record is LIVE only if its state is valid and the phone
/// received it at most this long ago; an older record is shown as stale.
const Duration vehicleSignalLiveWithin = Duration(milliseconds: 2000);

/// Unit text for display. The catalog stores ASCII units (`degC`); this only
/// renders them (the degree sign), it does not define units.
String displayUnit(String unit) => switch (unit) {
      'degC' => '°C',
      'deg' => '°',
      _ => unit,
    };

/// Fraction digits for a value decoded from a vehicle-signal record: the
/// fewest (0..3) that show the catalog step `factorNum / factorDen` exactly,
/// else 1 (e.g. 100/255 percent).
int vehicleSignalDecimals(VehicleSignal signal) {
  final step = signal.factorNum / signal.factorDen;
  var scale = 1.0;
  for (var d = 0; d <= 3; d++) {
    final scaled = step * scale;
    if ((scaled - scaled.roundToDouble()).abs() < 1e-9) return d;
    scale *= 10;
  }
  return 1;
}

/// `ENGINE`-style group id -> `Engine` for headers.
String groupTitle(String group) =>
    group.isEmpty ? group : group[0].toUpperCase() + group.substring(1);

/// One catalog signal as the UI shows it.
class SignalView {
  const SignalView({
    required this.signal,
    required this.valueText,
    required this.value,
    required this.state,
    required this.ageMs,
    this.nrc,
  });

  final VehicleSignal signal;

  /// Formatted value, or [noValueText] unless [state] is [SignalState.live].
  final String valueText;

  /// Numeric value, only for live signals.
  final double? value;
  final SignalState state;

  /// Age of the value in ms as reported by the node (version 3 and 4 packets,
  /// or a vehicle-signal record plus the time since the phone received it).
  final int? ageMs;

  /// The negative response code, only for [SignalState.negativeResponse].
  final int? nrc;

  String get label => signal.label;
  String get unitText => displayUnit(signal.unit);
  bool get isLive => state == SignalState.live;

  /// `0xF40C`-style DID of the signal.
  String get didText => didHex(signal.did);

  /// Position of the value within the catalog range, 0..1, for bar displays.
  double? get fraction {
    final v = value;
    if (v == null) return null;
    final span = signal.max - signal.min;
    if (span <= 0) return null;
    return ((v - signal.min) / span).clamp(0.0, 1.0);
  }
}

/// All signals of one catalog group, in catalog order.
class SignalGroupView {
  const SignalGroupView({required this.group, required this.signals});

  final String group;
  final List<SignalView> signals;

  String get title => groupTitle(group);
  int get liveCount => signals.where((s) => s.isLive).length;
}

/// The whole catalog rendered against one telemetry packet.
class SignalSnapshot {
  const SignalSnapshot._(this.signals);

  /// One entry per catalog signal, in catalog order.
  final List<SignalView> signals;

  /// Builds the snapshot.
  ///
  /// * [connected]: BLE link state; not connected means no polled signal has
  ///   data.
  /// * [sinceLastPacket]: time since the newest valid packet arrived; when it
  ///   exceeds [linkStaleAfter], values that were live become stale.
  /// * [records]: the latest vehicle-signal record per DID with the phone time
  ///   it arrived at (ignored while not [connected]); see [_fromRecord].
  /// * [now]: the current time, to age the records (defaults to the wall clock).
  factory SignalSnapshot.from(
    TelemetryData data, {
    required bool connected,
    Duration? sinceLastPacket,
    Map<int, ReceivedVehicleSignal> records = const {},
    DateTime? now,
  }) {
    final hasPacket = data.packetVersion != 0;
    final linkQuiet = sinceLastPacket != null && sinceLastPacket > linkStaleAfter;
    final hasAges = data.packetVersion >= TelemetryVersion.v3;
    final at = now ?? DateTime.now();

    SignalView fromPacket(VehicleSignal signal) {
      if (!signal.isPolled) {
        return SignalView(
          signal: signal,
          valueText: noValueText,
          value: null,
          state: SignalState.notPolled,
          ageMs: null,
        );
      }
      final binding = _bindings[signal.name];
      if (binding == null || !connected || !hasPacket) {
        return SignalView(
          signal: signal,
          valueText: noValueText,
          value: null,
          state: SignalState.noData,
          ageMs: null,
        );
      }
      final age = hasAges ? binding.ageMs(data) : null;
      if (binding.valid(data)) {
        if (linkQuiet) {
          return SignalView(
            signal: signal,
            valueText: noValueText,
            value: null,
            state: SignalState.stale,
            ageMs: age,
          );
        }
        final v = binding.value(data);
        return SignalView(
          signal: signal,
          valueText: v.toStringAsFixed(binding.decimals),
          value: v,
          state: SignalState.live,
          ageMs: age,
        );
      }
      // Not valid. Version 3/4 packets say whether the signal was ever
      // received (age present); version 2 cannot tell, so it is "no data".
      return SignalView(
        signal: signal,
        valueText: noValueText,
        value: null,
        state: age != null ? SignalState.stale : SignalState.noData,
        ageMs: age,
      );
    }

    SignalView build(VehicleSignal signal) {
      final fromV4 = fromPacket(signal);
      // The v4 packet is the faster source for its five signals: while it
      // says LIVE it wins.
      if (fromV4.isLive) return fromV4;
      final received = connected ? records[signal.did] : null;
      if (received == null) return fromV4;
      return _fromRecord(signal, received, at) ?? fromV4;
    }

    return SignalSnapshot._(List<SignalView>.unmodifiable(vehicleSignalCatalog.map(build)));
  }

  /// One catalog signal from its latest vehicle-signal record, or `null` when
  /// the record says nothing (state neverReceived on a polled signal: the
  /// packet-derived view stands).
  ///
  /// LIVE: state valid, a decodable value (raw fits the DID length) and the
  /// phone received the record at most [vehicleSignalLiveWithin] ago. STALE:
  /// state stale, or a valid record older than that. A valid record whose raw
  /// does not fit the DID length is malformed: NO DATA.
  static SignalView? _fromRecord(VehicleSignal signal, ReceivedVehicleSignal received, DateTime now) {
    final record = received.record;
    final since = now.difference(received.receivedAt);
    final wireAge = record.knownAgeMs;
    final age = wireAge == null ? null : wireAge + since.inMilliseconds;

    SignalView view(SignalState state, {double? value, int? nrc}) => SignalView(
          signal: signal,
          valueText: value == null ? noValueText : value.toStringAsFixed(vehicleSignalDecimals(signal)),
          value: value,
          state: state,
          ageMs: age,
          nrc: nrc,
        );

    switch (record.state) {
      case BleVehicleSignalState.valid:
        final value = record.value;
        if (value == null) return view(SignalState.noData);
        if (since > vehicleSignalLiveWithin) return view(SignalState.stale);
        return view(SignalState.live, value: value);
      case BleVehicleSignalState.stale:
        return view(SignalState.stale);
      case BleVehicleSignalState.skipped:
        return view(SignalState.skipped);
      case BleVehicleSignalState.negativeResponse:
        return view(SignalState.negativeResponse, nrc: record.nrc);
      case BleVehicleSignalState.neverReceived:
        // The node has this DID in its table but no answer yet. A polled
        // signal keeps its packet-derived view; a candidate the node polls
        // anyway is "no data" rather than "not polled".
        return signal.isPolled ? null : view(SignalState.noData);
      default:
        return null;
    }
  }

  /// Snapshot with no connection and no data.
  factory SignalSnapshot.empty() => SignalSnapshot.from(TelemetryData.initial(), connected: false);

  SignalView? byName(String name) {
    for (final s in signals) {
      if (s.signal.name == name) return s;
    }
    return null;
  }

  int get liveCount => signals.where((s) => s.state == SignalState.live).length;
  int get polledCount => signals.where((s) => s.signal.isPolled).length;
  int get candidateCount => signals.where((s) => !s.signal.isPolled).length;

  /// Signals grouped in [vehicleSignalGroups] order. Groups with no signal
  /// are skipped; a signal whose group is missing from the list is appended
  /// in a trailing group so no catalog entry is ever dropped.
  List<SignalGroupView> get groups {
    final result = <SignalGroupView>[];
    final seen = <String>{};
    for (final g in vehicleSignalGroups) {
      final members = signals.where((s) => s.signal.group == g).toList(growable: false);
      seen.add(g);
      if (members.isNotEmpty) result.add(SignalGroupView(group: g, signals: members));
    }
    final extras = <String, List<SignalView>>{};
    for (final s in signals) {
      if (!seen.contains(s.signal.group)) {
        extras.putIfAbsent(s.signal.group, () => <SignalView>[]).add(s);
      }
    }
    extras.forEach((g, members) => result.add(SignalGroupView(group: g, signals: members)));
    return result;
  }
}
