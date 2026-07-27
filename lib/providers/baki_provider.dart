import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/baki_payment.dart';
import '../models/sale.dart';

// Increment to force a refresh of all baki-related providers
final bakiRefreshProvider = StateProvider<int>((ref) => 0);

final bakiSummaryProvider =
    FutureProvider<List<CustomerBakiSummary>>((ref) async {
  ref.watch(bakiRefreshProvider);
  return DatabaseHelper().getCustomerBakiSummaries();
});

final customerPaymentsProvider =
    FutureProvider.family<List<BakiPayment>, int>((ref, customerId) async {
  ref.watch(bakiRefreshProvider);
  return DatabaseHelper().getBakiPaymentsForCustomer(customerId);
});

final customerBakiSalesProvider =
    FutureProvider.family<List<Sale>, int>((ref, customerId) async {
  ref.watch(bakiRefreshProvider);
  return DatabaseHelper().getBakiSalesForCustomer(customerId);
});

final customerSearchProvider =
    FutureProvider.family<List<Customer>, String>((ref, query) async {
  if (query.isEmpty) return DatabaseHelper().getAllCustomers();
  return DatabaseHelper().searchCustomers(query);
});
