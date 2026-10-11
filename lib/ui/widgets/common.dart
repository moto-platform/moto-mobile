import 'package:flutter/material.dart';

import '../telemetry/link_status.dart';
import '../telemetry/signal_view.dart';
import '../theme/app_theme.dart';

/// Colour of a signal state (tokens only).
Color stateColor(BuildContext context, SignalState state) {
  final t = context.moto;
  return switch (state) {
    SignalState.live => t.live,
    SignalState.stale => t.stale,
    SignalState.noData => t.noData,
    SignalState.notPolled => t.notPolled,
  };
}

/// Short upper-case label of a signal state. State is always conveyed by
/// text and icon as well as colour.
String stateLabel(SignalState state) => switch (state) {
      SignalState.live => 'LIVE',
      SignalState.stale => 'STALE',
      SignalState.noData => 'NO DATA',
      SignalState.notPolled => 'NOT POLLED',
    };

IconData stateIcon(SignalState state) => switch (state) {
      SignalState.live => Icons.circle,
      SignalState.stale => Icons.schedule,
      SignalState.noData => Icons.remove_circle_outline,
      SignalState.notPolled => Icons.do_not_disturb_on_outlined,
    };

/// Upper-case caption above a block of content.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Surface card with the standard padding.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.lg),
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final t = context.moto;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: borderColor ?? t.outline, width: borderColor == null ? 1 : 2),
      ),
      // Transparent Material so ink effects of list tiles / switches inside
      // the card paint above the card background.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

Color toneColor(BuildContext context, Tone tone) {
  final t = context.moto;
  return switch (tone) {
    Tone.ok => t.live,
    Tone.warn => t.stale,
    Tone.error => t.error,
    Tone.neutral => t.noData,
    Tone.accent => t.accent,
  };
}

/// Compact status chip: icon + text, tinted by [tone].
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.icon, required this.label, this.tone = Tone.neutral});

  final IconData icon;
  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium!.copyWith(color: context.moto.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width message box (warnings, errors, notes).
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.text, this.tone = Tone.warn, this.title});

  final IconData icon;
  final String text;
  final String? title;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: theme.textTheme.titleSmall!.copyWith(color: color)),
                Text(text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// State chip of a signal: dot/icon + text, never colour alone.
class StateChip extends StatelessWidget {
  const StateChip(this.state, {super.key});

  final SignalState state;

  @override
  Widget build(BuildContext context) {
    final color = stateColor(context, state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stateIcon(state), size: state == SignalState.live ? 10 : 14, color: color),
          const SizedBox(width: Spacing.xs + 2),
          Text(
            stateLabel(state),
            style: Theme.of(context).textTheme.labelSmall!.copyWith(color: color, letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}

/// Label on the left, value on the right; wraps instead of overflowing.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Text(label, style: theme.textTheme.bodyMedium!.copyWith(color: context.moto.textSecondary)),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              flex: 6,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: theme.textTheme.titleSmall!.copyWith(color: valueColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A big-numeral tile for one catalog signal (label, value, unit, state).
class SignalTile extends StatelessWidget {
  const SignalTile({super.key, required this.view, this.valueStyle, this.showBar = false});

  final SignalView view;

  /// Defaults to `textTheme.displaySmall`.
  final TextStyle? valueStyle;

  /// Show a catalog-range bar under the value (live only).
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.moto;
    final live = view.isLive;
    final color = live ? t.textPrimary : stateColor(context, view.state);
    final style = (valueStyle ?? theme.textTheme.displaySmall!).copyWith(color: color);
    final fraction = view.fraction;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(view.label.toUpperCase(), style: theme.textTheme.labelSmall)),
              if (!live) Icon(stateIcon(view.state), size: 16, color: stateColor(context, view.state)),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(view.valueText, style: style),
                const SizedBox(width: Spacing.sm),
                Text(view.unitText, style: theme.textTheme.titleMedium!.copyWith(color: t.accent)),
              ],
            ),
          ),
          if (showBar) ...[
            const SizedBox(height: Spacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.chip),
              child: LinearProgressIndicator(
                value: fraction ?? 0,
                minHeight: 8,
                backgroundColor: t.surfaceRaised,
                color: t.accent,
              ),
            ),
          ],
          if (!live) ...[
            const SizedBox(height: Spacing.sm),
            Text(stateLabel(view.state), style: theme.textTheme.labelSmall!.copyWith(color: color)),
          ],
        ],
      ),
    );
  }
}
