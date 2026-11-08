import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_helper.dart';
import '../models/staff_activity.dart';

final staffActivityProvider = FutureProvider<List<StaffActivity>>(
  (ref) => DatabaseHelper().getStaffActivity(),
);
