import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:moto_defs/moto_defs.dart';
import '../models/telemetry_data.dart';

/// BLE client. GATT UUIDs and the requested ATT MTU come from the generated
/// [BleGatt] (moto-vehicle-defs `ble/ble_schema.json`, D-061); nothing about
/// the GATT layout is hand-written here.
class BleService {
  /// Advertised-name prefix of the vehicle's BLE server. Exposed so callers
  /// (e.g. session metadata) can reference the same constant instead of
  /// hand-copying the literal. Not part of the BLE schema (a scan filter, not
  /// a layout fact).
  static const String targetDeviceNamePrefix = "Honda-CL250";

  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _deviceStateSubscription;
  StreamSubscription? _valueSubscription;
  StreamSubscription? _imuValueSubscription;
  StreamSubscription<int>? _mtuSubscription;

  final StreamController<TelemetryData> _telemetryStreamController = StreamController<TelemetryData>.broadcast();
  Stream<TelemetryData> get telemetryStream => _telemetryStreamController.stream;

  /// Every raw BLE notification payload, before decoding. Used by the ride
  /// session recorder to keep a re-decodable record (raw_hex) and to
  /// classify decode errors independently of [telemetryStream].
  final StreamController<Uint8List> _rawPacketStreamController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get rawPacketStream => _rawPacketStreamController.stream;

  /// Every raw IMU block notification payload, before decoding. Old
  /// firmware has no `imu` characteristic at all, so this stream may simply
  /// never emit for such a connection -- that is not itself an error.
  final StreamController<Uint8List> _rawImuBlockStreamController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get rawImuBlockStream => _rawImuBlockStreamController.stream;

  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionStateController.stream;

  /// Negotiated ATT MTU, updated after [requestMtu] (Android) or whenever
  /// the platform reports a change (`device.mtu` in flutter_blue_plus).
  /// `null` before any connection has been made.
  final StreamController<int> _mtuStreamController = StreamController<int>.broadcast();
  Stream<int> get mtuStream => _mtuStreamController.stream;
  int? _negotiatedMtu;
  int? get negotiatedMtu => _negotiatedMtu;

  bool _isConnecting = false;

  /// Name of the currently connected device, if any and if known.
  String? get connectedDeviceName {
    final device = _targetDevice;
    if (device == null) return null;
    if (device.platformName.isNotEmpty) return device.platformName;
    if (device.advName.isNotEmpty) return device.advName;
    return null;
  }

  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    return statuses[Permission.bluetoothScan] != PermissionStatus.denied &&
           statuses[Permission.bluetoothConnect] != PermissionStatus.denied;
  }

  Future<void> connectToBike() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      await _requestPermissions();

      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();

      // Start scanning for Honda CL250 BLE server
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          final devName = r.device.platformName.isNotEmpty ? r.device.platformName : r.device.advName;
          if (devName.contains(targetDeviceNamePrefix)) {
            await _scanSubscription?.cancel();
            _scanSubscription = null;
            await FlutterBluePlus.stopScan();

            _targetDevice = r.device;

            // Monitor device connection state changes
            await _deviceStateSubscription?.cancel();
            _deviceStateSubscription = _targetDevice!.connectionState.listen((state) {
              final isConn = (state == BluetoothConnectionState.connected);
              _connectionStateController.add(isConn);
              if (!isConn) {
                _valueSubscription?.cancel();
                _imuValueSubscription?.cancel();
                _mtuSubscription?.cancel();
              }
            });

            await _targetDevice!.connect(autoConnect: false);

            // Track the negotiated MTU (flutter_blue_plus seeds this stream
            // with the current value immediately on listen, so this also
            // captures iOS's automatic negotiation).
            await _mtuSubscription?.cancel();
            _mtuSubscription = _targetDevice!.mtu.listen((mtu) {
              _negotiatedMtu = mtu;
              _mtuStreamController.add(mtu);
            }, onError: (err) {
              debugPrint("BLE mtu stream error: $err");
            });

            // Android only: request a larger MTU so the firmware can send
            // the full-size telemetry layout (version 3 or 4) and full-size
            // IMU blocks instead of falling back to version 2 / suspending
            // IMU notifications (schema `gatt.mtu.rule`). iOS negotiates its
            // own MTU and has no equivalent API, so this is a no-op there.
            if (!kIsWeb && Platform.isAndroid) {
              try {
                await _targetDevice!.requestMtu(BleGatt.requestedMtu);
              } catch (e) {
                debugPrint("BLE requestMtu error: $e");
              }
            }

            List<BluetoothService> services = await _targetDevice!.discoverServices();
            for (var service in services) {
              if (service.uuid.toString().toLowerCase() == BleGatt.serviceUuid.toLowerCase()) {
                for (var characteristic in service.characteristics) {
                  if (characteristic.uuid.toString().toLowerCase() == BleGatt.telemetryCharacteristicUuid.toLowerCase()) {
                    await _valueSubscription?.cancel();

                    // Listen to notifications
                    _valueSubscription = characteristic.lastValueStream.listen((value) {
                      if (value.isNotEmpty) {
                        final bytes = Uint8List.fromList(value);
                        _rawPacketStreamController.add(bytes);
                        final data = TelemetryData.fromBinaryBuffer(bytes);
                        _telemetryStreamController.add(data);
                      }
                    }, onError: (err) {
                      debugPrint("BLE value stream error: $err");
                    });

                    await characteristic.setNotifyValue(true);
                  }
                  if (characteristic.uuid.toString().toLowerCase() == BleGatt.imuCharacteristicUuid.toLowerCase()) {
                    // Old firmware does not expose this characteristic at
                    // all; it simply never appears in this loop, and
                    // rawImuBlockStream then just never emits.
                    await _imuValueSubscription?.cancel();

                    _imuValueSubscription = characteristic.lastValueStream.listen((value) {
                      if (value.isNotEmpty) {
                        _rawImuBlockStreamController.add(Uint8List.fromList(value));
                      }
                    }, onError: (err) {
                      debugPrint("BLE IMU value stream error: $err");
                    });

                    await characteristic.setNotifyValue(true);
                  }
                  if (characteristic.uuid.toString().toLowerCase() == BleGatt.telematicsRxCharacteristicUuid.toLowerCase()) {
                    _rxCharacteristic = characteristic;
                  }
                }
              }
            }
            break;
          }
        }
      });
    } catch (e) {
      debugPrint("BLE connect error: $e");
      _connectionStateController.add(false);
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> syncTelematics(String songTitle, String artistName, int navDist) async {
    if (_rxCharacteristic != null && _targetDevice != null) {
      try {
        final payload = "SONG:$songTitle|ARTIST:$artistName|DIST:$navDist|ICON:1";
        await _rxCharacteristic!.write(payload.codeUnits, withoutResponse: true);
      } catch (e) {
        debugPrint("BLE sync write error: $e");
      }
    }
  }

  Future<void> disconnect() async {
    await _scanSubscription?.cancel();
    await _valueSubscription?.cancel();
    await _imuValueSubscription?.cancel();
    await _mtuSubscription?.cancel();
    await _deviceStateSubscription?.cancel();
    if (_targetDevice != null) {
      await _targetDevice!.disconnect();
      _targetDevice = null;
    }
    _negotiatedMtu = null;
    _connectionStateController.add(false);
  }
}

