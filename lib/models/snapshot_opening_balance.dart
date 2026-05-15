class SnapshotOpeningBalance {
  const SnapshotOpeningBalance({
    required this.debit,
    required this.credit,
    this.buyBags = 0,
    this.sellBags = 0,
  });

  final double debit;
  final double credit;
  final double buyBags;
  final double sellBags;

  bool get hasValue =>
      debit > 0 || credit > 0 || buyBags > 0 || sellBags > 0;

  double get finalBalance => debit - credit;
  double get finalRemainingBags => buyBags - sellBags;
}
