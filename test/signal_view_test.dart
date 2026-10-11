import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/gps_block.dart';
import 'package:moto_mobile/models/telemetry_data.dart';
import 'package:moto_mobile/ui/telemetry/link_status.dart';
import 'package:moto_mobile/ui/telemetry/signal_view.dart';

/// A packet with every polled signal valid (version 4 unless overridden).
TelemetryData packet({
  int version = TelemetryVersion.v4,
  bool rpmValid = true,
  bool speedValid = true,
  bool coolantValid = true,
  bool throttleValid = true,
  bool batteryValid = true,
  int? rpmAge = 40,
  int? speedAge = 30,
  int? coolantAge = 300,
  int? throttleAge = 80,
  int? batteryAge = 500,
}) {
  final withAges = version >= TelemetryVersion.v3;
  return TelemetryData(
    packetVersion: version,
    rpm: 3500,
    speed: 62,
    coolantTemp: 88,
    throttlePos: 17,
    batteryVolt: 13.8,
    leanAngle: null,
    maxLeanRight: null,
    maxLeanLeft: null,
    rpmValid: rpmValid,
    speedValid: speedValid,
    coolantTempValid: coolantValid,
    throttlePosValid: throttleValid,
    batteryVoltValid: batteryValid,
    leanValid: false,
    ecuPresent: true,
    rpmAgeMs: withAges ? rpmAge : null,
    speedAgeMs: withAges ? speedAge : null,
    coolantTempAgeMs: withAges ? coolantAge : null,
    throttlePosAgeMs: withAges ? throttleAge : null,
    batteryVoltAgeMs: withAges ? batteryAge : null,
  );
}

SignalView view(SignalSnapshot s, String name) => s.byName(name)!;

void main() {
  group('catalog coverage', () {
    test('every catalog entry is represented exactly once, in catalog order', () {
      final s = SignalSnapshot.from(packet(), connected: true);
      expect(s.signals.map((v) => v.signal.name).toList(),
          vehicleSignalCatalog.map((e) => e.name).toList());
    });

    test('catalog labels are unique (the Signals screen is keyed by label)', () {
      final labels = vehicleSignalCatalog.map((e) => e.label).toList();
      expect(labels.toSet().length, labels.length);
    });

    test('every polled catalog signal has a packet binding', () {
      final polled = vehicleSignalCatalog.where((e) => e.isPolled).map((e) => e.name).toSet();
      expect(boundSignalNames, polled);
    });

    test('groups follow vehicleSignalGroups order and contain every signal', () {
      final s = SignalSnapshot.from(packet(), connected: true);
      final groups = s.groups;
      final order = groups.map((g) => g.group).toList();
      final expected = vehicleSignalGroups.where((g) => vehicleSignalCatalog.any((e) => e.group == g)).toList();
      expect(order, expected);
      expect(groups.expand((g) => g.signals).length, vehicleSignalCatalog.length);
    });

    test('summary counts match the catalog', () {
      final s = SignalSnapshot.from(packet(), connected: true);
      expect(s.polledCount, vehicleSignalCatalog.where((e) => e.isPolled).length);
      expect(s.candidateCount, vehicleSignalCatalog.where((e) => !e.isPolled).length);
      expect(s.polledCount + s.candidateCount, vehicleSignalCatalog.length);
      expect(s.liveCount, s.polledCount);
    });
  });

  group('states', () {
    test('valid polled signals are live with formatted values', () {
      final s = SignalSnapshot.from(packet(), connected: true);
      final speed = view(s, VehicleSignalNames.vehicleSpeed);
      expect(speed.state, SignalState.live);
      expect(speed.valueText, '62');
      expect(speed.ageMs, 30);
      expect(view(s, VehicleSignalNames.engineSpeed).valueText, '3500');
      expect(view(s, VehicleSignalNames.throttlePos).valueText, '17');
      expect(view(s, VehicleSignalNames.coolantTemp).valueText, '88');
      expect(view(s, VehicleSignalNames.batteryVoltage).valueText, '13.8');
    });

    test('not valid but received before (age present) is stale', () {
      final s = SignalSnapshot.from(packet(coolantValid: false, coolantAge: 5000), connected: true);
      final v = view(s, VehicleSignalNames.coolantTemp);
      expect(v.state, SignalState.stale);
      expect(v.valueText, noValueText);
      expect(v.value, isNull);
      expect(v.ageMs, 5000);
    });

    test('not valid and never received (age sentinel -> null) is no data', () {
      final s = SignalSnapshot.from(packet(batteryValid: false, batteryAge: null), connected: true);
      expect(view(s, VehicleSignalNames.batteryVoltage).state, SignalState.noData);
    });

    test('version 2 packet carries no ages: invalid maps to no data, valid stays live', () {
      final s = SignalSnapshot.from(packet(version: TelemetryVersion.v2, rpmValid: false), connected: true);
      expect(view(s, VehicleSignalNames.engineSpeed).state, SignalState.noData);
      final speed = view(s, VehicleSignalNames.vehicleSpeed);
      expect(speed.state, SignalState.live);
      expect(speed.ageMs, isNull);
    });

    test('not connected: every polled signal is no data even with a packet', () {
      final s = SignalSnapshot.from(packet(), connected: false);
      for (final v in s.signals.where((v) => v.signal.isPolled)) {
        expect(v.state, SignalState.noData, reason: v.signal.name);
      }
      expect(s.liveCount, 0);
    });

    test('connected but nothing received yet is no data', () {
      final s = SignalSnapshot.from(TelemetryData.initial(), connected: true);
      for (final v in s.signals.where((v) => v.signal.isPolled)) {
        expect(v.state, SignalState.noData);
      }
    });

    test('a quiet link turns live values stale', () {
      final s = SignalSnapshot.from(
        packet(),
        connected: true,
        sinceLastPacket: linkStaleAfter + const Duration(milliseconds: 1),
      );
      for (final v in s.signals.where((v) => v.signal.isPolled)) {
        expect(v.state, SignalState.stale, reason: v.signal.name);
        expect(v.valueText, noValueText);
      }
      // A fresh packet keeps them live.
      final fresh = SignalSnapshot.from(packet(), connected: true, sinceLastPacket: const Duration(milliseconds: 150));
      expect(fresh.liveCount, fresh.polledCount);
    });

    test('candidates are never live and never carry a value, in any packet state', () {
      final cases = <SignalSnapshot>[
        SignalSnapshot.from(packet(), connected: true),
        SignalSnapshot.from(packet(), connected: false),
        SignalSnapshot.from(packet(version: TelemetryVersion.v2), connected: true),
        SignalSnapshot.from(TelemetryData.initial(), connected: true),
        SignalSnapshot.empty(),
      ];
      for (final s in cases) {
        final candidates = s.signals.where((v) => !v.signal.isPolled);
        expect(candidates, isNotEmpty);
        for (final v in candidates) {
          expect(v.state, SignalState.notPolled, reason: v.signal.name);
          expect(v.isLive, isFalse);
          expect(v.value, isNull);
          expect(v.valueText, noValueText);
          expect(v.ageMs, isNull);
        }
      }
    });
  });

  group('formatting', () {
    test('units come from the catalog, degree units are rendered', () {
      final s = SignalSnapshot.from(packet(), connected: true);
      expect(view(s, VehicleSignalNames.vehicleSpeed).unitText, 'km/h');
      expect(view(s, VehicleSignalNames.coolantTemp).unitText, '°C');
      expect(view(s, VehicleSignalNames.timingAdvance).unitText, '°');
      expect(view(s, VehicleSignalNames.batteryVoltage).unitText, 'V');
    });

    test('fraction maps the value into the catalog range', () {
      final s = SignalSnapshot.from(packet(), connected: true);
      expect(view(s, VehicleSignalNames.throttlePos).fraction, closeTo(0.17, 1e-9));
      expect(view(s, VehicleSignalNames.engineLoad).fraction, isNull);
    });

    test('didHex pads to four digits', () {
      expect(didHex(0xF40C), '0xF40C');
      expect(didHex(0x5), '0x0005');
    });

    test('formatAge switches to seconds from 1 s', () {
      expect(formatAge(null), '--');
      expect(formatAge(120), '120 ms');
      expect(formatAge(2400), '2.4 s');
    });
  });

  group('link status text', () {
    test('CAN bus state', () {
      expect(canStateStatus(null).tone, Tone.neutral);
      expect(canStateStatus(CanBusState.running).tone, Tone.ok);
      expect(canStateStatus(CanBusState.errorWarning).tone, Tone.warn);
      expect(canStateStatus(CanBusState.busOff).tone, Tone.error);
    });

    test('GPS status follows the subscription state and fix', () {
      expect(gpsStatus(GpsLinkStatus.disconnected, null).tone, Tone.neutral);
      expect(gpsStatus(const GpsLinkStatus(GpsLinkState.notOffered), null).tone, Tone.neutral);
      expect(gpsStatus(const GpsLinkStatus(GpsLinkState.subscribing), null).tone, Tone.warn);
      expect(gpsStatus(const GpsLinkStatus(GpsLinkState.failed, reason: 'x'), null).tone, Tone.warn);
      final waiting = gpsStatus(const GpsLinkStatus(GpsLinkState.subscribed), null);
      expect(waiting.tone, Tone.warn);
    });
  });
}
