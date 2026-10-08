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
carried over and updated for the BLE telemetry packet schema (now version 4,
D-058, with version 3 still decoded and version 2 kept as the low-MTU
fallback).

## BLE telemetry packet schema

The BLE notification formats decoded by `lib/models/telemetry_data.dart`
(telemetry, versions 2, 3 and 4) and `lib/models/imu_block.dart` (the IMU
sample block), plus the GATT UUIDs and MTU, are defined once, in
`moto-vehicle-defs` `ble/ble_schema.json` (D-061). This repo does not copy it:
the `external/moto-vehicle-defs` submodule provides the generated Dart path
package `moto_defs` (`external/moto-vehicle-defs/gen/dart/moto_defs`,
`import 'package:moto_defs/moto_defs.dart'`), and the decoders only read its
constants. After cloning, fetch the submodule first:

```
git submodule update --init
```

The tests build packets byte by byte from the generated offsets; a layout
change is a defs change plus a version bump, never a hand edit here.

## Ride session files and moto-server upload

Recording a ride writes `meta.json`, `telemetry.csv`, `events.csv`,
`summary.json` and (when the connected device sends IMU or GPS data) `imu.csv`
and `gps.csv` to `<app documents>/sessions/<session_id>/` -- see
`docs/session-format.md` for the exact contract shared with `moto-server`.
GPS is speed and heading only (D-060), and its characteristic needs the phone
to be paired (bonded) with the bike (D-062): on Android the app starts the
pairing on connect; telemetry and IMU work without it. Sessions can be shared locally
at any time; uploading them to a configured `moto-server` is a separate,
optional action (Settings screen sets the server URL/API token) and never
blocks recording or sharing.

## Commands

```
git submodule update --init   # moto-vehicle-defs, needed by the moto_defs path package
flutter pub get
flutter analyze
flutter test
```

## License

MIT, see `LICENSE` (D-036).
