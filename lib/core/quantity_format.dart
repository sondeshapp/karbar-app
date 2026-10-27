String formatQuantity(double value, int precision) {
  final digits = precision.clamp(0, 3);
  if (digits == 0) return value.toStringAsFixed(0);
  return value.toStringAsFixed(digits).replaceFirst(RegExp(r'\.?0+$'), '');
}

double quantityStep(int precision) => switch (precision) {
  <= 0 => 1,
  1 => 0.1,
  2 => 0.01,
  _ => 0.001,
};

bool isQuantityAllowed(double value, int precision) {
  if (!value.isFinite || value <= 0) return false;
  final digits = precision.clamp(0, 3);
  final factor = switch (digits) {
    0 => 1.0,
    1 => 10.0,
    2 => 100.0,
    _ => 1000.0,
  };
  return (value * factor - (value * factor).round()).abs() < 0.000001;
}
