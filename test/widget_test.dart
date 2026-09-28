import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:docscan/theme/app_theme.dart';

void main() {
  test('application theme uses the modern light DocScan design system', () {
    final theme = AppTheme.darkTheme;

    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, AppTheme.background);
    expect(theme.colorScheme.primary, AppTheme.primary);
    expect(theme.colorScheme.onPrimary, Colors.white);
  });
}
