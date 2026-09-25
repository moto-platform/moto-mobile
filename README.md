# moto-mobile

The phone companion app for the moto-platform motorcycle telemetry/diagnostics
system (see the workspace `CLAUDE.md` / `PLATFORM-RULES.md` for the full
platform picture). Written in Flutter (D-022). Scope: settings, ride
history/reports, park-mode alarm notifications, and profile selection. It
talks to the vehicle over BLE/Wi-Fi via `moto-connectivity-node`, and to the
`moto-server` API for historical data. The app is not involved in anything
safety-critical: the vehicle works fully whether or not the phone is
connected.

## Origin

Ported from `HondaCl250_Telemetry@legacy-final` (`mobile_app/flutter_app`)
per decision D-023. The web PWA and the complementary-filter lean angle
estimate were dropped; the BLE client, packet decoder and dashboard were
carried over and updated for the v2 BLE telemetry packet schema.

## BLE telemetry packet schema

The BLE notification format decoded by `lib/models/telemetry_data.dart` is
defined in `moto-connectivity-node/docs/ble_telemetry_packet_schema.json`
(schema version 2). A verbatim copy is checked into
`test/fixtures/ble_telemetry_packet_schema.json` and cross-checked against
the decoder by `test/telemetry_data_test.dart`.

## Commands

```
flutter pub get
flutter analyze
flutter test
```
