class StaffPermission {
  static const pos = 'pos';
  static const dashboard = 'dashboard';
  static const inventory = 'inventory';
  static const purchases = 'purchases';
  static const history = 'history';
  static const customerCredit = 'customer_credit';
  static const reports = 'reports';
  static const cashClose = 'cash_close';

  static const all = [
    pos,
    dashboard,
    inventory,
    purchases,
    history,
    customerCredit,
    reports,
    cashClose,
  ];
}

class StaffRole {
  final String id;
  final String name;
  final Set<String> permissions;
  final bool builtIn;

  const StaffRole({
    required this.id,
    required this.name,
    required this.permissions,
    this.builtIn = false,
  });

  factory StaffRole.fromJson(Map<String, dynamic> json) => StaffRole(
    id: json['id'] as String,
    name: json['name'] as String,
    permissions: (json['permissions'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .where(StaffPermission.all.contains)
        .toSet(),
    builtIn: json['builtIn'] == true,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'permissions': permissions.toList()..sort(),
    'builtIn': builtIn,
  };

  StaffRole copyWith({String? name, Set<String>? permissions}) => StaffRole(
    id: id,
    name: name ?? this.name,
    permissions: permissions ?? this.permissions,
    builtIn: builtIn,
  );

  static const defaults = [
    StaffRole(
      id: 'cashier',
      name: 'Cashier',
      permissions: {StaffPermission.pos},
      builtIn: true,
    ),
    StaffRole(
      id: 'inventory_manager',
      name: 'Inventory manager',
      permissions: {StaffPermission.inventory, StaffPermission.purchases},
      builtIn: true,
    ),
    StaffRole(
      id: 'accountant',
      name: 'Accountant',
      permissions: {
        StaffPermission.dashboard,
        StaffPermission.history,
        StaffPermission.customerCredit,
        StaffPermission.reports,
        StaffPermission.cashClose,
      },
      builtIn: true,
    ),
  ];
}
