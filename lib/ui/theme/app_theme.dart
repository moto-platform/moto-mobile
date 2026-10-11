import 'package:flutter/material.dart';

/// Spacing scale (logical pixels). Screens use these instead of literals.
abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Minimum interactive size (Material / WCAG touch target).
  static const double touchTarget = 48;
}

/// Corner radii.
abstract final class Radii {
  static const double chip = 8;
  static const double card = 16;
  static const double hero = 20;
}

/// Colour tokens of the app. One place; screens read them through
/// `context.moto` and never hard-code a colour.
///
/// Palette: near-black surfaces, one saturated accent (cyan), and semantic
/// colours for signal/link state. Text colours keep high contrast on the
/// surfaces so the display stays readable in direct sunlight.
@immutable
class MotoTokens extends ThemeExtension<MotoTokens> {
  const MotoTokens({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.live,
    required this.stale,
    required this.noData,
    required this.notPolled,
    required this.error,
    required this.record,
  });

  /// Screen background (near-black).
  final Color background;

  /// Card / tile surface.
  final Color surface;

  /// Raised surface (inputs, chips, selected rows).
  final Color surfaceRaised;

  /// Hairline borders and dividers.
  final Color outline;
  final Color textPrimary;
  final Color textSecondary;

  /// The single accent colour (selection, primary actions).
  final Color accent;
  final Color onAccent;

  /// Signal / link states.
  final Color live;
  final Color stale;
  final Color noData;
  final Color notPolled;
  final Color error;

  /// Recording indicator / record action.
  final Color record;

  /// Warning tone for caution banners (same hue as [stale]).
  Color get warning => stale;

  static const MotoTokens dark = MotoTokens(
    background: Color(0xFF050607),
    surface: Color(0xFF101318),
    surfaceRaised: Color(0xFF1A1E25),
    outline: Color(0xFF2E343E),
    textPrimary: Color(0xFFF7F9FC),
    textSecondary: Color(0xFFB7C0CC),
    accent: Color(0xFF19D3FF),
    onAccent: Color(0xFF00141A),
    live: Color(0xFF3DF07A),
    stale: Color(0xFFFFB82E),
    noData: Color(0xFF9AA4B2),
    notPolled: Color(0xFF8C9CC8),
    error: Color(0xFFFF5468),
    record: Color(0xFFFF3B4E),
  );

  @override
  MotoTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? outline,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? live,
    Color? stale,
    Color? noData,
    Color? notPolled,
    Color? error,
    Color? record,
  }) {
    return MotoTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      outline: outline ?? this.outline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      live: live ?? this.live,
      stale: stale ?? this.stale,
      noData: noData ?? this.noData,
      notPolled: notPolled ?? this.notPolled,
      error: error ?? this.error,
      record: record ?? this.record,
    );
  }

  @override
  MotoTokens lerp(ThemeExtension<MotoTokens>? other, double t) {
    if (other is! MotoTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return MotoTokens(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      outline: mix(outline, other.outline),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      live: mix(live, other.live),
      stale: mix(stale, other.stale),
      noData: mix(noData, other.noData),
      notPolled: mix(notPolled, other.notPolled),
      error: mix(error, other.error),
      record: mix(record, other.record),
    );
  }
}

/// `context.moto` -> the active [MotoTokens].
extension MotoThemeContext on BuildContext {
  MotoTokens get moto => Theme.of(this).extension<MotoTokens>() ?? MotoTokens.dark;
}

/// Tabular (fixed-width) numerals so changing values do not jitter.
const List<FontFeature> _tabular = <FontFeature>[FontFeature.tabularFigures()];

TextTheme _buildTextTheme(MotoTokens t) {
  TextStyle s(double size, FontWeight w, {Color? color, double? height, double? letterSpacing}) => TextStyle(
        fontSize: size,
        fontWeight: w,
        color: color ?? t.textPrimary,
        height: height,
        letterSpacing: letterSpacing,
        fontFeatures: _tabular,
      );
  return TextTheme(
    // Hero numerals (speed).
    displayLarge: s(104, FontWeight.w800, height: 1.0, letterSpacing: -2),
    // Large numerals (RPM, throttle).
    displayMedium: s(56, FontWeight.w800, height: 1.05, letterSpacing: -1),
    // Tile numerals (coolant, battery).
    displaySmall: s(36, FontWeight.w700, height: 1.1),
    headlineMedium: s(26, FontWeight.w700),
    headlineSmall: s(22, FontWeight.w700),
    titleLarge: s(22, FontWeight.w700),
    titleMedium: s(17, FontWeight.w600),
    titleSmall: s(15, FontWeight.w600),
    bodyLarge: s(16, FontWeight.w400, height: 1.35),
    bodyMedium: s(14, FontWeight.w400, height: 1.35),
    bodySmall: s(12.5, FontWeight.w400, color: t.textSecondary, height: 1.3),
    labelLarge: s(15, FontWeight.w700, letterSpacing: 0.3),
    labelMedium: s(13, FontWeight.w600, color: t.textSecondary, letterSpacing: 0.4),
    // Upper-case section captions.
    labelSmall: s(12, FontWeight.w700, color: t.textSecondary, letterSpacing: 1.1),
  );
}

/// The app theme: dark, high contrast, Material 3.
ThemeData buildAppTheme() {
  const t = MotoTokens.dark;
  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: t.accent,
    onPrimary: t.onAccent,
    secondary: t.accent,
    onSecondary: t.onAccent,
    error: t.error,
    onError: t.onAccent,
    surface: t.surface,
    onSurface: t.textPrimary,
    onSurfaceVariant: t.textSecondary,
    outline: t.outline,
    outlineVariant: t.outline,
    surfaceContainerLowest: t.background,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.surfaceRaised,
    surfaceContainerHighest: t.surfaceRaised,
  );
  final textTheme = _buildTextTheme(t);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.chip));
  const minButton = Size(64, Spacing.touchTarget);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.background,
    canvasColor: t.background,
    textTheme: textTheme,
    extensions: const <ThemeExtension<dynamic>>[t],
    appBarTheme: AppBarTheme(
      backgroundColor: t.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      foregroundColor: t.textPrimary,
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: t.outline),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.outline, thickness: 1, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.accent,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? t.onAccent : t.textSecondary, size: 26);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium!.copyWith(
          color: selected ? t.textPrimary : t.textSecondary,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: minButton,
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        textStyle: textTheme.labelLarge,
        shape: shape,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: minButton,
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        elevation: 0,
        textStyle: textTheme.labelLarge,
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minButton,
        foregroundColor: t.textPrimary,
        side: BorderSide(color: t.textSecondary),
        textStyle: textTheme.labelLarge,
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: minButton,
        foregroundColor: t.accent,
        textStyle: textTheme.labelLarge,
        shape: shape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(Spacing.touchTarget, Spacing.touchTarget),
        foregroundColor: t.textPrimary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surfaceRaised,
      labelStyle: textTheme.bodyMedium!.copyWith(color: t.textSecondary),
      hintStyle: textTheme.bodyMedium!.copyWith(color: t.noData),
      contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
        borderSide: BorderSide(color: t.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
        borderSide: BorderSide(color: t.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
        borderSide: BorderSide(color: t.accent, width: 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.onAccent : t.textSecondary),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.accent : t.surfaceRaised),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.accent : t.textSecondary),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.accent,
      unselectedLabelColor: t.textSecondary,
      indicatorColor: t.accent,
      dividerColor: t.outline,
      labelStyle: textTheme.labelLarge,
      unselectedLabelStyle: textTheme.labelLarge,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: minButton,
        backgroundColor: t.surface,
        foregroundColor: t.textPrimary,
        selectedBackgroundColor: t.accent,
        selectedForegroundColor: t.onAccent,
        side: BorderSide(color: t.outline),
        textStyle: textTheme.labelLarge,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.surfaceRaised,
      contentTextStyle: textTheme.bodyMedium,
      actionTextColor: t.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
        side: BorderSide(color: t.outline),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearTrackColor: t.surfaceRaised,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.textSecondary,
      textColor: t.textPrimary,
      minVerticalPadding: Spacing.sm,
    ),
  );
}
