import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database_helper.dart';
import '../models/dashboard_data.dart';
import 'sales_provider.dart';
import 'warehouse_provider.dart';

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  ref.watch(salesProvider);
  ref.watch(warehouseProvider);
  return DatabaseHelper().getDashboardData();
});
