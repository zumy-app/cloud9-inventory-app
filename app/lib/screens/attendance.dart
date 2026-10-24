// Attendance: GPS-gated clock in/out + hours + history.
// Rule: buttons enable only inside the calibrated store geofence.
// Server truth is hr.attendance; failed writes never fake success.
library;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../attendance_store.dart';
import '../audit_log.dart';
import '../i18n/lang.dart';
import '../odoo_client.dart';
import '../widgets/feedback.dart';

class AttendanceScreen extends StatefulWidget {
  final OdooClient client;
  final String user;
  const AttendanceScreen({super.key, required this.client, this.user = ''});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _busy = false;
  String? _err;
  AttendanceEmployee? _employee;
  AttendanceRecord? _open;
  List<AttendanceRecord> _history = [];
  Position? _pos;
  bool _gpsAvailable = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AttendanceStore.instance.addListener(_refresh);
    _boot();
  }

  @override
  void dispose() {
    AttendanceStore.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    await AttendanceStore.instance.load();
    await _refreshGps();
    await _loadServer();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsAvailable = false);
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() {
          _pos = p;
          _gpsAvailable = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _gpsAvailable = false);
    }
  }

  Future<void> _loadServer() async {
    setState(() => _err = null);
    try {
      final emp = await widget.client.myEmployee();
      if (!mounted) return;
      setState(() => _employee = emp);
      final open = await widget.client.openAttendance(emp.id);
      if (!mounted) return;
      setState(() => _open = open);
      final hist = await widget.client.attendanceHistory(emp.id);
      if (!mounted) return;
      setState(() => _history = hist);
    } on OdooException catch (e) {
      if (!mounted) return;
      setState(() => _err = _friendlyAttendanceError(e.message));
    }
  }

  String _friendlyAttendanceError(String m) {
    if (m.startsWith('ATTENDANCE_UNAVAILABLE')) {
      return t('att_err_unavailable');
    }
    if (m == 'ATTENDANCE_NO_EMPLOYEE') return t('att_err_no_employee');
    if (m == 'SESSION_EXPIRED') return t('waste_err_session');
    return OdooException.friendly(m);
  }

  ({bool allowed, String reason}) get _verdict {
    final s = AttendanceStore.instance;
    return geofenceVerdict(
      storeLat: s.storeLat,
      storeLng: s.storeLng,
      radiusM: s.radiusM,
      curLat: _pos?.latitude,
      curLng: _pos?.longitude,
      locationAvailable: _gpsAvailable,
    );
  }

  double get _todayHours {
    final now = DateTime.now().toUtc();
    return _history
        .where((r) {
          final inn = AttendanceRecord.tryParseTs(r.checkIn);
          return inn != null &&
              inn.year == now.year &&
              inn.month == now.month &&
              inn.day == now.day;
        })
        .fold(0.0, (a, r) => a + r.hours());
  }

  double get _weekHours {
    final now = DateTime.now().toUtc();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime.utc(monday.year, monday.month, monday.day);
    return _history
        .where((r) {
          final inn = AttendanceRecord.tryParseTs(r.checkIn);
          return inn != null && !inn.isBefore(start);
        })
        .fold(0.0, (a, r) => a + r.hours());
  }

  Future<void> _clockIn() async {
    final emp = _employee;
    if (emp == null || _open != null) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final rec = await widget.client.clockIn(emp.id);
      if (!mounted) return;
      setState(() => _open = rec);
      AuditLog.instance.add(AuditEntry(
        when: DateTime.now(),
        who: widget.user,
        mode: 'attendance',
        productId: 0,
        productName: emp.name,
        field: 'clock-in',
        oldValue: '',
        newValue: rec.checkIn,
      ));
      await _loadServer();
      if (!mounted) return;
      showOk(context, t('att_in_ok'));
    } on OdooException catch (e) {
      if (!mounted) return;
      setState(() => _err = _friendlyAttendanceError(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clockOut() async {
    final rec = _open;
    if (rec == null) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.client.clockOut(rec.id);
      if (!mounted) return;
      setState(() => _open = null);
      AuditLog.instance.add(AuditEntry(
        when: DateTime.now(),
        who: widget.user,
        mode: 'attendance',
        productId: 0,
        productName: _employee?.name ?? '',
        field: 'clock-out',
        oldValue: rec.checkIn,
        newValue: 'now',
      ));
      await _loadServer();
      if (!mounted) return;
      showOk(context, t('att_out_ok'));
    } on OdooException catch (e) {
      if (!mounted) return;
      setState(() => _err = _friendlyAttendanceError(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _calibrate() async {
    final p = _pos;
    if (p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('att_cal_title')),
        content: Text(Lang.instance.f('att_cal_body', {
          'lat': p.latitude.toStringAsFixed(6),
          'lng': p.longitude.toStringAsFixed(6),
        })),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('waste_cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('att_cal_go'))),
        ],
      ),
    );
    if (ok == true) {
      await AttendanceStore.instance.calibrate(p.latitude, p.longitude);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AttendanceStore.instance;
    final v = _verdict;
    final clockedIn = _open != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('att_title')),
        backgroundColor: const Color(0xFF032561),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _boot),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _statusCard(store, v, clockedIn),
                const SizedBox(height: 12),
                // Real buttons (enabled only inside geofence):
                if (!clockedIn)
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700),
                      onPressed:
                          (_busy || !v.allowed || _employee == null || _open != null)
                              ? null
                              : _clockIn,
                      child: Text(t('att_clock_in'),
                          style: const TextStyle(fontSize: 18)),
                    ),
                  )
                else
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700),
                      onPressed:
                          (_busy || !v.allowed || _open == null) ? null : _clockOut,
                      child: Text(t('att_clock_out'),
                          style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                const SizedBox(height: 8),
                if (!v.allowed) _gateHint(v.reason),
                if (_err != null) ...[
                  const SizedBox(height: 8),
                  Text(_err!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 12),
                _hoursCard(),
                const SizedBox(height: 12),
                _storeCard(store),
                const SizedBox(height: 12),
                _historyCard(),
              ],
            ),
    );
  }

  Widget _statusCard(AttendanceStore store, ({bool allowed, String reason}) v,
      bool clockedIn) {
    return Card(
      child: ListTile(
        leading: Icon(
            clockedIn ? Icons.timer : Icons.timer_outlined,
            size: 36,
            color: clockedIn ? Colors.green : Colors.grey),
        title: Text(_employee?.name ?? t('att_no_employee')),
        subtitle: Text(clockedIn
            ? Lang.instance.f('att_since', {
                'at': _open?.checkIn ?? '',
              })
            : t('att_out_state')),
        trailing: _gpsAvailable
            ? const Icon(Icons.location_on, color: Colors.green)
            : const Icon(Icons.location_off, color: Colors.red),
      ),
    );
  }

  Widget _gateHint(String reason) {
    final msg = switch (reason) {
      'store_unset' => t('att_gate_unset'),
      'no_gps' => t('att_gate_nogps'),
      _ => t('att_gate_outside'),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
          TextButton(
              onPressed: _busy ? null : _refreshGps,
              child: Text(t('att_retry_gps'))),
        ],
      ),
    );
  }

  Widget _hoursCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                Text(t('att_today'),
                    style: const TextStyle(color: Colors.grey)),
                Text(AttendanceStore.fmtHours(_todayHours),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
            Column(
              children: [
                Text(t('att_week'),
                    style: const TextStyle(color: Colors.grey)),
                Text(AttendanceStore.fmtHours(_weekHours),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
            Column(
              children: [
                Text(t('att_shifts'),
                    style: const TextStyle(color: Colors.grey)),
                Text('${_history.length}',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _storeCard(AttendanceStore store) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('att_store_title'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(store.isCalibrated
                ? '${store.storeLat!.toStringAsFixed(5)}, ${store.storeLng!.toStringAsFixed(5)} • ${store.radiusM.toStringAsFixed(0)}m'
                : t('att_store_unset')),
            if (_pos != null)
              Text(
                  'GPS ${_pos!.latitude.toStringAsFixed(5)}, ${_pos!.longitude.toStringAsFixed(5)} (±${_pos!.accuracy.toStringAsFixed(0)}m)',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (_pos == null || _busy) ? null : _calibrate,
                    child: Text(t('att_cal_here')),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<double>(
                  value: store.radiusM,
                  items: const [100, 150, 250, 500]
                      .map((r) => DropdownMenuItem(
                          value: r.toDouble(), child: Text('${r}m')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) store.setRadius(v);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('att_history'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            if (_history.isEmpty)
              Text(t('att_history_empty'))
            else
              for (final r in _history.take(15))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                      r.isOpen ? Icons.timer : Icons.check_circle_outline,
                      color: r.isOpen ? Colors.green : Colors.grey),
                  title: Text(r.checkIn),
                  subtitle: r.isOpen
                      ? Text(t('att_open_now'))
                      : Text(
                          '${r.checkOut} • ${r.hours().toStringAsFixed(2)}h'),
                ),
          ],
        ),
      ),
    );
  }
}
