class DailyCashClose {
  final int? id;
  final DateTime businessDate;
  final double expectedCash;
  final double countedCash;
  final double cashReceipts;
  final double bakiIssued;
  final double bakiCollected;
  final double refundsTotal;
  final Map<String, double> paymentTotals;
  final String note;
  final DateTime closedAt;
  final int? staffId;

  const DailyCashClose({
    this.id,
    required this.businessDate,
    required this.expectedCash,
    required this.countedCash,
    required this.cashReceipts,
    required this.bakiIssued,
    required this.bakiCollected,
    required this.refundsTotal,
    required this.paymentTotals,
    required this.note,
    required this.closedAt,
    this.staffId,
  });

  double get difference => countedCash - expectedCash;
}
