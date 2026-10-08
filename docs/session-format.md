# Ride session file format

This is moto-mobile's side of the session file contract shared with
`moto-server`: what `SessionRecorder` (`lib/services/session_recorder.dart`)
writes to `<app documents>/sessions/<session_id>/`, and what the upload
archive (`lib/services/session_upload.dart`) contains. moto-server is built
against the same contract independently -- if you change anything here,
change it on both sides together.

The BLE packet layouts referenced throughout (telemetry versions 2, 3 and 4,
the IMU block and the GPS block) have exactly one source of truth: `ble/ble_schema.json` in
`moto-vehicle-defs` (D-061). This repo takes it through the
`external/moto-vehicle-defs` submodule and the generated Dart package
`moto_defs` (`package:moto_defs/moto_defs.dart`, a path dependency); there is
no copy of the schema and no drift test here. Never hand-invent a field name,
offset or scale -- it comes from the schema (its `testerStats` section
explains the version 4 fields), and a layout change is a defs change plus a
version bump.

`session_id` format: `YYYYMMDD-HHMMSS-xxxx` (UTC, 4 lowercase hex digits),
stamped by `SessionRecorder.start()`.

## meta.json

Written once, immediately when recording starts. Existing keys (unchanged
since the version-2-only app): `session_id`, `created_utc`, `rider_name`,
`rider_weight_kg`, `extra_load_kg`, `ambient_temp_c`, `weather`,
`tire_pressure_front_bar`, `tire_pressure_rear_bar`, `fuel_level`,
`vehicle_config`, `condition_label`, `route_type`, `note`, `app_version`,
`ble_schema_version` (int; this app writes `4`, the schema's current
telemetry version -- sessions recorded by the earlier app carry `3`),
`device_name`.

New keys (D-032):
- `imu_block_version` (int, `1`) -- the IMU block schema version this app
  decodes.
- `gps_block_version` (int, `1`, D-060) -- the GPS block schema version this
  app decodes (absent in sessions from earlier app builds).
- `requested_mtu` (int, `185`) -- the ATT MTU this app requests right after
  connecting (the schema's `gatt.mtu.requested`, generated as
  `BleGatt.requestedMtu`), regardless of what was actually
  negotiated (that lives in `summary.json`'s `mtu`).

## telemetry.csv

One row per telemetry BLE notification, decoded or not.

The first 21 columns are unchanged from the version-2-only app:
```
rx_utc_iso,rx_mono_ms,seq,lost_since_prev,raw_hex,rpm,speed_kmh,coolant_c,
tps_pct,battery_v,lean_deg,max_lean_right_deg,max_lean_left_deg,rpm_valid,
speed_valid,coolant_valid,tps_valid,battery_valid,lean_valid,ecu_present,
decode_error
```

The version-3 app appended 14 more (35 columns):
```
packet_version,device_time_ms,rpm_age_ms,speed_age_ms,coolant_age_ms,
tps_age_ms,battery_age_ms,imu_active,can_bus_state,can_tec,can_rec,
can_bus_off_count,unanswered_did_count,can_flags
```

Telemetry version 4 (D-058) adds 8 more at the end (43 columns total), the
tester statistics of the schema's `testerStats` section:
```
step_gap_max_ms,step_gap_over_count,rtt_did,rtt_min_ms,rtt_max_ms,
rtt_sum_ms,rtt_count,rtt_nrc78_count
```

Notes:
- `raw_hex` is lowercase hex of the *entire* notification payload (16 bytes
  for version 2, 37 for version 3, 57 for version 4) and is authoritative: moto-server
  re-decodes it from the schema and only uses this app's decoded columns as
  a consistency check.
- A row whose packet decoded as version 2 (old firmware, or the negotiated
  MTU was too small for version 3) has `packet_version=2` and all 22
  appended columns (14 version-3 plus 8 version-4) empty -- there is no
  version 3 or 4 data to report. A version 3 row (`packet_version=3`, old
  firmware or an old recording) fills the 14 version-3 columns and leaves the
  8 version-4 columns empty. A version 4 row fills all 22.
- A row that failed to decode at all (`decode_error` non-empty: unrecognized
  version, or the wrong length for the version it claims) has every decoded
  column empty, including `packet_version`.
- The three `lean_*` columns are DEPRECATED (D-023): a version 3 or 4 packet
  always reports them as unavailable, so they are always empty for
  `packet_version=3` and `4` rows. Do not use them for analysis.
- The eight version-4 columns are measurements of the vehicle-bus tester (not
  vehicle signals) and are TEMPORARY: rt-core's health DID 0xFD02 (D-055)
  replaces them once rt-core is the tester. They hold the raw wire values,
  sentinels included, so the contract has no "null" encoding of its own:
  - `step_gap_max_ms`: largest gap since boot between two tester steps (ms,
    rounded up, saturates at 65535; `0` when the node has no tester).
  - `step_gap_over_count`: number of those gaps above `client_step_max_ms`
    (saturating at 65535).
  - `rtt_did`: DID of this packet's rotating round-trip record (the node
    cycles through its DID table, one DID per packet); `0` means this packet
    has no record, and the other `rtt_*` columns then carry no sample.
  - `rtt_min_ms`: smallest round trip of `rtt_did` since boot, in ms
    (`65535` = no sample yet).
  - `rtt_max_ms`: largest round trip of `rtt_did` since boot, in ms (`0` = no
    sample yet).
  - `rtt_sum_ms` / `rtt_count`: sum of the round trips and number of samples
    (uint32, saturating at 4294967295). Average = `rtt_sum_ms / rtt_count`,
    invalid if either saturated.
  - `rtt_nrc78_count`: requests of `rtt_did` answered with NRC 0x78
    (responsePending); they give no round-trip sample (saturating at 65535).
  A round trip is the time from the request's send to the tester step that
  drains its answer, so it includes one step and loop latency (see the
  schema's `testerStats.roundTrip`).
- **moto-server must accept the same 43 columns** (the 8 new ones are empty
  for version 2 and 3 rows). This is part of the contract shared with
  moto-server; change it on both sides together.
- `can_bus_state` and `can_flags` are the raw integers from the schema's
  `canHealth.busState` / `canHealth.canFlags`, not names.
- Booleans are `1`/`0`; every other unavailable value (including an age
  equal to the schema's `age.neverReceived` sentinel, 65535) is an empty
  field, never a literal "null" or "-1".

## imu.csv (optional)

Created lazily, the first time an IMU block decodes successfully -- a
session where the connected firmware has no IMU characteristic, or none
ever notified, simply has no `imu.csv`. One row per IMU **sample** (not per
block):

```
rx_utc_iso,rx_mono_ms,block_seq,block_flags,block_missing_samples,
sample_index,device_time_ms,ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw,
ax_g,ay_g,az_g,gx_dps,gy_dps,gz_dps
```

- `rx_utc_iso` / `rx_mono_ms`: phone receive time of the *block*, repeated
  for every sample in it.
- `block_missing_samples`: the result of the schema's
  `imuBlock.sampleIndex.rule` gap computation, written on the first row of
  each block only (0 for every other row, and 0 for the first block of the
  session). `lib/models/imu_block.dart`'s `ImuGapTracker` computes this.
- `sample_index` = `firstSampleIndex + i` (mod 65536); `device_time_ms` =
  `deviceTimeMs + i * samplePeriodMs` -- both per the schema's `timeRule`.
- `*_raw` are the signed 16-bit values straight off the wire; `*_g` / `*_dps`
  are `raw / scale` using the schema's `imuBlock.scale` (moto-server
  recomputes these from the raw values independently).
- A block that fails to decode (bad version, bad size, `sampleCount` out of
  range) never gets a row here -- it is counted as a `decode_error` event
  instead (see below) and simply skipped.

## gps.csv (optional, D-060)

Speed and heading of connectivity-node's GPS, from the schema's `gpsBlock`
(notified on the `gps` characteristic, one block per UBX-NAV-PVT, 10 Hz).
**There is no position:** latitude, longitude and height never leave the node
(D-060 item 3, invariant 7), and moto-server rejects a `gps.csv` whose header
is not exactly the one below.

Created lazily, the first time a GPS block decodes successfully -- a session
whose firmware has no `gps` characteristic, or whose phone is not bonded
(see below), has no `gps.csv`. One row per **block**:

```
rx_utc_iso,rx_mono_ms,seq,lost_since_prev,raw_hex,device_time_ms,
ground_speed,heading_of_motion,speed_accuracy,heading_accuracy,fix_type,
num_sv,flags,ground_speed_mps,heading_of_motion_deg,speed_accuracy_mps,
heading_accuracy_deg,gnss_fix_ok,parse_error,uart_overflow
```

- `raw_hex` is lowercase hex of the whole 26-byte block and is
  authoritative: moto-server re-decodes it and uses the other columns only as
  a consistency check.
- `lost_since_prev` = `(seq - prev.seq - 1) mod 256` (schema `sequenceRule`;
  0 for the first block of the session). It counts blocks lost on the radio
  **and** blocks the node skipped because the MTU was too small (D-062 item
  2), so it is not a radio-loss figure.
- `device_time_ms` ... `flags` are the raw fields (their schema names in
  snake_case, wire units: mm/s and 1e-5 deg). `ground_speed` and
  `heading_of_motion` are signed.
- `*_mps` / `*_deg` are `raw / scale` using the schema's `gpsBlock.scale`.
- `fix_type` is the NAV-PVT value (`BleGpsFixType`); the CAN speed check uses
  only rows with `fix_type` 3 or 4 and `gnss_fix_ok=1` (schema
  `fixType.rule`).
- `gnss_fix_ok`, `parse_error`, `uart_overflow` are the flag bits (`1`/`0`).
  The two error flags cover the interval since the previous block, sent or
  skipped.
- A block that fails to decode (wrong size or version) gets no row; it is a
  `decode_error` event with a `gps:` prefix.

**Bonded link (D-062).** The `gps` characteristic accepts a subscription only
on a bonded, encrypted link. After telemetry and IMU are subscribed, the app
bonds first on Android (system pairing dialog; iOS pairs on its own when the
subscription is refused), then subscribes. It tries once per connection: the
node clears the subscription on every connect, so it subscribes again on the
next one. A failure never affects telemetry or IMU.

**Residual privacy risk (D-060 item 5).** A speed + heading series can rebuild
the route's shape by dead reckoning. A session with `gps.csv` goes only to
the user's own local moto-server (Phase 0 runs it on the laptop), never to a
server that is not local, and real sessions are never committed (D-033).

## events.csv (unchanged header)

```
rx_utc_iso,rx_mono_ms,event,detail
```

Existing events: `recording_started`, `decode_error`, `packet_gap`,
`ble_connected`, `ble_reconnected`, `ble_disconnected`, `recording_stopped`.

New events (D-032):
- `mtu_negotiated` -- `detail=mtu=<n>`, whenever `BleService` reports a new
  negotiated ATT MTU.
- `packet_version` -- `detail=version=<2|3|4>`, whenever the telemetry
  packet's version differs from the previous packet (the first packet
  always logs one).
- `firmware_update_recommended` -- `detail=only v2 packets received`, at
  most once per session, once the first 20 telemetry packets have all been
  version 2 *and* the MTU is not independently known to be too small to
  explain it (see `SessionRecorder._mtuTooSmallForV3`). Also surfaced live
  in the Record screen as `SessionRecorder.firmwareUpdateRecommended`.
- `can_health` -- `detail=state=<name>;tec=<n>;rec=<n>;bus_off=<n>;flags=<n>`,
  whenever `can_bus_state`, `can_flags` or `can_bus_off_count` changes (the
  first version 3 or 4 packet always logs one).
- `did_unanswered` -- `detail=count=<n>;delta=<d>`, whenever
  `unanswered_did_count` increases.
- `imu_gap` -- `detail=missing=<n>;sample_index=<i>`, whenever an IMU block's
  `block_missing_samples` is greater than 0.
- `decode_error` is also used for a bad IMU block, with the detail prefixed
  `imu:` so it is distinguishable from a telemetry decode error.

New events (D-060, D-062):
- `gps_gap` -- `detail=missing=<n>;seq=<s>`, whenever a GPS block's
  `lost_since_prev` is greater than 0 (lost or MTU-skipped).
- `gps_subscribed` -- empty detail, when the `gps` subscription succeeds on a
  connection (logged once per change of the subscription state).
- `gps_subscribe_failed` -- `detail=reason=<error>`, when bonding or the
  subscription fails. Bluetooth addresses and device ids in the error are
  replaced with `<device>` / `<id>` (D-033).
- `decode_error` with the detail prefixed `gps:` for a bad GPS block.

## summary.json (written on stop)

Existing keys: `duration_ms`, `packet_count`, `lost_count`, `loss_percent`,
`decode_error_count`, `disconnect_count`, `first_packet_utc`,
`last_packet_utc`.

New keys (D-032):
- `packet_versions` -- object keyed by version as a string, e.g.
  `{"2": 3, "4": 1200}`.
- `imu_block_count`, `imu_sample_count`, `imu_missing_samples`,
  `imu_loss_percent` -- IMU totals for the whole session (0 / `0.0` when no
  IMU data ever arrived).
- `mtu` -- last negotiated ATT MTU, or `null` if never reported.

New keys (D-060):
- `gps_block_count`, `gps_lost_or_skipped_blocks`,
  `gps_lost_or_skipped_percent` -- GPS totals for the session (0 / `0.0` when
  no GPS block arrived); "lost or skipped" as in `gps.csv`'s
  `lost_since_prev`.

## Upload to moto-server

- `POST {baseUrl}/sessions`, `multipart/form-data`, field name `archive`,
  filename `<session_id>.zip`, header `Authorization: Bearer <token>`.
- The archive contains, at its root: `meta.json`, `telemetry.csv`,
  `events.csv`, `summary.json`, and `imu.csv` / `gps.csv` if present. It never contains
  `upload.json` (see below) -- that is app-local bookkeeping, not session
  data.
- Responses: `201` created, `200` already uploaded (idempotent, treated as
  success), `409` conflict (same session id, different content -- shown as
  failed, never retried automatically), `401`/`413`/anything else -> failed
  with the server's message when it sends one.
- Per-session upload status is persisted at `<session>/upload.json`
  (`SessionUploadState`: `notUploaded` / `uploading` / `uploaded` / `failed`,
  plus a `reason` and `uploaded_at_utc`). Recording and sharing a session
  work fully with no server configured; only the Upload action needs it.
- "Upload only on Wi-Fi" (default on, Settings screen) blocks an upload when
  Wi-Fi is confirmed absent *or* unknown -- an unknown state is only ever
  let through when the setting itself is off.
- A session with `gps.csv` uploads only to a local server (D-063,
  `isLocalServerUrl`): `localhost`, a `.local` name, or a loopback, private
  (RFC 1918, IPv6 ULA) or link-local address. Any other host fails the
  upload before a network call, with reason `session has GPS data: upload
  only to a local server (D-063)`. Sessions without `gps.csv` are unaffected.
