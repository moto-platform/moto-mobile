import 'package:connectivity_plus/connectivity_plus.dart';

/// Abstraction over "is this device currently on Wi-Fi", so the upload
/// gate does not hard-depend on one specific connectivity package or on a
/// real platform channel in tests.
///
/// TODO(D-023 follow-up): if `connectivity_plus` ever needs to be dropped
/// (e.g. it becomes unavailable offline again), only
/// [ConnectivityPlusNetworkInfo] needs to change -- callers depend on this
/// interface, not the package.
abstract class NetworkInfo {
  /// `true` on Wi-Fi, `false` when known to be on something else (mobile
  /// data, none), `null` when it could not be determined. Callers that care
  /// about a strict Wi-Fi-only policy should treat `null` as "not on
  /// Wi-Fi" -- see [AppSettings.uploadOnlyOnWifi] handling in the uploader.
  Future<bool?> get isOnWifi;
}

class ConnectivityPlusNetworkInfo implements NetworkInfo {
  ConnectivityPlusNetworkInfo({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool?> get isOnWifi async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.wifi);
    } catch (_) {
      // Platform channel unavailable (e.g. running on an unsupported host,
      // or in a test with no plugin registered): unknown, not "not on Wi-Fi".
      return null;
    }
  }
}
