# Ride session file format

This is moto-mobile's side of the session file contract shared with
`moto-server`: what `SessionRecorder` (`lib/services/session_recorder.dart`)
writes to `<app documents>/sessions/<session_id>/`, and what the upload
archive (`lib/services/session_upload.dart`) contains. moto-server is built
against the same contract independently -- if you change anything here,
change it on both sides together.

The BLE packet layouts referenced throughout (telemetry versions 2 and 3,
and the IMU block) have exactly one source of truth:
`moto-connectivity-node/docs/ble_telemetry_packet_schema.json`. This repo
keeps a byte-identical copy at `test/fixtures/ble_telemetry_packet_schema.json`
and `test/schema_drift_test.dart` fails if it drifts. Never hand-invent a
field name, offset or scale here -- copy it from that schema.

`session_id` format: `YYYYMMDD-HHMMSS-xxxx` (UTC, 4 lowercase hex digits),
stamped by `SessionRecorder.start()`.

## meta.json

Written once, immediately when recording starts. Existing keys (unchanged
since the version-2-only app): `session_id`, `created_utc`, `rider_name`,
`rider_weight_kg`, `extra_load_kg`, `ambient_temp_c`, `weather`,
`tire_pressure_front_bar`, `tire_pressure_rear_bar`, `fuel_level`,
`vehicle_config`, `condition_label`, `route_type`, `note`, `app_version`,
`ble_schema_version` (int; this app always writes `3`), `device_name`.

New keys (D-032):
- `imu_block_version` (int, `1`) -- the IMU block schema version this app
  decodes.
- `requested_mtu` (int, `185`) -- the ATT MTU this app requests right after
  connecting (`BleService.requestedMtu`), regardless of what was actually
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

This app appends 14 more (35 columns total):
```
packet_version,device_time_ms,rpm_age_ms,speed_age_ms,coolant_age_ms,
tps_age_ms,battery_age_ms,imu_active,can_bus_state,can_tec,can_rec,
can_bus_off_count,unanswered_did_count,can_flags
```

Notes:
- `raw_hex` is lowercase hex of the *entire* notification payload (16 bytes
  for version 2, 37 for version 3) and is authoritative: moto-server
  re-decodes it from the schema and only uses this app's decoded columns as
  a consistency check.
- A row whose packet decoded as version 2 (old firmware, or the negotiated
  MTU was too small for version 3) has `packet_version=2` and all 14
  appended columns empty -- there is no v3 data to report.
- A row that failed to decode at all (`decode_error` non-empty: unrecognized
  version, or the wrong length for the version it claims) has every decoded
  column empty, including `packet_version`.
- The three `lean_*` columns are DEPRECATED (D-023): a version-3 packet
  always reports them as unavailable, so they are always empty for
  `packet_version=3` rows. Do not use them for analysis.
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

## events.csv (unchanged header)

```
rx_utc_iso,rx_mono_ms,event,detail
```

Existing events: `recording_started`, `decode_error`, `packet_gap`,
`ble_connected`, `ble_reconnected`, `ble_disconnected`, `recording_stopped`.

New events (D-032):
- `mtu_negotiated` -- `detail=mtu=<n>`, whenever `BleService` reports a new
  negotiated ATT MTU.
- `packet_version` -- `detail=version=<2|3>`, whenever the telemetry
  packet's version differs from the previous packet (the first packet
  always logs one).
- `firmware_update_recommended` -- `detail=only v2 packets received`, at
  most once per session, once the first 20 telemetry packets have all been
  version 2 *and* the MTU is not independently known to be too small to
  explain it (see `SessionRecorder._mtuTooSmallForV3`). Also surfaced live
  in the Record screen as `SessionRecorder.firmwareUpdateRecommended`.
- `can_health` -- `detail=state=<name>;tec=<n>;rec=<n>;bus_off=<n>;flags=<n>`,
  whenever `can_bus_state`, `can_flags` or `can_bus_off_count` changes (the
  first version-3 packet always logs one).
- `did_unanswered` -- `detail=count=<n>;delta=<d>`, whenever
  `unanswered_did_count` increases.
- `imu_gap` -- `detail=missing=<n>;sample_index=<i>`, whenever an IMU block's
  `block_missing_samples` is greater than 0.
- `decode_error` is also used for a bad IMU block, with the detail prefixed
  `imu:` so it is distinguishable from a telemetry decode error.

## summary.json (written on stop)

Existing keys: `duration_ms`, `packet_count`, `lost_count`, `loss_percent`,
`decode_error_count`, `disconnect_count`, `first_packet_utc`,
`last_packet_utc`.

New keys (D-032):
- `packet_versions` -- object keyed by version as a string, e.g.
  `{"2": 3, "3": 1200}`.
- `imu_block_count`, `imu_sample_count`, `imu_missing_samples`,
  `imu_loss_percent` -- IMU totals for the whole session (0 / `0.0` when no
  IMU data ever arrived).
- `mtu` -- last negotiated ATT MTU, or `null` if never reported.

## Upload to moto-server

- `POST {baseUrl}/sessions`, `multipart/form-data`, field name `archive`,
  filename `<session_id>.zip`, header `Authorization: Bearer <token>`.
- The archive contains, at its root: `meta.json`, `telemetry.csv`,
  `events.csv`, `summary.json`, and `imu.csv` if present. It never contains
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
