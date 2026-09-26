import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/telemetry_data.dart';

class BleService {
  static const String serviceUuidStr = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String txCharUuidStr   = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String rxCharUuidStr   = "828919fe-e41c-40ee-b4c6-2c974c2d3345";

  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _deviceStateSubscription;
  StreamSubscription? _valueSubscription;

  final StreamController<TelemetryData> _telemetryStreamController = StreamController<TelemetryData>.broadcast();
  Stream<TelemetryData> get telemetryStream => _telemetryStreamController.stream;

  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionStateController.stream;

  bool _isConnecting = false;

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
          if (devName.contains("Honda-CL250")) {
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
              }
            });

            await _targetDevice!.connect(autoConnect: false);

            List<BluetoothService> services = await _targetDevice!.discoverServices();
            for (var service in services) {
              if (service.uuid.toString().toLowerCase() == serviceUuidStr.toLowerCase()) {
                for (var characteristic in service.characteristics) {
                  if (characteristic.uuid.toString().toLowerCase() == txCharUuidStr.toLowerCase()) {
                    await _valueSubscription?.cancel();
                    
                    // Listen to notifications
                    _valueSubscription = characteristic.lastValueStream.listen((value) {
                      if (value.isNotEmpty) {
                        final data = TelemetryData.fromBinaryBuffer(Uint8List.fromList(value));
                        _telemetryStreamController.add(data);
                      }
                    }, onError: (err) {
                      debugPrint("BLE value stream error: $err");
                    });

                    await characteristic.setNotifyValue(true);
                  }
                  if (characteristic.uuid.toString().toLowerCase() == rxCharUuidStr.toLowerCase()) {
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
    await _deviceStateSubscription?.cancel();
    if (_targetDevice != null) {
      await _targetDevice!.disconnect();
      _targetDevice = null;
    }
    _connectionStateController.add(false);
  }
}

