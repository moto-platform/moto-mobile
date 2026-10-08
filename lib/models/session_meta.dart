import 'package:moto_defs/moto_defs.dart';

import 'telemetry_data.dart' show TelemetryVersion;

/// App version string. Keep in sync with the `version:` field in
/// pubspec.yaml. Recorded in every session's meta.json so a CSV export can
/// always be traced back to the app build that produced it.
const String kAppVersion = '0.2.0+3'; // keep equal to pubspec.yaml

/// Metadata captured once per ride-recording session, per the
/// moto-vehicle-defs phase0 data-collection plan §3.2. Persisted verbatim as
/// `meta.json` alongside that session's `telemetry.csv` and `events.csv`.
///
/// Every numeric field is nullable: the rider may not know or may not want
/// to fill in every value before a ride, and a missing measurement should
/// never block recording telemetry.
class SessionMeta {
  /// `YYYYMMDD-HHMMSS-<4 random hex>` (UTC), stamped by
  /// [SessionRecorder.start] at the moment recording actually begins.
  final String sessionId;

  /// UTC ISO-8601 timestamp, stamped alongside [sessionId].
  final String createdUtc;

  final String? riderName;
  final double? riderWeightKg;
  final double? extraLoadKg;
  final double? ambientTempC;

  /// One of 'dry', 'wet', 'unknown'.
  final String weather;

  final double? tirePressureFrontBar;
  final double? tirePressureRearBar;

  /// Free text (e.g. "full", "1/2", "reserve").
  final String? fuelLevel;

  /// Free text describing non-stock configuration (gearing/exhaust/filter).
  final String? vehicleConfig;

  /// 'healthy' or a free-text fault description. Defaults to 'healthy'.
  final String conditionLabel;

  /// One of 'urban', 'rural', 'highway', 'closed_course', 'stationary'.
  final String? routeType;

  final String? note;

  final String appVersion;
  final int bleSchemaVersion;

  /// Connected BLE device/firmware name, when known at recording start.
  final String? deviceName;

  /// IMU block format version in use (schema `imuBlock.version`), or `null`
  /// if this app build predates the IMU block.
  final int? imuBlockVersion;

  /// GPS block format version this app decodes (schema `gpsBlock.version`,
  /// D-060), or `null` if this app build predates the GPS block.
  final int? gpsBlockVersion;

  /// ATT MTU requested right after connecting (schema `gatt.mtu.requested`),
  /// or `null` if this app build predates MTU negotiation.
  final int? requestedMtu;

  const SessionMeta({
    required this.sessionId,
    required this.createdUtc,
    this.riderName,
    this.riderWeightKg,
    this.extraLoadKg,
    this.ambientTempC,
    this.weather = 'unknown',
    this.tirePressureFrontBar,
    this.tirePressureRearBar,
    this.fuelLevel,
    this.vehicleConfig,
    this.conditionLabel = 'healthy',
    this.routeType,
    this.note,
    this.appVersion = kAppVersion,
    this.bleSchemaVersion = BleTelemetry.currentVersion,
    this.deviceName,
    this.imuBlockVersion = BleImuBlock.version,
    this.gpsBlockVersion = BleGpsBlock.version,
    this.requestedMtu,
  });

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'created_utc': createdUtc,
        'rider_name': riderName,
        'rider_weight_kg': riderWeightKg,
        'extra_load_kg': extraLoadKg,
        'ambient_temp_c': ambientTempC,
        'weather': weather,
        'tire_pressure_front_bar': tirePressureFrontBar,
        'tire_pressure_rear_bar': tirePressureRearBar,
        'fuel_level': fuelLevel,
        'vehicle_config': vehicleConfig,
        'condition_label': conditionLabel,
        'route_type': routeType,
        'note': note,
        'app_version': appVersion,
        'ble_schema_version': bleSchemaVersion,
        'device_name': deviceName,
        'imu_block_version': imuBlockVersion,
        'gps_block_version': gpsBlockVersion,
        'requested_mtu': requestedMtu,
      };

  factory SessionMeta.fromJson(Map<String, dynamic> json) => SessionMeta(
        sessionId: json['session_id'] as String,
        createdUtc: json['created_utc'] as String,
        riderName: json['rider_name'] as String?,
        riderWeightKg: (json['rider_weight_kg'] as num?)?.toDouble(),
        extraLoadKg: (json['extra_load_kg'] as num?)?.toDouble(),
        ambientTempC: (json['ambient_temp_c'] as num?)?.toDouble(),
        weather: json['weather'] as String? ?? 'unknown',
        tirePressureFrontBar: (json['tire_pressure_front_bar'] as num?)?.toDouble(),
        tirePressureRearBar: (json['tire_pressure_rear_bar'] as num?)?.toDouble(),
        fuelLevel: json['fuel_level'] as String?,
        vehicleConfig: json['vehicle_config'] as String?,
        conditionLabel: json['condition_label'] as String? ?? 'healthy',
        routeType: json['route_type'] as String?,
        note: json['note'] as String?,
        appVersion: json['app_version'] as String? ?? kAppVersion,
        bleSchemaVersion: json['ble_schema_version'] as int? ?? TelemetryVersion.v3,
        deviceName: json['device_name'] as String?,
        imuBlockVersion: json['imu_block_version'] as int?,
        gpsBlockVersion: json['gps_block_version'] as int?,
        requestedMtu: json['requested_mtu'] as int?,
      );

  SessionMeta copyWith({
    String? sessionId,
    String? createdUtc,
    String? riderName,
    double? riderWeightKg,
    double? extraLoadKg,
    double? ambientTempC,
    String? weather,
    double? tirePressureFrontBar,
    double? tirePressureRearBar,
    String? fuelLevel,
    String? vehicleConfig,
    String? conditionLabel,
    String? routeType,
    String? note,
    String? appVersion,
    int? bleSchemaVersion,
    String? deviceName,
    int? imuBlockVersion,
    int? gpsBlockVersion,
    int? requestedMtu,
  }) =>
      SessionMeta(
        sessionId: sessionId ?? this.sessionId,
        createdUtc: createdUtc ?? this.createdUtc,
        riderName: riderName ?? this.riderName,
        riderWeightKg: riderWeightKg ?? this.riderWeightKg,
        extraLoadKg: extraLoadKg ?? this.extraLoadKg,
        ambientTempC: ambientTempC ?? this.ambientTempC,
        weather: weather ?? this.weather,
        tirePressureFrontBar: tirePressureFrontBar ?? this.tirePressureFrontBar,
        tirePressureRearBar: tirePressureRearBar ?? this.tirePressureRearBar,
        fuelLevel: fuelLevel ?? this.fuelLevel,
        vehicleConfig: vehicleConfig ?? this.vehicleConfig,
        conditionLabel: conditionLabel ?? this.conditionLabel,
        routeType: routeType ?? this.routeType,
        note: note ?? this.note,
        appVersion: appVersion ?? this.appVersion,
        bleSchemaVersion: bleSchemaVersion ?? this.bleSchemaVersion,
        deviceName: deviceName ?? this.deviceName,
        imuBlockVersion: imuBlockVersion ?? this.imuBlockVersion,
        gpsBlockVersion: gpsBlockVersion ?? this.gpsBlockVersion,
        requestedMtu: requestedMtu ?? this.requestedMtu,
      );
}
