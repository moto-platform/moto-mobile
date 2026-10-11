import 'package:flutter/material.dart';

import '../services/ble_service.dart';
import 'diagnostics_screen.dart';
import 'live_screen.dart';
import 'record_screen.dart';
import 'settings_screen.dart';
import 'signals_screen.dart';
import 'telemetry/telemetry_store.dart';

/// Top-level destinations, in navigation-bar order.
enum ShellTab { live, signals, record, diagnostics, settings }

/// Navigation shell: a Material 3 NavigationBar over the five destinations.
///
/// Record and Settings keep their state once opened (an active recording and
/// unsaved form input must survive tab switches); the telemetry screens are
/// rebuilt on demand because their state lives in the [TelemetryStore].
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.bleService, this.store});

  final BleService bleService;

  /// Optional store for tests. When null the shell creates one and attaches
  /// it to [bleService].
  final TelemetryStore? store;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final TelemetryStore _store;
  late final bool _ownsStore;
  /// Bumped when the Settings destination saves; Record listens to refresh.
  final ValueNotifier<int> _settingsChanged = ValueNotifier<int>(0);
  ShellTab _tab = ShellTab.live;
  final Set<ShellTab> _visited = {ShellTab.live};

  @override
  void initState() {
    super.initState();
    final provided = widget.store;
    _ownsStore = provided == null;
    _store = provided ?? (TelemetryStore()..attach(widget.bleService));
  }

  @override
  void dispose() {
    if (_ownsStore) _store.dispose();
    _settingsChanged.dispose();
    super.dispose();
  }

  void _select(ShellTab tab) {
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
  }

  Widget _build(ShellTab tab) {
    switch (tab) {
      case ShellTab.live:
        return LiveScreen(
          store: _store,
          bleService: widget.bleService,
          onOpenRecord: () => _select(ShellTab.record),
        );
      case ShellTab.signals:
        return SignalsScreen(store: _store);
      case ShellTab.record:
        return RecordScreen(
          bleService: widget.bleService,
          initiallyConnected: _store.connected,
          settingsChanged: _settingsChanged,
        );
      case ShellTab.diagnostics:
        return DiagnosticsScreen(store: _store);
      case ShellTab.settings:
        return SettingsScreen(onSaved: () => _settingsChanged.value++);
    }
  }

  /// Tabs whose state must outlive a tab switch once they were opened.
  bool _keepAlive(ShellTab tab) => tab == ShellTab.record || tab == ShellTab.settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab.index,
        children: [
          for (final tab in ShellTab.values)
            if (tab == _tab || (_keepAlive(tab) && _visited.contains(tab)))
              KeyedSubtree(key: ValueKey(tab), child: _build(tab))
            else
              const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (i) => _select(ShellTab.values[i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors),
            label: 'Signals',
          ),
          NavigationDestination(
            icon: Icon(Icons.fiber_manual_record_outlined),
            selectedIcon: Icon(Icons.fiber_manual_record),
            label: 'Record',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Diagnostics',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
