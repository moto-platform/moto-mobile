import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/gps_block.dart';
import '../../models/telemetry_data.dart';
import '../../services/ble_service.dart';
import 'signal_view.dart';

/// Shared, read-only view of the live BLE state for every screen.
///
/// Subscribes once to the [BleService] streams (it does not change the
/// service) and republishes the latest connection state, telemetry packet,
/// MTU and GPS state as a [ChangeNotifier]. A 500 ms tick refreshes ages
/// when no packet arrives. Tests drive it through the `update*` methods
/// without a BLE stack.
class TelemetryStore extends ChangeNotifier {
  TelemetryStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  bool _connected = false;
  TelemetryData _data = TelemetryData.initial();
  DateTime? _lastPacketAt;
  int? _mtu;
  String? _deviceName;
  GpsLinkStatus _gpsLink = GpsLinkStatus.disconnected;
  GpsBlock? _lastGpsBlock;
  DateTime? _lastGpsAt;

  BleService? _ble;
  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _tick;
  bool _disposed = false;

  bool get connected => _connected;

  /// Newest decoded packet. `packetVersion == 0` means none received yet.
  TelemetryData get data => _data;
  bool get hasPacket => _data.packetVersion != 0;
  DateTime? get lastPacketAt => _lastPacketAt;
  int? get mtu => _mtu;
  String? get deviceName => _deviceName;
  GpsLinkStatus get gpsLink => _gpsLink;
  GpsBlock? get lastGpsBlock => _lastGpsBlock;

  /// Time since the newest valid telemetry packet, or null if none yet.
  Duration? get sinceLastPacket {
    final at = _lastPacketAt;
    return at == null ? null : _clock().difference(at);
  }

  /// Time since the newest GPS block, or null if none yet.
  Duration? get sinceLastGps {
    final at = _lastGpsAt;
    return at == null ? null : _clock().difference(at);
  }

  /// The catalog rendered against the newest packet.
  SignalSnapshot get snapshot => SignalSnapshot.from(
        _data,
        connected: _connected,
        sinceLastPacket: sinceLastPacket,
      );

  /// Starts listening to [ble]. Call once.
  void attach(BleService ble) {
    if (_ble != null) return;
    _ble = ble;
    _mtu = ble.negotiatedMtu;
    _gpsLink = ble.gpsLinkStatus;
    _subs.add(ble.connectionStream.listen((c) => updateConnection(c, deviceName: ble.connectedDeviceName)));
    _subs.add(ble.telemetryStream.listen((d) => updateTelemetry(d)));
    _subs.add(ble.mtuStream.listen(updateMtu));
    _subs.add(ble.gpsLinkStream.listen(updateGpsLink));
    _subs.add(ble.rawGpsBlockStream.listen(_onRawGps));
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _notify());
  }

  void updateConnection(bool connected, {String? deviceName}) {
    _connected = connected;
    _deviceName = connected ? deviceName : null;
    if (!connected) _lastGpsBlock = null;
    _notify();
  }

  /// A packet that failed to decode comes through as an empty
  /// `packetVersion == 0` record; it is ignored here (the rejected counters
  /// on the Diagnostics screen still show it) so one bad packet does not
  /// blank the display.
  void updateTelemetry(TelemetryData data, {DateTime? at}) {
    if (data.packetVersion == 0) {
      _notify();
      return;
    }
    _data = data;
    _lastPacketAt = at ?? _clock();
    _notify();
  }

  void updateMtu(int mtu) {
    _mtu = mtu;
    _notify();
  }

  void updateGpsLink(GpsLinkStatus status) {
    _gpsLink = status;
    _notify();
  }

  void updateGpsBlock(GpsBlock block, {DateTime? at}) {
    _lastGpsBlock = block;
    _lastGpsAt = at ?? _clock();
    _notify();
  }

  void _onRawGps(Uint8List bytes) {
    try {
      updateGpsBlock(GpsBlock.decode(bytes));
    } on GpsBlockDecodeException {
      // Malformed block: the recorder counts these; nothing to show.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }
}
