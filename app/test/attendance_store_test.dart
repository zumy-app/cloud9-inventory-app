// Attendance: whitebox (geofence math, store) + integration (Odoo RPCs).
import 'dart:convert';

import 'package:cloud9_inventory_app/attendance_store.dart';
import 'package:cloud9_inventory_app/odoo_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ---- Whitebox: geofence math ----
  test('whitebox: haversine is ~111km per degree and 0 for same point', () {
    expect(haversineMeters(40.0, -74.0, 40.0, -74.0), 0.0);
    final d = haversineMeters(40.0, -74.0, 41.0, -74.0);
    expect(d, closeTo(111195, 500));
  });

  test('whitebox: verdict blocks unset store, missing gps, outside', () {
    var v = geofenceVerdict(
      storeLat: null,
      storeLng: null,
      radiusM: 150,
      curLat: 40.0,
      curLng: -74.0,
      locationAvailable: true,
    );
    expect(v.allowed, isFalse);
    expect(v.reason, 'store_unset');

    v = geofenceVerdict(
      storeLat: 40.0,
      storeLng: -74.0,
      radiusM: 150,
      curLat: null,
      curLng: null,
      locationAvailable: false,
    );
    expect(v.allowed, isFalse);
    expect(v.reason, 'no_gps');

    v = geofenceVerdict(
      storeLat: 40.0,
      storeLng: -74.0,
      radiusM: 150,
      curLat: 41.0,
      curLng: -74.0,
      locationAvailable: true,
    );
    expect(v.allowed, isFalse);
    expect(v.reason, 'outside');
  });

  test('whitebox: verdict allows inside radius (boundary inclusive)', () {
    // ~111m north of the store, inside a 150m fence.
    final v = geofenceVerdict(
      storeLat: 40.0,
      storeLng: -74.0,
      radiusM: 150,
      curLat: 40.001,
      curLng: -74.0,
      locationAvailable: true,
    );
    expect(v.allowed, isTrue);
    expect(v.reason, 'inside');
  });

  test('whitebox: hours formatting', () {
    expect(AttendanceStore.fmtHours(0), '0h 0m');
    expect(AttendanceStore.fmtHours(8.5), '8h 30m');
    expect(AttendanceStore.totalHours([1.5, 2.25]), 3.75);
  });

  test('whitebox: store calibrate + radius persist', () async {
    final s = AttendanceStore.instance;
    await s.calibrate(40.1, -74.1);
    await s.setRadius(250);
    expect(s.isCalibrated, isTrue);
    expect(s.radiusM, 250);
    // Radius clamps to [50, 1000].
    await s.setRadius(5000);
    expect(s.radiusM, 1000);
    await s.setRadius(1);
    expect(s.radiusM, 50);
  });

  // ---- Integration: Odoo attendance RPCs ----
  MockClient mockAttendance() => MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final url = req.url.toString();
        if (url.contains('get_session_info')) {
          return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'result': {'uid': 7}
              }),
              200);
        }
        final params = body['params'] as Map<String, dynamic>;
        final model = params['model'];
        final method = params['method'];
        if (model == 'hr.employee') {
          return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'result': [
                  {'id': 3, 'name': 'Jane'}
                ]
              }),
              200);
        }
        if (model == 'hr.attendance' && method == 'search_read') {
          return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'result': [
                  {
                    'id': 11,
                    'check_in': '2026-10-24 08:00:00',
                    'check_out': false
                  }
                ]
              }),
              200);
        }
        if (model == 'hr.attendance' && method == 'create') {
          return http.Response(
              jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': 12}), 200);
        }
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': true}), 200);
      });

  test('integration: myEmployee resolves via session uid', () async {
    final c = OdooClient(baseUrl: 'https://x', httpClient: mockAttendance());
    final e = await c.myEmployee();
    expect(e.id, 3);
    expect(e.name, 'Jane');
  });

  test('integration: open attendance parses check_out=false as open',
      () async {
    // Open shift started 2h ago (relative — avoids TZ/date flakes).
    final twoH = DateTime.now().toUtc().subtract(const Duration(hours: 2));
    String p(int n) => n.toString().padLeft(2, '0');
    final ts =
        '${twoH.year}-${p(twoH.month)}-${p(twoH.day)} ${p(twoH.hour)}:${p(twoH.minute)}:00';
    final mock = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final url = req.url.toString();
      if (url.contains('get_session_info')) {
        return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'result': {'uid': 7}
            }),
            200);
      }
      return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'result': [
              {'id': 11, 'check_in': ts, 'check_out': false}
            ]
          }),
          200);
    });
    final c = OdooClient(baseUrl: 'https://x', httpClient: mock);
    final r = await c.openAttendance(3);
    expect(r, isNotNull);
    expect(r!.isOpen, isTrue);
    expect(r.hours(), closeTo(2.0, 0.05));
  });

  test('integration: record hours math on closed shift', () {
    const r = AttendanceRecord(
        id: 1,
        checkIn: '2026-10-24 08:00:00',
        checkOut: '2026-10-24 16:30:00');
    expect(r.isOpen, isFalse);
    expect(r.hours(), closeTo(8.5, 0.001));
  });

  test('integration: clockIn posts UTC timestamp, clockOut writes it',
      () async {
    final seen = <String>[];
    final mock = MockClient((req) async {
      seen.add(req.body);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final params = body['params'] as Map<String, dynamic>;
      if (params['model'] == 'hr.attendance' &&
          params['method'] == 'create') {
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': 12}), 200);
      }
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': true}), 200);
    });
    final c = OdooClient(baseUrl: 'https://x', httpClient: mock);
    final rec = await c.clockIn(3, at: DateTime.utc(2026, 10, 24, 8, 0, 0));
    expect(rec.id, 12);
    expect(rec.checkIn, '2026-10-24 08:00:00');
    await c.clockOut(12, at: DateTime.utc(2026, 10, 24, 16, 0, 0));
    expect(seen.join(), contains('2026-10-24 16:00:00'));
  });

  test('integration: missing Attendance app maps to ATTENDANCE_UNAVAILABLE',
      () async {
    final mock = MockClient((req) async {
      final url = req.url.toString();
      if (url.contains('get_session_info')) {
        return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'result': {'uid': 7}
            }),
            200);
      }
      return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'error': {
              'code': 200,
              'message': 'Odoo Server Error',
              'data': {'message': 'Model hr.employee does not exist'}
            }
          }),
          200);
    });
    final c = OdooClient(baseUrl: 'https://x', httpClient: mock);
    try {
      await c.myEmployee();
      fail('expected throw');
    } on OdooException catch (e) {
      expect(e.message, contains('ATTENDANCE_UNAVAILABLE'));
    }
  });
}
