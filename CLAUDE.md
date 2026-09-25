# CLAUDE.md — moto-mobile

@.claude/PLATFORM-RULES.md

## What this repo is

The phone companion app, in **Flutter** (D-022). Starting point: the legacy `HondaCl250_Telemetry/mobile_app/flutter_app` (BLE client + decoder + dashboard), ported per D-023. Scope: settings, ride history/reports, park-mode alarm notifications, profile selection. Talks to the vehicle over BLE/Wi-Fi via `moto-connectivity-node`, and to the `moto-server` API for historical data.

## What this repo is NOT / rules

- **It is not involved in anything safety-critical.** The system works fully without the phone. When the phone connection drops, nothing changes on the vehicle side.
- Everything written from the phone to the vehicle is only a setting/preference (profile, brightness, etc.). Things like the safety threshold or unlocking the immobilizer do not belong in this repo; if asked to add them, ask the user.
- Signal names come from `moto-vehicle-defs` (VSS paths), never hand-written.
- This is the last repo to be set up during bring-up. Don't start development here before the earlier repos have settled.

## Context

ARCHITECTURE §5, §7 · `../moto-vehicle-defs/docs/hardware-architecture.md` §5b.4.
