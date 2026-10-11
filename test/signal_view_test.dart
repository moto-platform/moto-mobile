import 'package:flutter_test/flutter_test.dart';
import 'package:moto_defs/moto_defs.dart';
import 'package:moto_mobile/models/gps_block.dart';
import 'package:moto_mobile/models/telemetry_data.dart';
import 'package:moto_mobile/models/vehicle_signal_block.dart';
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

final DateTime t0 = DateTime.utc(2026, 10, 11, 12);

/// The latest record of [did] received [ago] before [t0].
ReceivedVehicleSignal received(
  int did,
  int state, {
  int raw = 0,
  int wireAge = 0,
  Duration ago = Duration.zero,
}) =>
    ReceivedVehicleSignal(
      VehicleSignalRecord(did: did, state: state, ageMs: wireAge, raw: raw),
      t0.subtract(ago),
    );

/// A snapshot at [t0] with the v4 [packet] (or none) and the given records.
SignalSnapshot snapshotWith(
  List<ReceivedVehicleSignal> records, {
  TelemetryData? data,
  bool connected = true,
}) =>
    SignalSnapshot.from(
      data ?? TelemetryData.initial(),
      connected: connected,
      records: {for (final r in records) r.record.did: r},
      now: t0,
    );

VehicleSignal firstCandidate() => vehicleSignalCatalog.firstWhere((s) => !s.isPolled);

VehicleSignal byNameCatalog(String name) => vehicleSignalCatalog.firstWhere((s) => s.name == name);

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

  group('vehicle-signal records', () {
    final candidate = firstCandidate();

    test('a candidate that arrives valid and fresh is LIVE with its decoded value', () {
      final raw = candidate.length == 1 ? 100 : 1000;
      final v = view(
        snapshotWith([received(candidate.did, BleVehicleSignalState.valid, raw: raw, wireAge: 150)]),
        candidate.name,
      );
      expect(v.state, SignalState.live);
      expect(v.isLive, isTrue);
      expect(v.value, candidate.physical(raw));
      expect(v.valueText, candidate.physical(raw).toStringAsFixed(vehicleSignalDecimals(candidate)));
      expect(v.unitText, displayUnit(candidate.unit));
      expect(v.ageMs, 150);
      expect(v.nrc, isNull);
    });

    test('LIVE is decided by the phone receive time: 2000 ms is live, 2001 ms is stale', () {
      SignalView at(int ms) => view(
            snapshotWith([
              received(candidate.did, BleVehicleSignalState.valid, raw: 1, ago: Duration(milliseconds: ms)),
            ]),
            candidate.name,
          );
      expect(at(0).state, SignalState.live);
      expect(at(vehicleSignalLiveWithin.inMilliseconds).state, SignalState.live);
      final stale = at(vehicleSignalLiveWithin.inMilliseconds + 1);
      expect(stale.state, SignalState.stale);
      expect(stale.valueText, noValueText);
      expect(stale.value, isNull);
      // The displayed age grows with the time since the phone got the record.
      expect(stale.ageMs, vehicleSignalLiveWithin.inMilliseconds + 1);
    });

    test('state stale is STALE even when just received', () {
      final v = view(
        snapshotWith([received(candidate.did, BleVehicleSignalState.stale, raw: 1, wireAge: 5000)]),
        candidate.name,
      );
      expect(v.state, SignalState.stale);
      expect(v.valueText, noValueText);
      expect(v.ageMs, 5000);
    });

    test('state skipped is SKIPPED', () {
      final v = view(snapshotWith([received(candidate.did, BleVehicleSignalState.skipped)]), candidate.name);
      expect(v.state, SignalState.skipped);
      expect(v.isLive, isFalse);
      expect(v.valueText, noValueText);
    });

    test('state negativeResponse carries the NRC from raw', () {
      final v = view(
        snapshotWith([
          received(candidate.did, BleVehicleSignalState.negativeResponse, raw: 0x31, wireAge: BleTelemetry.ageNeverReceived),
        ]),
        candidate.name,
      );
      expect(v.state, SignalState.negativeResponse);
      expect(v.nrc, 0x31);
      expect(v.ageMs, isNull); // the never-received sentinel is not an age
      expect(v.valueText, noValueText);
    });

    test('state neverReceived: a candidate is NO DATA, a polled signal keeps its packet view', () {
      final c = view(snapshotWith([received(candidate.did, BleVehicleSignalState.neverReceived)]), candidate.name);
      expect(c.state, SignalState.noData);

      final polled = vehicleSignalCatalog.firstWhere((s) => s.isPolled);
      final p = view(
        snapshotWith([received(polled.did, BleVehicleSignalState.neverReceived)], data: packet()),
        polled.name,
      );
      expect(p.state, SignalState.live); // from the v4 packet
    });

    test('a valid record whose raw does not fit the DID length is NO DATA, never a value', () {
      final v = view(
        snapshotWith([received(candidate.did, BleVehicleSignalState.valid, raw: maxRawForLength(candidate.length) + 1)]),
        candidate.name,
      );
      expect(v.state, SignalState.noData);
      expect(v.value, isNull);
    });

    test('without a record a candidate stays NOT POLLED', () {
      final v = view(snapshotWith(const []), candidate.name);
      expect(v.state, SignalState.notPolled);
    });

    test('records are ignored while not connected', () {
      final v = view(
        snapshotWith([received(candidate.did, BleVehicleSignalState.valid, raw: 1)], connected: false),
        candidate.name,
      );
      expect(v.state, SignalState.notPolled);
    });

    test('a polled signal with no telemetry packet at all is LIVE from its record', () {
      final speed = byNameCatalog(VehicleSignalNames.vehicleSpeed);
      final v = view(snapshotWith([received(speed.did, BleVehicleSignalState.valid, raw: 55)]), speed.name);
      expect(v.state, SignalState.live);
      expect(v.valueText, '55');
    });

    test('the v4 packet wins while it says LIVE; otherwise the record decides', () {
      final speed = byNameCatalog(VehicleSignalNames.vehicleSpeed);
      // v4 says 62 and LIVE; the record says a negative response: v4 wins.
      final v4Live = view(
        snapshotWith([received(speed.did, BleVehicleSignalState.negativeResponse, raw: 0x31)], data: packet()),
        speed.name,
      );
      expect(v4Live.state, SignalState.live);
      expect(v4Live.valueText, '62');

      // v4 says not valid (stale), the record is valid and fresh: LIVE from the record.
      final v4Stale = view(
        snapshotWith(
          [received(speed.did, BleVehicleSignalState.valid, raw: 70)],
          data: packet(speedValid: false, speedAge: 4000),
        ),
        speed.name,
      );
      expect(v4Stale.state, SignalState.live);
      expect(v4Stale.valueText, '70');

      // v4 stale and the record says skipped: SKIPPED.
      final skipped = view(
        snapshotWith(
          [received(speed.did, BleVehicleSignalState.skipped)],
          data: packet(speedValid: false, speedAge: 4000),
        ),
        speed.name,
      );
      expect(skipped.state, SignalState.skipped);
    });

    test('a record is keyed by DID: the other signals are untouched', () {
      final s = snapshotWith([received(candidate.did, BleVehicleSignalState.valid, raw: 1)]);
      expect(s.liveCount, 1);
      for (final v in s.signals.where((v) => v.signal.did != candidate.did)) {
        expect(v.isLive, isFalse, reason: v.signal.name);
      }
    });

    test('decimals follow the catalog step', () {
      expect(vehicleSignalDecimals(byNameCatalog(VehicleSignalNames.vehicleSpeed)), 0);
      expect(vehicleSignalDecimals(byNameCatalog(VehicleSignalNames.engineSpeed)), 2); // 1/4 rpm
      expect(vehicleSignalDecimals(byNameCatalog(VehicleSignalNames.batteryVoltage)), 3); // 1/1000 V
      expect(vehicleSignalDecimals(byNameCatalog(VehicleSignalNames.throttlePos)), 1); // 100/255 %
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
