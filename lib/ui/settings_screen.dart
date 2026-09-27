import 'package:flutter/material.dart';

import '../services/app_settings.dart';

/// Server-upload settings: base URL, API token, and the Wi-Fi-only upload
/// policy. Recording and sharing sessions never depend on any of this being
/// filled in -- only the "Upload" action in the sessions list does.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.store = const AppSettingsStore()});

  final AppSettingsStore store;

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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MOTO-SERVER UPLOAD', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baseUrlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Server base URL',
                      hintText: 'https://moto-server.example.com',
                    ),
                    onChanged: (_) => setState(() => _saved = false),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiTokenCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'API token'),
                    onChanged: (_) => setState(() => _saved = false),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Upload only on Wi-Fi'),
                    subtitle: const Text('Session archives can be several MB; avoid mobile data by default.'),
                    value: _uploadOnlyOnWifi,
                    onChanged: (v) => setState(() {
                      _uploadOnlyOnWifi = v;
                      _saved = false;
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (_baseUrlCtrl.text.trim().isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'No server configured yet: recording and sharing sessions work fully without '
                        'this. Set a URL here to enable the Upload action in the sessions list.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _save,
                      child: Text(_saved ? 'Saved' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
