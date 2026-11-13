import 'package:flutter/material.dart';

/// Context-aware financial accent palette.
///
/// The ledger semantics never change (debit = money coming in from a
/// customer's account, credit = money going out), but the exact hues adapt to
/// brightness so amounts stay legible on both paper-white and night surfaces.
/// Prefer [BalanceColors.of] in widgets over hard-coded [AppColors] constants.
@immutable
class BalanceColors extends ThemeExtension<BalanceColors> {
  const BalanceColors({
    required this.debit,
    required this.credit,
    required this.brass,
    required this.debitSoft,
    required this.creditSoft,
    required this.brassSoft,
    required this.debitOnSoft,
    required this.creditOnSoft,
    required this.brassOnSoft,
  });

  /// Receivable / money-in accent.
  final Color debit;

  /// Payable / money-out accent.
  final Color credit;

  /// Premium highlight accent (fiscal year, badges, featured chips).
  final Color brass;

  /// Tinted container behind a debit figure or chip.
  final Color debitSoft;

  /// Tinted container behind a credit figure or chip.
  final Color creditSoft;

  /// Tinted container behind a brass figure or chip.
  final Color brassSoft;

  /// Readable foreground on [debitSoft].
  final Color debitOnSoft;

  /// Readable foreground on [creditSoft].
  final Color creditOnSoft;

  /// Readable foreground on [brassSoft].
  final Color brassOnSoft;

  static const BalanceColors light = BalanceColors(
    debit: Color(0xFF0E7A5F),
    credit: Color(0xFFC72B4A),
    brass: Color(0xFF8A6D1D),
    debitSoft: Color(0xFFE2EFE7),
    creditSoft: Color(0xFFFBE7EC),
    brassSoft: Color(0xFFF3ECD8),
    debitOnSoft: Color(0xFF0B5240),
    creditOnSoft: Color(0xFF8A1F36),
    brassOnSoft: Color(0xFF5C4A12),
  );

  static const BalanceColors dark = BalanceColors(
    debit: Color(0xFF47D8A0),
    credit: Color(0xFFFB7A95),
    brass: Color(0xFFE3B95B),
    debitSoft: Color(0xFF16301F),
    creditSoft: Color(0xFF371E26),
    brassSoft: Color(0xFF33290F),
    debitOnSoft: Color(0xFF8CF0BC),
    creditOnSoft: Color(0xFFFFC4D0),
    brassOnSoft: Color(0xFFF3DC9C),
  );

  static BalanceColors of(BuildContext context) =>
      Theme.of(context).extension<BalanceColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  /// Accent for a signed balance (positive → debit, negative → credit).
  Color balanceColor(double balance) {
    if (balance > 0) return debit;
    if (balance < 0) return credit;
    return const Color(0xFF667085);
  }

  @override
  BalanceColors copyWith({
    Color? debit,
    Color? credit,
    Color? brass,
    Color? debitSoft,
    Color? creditSoft,
    Color? brassSoft,
    Color? debitOnSoft,
    Color? creditOnSoft,
    Color? brassOnSoft,
  }) {
    return BalanceColors(
      debit: debit ?? this.debit,
      credit: credit ?? this.credit,
      brass: brass ?? this.brass,
      debitSoft: debitSoft ?? this.debitSoft,
      creditSoft: creditSoft ?? this.creditSoft,
      brassSoft: brassSoft ?? this.brassSoft,
      debitOnSoft: debitOnSoft ?? this.debitOnSoft,
      creditOnSoft: creditOnSoft ?? this.creditOnSoft,
      brassOnSoft: brassOnSoft ?? this.brassOnSoft,
    );
  }

  @override
  BalanceColors lerp(covariant BalanceColors? other, double t) {
    if (other == null) return this;
    return BalanceColors(
      debit: Color.lerp(debit, other.debit, t)!,
      credit: Color.lerp(credit, other.credit, t)!,
      brass: Color.lerp(brass, other.brass, t)!,
      debitSoft: Color.lerp(debitSoft, other.debitSoft, t)!,
      creditSoft: Color.lerp(creditSoft, other.creditSoft, t)!,
      brassSoft: Color.lerp(brassSoft, other.brassSoft, t)!,
      debitOnSoft: Color.lerp(debitOnSoft, other.debitOnSoft, t)!,
      creditOnSoft: Color.lerp(creditOnSoft, other.creditOnSoft, t)!,
      brassOnSoft: Color.lerp(brassOnSoft, other.brassOnSoft, t)!,
    );
  }
}
