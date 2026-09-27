import 'package:shared_preferences/shared_preferences.dart';

/// App-wide settings for talking to moto-server: where it is, how to
/// authenticate, and whether uploads should wait for Wi-Fi. Persisted with
/// shared_preferences so they survive app restarts.
class AppSettings {
  const AppSettings({
    this.serverBaseUrl,
    this.apiToken,
    this.uploadOnlyOnWifi = true,
  });

  /// e.g. `https://moto-server.example.com`. `null`/empty means "no server
  /// configured yet" -- uploads are disabled in the UI in that case, but
  /// recording and sharing sessions locally keep working regardless.
  final String? serverBaseUrl;

  final String? apiToken;

  /// Default on: avoid uploading a multi-megabyte session archive over a
  /// mobile data connection without the rider asking for it.
  final bool uploadOnlyOnWifi;

  bool get isServerConfigured => serverBaseUrl != null && serverBaseUrl!.trim().isNotEmpty;

  AppSettings copyWith({
    String? serverBaseUrl,
    String? apiToken,
    bool? uploadOnlyOnWifi,
  }) =>
      AppSettings(
        serverBaseUrl: serverBaseUrl ?? this.serverBaseUrl,
        apiToken: apiToken ?? this.apiToken,
        uploadOnlyOnWifi: uploadOnlyOnWifi ?? this.uploadOnlyOnWifi,
      );
}

/// Reads and writes [AppSettings] from shared_preferences.
class AppSettingsStore {
  const AppSettingsStore();

  static const String _keyServerBaseUrl = 'settings.server_base_url';
  static const String _keyApiToken = 'settings.api_token';
  static const String _keyUploadOnlyOnWifi = 'settings.upload_only_on_wifi';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_keyServerBaseUrl);
    final token = prefs.getString(_keyApiToken);
    return AppSettings(
      serverBaseUrl: (baseUrl == null || baseUrl.isEmpty) ? null : baseUrl,
      apiToken: (token == null || token.isEmpty) ? null : token,
      uploadOnlyOnWifi: prefs.getBool(_keyUploadOnlyOnWifi) ?? true,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = settings.serverBaseUrl?.trim() ?? '';
    final token = settings.apiToken?.trim() ?? '';

    if (baseUrl.isEmpty) {
      await prefs.remove(_keyServerBaseUrl);
    } else {
      await prefs.setString(_keyServerBaseUrl, baseUrl);
    }

    if (token.isEmpty) {
      await prefs.remove(_keyApiToken);
    } else {
      await prefs.setString(_keyApiToken, token);
    }

    await prefs.setBool(_keyUploadOnlyOnWifi, settings.uploadOnlyOnWifi);
  }
}
