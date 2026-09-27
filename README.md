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
carried over and updated for the BLE telemetry packet schema (now version 3,
D-032, with version 2 kept as the low-MTU fallback).

## BLE telemetry packet schema

The BLE notification formats decoded by `lib/models/telemetry_data.dart`
(telemetry, versions 2 and 3) and `lib/models/imu_block.dart` (the IMU
sample block) are defined in
`moto-connectivity-node/docs/ble_telemetry_packet_schema.json`. A verbatim
copy is checked into `test/fixtures/ble_telemetry_packet_schema.json` and
cross-checked against the decoders by `test/telemetry_data_test.dart`,
`test/imu_block_test.dart` and `test/schema_drift_test.dart`.

## Ride session files and moto-server upload

Recording a ride writes `meta.json`, `telemetry.csv`, `events.csv`,
`summary.json` and (when the connected device sends IMU data) `imu.csv` to
`<app documents>/sessions/<session_id>/` -- see `docs/session-format.md` for
the exact contract shared with `moto-server`. Sessions can be shared locally
at any time; uploading them to a configured `moto-server` is a separate,
optional action (Settings screen sets the server URL/API token) and never
blocks recording or sharing.

## Commands

```
flutter pub get
flutter analyze
flutter test
```
