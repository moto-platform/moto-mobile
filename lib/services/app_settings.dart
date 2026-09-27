import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide settings for talking to moto-server: where it is, how to
/// authenticate, and whether uploads should wait for Wi-Fi. The URL and the
/// Wi-Fi switch live in shared_preferences; the API token lives in the
/// platform keystore (see [SecretStore]).
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

  /// True when the configured URL is plain `http://` to a host other than the
  /// phone itself: the bearer token would cross the network unencrypted. Allowed
  /// (a workshop laptop on the local Wi-Fi is the common case) but warned about.
  bool get sendsTokenInCleartext => isCleartextRemoteUrl(serverBaseUrl);

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

/// True for an `http://` URL whose host is not the phone itself.
bool isCleartextRemoteUrl(String? url) {
  final uri = Uri.tryParse(url?.trim() ?? '');
  if (uri == null || uri.scheme.toLowerCase() != 'http') return false;
  const local = {'localhost', '127.0.0.1', '::1'};
  return !local.contains(uri.host.toLowerCase());
}

/// Minimal key/value secret storage, injectable so tests do not need the
/// platform keystore.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore / iOS Keychain backed [SecretStore].
class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Reads and writes [AppSettings]: URL and Wi-Fi switch in shared_preferences,
/// the API token in a [SecretStore] (never in plain shared_preferences).
class AppSettingsStore {
  const AppSettingsStore({this.secrets = const PlatformSecretStore()});

  final SecretStore secrets;

  static const String _keyServerBaseUrl = 'settings.server_base_url';
  static const String _keyApiToken = 'settings.api_token';
  static const String _keyUploadOnlyOnWifi = 'settings.upload_only_on_wifi';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_keyServerBaseUrl);
    var token = await secrets.read(_keyApiToken);
    // Builds before the keystore move kept the token in shared_preferences:
    // move it once, then remove the plain copy.
    final legacyToken = prefs.getString(_keyApiToken);
    if (legacyToken != null) {
      if ((token == null || token.isEmpty) && legacyToken.isNotEmpty) {
        await secrets.write(_keyApiToken, legacyToken);
        token = legacyToken;
      }
      await prefs.remove(_keyApiToken);
    }
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
      await secrets.delete(_keyApiToken);
    } else {
      await secrets.write(_keyApiToken, token);
    }
    await prefs.remove(_keyApiToken); // never keep a plain copy

    await prefs.setBool(_keyUploadOnlyOnWifi, settings.uploadOnlyOnWifi);
  }
}
