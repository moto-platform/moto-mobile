import '../../models/gps_block.dart';
import '../../models/telemetry_data.dart';

// Pure-Dart helpers that turn link / CAN / GPS state into short display text
// and a tone. No Flutter imports, so they are unit tested directly.

/// Severity of a status item; the widget layer maps it to a token colour.
enum Tone { ok, warn, error, neutral, accent }

/// Text plus tone of one status item.
class StatusText {
  const StatusText(this.text, this.tone);

  final String text;
  final Tone tone;
}

/// CAN bus state of the node's vehicle-bus controller. `null` means the
/// packet version carries no CAN health (version 2).
StatusText canStateStatus(CanBusState? state) {
  if (state == null) return const StatusText('CAN n/a', Tone.neutral);
  return switch (state) {
    CanBusState.running => const StatusText('CAN running', Tone.ok),
    CanBusState.errorWarning => const StatusText('CAN error warning', Tone.warn),
    CanBusState.busOff => const StatusText('CAN bus-off', Tone.error),
    CanBusState.stopped => const StatusText('CAN stopped', Tone.warn),
    CanBusState.notInstalled => const StatusText('CAN not installed', Tone.neutral),
  };
}

/// GPS link: subscription state plus the newest fix, if any.
StatusText gpsStatus(GpsLinkStatus link, GpsBlock? block) {
  switch (link.state) {
    case GpsLinkState.disconnected:
      return const StatusText('GPS --', Tone.neutral);
    case GpsLinkState.notOffered:
      return const StatusText('GPS not offered', Tone.neutral);
    case GpsLinkState.subscribing:
      return const StatusText('GPS pairing...', Tone.warn);
    case GpsLinkState.failed:
      return const StatusText('GPS: pair phone with bike', Tone.warn);
    case GpsLinkState.subscribed:
      if (block == null) return const StatusText('GPS waiting for data', Tone.warn);
      final text = 'GPS ${block.fixTypeLabel} · ${block.numSv} sats';
      return StatusText(text, block.gnssFixOk ? Tone.ok : Tone.warn);
  }
}

/// `1234` -> `1234 ms`, `null` -> `--`.
String formatMs(int? ms) => ms == null ? '--' : '$ms ms';

/// Age text for a signal row: `120 ms`, `2.4 s`, or `--`.
String formatAge(int? ms) {
  if (ms == null) return '--';
  if (ms < 1000) return '$ms ms';
  return '${(ms / 1000).toStringAsFixed(1)} s';
}

/// `0xF40C`-style hex of a DID.
String didHex(int did) => '0x${did.toRadixString(16).toUpperCase().padLeft(4, '0')}';

/// `0x31`-style hex of a negative response code.
String nrcHex(int nrc) => '0x${nrc.toRadixString(16).toUpperCase().padLeft(2, '0')}';
