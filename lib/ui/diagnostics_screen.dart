import 'package:flutter/material.dart';
import 'package:moto_defs/moto_defs.dart';

import '../models/telemetry_data.dart';
import 'telemetry/link_status.dart';
import 'telemetry/telemetry_store.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

/// Link, packet, CAN and tester health. Read-only; everything comes from the
/// newest BLE telemetry packet and the decoder's counters.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key, required this.store});

  final TelemetryStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xl),
            children: [
              _linkSection(context),
              const SizedBox(height: Spacing.lg),
              _packetSection(context),
              const SizedBox(height: Spacing.lg),
              _canSection(context),
              const SizedBox(height: Spacing.lg),
              _testerSection(context),
            ],
          );
        },
      ),
    );
  }

  String _num(int? v) => v == null ? '--' : '$v';

  Widget _flagRow(BuildContext context, String label, bool? value, {required bool badWhenTrue}) {
    final t = context.moto;
    if (value == null) return KeyValueRow(label: label, value: '--');
    final bad = value == badWhenTrue;
    return KeyValueRow(
      label: label,
      value: value ? 'yes' : 'no',
      valueColor: bad ? t.error : t.live,
    );
  }

  Widget _linkSection(BuildContext context) {
    final data = store.data;
    final since = store.sinceLastPacket;
    final t = context.moto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Link'),
        SectionCard(
          child: Column(
            children: [
              KeyValueRow(
                label: 'BLE',
                value: store.connected ? 'connected' : 'disconnected',
                valueColor: store.connected ? t.live : t.noData,
              ),
              KeyValueRow(label: 'Device', value: store.deviceName ?? '--'),
              KeyValueRow(label: 'ATT MTU', value: store.mtu == null ? '--' : '${store.mtu}'),
              const KeyValueRow(label: 'Requested MTU', value: '${BleGatt.requestedMtu}'),
              KeyValueRow(label: 'Packet version', value: store.hasPacket ? '${data.packetVersion}' : '--'),
              KeyValueRow(label: 'Last packet', value: since == null ? '--' : '${formatAge(since.inMilliseconds)} ago'),
              KeyValueRow(label: 'Device time', value: data.deviceTimeMs == null ? '--' : '${data.deviceTimeMs} ms'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _packetSection(BuildContext context) {
    final received = TelemetryData.receivedCount;
    final lost = TelemetryData.lostCount;
    final total = received + lost;
    final loss = total == 0 ? '--' : '${(lost * 100 / total).toStringAsFixed(1)} %';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Packets'),
        SectionCard(
          child: Column(
            children: [
              KeyValueRow(label: 'Received', value: '$received'),
              KeyValueRow(label: 'Lost (sequence gaps)', value: '$lost'),
              KeyValueRow(label: 'Loss', value: loss),
              KeyValueRow(
                label: 'Rejected (version)',
                value: '${TelemetryData.versionRejectedCount}',
                valueColor: TelemetryData.versionRejectedCount > 0 ? context.moto.error : null,
              ),
              KeyValueRow(
                label: 'Rejected (size)',
                value: '${TelemetryData.sizeRejectedCount}',
                valueColor: TelemetryData.sizeRejectedCount > 0 ? context.moto.error : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _canSection(BuildContext context) {
    final data = store.data;
    final can = canStateStatus(data.canBusState);
    final hasCan = data.canBusState != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Vehicle CAN bus'),
        SectionCard(
          child: Column(
            children: [
              KeyValueRow(label: 'Bus state', value: can.text, valueColor: toneColor(context, can.tone)),
              KeyValueRow(label: 'TX errors', value: _num(data.canTxErrorCount)),
              KeyValueRow(label: 'RX errors', value: _num(data.canRxErrorCount)),
              KeyValueRow(label: 'Bus-off events', value: _num(data.canBusOffCount)),
              KeyValueRow(label: 'Unanswered DIDs', value: _num(data.unansweredDidCount)),
              _flagRow(context, 'Poller enabled', data.pollerEnabled, badWhenTrue: false),
              _flagRow(context, 'Foreign tester latched', data.latchedForeignTester, badWhenTrue: true),
              _flagRow(context, 'Bus-off latched', data.latchedBusOff, badWhenTrue: true),
              _flagRow(context, 'Synthetic data', data.syntheticData, badWhenTrue: true),
              if (!hasCan)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    'CAN health needs a version ${TelemetryVersion.v3} or newer packet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _testerSection(BuildContext context) {
    final data = store.data;
    final hasTester = data.stepGapMaxMs != null;
    final count = data.rttCount;
    final sum = data.rttSumMs;
    final avg = (count != null && count > 0 && sum != null) ? '${(sum / count).toStringAsFixed(1)} ms' : '--';

    String didText = '--';
    final did = data.rttDid;
    if (did != null) {
      final match = vehicleSignalCatalog.where((s) => s.did == did);
      didText = match.isEmpty ? didHex(did) : '${match.first.label} (${didHex(did)})';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Tester (diagnostic poller)'),
        SectionCard(
          child: Column(
            children: [
              KeyValueRow(label: 'Step gap, max', value: formatMs(data.stepGapMaxMs)),
              KeyValueRow(
                label: 'Step gap, over limit',
                value: _num(data.stepGapOverCount),
                valueColor: (data.stepGapOverCount ?? 0) > 0 ? context.moto.stale : null,
              ),
              const Divider(),
              const SizedBox(height: Spacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Round trip, rotating DID', style: Theme.of(context).textTheme.labelSmall),
              ),
              KeyValueRow(label: 'DID', value: didText),
              KeyValueRow(label: 'Min', value: formatMs(data.rttMinMs)),
              KeyValueRow(label: 'Max', value: formatMs(data.rttMaxMs)),
              KeyValueRow(label: 'Mean', value: avg),
              KeyValueRow(label: 'Samples', value: _num(data.rttCount)),
              KeyValueRow(label: 'NRC 0x78 (pending)', value: _num(data.rttNrc78Count)),
              if (!hasTester)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    'Tester stats need a version ${TelemetryVersion.v4} packet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
