import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import 'telemetry/link_status.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

/// Server-upload settings: base URL, API token, and the Wi-Fi-only upload
/// policy. Recording and sharing sessions never depend on any of this being
/// filled in -- only the "Upload" action in the sessions list does.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.store = const AppSettingsStore(), this.onSaved});

  final AppSettingsStore store;

  /// Called after the settings were saved (the shell uses it to refresh
  /// screens that depend on them, e.g. the upload action in Record).
  final VoidCallback? onSaved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _baseUrlCtrl = TextEditingController();
  final _apiTokenCtrl = TextEditingController();
  bool _uploadOnlyOnWifi = true;
  bool _loading = true;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _baseUrlCtrl.text = settings.serverBaseUrl ?? '';
      _apiTokenCtrl.text = settings.apiToken ?? '';
      _uploadOnlyOnWifi = settings.uploadOnlyOnWifi;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await widget.store.save(AppSettings(
      serverBaseUrl: _baseUrlCtrl.text.trim().isEmpty ? null : _baseUrlCtrl.text.trim(),
      apiToken: _apiTokenCtrl.text.trim().isEmpty ? null : _apiTokenCtrl.text.trim(),
      uploadOnlyOnWifi: _uploadOnlyOnWifi,
    ));
    widget.onSaved?.call();
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved.')),
    );
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiTokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.moto;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('moto-server upload'),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _baseUrlCtrl,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Server base URL',
                            hintText: 'https://moto-server.example.com',
                          ),
                          onChanged: (_) => setState(() => _saved = false),
                        ),
                        const SizedBox(height: Spacing.md),
                        TextField(
                          controller: _apiTokenCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'API token'),
                          onChanged: (_) => setState(() => _saved = false),
                        ),
                        const SizedBox(height: Spacing.sm),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Upload only on Wi-Fi', style: theme.textTheme.titleSmall),
                          subtitle: Text(
                            'Session archives can be several MB; avoid mobile data by default.',
                            style: theme.textTheme.bodySmall,
                          ),
                          value: _uploadOnlyOnWifi,
                          onChanged: (v) => setState(() {
                            _uploadOnlyOnWifi = v;
                            _saved = false;
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  if (isCleartextRemoteUrl(_baseUrlCtrl.text))
                    const Padding(
                      padding: EdgeInsets.only(bottom: Spacing.md),
                      child: InfoBanner(
                        icon: Icons.warning_amber_rounded,
                        tone: Tone.warn,
                        text: 'Warning: http:// sends the API token and ride data unencrypted. Use it only '
                            'on a trusted local network; use https:// for any server reachable from outside.',
                      ),
                    ),
                  if (_baseUrlCtrl.text.trim().isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.md),
                      child: Text(
                        'No server configured yet: recording and sharing sessions work fully without '
                        'this. Set a URL here to enable the Upload action in the sessions list.',
                        style: theme.textTheme.bodySmall!.copyWith(color: t.textSecondary),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: _save,
                    child: Text(_saved ? 'Saved' : 'Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
