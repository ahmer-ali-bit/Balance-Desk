import 'package:flutter/material.dart';

/// Standardized color constants for debit/credit/balance throughout the app.
///
/// Debit  → Green (money coming in)
/// Credit → Red   (money going out)
/// Balance: positive (Debit) → Green, negative (Credit) → Red
class AppColors {
  AppColors._();

  // ── Debit (Green) ──
  static const Color debit = Color(0xFF16A34A);
  static const Color debitLight = Color(0xFFDCFCE7);
  static const Color debitSurface = Color(0xFFEFFCF3);

  // ── Credit (Red) ──
  static const Color credit = Color(0xFFDC2626);
  static const Color creditLight = Color(0xFFFEE2E2);
  static const Color creditSurface = Color(0xFFFFF1F2);

  /// Returns the accent color for a balance value.
  /// Positive (debit balance) → green, negative (credit balance) → red.
  static Color balanceColor(double balance) {
    if (balance > 0) return debit;
    if (balance < 0) return credit;
    return const Color(0xFF6B7280); // neutral grey for zero
  }

  /// Returns the accent color for a balance string label.
  /// If the label contains "Debit" → green, "Credit" → red.
  static Color balanceLabelColor(String balanceLabel) {
    final lower = balanceLabel.toLowerCase();
    if (lower.contains('debit')) return debit;
    if (lower.contains('credit')) return credit;
    return const Color(0xFF6B7280);
  }
}
