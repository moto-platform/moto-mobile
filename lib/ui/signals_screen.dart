import 'package:flutter/material.dart';

import 'telemetry/link_status.dart';
import 'telemetry/signal_view.dart';
import 'telemetry/telemetry_store.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

enum _Filter { all, polled, candidates }

/// Every signal of the generated catalog, grouped in catalog group order,
/// with its state, age and poll period. This is where the user sees which
/// data actually flows.
class SignalsScreen extends StatefulWidget {
  const SignalsScreen({super.key, required this.store});

  final TelemetryStore store;

  @override
  State<SignalsScreen> createState() => _SignalsScreenState();
}

class _SignalsScreenState extends State<SignalsScreen> {
  _Filter _filter = _Filter.all;

  bool _matches(SignalView v) => switch (_filter) {
        _Filter.all => true,
        _Filter.polled => v.signal.isPolled,
        _Filter.candidates => !v.signal.isPolled,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signals')),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final snapshot = widget.store.snapshot;
          final items = <Widget>[
            _SummaryCard(snapshot: snapshot),
            const SizedBox(height: Spacing.md),
            _FilterBar(
              value: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
            const SizedBox(height: Spacing.sm),
          ];
          for (final group in snapshot.groups) {
            final rows = group.signals.where(_matches).toList(growable: false);
            if (rows.isEmpty) continue;
            items.add(_GroupHeader(title: group.title, live: group.liveCount, total: group.signals.length));
            for (final v in rows) {
              items.add(Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: _SignalRow(view: v),
              ));
            }
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xl),
            itemCount: items.length,
            itemBuilder: (context, i) => items[i],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.snapshot});

  final SignalSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = context.moto;
    return SectionCard(
      child: Row(
        children: [
          Expanded(child: _Stat(value: snapshot.liveCount, caption: 'live', color: t.live)),
          Expanded(child: _Stat(value: snapshot.polledCount, caption: 'polled', color: t.textPrimary)),
          Expanded(child: _Stat(value: snapshot.candidateCount, caption: 'candidates', color: t.notPolled)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.caption, required this.color});

  final int value;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('$value', style: theme.textTheme.displaySmall!.copyWith(color: color)),
        ),
        Text(caption.toUpperCase(), style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.onChanged});

  final _Filter value;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<_Filter>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: _Filter.all, label: Text('All')),
          ButtonSegment(value: _Filter.polled, label: Text('Polled')),
          ButtonSegment(value: _Filter.candidates, label: Text('Candidates')),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.live, required this.total});

  final String title;
  final int live;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.sm),
      child: SectionLabel(title, trailing: Text('$live / $total live', style: Theme.of(context).textTheme.labelSmall)),
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.view});

  final SignalView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.moto;
    final live = view.isLive;
    final valueColor = live ? t.textPrimary : stateColor(context, view.state);
    final signal = view.signal;
    final String detail;
    if (!signal.isPolled) {
      detail = 'Not polled';
    } else {
      final poll = 'Poll every ${signal.pollPeriodMs} ms';
      detail = view.ageMs == null ? poll : 'Age ${formatAge(view.ageMs)} · $poll';
    }
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: live ? t.live.withValues(alpha: 0.6) : t.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(view.label, style: theme.textTheme.titleMedium),
                    Text(view.didText, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.md),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(view.valueText, style: theme.textTheme.headlineMedium!.copyWith(color: valueColor)),
                      const SizedBox(width: Spacing.xs),
                      Text(view.unitText, style: theme.textTheme.titleSmall!.copyWith(color: t.accent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.md,
            runSpacing: Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StateChip(view.state),
              Text(detail, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
