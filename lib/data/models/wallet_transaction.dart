import '../../core/utils/json_utils.dart';

class WalletTransaction {
  final String label;
  final String labelAr;
  final double amount; // positive = credit, negative = debit
  final String dateDisplay;

  const WalletTransaction({
    required this.label,
    required this.labelAr,
    required this.amount,
    required this.dateDisplay,
  });

  /// From wallet `tx[]`: `{ method, detail, amount, date, order }`.
  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    final method = asString(json, const ['method']);
    final detail = asString(json, const ['detail']);
    final order = asStringOrNull(json, const ['order']);
    final label = [method, detail].where((s) => s.isNotEmpty).join(' · ') +
        (order != null && order.isNotEmpty ? ' · Order $order' : '');
    return WalletTransaction(
      label: label.isNotEmpty ? label : 'Transaction',
      labelAr: label.isNotEmpty ? label : 'معاملة',
      amount: asDouble(json, const ['amount']),
      dateDisplay: asString(json, const ['date']),
    );
  }
}

/// From `GET /acct/wallet`: `{ balance, credited, used, tx:[...] }`.
class WalletSummary {
  final double balance;
  final double credited;
  final double used;
  final List<WalletTransaction> transactions;

  const WalletSummary({required this.balance, required this.credited, required this.used, required this.transactions});

  static const empty = WalletSummary(balance: 0, credited: 0, used: 0, transactions: []);

  factory WalletSummary.fromJson(Map<String, dynamic> json) => WalletSummary(
        balance: asDouble(json, const ['balance']),
        credited: asDouble(json, const ['credited']),
        used: asDouble(json, const ['used']),
        transactions: asList(json, const ['tx', 'transactions']).map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
