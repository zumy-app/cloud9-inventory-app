// Price-guard rule for the v2 inventory loop.
// Below-cost or large-delta price writes require a typed reason (recorded in
// the audit line). Stepping stone to manager-key approval (P1).
library;

import 'i18n/lang.dart';

class PriceGuard {
  /// Fractional delta that triggers the guard (matches 04 §3.6 default).
  static const double deltaPct = 0.20;

  static bool needsReason({
    required double newPrice,
    required double cost,
    required double oldPrice,
  }) {
    if (newPrice < cost) return true;
    if (oldPrice.abs() < 1e-9) return false;
    return ((newPrice - oldPrice) / oldPrice).abs() > deltaPct;
  }

  static String describe({
    required double newPrice,
    required double cost,
    required double oldPrice,
  }) {
    if (newPrice < cost) return Lang.instance.t('pg_below');
    return Lang.instance.t('pg_delta');
  }
}
