import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_helper.dart';
import '../models/sales_report.dart';
import 'baki_provider.dart';
import 'sales_provider.dart';
import 'warehouse_provider.dart';

final salesReportProvider = FutureProvider.family<SalesReportData, ReportRange>(
  (ref, range) async {
    ref.watch(salesProvider);
    ref.watch(bakiRefreshProvider);
    ref.watch(warehouseProvider);
    return DatabaseHelper().getSalesReportData(range);
  },
);
