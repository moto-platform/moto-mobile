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

## App screens

Dark, high-contrast Material 3 theme; every color and text style lives in
`lib/ui/theme/app_theme.dart`. Five destinations (`lib/ui/app_shell.dart`):

- **Live:** speed, RPM, throttle, coolant and battery with their state, and a
  status strip (BLE, ECU, CAN state, latches, mock data, IMU, GPS).
- **Signals:** every signal of the defs catalog (D-066,
  `vehicleSignalCatalog`), grouped, with a LIVE / STALE / SKIPPED / `NRC 0x31` /
  NO DATA / NOT POLLED chip, age and poll period. The latest vehicle-signal
  record per DID drives it: a signal is LIVE when its record is valid and the
  phone received it within 2000 ms (the five telemetry-v4 signals keep their
  100 ms v4 values while those say LIVE). Candidates stay NOT POLLED until the
  node reports them; once a candidate is promoted in the firmware it turns LIVE
  with no code change. This screen is how the bike shows which signals flow.
- **Record:** session metadata, live counters, sessions and upload (unchanged
  behaviour, D-063 still applies).
- **Diagnostics:** link, packet loss, vehicle CAN counters and the D-058 tester
  statistics.
- **Settings:** server URL and API token.

`lib/ui/telemetry/signal_view.dart` maps the polled catalog signals to the
decoded telemetry fields, keyed by the generated `VehicleSignalNames`; a test
fails if a polled DID has no binding. The Nextion telematics form of the legacy
dashboard is gone (the display is deferred in Phase 0).

## BLE telemetry packet schema

The BLE notification formats decoded by `lib/models/telemetry_data.dart`
(telemetry, versions 2, 3 and 4), `lib/models/imu_block.dart` (the IMU
sample block), `lib/models/gps_block.dart` (the GPS block) and
`lib/models/vehicle_signal_block.dart` (the D-066 vehicle-signal block, records
keyed by DID, physical values through the generated catalog), plus the GATT
UUIDs and MTU, are defined once, in
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
`summary.json` and (when the connected device sends IMU, GPS or vehicle-signal
data) `imu.csv`, `gps.csv` and `signals.csv` to `<app documents>/sessions/<session_id>/` -- see
`docs/session-format.md` for the exact contract shared with `moto-server`.
GPS is speed and heading only (D-060), and its characteristic needs the phone
to be paired (bonded) with the bike (D-062): on Android the app starts the
pairing on connect; telemetry, IMU and the vehicle-signal characteristic work
without it (firmware without a characteristic is simply not subscribed to).
`signals.csv` holds engine data only, so the D-063 local-only rule is for
`gps.csv` alone. Sessions can be shared locally
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
