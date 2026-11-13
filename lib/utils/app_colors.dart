import 'package:flutter/material.dart';

/// Legacy static accent constants.
///
/// Kept for call sites that do not carry a [BuildContext]. The values are
/// chosen to clear WCAG AA large-text contrast on light paper; for the best
/// result prefer `BalanceColors.of(context)` from `theme/finance_colors.dart`.
class AppColors {
  AppColors._();

  // ── Debit (money in) ──
  static const Color debit = Color(0xFF0E7A5F);
  static const Color debitLight = Color(0xFFE2EFE7);
  static const Color debitSurface = Color(0xFFE2EFE7);

  // ── Credit (money out) ──
  static const Color credit = Color(0xFFC72B4A);
  static const Color creditLight = Color(0xFFFBE7EC);
  static const Color creditSurface = Color(0xFFFBE7EC);

  // ── Neutral ──
  static const Color neutral = Color(0xFF667085);

  /// Returns the accent color for a balance value.
  /// Positive (debit balance) → deep teal, negative (credit balance) → rose.
  static Color balanceColor(double balance) {
    if (balance > 0) return debit;
    if (balance < 0) return credit;
    return neutral;
  }

  /// Returns the accent color for a balance string label.
  /// If the label contains "Debit" → teal, "Credit" → rose.
  static Color balanceLabelColor(String balanceLabel) {
    final upper = balanceLabel.toUpperCase();
    if (upper.contains('DEBIT') || upper.endsWith(' D') || upper == 'D') {
      return debit;
    }
    if (upper.contains('CREDIT') || upper.endsWith(' C') || upper == 'C') {
      return credit;
    }
    return neutral;
  }
}
