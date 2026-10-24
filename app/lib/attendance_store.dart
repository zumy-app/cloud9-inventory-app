// Attendance geofence: clock in/out only inside the store radius.
// Store location is calibrated on-device by a manager standing in the
// store ("Set store location here") — no hardcoded coordinates, no
// backend changes. All math is pure + unit-tested.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Haversine distance in meters. Pure — whitebox-tested.
double haversineMeters(
    double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  return 2 * r * asin(sqrt(a.clamp(0.0, 1.0)));
}

double _rad(double d) => d * pi / 180.0;

/// Geofence verdict used to gate clock in/out. Pure — whitebox-tested.
({bool allowed, String reason}) geofenceVerdict({
  required double? storeLat,
  required double? storeLng,
  required double radiusM,
  required double? curLat,
  required double? curLng,
  required bool locationAvailable,
}) {
  if (storeLat == null || storeLng == null) {
    return (allowed: false, reason: 'store_unset');
  }
  if (!locationAvailable || curLat == null || curLng == null) {
    return (allowed: false, reason: 'no_gps');
  }
  final d = haversineMeters(storeLat, storeLng, curLat, curLng);
  if (d <= radiusM) return (allowed: true, reason: 'inside');
  return (allowed: false, reason: 'outside');
}

class AttendanceStore extends ChangeNotifier {
  AttendanceStore._();
  static final AttendanceStore instance = AttendanceStore._();

  static const _kLat = 'store_lat';
  static const _kLng = 'store_lng';
  static const _kRadius = 'store_radius_m';
  static const double defaultRadiusM = 150;

  double? storeLat;
  double? storeLng;
  double radiusM = defaultRadiusM;

  bool get isCalibrated => storeLat != null && storeLng != null;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final la = p.getDouble(_kLat);
      final ln = p.getDouble(_kLng);
      if (la != null && ln != null) {
        storeLat = la;
        storeLng = ln;
      }
      radiusM = p.getDouble(_kRadius) ?? defaultRadiusM;
      notifyListeners();
    } catch (_) {}
  }

  /// Calibrate to the manager's current position (must be standing in store).
  Future<void> calibrate(double lat, double lng) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_kLat, lat);
      await p.setDouble(_kLng, lng);
    } catch (_) {}
    storeLat = lat;
    storeLng = lng;
    notifyListeners();
  }

  Future<void> setRadius(double m) async {
    final v = m.clamp(50.0, 1000.0);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_kRadius, v);
    } catch (_) {}
    radiusM = v;
    notifyListeners();
  }

  /// Sum worked hours across records (open record counts to now).
  static double totalHours(List<double> hoursList) =>
      hoursList.fold(0.0, (a, h) => a + h);

  static String fmtHours(double h) {
    final m = (h * 60).round();
    return '${m ~/ 60}h ${m % 60}m';
  }
}
