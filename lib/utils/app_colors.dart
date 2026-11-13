import 'package:flutter/material.dart';

/// Standardized color constants for debit/credit/balance throughout the app.
///
/// Debit  → Teal/green (money in / receivable side emphasis)
/// Credit → Rose/red (money out / payable side emphasis)
/// Balance: positive (Debit) → teal, negative (Credit) → rose
class AppColors {
  AppColors._();

  // ── Debit (Green/Teal) ──
  static const Color debit = Color(0xFF14B8A6);
  static const Color debitLight = Color(0xFFCCFBF1);
  static const Color debitSurface = Color(0xFF0D2E2A);

  // ── Credit (Red/Rose) ──
  static const Color credit = Color(0xFFF43F5E);
  static const Color creditLight = Color(0xFFFFE4E6);
  static const Color creditSurface = Color(0xFF2D1218);

  /// Returns the accent color for a balance value.
  /// Positive (debit balance) → teal, negative (credit balance) → rose.
  static Color balanceColor(double balance) {
    if (balance > 0) return debit;
    if (balance < 0) return credit;
    return const Color(0xFF94A3B8); // neutral slate for zero
  }

  /// Returns the accent color for a balance string label.
  /// If the label contains "Debit" → teal, "Credit" → rose.
  static Color balanceLabelColor(String balanceLabel) {
    final upper = balanceLabel.toUpperCase();
    if (upper.contains('DEBIT') || upper.endsWith(' D') || upper == 'D') return debit;
    if (upper.contains('CREDIT') || upper.endsWith(' C') || upper == 'C') return credit;
    return const Color(0xFF94A3B8);
  }
}
