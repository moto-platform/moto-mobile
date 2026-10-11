import 'dart:async';

import 'package:flutter/material.dart';
import 'package:moto_defs/moto_defs.dart';

import '../services/ble_service.dart';
import 'telemetry/link_status.dart';
import 'telemetry/signal_view.dart';
import 'telemetry/telemetry_store.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

/// Live dashboard: hero speed, RPM and throttle, secondary tiles, and a
/// compact status strip showing which links and sources are healthy.
class LiveScreen extends StatefulWidget {
  const LiveScreen({
    super.key,
    required this.store,
    required this.bleService,
    required this.onOpenRecord,
  });

  final TelemetryStore store;
  final BleService bleService;

  /// Switches the shell to the Record destination.
  final VoidCallback onOpenRecord;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  /// A scan is running (the scan times out after 15 s in [BleService]).
  bool _connecting = false;
  Timer? _connectTimeout;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  void _onStore() {
    if (_connecting && widget.store.connected) {
      _connectTimeout?.cancel();
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _connectTimeout?.cancel();
    super.dispose();
  }

  void _connectOrDisconnect() {
    if (widget.store.connected) {
      widget.bleService.disconnect();
      return;
    }
    if (_connecting) return;
    setState(() => _connecting = true);
    _connectTimeout?.cancel();
    _connectTimeout = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _connecting = false);
    });
    widget.bleService.connectToBike();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CL250 Telemetry'),
        actions: [
          IconButton(
            tooltip: 'Open the Record screen',
            onPressed: widget.onOpenRecord,
            icon: Icon(Icons.fiber_manual_record, color: context.moto.record),
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final snapshot = widget.store.snapshot;
          return LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final main = _mainColumn(context, snapshot);
            final side = _sideColumn(context, snapshot);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xl),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: main),
                        const SizedBox(width: Spacing.lg),
                        Expanded(flex: 2, child: side),
                      ],
                    )
                  : Column(children: [main, const SizedBox(height: Spacing.lg), side]),
            );
          });
        },
      ),
    );
  }

  // ---- main column: warnings, hero, rpm + throttle ----

  Widget _mainColumn(BuildContext context, SignalSnapshot snapshot) {
    final store = widget.store;
    final speed = snapshot.byName(VehicleSignalNames.vehicleSpeed);
    final rpm = snapshot.byName(VehicleSignalNames.engineSpeed);
    final throttle = snapshot.byName(VehicleSignalNames.throttlePos);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (store.data.syntheticData == true) ...[
          const InfoBanner(
            icon: Icons.science_outlined,
            tone: Tone.error,
            title: 'SYNTHETIC DATA',
            text: 'The node is generating mock values. Nothing shown here comes from the bike.',
          ),
          const SizedBox(height: Spacing.md),
        ],
        _ConnectionCard(
          store: store,
          connecting: _connecting,
          onPressed: _connectOrDisconnect,
        ),
        const SizedBox(height: Spacing.md),
        if (speed != null) _HeroTile(view: speed),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rpm != null)
              Expanded(child: SignalTile(view: rpm, valueStyle: theme.textTheme.displayMedium)),
            const SizedBox(width: Spacing.md),
            if (throttle != null)
              Expanded(
                child: SignalTile(view: throttle, valueStyle: theme.textTheme.displayMedium, showBar: true),
              ),
          ],
        ),
      ],
    );
  }

  // ---- side column: coolant, battery, status strip, record ----

  Widget _sideColumn(BuildContext context, SignalSnapshot snapshot) {
    final coolant = snapshot.byName(VehicleSignalNames.coolantTemp);
    final battery = snapshot.byName(VehicleSignalNames.batteryVoltage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (coolant != null) Expanded(child: SignalTile(view: coolant)),
            const SizedBox(width: Spacing.md),
            if (battery != null) Expanded(child: SignalTile(view: battery)),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        const SectionLabel('Status'),
        _StatusStrip(store: widget.store),
        const SizedBox(height: Spacing.lg),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: context.moto.record,
            foregroundColor: context.moto.textPrimary,
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: widget.onOpenRecord,
          icon: const Icon(Icons.fiber_manual_record),
          label: const Text('RECORD A SESSION'),
        ),
      ],
    );
  }
}

/// Speed in huge numerals; the card border follows the signal state.
class _HeroTile extends StatelessWidget {
  const _HeroTile({required this.view});

  final SignalView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.moto;
    final live = view.isLive;
    final color = live ? t.textPrimary : stateColor(context, view.state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.xl),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Radii.hero),
        border: Border.all(color: live ? t.accent : t.outline, width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(view.label.toUpperCase(), style: theme.textTheme.labelSmall)),
              StateChip(view.state),
            ],
          ),
          const SizedBox(height: Spacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(view.valueText, style: theme.textTheme.displayLarge!.copyWith(color: color)),
          ),
          Text(
            view.unitText.toUpperCase(),
            style: theme.textTheme.titleMedium!.copyWith(color: t.accent, letterSpacing: 2),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.store, required this.connecting, required this.onPressed});

  final TelemetryStore store;
  final bool connecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.moto;
    final connected = store.connected;
    final since = store.sinceLastPacket;
    final String title;
    final String subtitle;
    if (connected) {
      title = store.deviceName ?? 'Connected';
      subtitle = since == null ? 'Waiting for the first packet' : 'Last packet ${formatAge(since.inMilliseconds)} ago';
    } else if (connecting) {
      title = 'Scanning...';
      subtitle = 'Looking for the bike';
    } else {
      title = 'Not connected';
      subtitle = 'Tap Connect to scan for the bike';
    }
    return SectionCard(
      padding: const EdgeInsets.all(Spacing.md),
      child: Wrap(
        spacing: Spacing.md,
        runSpacing: Spacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: connected ? t.live : t.noData,
                size: 28,
              ),
              const SizedBox(width: Spacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          connected
              ? OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                )
              : FilledButton.icon(
                  onPressed: connecting ? null : onPressed,
                  icon: connecting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(connecting ? 'Scanning' : 'Connect'),
                ),
        ],
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.store});

  final TelemetryStore store;

  @override
  Widget build(BuildContext context) {
    final data = store.data;
    final live = store.connected && store.hasPacket;
    final pills = <Widget>[];

    pills.add(StatusPill(
      icon: store.connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
      label: store.connected ? 'BLE ${store.deviceName ?? 'connected'}' : 'BLE disconnected',
      tone: store.connected ? Tone.ok : Tone.neutral,
    ));

    pills.add(live
        ? StatusPill(
            icon: data.ecuPresent ? Icons.memory : Icons.error_outline,
            label: data.ecuPresent ? 'ECU present' : 'ECU not found',
            tone: data.ecuPresent ? Tone.ok : Tone.error,
          )
        : const StatusPill(icon: Icons.memory, label: 'ECU --'));

    final can = live ? canStateStatus(data.canBusState) : const StatusText('CAN --', Tone.neutral);
    pills.add(StatusPill(icon: Icons.settings_ethernet, label: can.text, tone: can.tone));

    if (live && data.pollerEnabled == false) {
      pills.add(const StatusPill(icon: Icons.pause_circle_outline, label: 'Poller off', tone: Tone.warn));
    }

    // Latch flags: shown as alarms when set, one calm pill when both clear.
    if (live) {
      final foreign = data.latchedForeignTester;
      final busOff = data.latchedBusOff;
      if (foreign == true) {
        pills.add(const StatusPill(icon: Icons.lock, label: 'Foreign tester latched', tone: Tone.error));
      }
      if (busOff == true) {
        pills.add(const StatusPill(icon: Icons.lock, label: 'Bus-off latched', tone: Tone.error));
      }
      if (foreign == false && busOff == false) {
        pills.add(const StatusPill(icon: Icons.lock_open, label: 'Latches clear', tone: Tone.ok));
      }
      if (data.syntheticData == true) {
        pills.add(const StatusPill(icon: Icons.science_outlined, label: 'Synthetic data', tone: Tone.error));
      }
    }

    pills.add(StatusPill(
      icon: Icons.vibration,
      label: live ? (data.imuActive ? 'IMU active' : 'IMU inactive') : 'IMU --',
      tone: live ? (data.imuActive ? Tone.ok : Tone.warn) : Tone.neutral,
    ));

    final gps = gpsStatus(store.gpsLink, store.lastGpsBlock);
    pills.add(StatusPill(icon: Icons.satellite_alt, label: gps.text, tone: gps.tone));

    return Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: pills);
  }
}
